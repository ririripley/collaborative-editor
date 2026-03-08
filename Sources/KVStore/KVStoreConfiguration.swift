import Foundation

/// Eviction policy used by both the in-memory cache and the disk store.
public enum EvictionPolicy {
    /// Evict the entry that was least recently accessed.
    case lru
    /// Evict the entry with the lowest access frequency.
    case lfu
    /// Evict the entry that was least recently modified on disk.
    case lmt
}

/// Configuration passed to `KVStore` at initialization time.
public struct KVStoreConfiguration {
    /// Maximum total estimated byte size of the in-memory cache.
    public let maxMemoryBytes: Int
    /// Maximum number of entries allowed in the in-memory cache.
    public let maxMemoryEntries: Int
    /// Maximum total byte size of the on-disk store before eviction triggers.
    public let maxDiskBytes: Int
    /// Eviction policy applied to both the in-memory cache and the disk store.
    public let evictionPolicy: EvictionPolicy
    /// Directory where large-value blob files are stored.
    /// Defaults to `<Documents>/kv-blobs`.
    public let blobDirectory: URL

    public init(
        maxMemoryBytes: Int = 20 * 1024 * 1024,   // 20 MB default
        maxMemoryEntries: Int = 1000,
        maxDiskBytes: Int = 200 * 1024 * 1024,    // 200 MB default
        evictionPolicy: EvictionPolicy = .lru,
        blobDirectory: URL? = nil
    ) {
        self.maxMemoryBytes = maxMemoryBytes
        self.maxMemoryEntries = maxMemoryEntries
        self.maxDiskBytes = maxDiskBytes
        self.evictionPolicy = evictionPolicy

        if let dir = blobDirectory {
            self.blobDirectory = dir
        } else {
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            self.blobDirectory = documents.appendingPathComponent("kv-blobs", isDirectory: true)
        }
    }
}
