import Foundation
import SQLite

/// Scans the blob directory on startup and deletes any orphaned files
/// that have no corresponding `blob_path` row in SQLite.
final class IntegrityChecker {

    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    func run() throws {
        let fm = FileManager.default
        let blobDir = dbManager.blobDirectory

        // Task 4.1 — Enumerate all files under the blob directory
        guard let enumerator = fm.enumerator(
            at: blobDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        // Collect all blob_path values from SQLite once for efficiency
        var knownPaths = Set<String>()
        for row in try dbManager.db.prepare(kvTable.select(colBlobPath)) {
            if let path = row[colBlobPath] {
                knownPaths.insert(path)
            }
        }

        // Task 4.2 — Delete any file not referenced in SQLite
        for case let fileURL as URL in enumerator {
            guard !fileURL.hasDirectoryPath else { continue }
            if !knownPaths.contains(fileURL.path) {
                try? fm.removeItem(at: fileURL)
            }
        }
    }
}
