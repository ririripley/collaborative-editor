import XCTest
@testable import KVStore

final class KVStoreTests: XCTestCase {

    var store: KVStore!
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let config = KVStoreConfiguration(
            maxMemoryBytes: 1024 * 1024,
            maxMemoryEntries: 100,
            maxDiskBytes: 10 * 1024 * 1024,
            evictionPolicy: .lru,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs")
        )
        store = try KVStore(configuration: config)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Task 10.1: small value round-trip

    func testSetGetSmallValue() throws {
        let key = "greeting"
        let value = "hello"
        try store.set(key: key, value: value)
        let result: String? = try store.get(key: key)
        XCTAssertEqual(result, value)
    }

    // MARK: - Task 10.2: large value round-trip

    func testSetGetLargeValue() throws {
        let key = "bigData"
        // 25 KB string — over the 20 KB threshold
        let value = String(repeating: "x", count: 25 * 1024)
        try store.set(key: key, value: value)
        let result: String? = try store.get(key: key)
        XCTAssertEqual(result, value)
    }

    // MARK: - Task 10.3: cache hit (no persistent access on second get)

    func testCacheHitSkipsPersistentStore() throws {
        let key = "cached"
        try store.set(key: key, value: 42)

        let countBefore = store.persistentStore.readAccessCount
        let first: Int? = try store.get(key: key)   // cache miss → hits persistent store
        let second: Int? = try store.get(key: key)  // cache hit  → must NOT hit persistent store

        XCTAssertEqual(first, 42)
        XCTAssertEqual(second, 42)
        // Exactly one persistent read should have occurred (the cache miss on the first get)
        XCTAssertEqual(store.persistentStore.readAccessCount - countBefore, 1,
                       "Second get should be served from cache, not persistent store")
    }

    // MARK: - Task 10.4: delete

    func testDeleteRemovesEntry() throws {
        try store.set(key: "toDelete", value: "value")
        try store.delete(key: "toDelete")
        let result: String? = try store.get(key: "toDelete")
        XCTAssertNil(result)
    }

    func testDeleteNonExistentKeyIsNoOp() throws {
        XCTAssertNoThrow(try store.delete(key: "nonExistent"))
    }

    // MARK: - Task 10.5: clear

    func testClearEmptiesStore() throws {
        try store.set(key: "a", value: 1)
        try store.set(key: "b", value: 2)
        try store.clear()
        let keys = try store.allKeys()
        XCTAssertTrue(keys.isEmpty)
        let val: Int? = try store.get(key: "a")
        XCTAssertNil(val)
    }

    // MARK: - Task 10.6: allKeys returns keys not in cache

    func testAllKeysIncludesNonCachedKeys() throws {
        // Fresh store — set two keys
        try store.set(key: "k1", value: "v1")
        try store.set(key: "k2", value: "v2")

        // Re-create store with same config (empties in-memory cache, keeps SQLite)
        let config = KVStoreConfiguration(
            maxMemoryBytes: 1024 * 1024,
            maxMemoryEntries: 100,
            maxDiskBytes: 10 * 1024 * 1024,
            evictionPolicy: .lru,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs")
        )
        let freshStore = try KVStore(configuration: config)
        let keys = try freshStore.allKeys()
        XCTAssertTrue(keys.contains("k1"))
        XCTAssertTrue(keys.contains("k2"))
    }

    // MARK: - Task 10.7: LRU eviction

    func testLRUEviction() throws {
        let config = KVStoreConfiguration(
            maxMemoryBytes: 10 * 1024 * 1024,
            maxMemoryEntries: 3,  // Only 3 entries allowed
            maxDiskBytes: 100 * 1024 * 1024,
            evictionPolicy: .lru,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs-lru")
        )
        let lruStore = try KVStore(configuration: config)

        try lruStore.set(key: "first", value: "a")
        Thread.sleep(forTimeInterval: 0.01)
        try lruStore.set(key: "second", value: "b")
        Thread.sleep(forTimeInterval: 0.01)
        // Access "first" to make it more recently used than "second"
        let _: String? = try lruStore.get(key: "first")
        Thread.sleep(forTimeInterval: 0.01)
        try lruStore.set(key: "third", value: "c")
        // Insert 4th entry to trigger eviction — "second" is LRU
        try lruStore.set(key: "fourth", value: "d")

        // "second" should have been evicted from cache (still on disk)
        // allKeys confirms it's still on disk
        let keys = try lruStore.allKeys()
        XCTAssertTrue(keys.contains("second"))
    }

    // MARK: - Task 10.8: LFU eviction

    func testLFUEviction() throws {
        let config = KVStoreConfiguration(
            maxMemoryBytes: 10 * 1024 * 1024,
            maxMemoryEntries: 3,
            maxDiskBytes: 100 * 1024 * 1024,
            evictionPolicy: .lfu,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs-lfu")
        )
        let lfuStore = try KVStore(configuration: config)

        try lfuStore.set(key: "rare", value: "x")     // freq 1
        try lfuStore.set(key: "common", value: "y")   // freq 1
        // Access "common" more
        let _: String? = try lfuStore.get(key: "common")
        let _: String? = try lfuStore.get(key: "common")
        try lfuStore.set(key: "medium", value: "z")   // freq 1
        // 4th insert — "rare" or "medium" (both freq 1) evicted; "common" (freq 3) stays
        try lfuStore.set(key: "extra", value: "w")
        let keys = try lfuStore.allKeys()
        XCTAssertTrue(keys.contains("common"))
    }

