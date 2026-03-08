import Foundation
import SQLite
import CryptoKit

struct RowMetadata {
    let size: Int
    let contentType: String?
    let createdAt: Date
    let lastModifiedAt: Date
}

// MARK: - PersistentStore

final class PersistentStore {

    private let dbManager: DatabaseManager
    let semaphore: PersistentStoreSemaphore

    /// Counts how many times persistent storage was actually read (for testing).
    private(set) var readAccessCount: Int = 0

    init(dbManager: DatabaseManager, semaphore: PersistentStoreSemaphore) {
        self.dbManager = dbManager
        self.semaphore = semaphore
    }

    // MARK: - Task 6.1: persistSmall

    func persistSmall(key: String, data: Data, metadata: RowMetadata) throws {
        try semaphore.withAccess {
            let now = Date()
            let nowMs = Int64(now.timeIntervalSince1970 * 1000)
            let createdMs = Int64(metadata.createdAt.timeIntervalSince1970 * 1000)
            let modifiedMs = Int64(metadata.lastModifiedAt.timeIntervalSince1970 * 1000)

            try dbManager.db.run(
                kvTable.insert(or: .replace,
                    colKey            <- key,
                    colSize           <- data.count,
                    colContentType    <- metadata.contentType,
                    colCreatedAt      <- createdMs,
                    colLastModifiedAt <- modifiedMs,
                    colLastAccessedAt <- nowMs,
                    colAccessFreq     <- 1,
                    colBlobPath       <- nil,
                    colData           <- data
                )
            )
        }
    }

    // MARK: - Task 6.2: loadSmall

    func loadSmall(key: String) throws -> Data? {
        readAccessCount += 1
        return try semaphore.withAccess {
            let query = kvTable
                .filter(colKey == key && colBlobPath == nil)
                .select(colData)
            guard let row = try dbManager.db.pluck(query) else { return nil }
            // Update access metadata
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            try dbManager.db.run(
                kvTable.filter(colKey == key).update(
                    colLastAccessedAt <- nowMs,
                    colAccessFreq     <- colAccessFreq + 1
                )
            )
            return row[colData]
        }
    }

    // MARK: - Task 7.1: blobPath(for:)

    func blobPath(for key: String) -> URL {
        let keyData = Data(key.utf8)
        let hash: String
        if #available(iOS 13, *) {
            hash = SHA256.hash(data: keyData).map { String(format: "%02x", $0) }.joined()
        } else {
            // Fallback: simple hex of key bytes (not cryptographically safe, but unique enough)
            hash = keyData.map { String(format: "%02x", $0) }.joined()
        }
        let prefix = String(hash.prefix(2))
        return dbManager.blobDirectory
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(hash)
    }

    // MARK: - Task 7.2 + 7.3: persistLarge (atomic write + rollback)

    func persistLarge(key: String, data: Data, metadata: RowMetadata) throws {
        let finalURL = blobPath(for: key)
        let tmpURL = finalURL.appendingPathExtension("tmp")

        // Ensure subdirectory exists
        try FileManager.default.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Step 1: Write to .tmp
        try data.write(to: tmpURL, options: .atomic)

        // Step 2: Atomic rename .tmp → final_path
        _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tmpURL)

        // Steps 3–5: SQLite transaction
        try semaphore.withAccess {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let createdMs = Int64(metadata.createdAt.timeIntervalSince1970 * 1000)
            let modifiedMs = Int64(metadata.lastModifiedAt.timeIntervalSince1970 * 1000)

            do {
                try dbManager.db.transaction {
                    try dbManager.db.run(
                        kvTable.insert(or: .replace,
                            colKey            <- key,
                            colSize           <- data.count,
                            colContentType    <- metadata.contentType,
                            colCreatedAt      <- createdMs,
                            colLastModifiedAt <- modifiedMs,
                            colLastAccessedAt <- nowMs,
                            colAccessFreq     <- 1,
                            colBlobPath       <- finalURL.path,
                            colData           <- nil
                        )
                    )
                }
            } catch {
                // Rollback: remove the .tmp if it still exists
                try? FileManager.default.removeItem(at: tmpURL)
                throw error
            }
        }
    }

    // MARK: - Task 7.4: loadLarge

    func loadLarge(key: String) throws -> Data? {
        readAccessCount += 1
        let blobPathValue: String? = try semaphore.withAccess {
            let query = kvTable.filter(colKey == key).select(colBlobPath)
            guard let row = try dbManager.db.pluck(query) else { return nil }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            try dbManager.db.run(
                kvTable.filter(colKey == key).update(
                    colLastAccessedAt <- nowMs,
                    colAccessFreq     <- colAccessFreq + 1
                )
            )
            return row[colBlobPath]
        }
        guard let path = blobPathValue else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // MARK: - Delete helpers (used by KVStore)

    func delete(key: String) throws {
        try semaphore.withAccess {
            // Get blob path before deleting the row
            let query = kvTable.filter(colKey == key).select(colBlobPath)
            if let row = try dbManager.db.pluck(query),
               let path = row[colBlobPath] {
                try? FileManager.default.removeItem(atPath: path)
            }
            try dbManager.db.run(kvTable.filter(colKey == key).delete())
        }
    }

    func deleteAll() throws {
        try semaphore.withAccess {
            try dbManager.db.run(kvTable.delete())
            let fm = FileManager.default
            let contents = try fm.contentsOfDirectory(
                at: dbManager.blobDirectory,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                try? fm.removeItem(at: url)
            }
        }
    }

    func allKeys() throws -> [String] {
        try semaphore.withAccess {
            try dbManager.db.prepare(kvTable.select(colKey)).map { $0[colKey] }
        }
    }

    func isSmall(key: String) throws -> Bool? {
        try semaphore.withAccess {
            let query = kvTable.filter(colKey == key).select(colBlobPath)
            guard let row = try dbManager.db.pluck(query) else { return nil }
            return row[colBlobPath] == nil
        }
    }
}
