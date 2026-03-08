import Foundation

// MARK: - Node (Task 5.1)

/// A cache entry holding a full deserialized value alongside its eviction metadata.
final class Node {
    let key: String
    let value: Any
    var lastAccessedAt: Date
    var lastModifiedAt: Date
    var accessFrequency: Int
    var estimatedSize: Int

    init(key: String, value: Any, lastModifiedAt: Date, estimatedSize: Int) {
        self.key = key
        self.value = value
        self.lastAccessedAt = Date()
        self.lastModifiedAt = lastModifiedAt
        self.accessFrequency = 1
        self.estimatedSize = estimatedSize
    }
}

// MARK: - MemoryCache (Task 5.2)

/// Thread-safe in-memory cache backed by `Dictionary<String, Node>`.
final class MemoryCache {

    private var store: [String: Node] = [:]
    private let lock = UnfairLock()
    private let policy: EvictionPolicy
    private let maxBytes: Int
    private let maxEntries: Int

    /// Current total estimated byte size of all cached values.
    private var totalBytes: Int = 0

    init(policy: EvictionPolicy, maxBytes: Int, maxEntries: Int) {
        self.policy = policy
        self.maxBytes = maxBytes
        self.maxEntries = maxEntries
        registerMemoryWarning()
    }

    // MARK: - Task 5.3: insert

    func insert(key: String, value: Any, estimatedSize: Int, lastModifiedAt: Date = Date()) {
        lock.withLock {
            if let existing = store[key] {
                totalBytes -= existing.estimatedSize
            }
            let node = Node(key: key, value: value, lastModifiedAt: lastModifiedAt, estimatedSize: estimatedSize)
            store[key] = node
            totalBytes += estimatedSize
            _trimIfNeededLocked()
        }
    }

    // MARK: - Task 5.4: get

    func get(key: String) -> Any? {
        lock.withLock {
            guard let node = store[key] else { return nil }
            node.lastAccessedAt = Date()
            node.accessFrequency += 1
            return node.value
        }
    }

    // MARK: - Task 5.5: remove / removeAll

    func remove(key: String) {
        lock.withLock {
            if let node = store.removeValue(forKey: key) {
                totalBytes -= node.estimatedSize
            }
        }
    }

    func removeAll() {
        lock.withLock {
            store.removeAll()
            totalBytes = 0
        }
    }

    // MARK: - Task 5.6: trimIfNeeded

    /// Public entry point — acquires the lock then trims.
    /// Safe to call from any context that does NOT already hold `lock`.
    func trimIfNeeded() {
        lock.withLock { _trimIfNeededLocked() }
    }

    /// Lock-assumed trim. MUST only be called while `lock` is already held.
    private func _trimIfNeededLocked() {
        while totalBytes > maxBytes || store.count > maxEntries {
            guard let victim = _selectVictim() else { break }
            totalBytes -= victim.estimatedSize
            store.removeValue(forKey: victim.key)
        }
    }

    // MARK: - Private eviction scoring

    /// Must be called while `lock` is held.
    private func _selectVictim() -> Node? {
        guard !store.isEmpty else { return nil }
        switch policy {
        case .lru:  // Task 5.7
            return store.values.min(by: { $0.lastAccessedAt < $1.lastAccessedAt })
        case .lfu:  // Task 5.8
            return store.values.min(by: { $0.accessFrequency < $1.accessFrequency })
        case .lmt:  // Task 5.9
            return store.values.min(by: { $0.lastModifiedAt < $1.lastModifiedAt })
        }
    }

    // MARK: - Task 5.10: memory warning

    private func registerMemoryWarning() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        trimIfNeeded()
    }
}