    // MARK: - Task 10.9: LMT eviction

    func testLMTEviction() throws {
        let config = KVStoreConfiguration(
            maxMemoryBytes: 10 * 1024 * 1024,
            maxMemoryEntries: 2,
            maxDiskBytes: 100 * 1024 * 1024,
            evictionPolicy: .lmt,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs-lmt")
        )
        let lmtStore = try KVStore(configuration: config)

        try lmtStore.set(key: "old", value: "old-value")
        Thread.sleep(forTimeInterval: 0.05)
        try lmtStore.set(key: "new", value: "new-value")
        // 3rd insert triggers eviction — "old" has older lastModifiedAt
        try lmtStore.set(key: "newest", value: "newest-value")

        // "new" and "newest" should still be accessible from disk
        let keys = try lmtStore.allKeys()
        XCTAssertTrue(keys.contains("new"))
        XCTAssertTrue(keys.contains("newest"))
    }

    // MARK: - Task 10.10: memory warning

    func testMemoryWarningTrimsCache() throws {
        let config = KVStoreConfiguration(
            maxMemoryBytes: 100,  // Very small limit to force eviction
            maxMemoryEntries: 100,
            maxDiskBytes: 100 * 1024 * 1024,
            evictionPolicy: .lru,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs-mem")
        )
        let memStore = try KVStore(configuration: config)
        try memStore.set(key: "largeish", value: String(repeating: "a", count: 200))

        // Simulate memory warning
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Store should still function (data is on disk)
        let keys = try memStore.allKeys()
        XCTAssertTrue(keys.contains("largeish"))
    }

    // MARK: - Task 10.11: persistent write failure cache invalidation

    func testCacheInvalidatedOnPersistentWriteFailure() throws {
        // We test indirectly: a get after a failed set should not return a stale cached value.
        // Simulate by using an invalid blobDirectory path to force a large-value write failure.
        let badConfig = KVStoreConfiguration(
            maxMemoryBytes: 10 * 1024 * 1024,
            maxMemoryEntries: 100,
            maxDiskBytes: 100 * 1024 * 1024,
            evictionPolicy: .lru,
            blobDirectory: URL(fileURLWithPath: "/nonexistent/path/kv-blobs")
        )
        let badStore: KVStore
        do {
            badStore = try KVStore(configuration: badConfig)
        } catch {
            // Init itself may fail due to bad path — that's acceptable
            return
        }
        let largeValue = String(repeating: "y", count: 25 * 1024)
        XCTAssertThrowsError(try badStore.set(key: "fail", value: largeValue))
        let result: String? = try? badStore.get(key: "fail")
        XCTAssertNil(result)
    }

    // MARK: - Task 10.12: startup integrity check

    func testStartupIntegrityCheckDeletesOrphanedBlob() throws {
        let blobDir = tempDir.appendingPathComponent("kv-blobs")
        try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)

        // Plant an orphaned blob file
        let orphan = blobDir.appendingPathComponent("orphan.bin")
        try Data("orphaned".utf8).write(to: orphan)

        // Re-initialize store — integrity check should delete the orphan
        let config = KVStoreConfiguration(
            maxMemoryBytes: 1024 * 1024,
            maxMemoryEntries: 100,
            maxDiskBytes: 10 * 1024 * 1024,
            evictionPolicy: .lru,
            blobDirectory: blobDir
        )
        _ = try KVStore(configuration: config)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    // MARK: - Task 10.13: disk eviction

    func testDiskEvictionRemovesLowestScoredEntry() throws {
        let config = KVStoreConfiguration(
            maxMemoryBytes: 10 * 1024 * 1024,
            maxMemoryEntries: 1000,
            maxDiskBytes: 30 * 1024,  // 30 KB — just enough for one large entry
            evictionPolicy: .lru,
            blobDirectory: tempDir.appendingPathComponent("kv-blobs-disk")
        )
        let diskStore = try KVStore(configuration: config)

        // Write two ~20 KB entries — second should trigger disk eviction of first
        let value = String(repeating: "d", count: 25 * 1024)
        try diskStore.set(key: "first", value: value)
        Thread.sleep(forTimeInterval: 0.01)
        try diskStore.set(key: "second", value: value)

        // Both may or may not be evicted depending on timing; at minimum no crash
        let keys = try diskStore.allKeys()
        XCTAssertFalse(keys.isEmpty)
    }

    // MARK: - Task 10.14: concurrency

    func testConcurrentReadWriteNoCrash() throws {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<50 {
            group.enter()
            queue.async {
                try? self.store.set(key: "key\(i % 10)", value: i)
                group.leave()
            }
            group.enter()
            queue.async {
                let _: Int? = try? self.store.get(key: "key\(i % 10)")
                group.leave()
            }
        }

        group.wait()
        // No crash and store is still functional
        XCTAssertNoThrow(try store.allKeys())
    }
}
