import Foundation

/// The threshold in bytes below which a value is stored inline in SQLite.
private let kSmallValueThreshold = 20 * 1024  // 20 KB

public final class KVStore {

    private let cache: MemoryCache
    let persistentStore: PersistentStore
    private let diskEviction: DiskEviction

    public init(configuration: KVStoreConfiguration = KVStoreConfiguration()) throws {
        let dbManager = try DatabaseManager(blobDirectory: configuration.blobDirectory)
        try IntegrityChecker(dbManager: dbManager).run()

        let semaphore = PersistentStoreSemaphore()

        self.cache = MemoryCache(
            policy: configuration.evictionPolicy,
            maxBytes: configuration.maxMemoryBytes,
            maxEntries: configuration.maxMemoryEntries
        )
        self.persistentStore = PersistentStore(dbManager: dbManager, semaphore: semaphore)
        self.diskEviction = DiskEviction(
            dbManager: dbManager,
            policy: configuration.evictionPolicy,
            maxDiskBytes: configuration.maxDiskBytes,
            semaphore: semaphore
        )
    }

    // MARK: - Task 8.1: set

    public func set<T: Encodable>(key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        let now = Date()

        // Write to in-memory cache first
        cache.insert(key: key, value: value, estimatedSize: data.count, lastModifiedAt: now)

        let metadata = RowMetadata(
            size: data.count,
            contentType: String(describing: T.self),
            createdAt: now,
            lastModifiedAt: now
        )

        do {
            if data.count <= kSmallValueThreshold {
                try persistentStore.persistSmall(key: key, data: data, metadata: metadata)
            } else {
                try persistentStore.persistLarge(key: key, data: data, metadata: metadata)
            }
        } catch {
            // Task 8.1: invalidate cache entry on persistent write failure
            cache.remove(key: key)
            throw error
        }

        diskEviction.evictIfNeeded()
    }

    // MARK: - Task 8.2: get

    public func get<T: Decodable>(key: String, as type: T.Type = T.self) throws -> T? {
        // Check in-memory cache first
        if let cached = cache.get(key: key) as? T {
            return cached
        }

        // Cache miss — load from persistent store
        guard let isSmall = try persistentStore.isSmall(key: key) else {
            return nil  // Key does not exist
        }

        let data: Data?
        if isSmall {
            data = try persistentStore.loadSmall(key: key)
        } else {
            data = try persistentStore.loadLarge(key: key)
        }

        guard let rawData = data else { return nil }

        let decoded = try JSONDecoder().decode(T.self, from: rawData)

        // Populate cache
        cache.insert(key: key, value: decoded, estimatedSize: rawData.count)

        return decoded
    }

    // MARK: - Task 8.3: delete

    public func delete(key: String) throws {
        cache.remove(key: key)
        try persistentStore.delete(key: key)
    }

    // MARK: - Task 8.4: clear

    public func clear() throws {
        cache.removeAll()
        try persistentStore.deleteAll()
    }

    // MARK: - Task 8.5: allKeys

    public func allKeys() throws -> [String] {
        try persistentStore.allKeys()
    }
}
