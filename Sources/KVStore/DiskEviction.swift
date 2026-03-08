import Foundation
import SQLite

final class DiskEviction {

    private let dbManager: DatabaseManager
    private let policy: EvictionPolicy
    private let maxDiskBytes: Int
    private let semaphore: PersistentStoreSemaphore
    private var timer: DispatchSourceTimer?

    init(dbManager: DatabaseManager, policy: EvictionPolicy, maxDiskBytes: Int, semaphore: PersistentStoreSemaphore) {
        self.dbManager = dbManager
        self.policy = policy
        self.maxDiskBytes = maxDiskBytes
        self.semaphore = semaphore
        scheduleBackgroundTimer()
    }

    // MARK: - Task 9.1: totalDiskBytes

    func totalDiskBytes() -> Int {
        let result = try? semaphore.withAccess {
            try dbManager.db.scalar(kvTable.select(colSize.sum)) ?? 0
        }
        return result ?? 0
    }

    // MARK: - Task 9.2: evictFromDiskIfNeeded

    func evictIfNeeded() {
        try? semaphore.withAccess {
            while (try? dbManager.db.scalar(kvTable.select(colSize.sum)) ?? 0) ?? 0 > maxDiskBytes {
                guard let row = try? _lowestScoredRow() else { break }
                let key = row[colKey]
                if let blobPath = row[colBlobPath] {
                    try? FileManager.default.removeItem(atPath: blobPath)
                }
                try? dbManager.db.run(kvTable.filter(colKey == key).delete())
            }
        }
    }

    // MARK: - Task 9.4: background timer

    private func scheduleBackgroundTimer() {
        let queue = DispatchQueue(label: "com.kvstore.disk-eviction", qos: .background)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 60, repeating: 60)
        t.setEventHandler { [weak self] in self?.evictIfNeeded() }
        t.resume()
        timer = t
    }

    // MARK: - Private scoring

    private func _lowestScoredRow() throws -> Row? {
        let query: Table
        switch policy {
        case .lru:
            query = kvTable.order(colLastAccessedAt.asc).limit(1)
        case .lfu:
            query = kvTable.order(colAccessFreq.asc).limit(1)
        case .lmt:
            query = kvTable.order(colLastModifiedAt.asc).limit(1)
        }
        return try dbManager.db.pluck(query)
    }
}
