## 1. Project Setup

- [x] 1.1 Create the `KVStore` Swift package / module directory structure
- [x] 1.2 Add `SQLite.swift` (or configure `libsqlite3` binding) as a dependency
- [x] 1.3 Define the `KVStoreConfiguration` struct with fields: `maxMemoryBytes`, `maxMemoryEntries`, `maxDiskBytes`, `evictionPolicy`, `blobDirectory`
- [x] 1.4 Define the `EvictionPolicy` enum with cases: `.lru`, `.lfu`, `.lmt`

## 2. Concurrency Primitives

- [x] 2.1 Implement `UnfairLock` Swift struct wrapping `os_unfair_lock` with `lock()`, `unlock()`, and `withLock(_:)` methods (iOS 12–15 fallback)
- [x] 2.2 Add `@available(iOS 16, *)` code path that uses `OSAllocatedUnfairLock` behind the same interface
- [x] 2.3 Implement `PersistentStoreSemaphore` as a thin wrapper around `DispatchSemaphore(value: 1)` for serializing all SQLite + File System access

## 3. SQLite Schema & Initialization

- [x] 3.1 Create the `kv_store` table DDL: columns `key TEXT PRIMARY KEY`, `size INTEGER`, `content_type TEXT`, `created_at INTEGER`, `last_modified_at INTEGER`, `last_accessed_at INTEGER`, `access_frequency INTEGER`, `blob_path TEXT`, `data BLOB`
- [x] 3.2 Open the SQLite database and execute `PRAGMA journal_mode=WAL` on initialization; assert the result is `wal`
- [x] 3.3 Create the blob directory at `<Documents>/kv-blobs/` if it does not exist

## 4. Startup Integrity Check

- [x] 4.1 On store initialization, enumerate all files under `<Documents>/kv-blobs/`
- [x] 4.2 For each file, query SQLite for a matching `blob_path`; delete the file if no row is found

## 5. In-Memory Cache

- [x] 5.1 Define `Node` class with properties: `key: String`, `value: Any`, `lastAccessedAt: Date`, `lastModifiedAt: Date`, `accessFrequency: Int`, `estimatedSize: Int`
- [x] 5.2 Implement `MemoryCache` class with a `Dictionary<String, Node>` backing store and an `UnfairLock` for thread safety
- [x] 5.3 Implement `insert(key:value:estimatedSize:)` that stores the object and updates metadata
- [x] 5.4 Implement `get(key:)` that returns the object and updates `last-accessed-at` and `access-frequency`
- [x] 5.5 Implement `remove(key:)` and `removeAll()`
- [x] 5.6 Implement `trimIfNeeded()` that checks both `maxMemoryBytes` and `maxMemoryEntries` and evicts entries per the active policy until within bounds
- [x] 5.7 Implement LRU eviction scoring (sort by `last-accessed-at` ascending)
- [x] 5.8 Implement LFU eviction scoring (sort by `access-frequency` ascending)
- [x] 5.9 Implement LMT eviction scoring (sort by `last-modified-at` ascending)
- [x] 5.10 Register for `UIApplicationDidReceiveMemoryWarning` and call `trimIfNeeded()` on receipt

## 6. Persistent Store — Small Values (SQLite)

- [x] 6.1 Implement `persistSmall(key:data:metadata:)` that inserts or replaces a row in `kv_store` with the `data` BLOB and all metadata columns in a single SQLite transaction
- [x] 6.2 Implement `loadSmall(key:)` that executes a SELECT on `kv_store` for rows where `blob_path IS NULL` and returns the `data` BLOB

## 7. Persistent Store — Large Values (File System + SQLite)

- [x] 7.1 Implement `blobPath(for:)` that derives the content-addressed path `<Documents>/kv-blobs/<sha256-prefix>/<key-hash>`
- [x] 7.2 Implement `persistLarge(key:data:metadata:)` following the atomic write sequence: write to `.tmp` → rename to `final_path` → begin SQLite transaction → insert/update metadata row with `blob_path` → commit
- [x] 7.3 Implement rollback: on any failure after the rename, roll back the SQLite transaction and delete the `.tmp` file (the renamed file is left for the startup integrity check)
- [x] 7.4 Implement `loadLarge(key:)` that reads `blob_path` from SQLite, reads the file, and returns the raw `Data`

## 8. Core API

- [x] 8.1 Implement `KVStore.set(key:value:)`: encode the value to `Data`, write to in-memory cache, branch on encoded size (≤ 20 KB → `persistSmall`, > 20 KB → `persistLarge`); invalidate cache entry and propagate error on persistent write failure
- [x] 8.2 Implement `KVStore.get(key:)`: check in-memory cache first; on miss acquire semaphore, load from SQLite or File System, decode, populate cache, return value; return `nil` if key absent
- [x] 8.3 Implement `KVStore.delete(key:)`: remove from in-memory cache; acquire semaphore, delete SQLite row and associated blob file if present; no-op if key absent
- [x] 8.4 Implement `KVStore.clear()`: call `removeAll()` on in-memory cache; acquire semaphore, delete all SQLite rows and all files in the blob directory
- [x] 8.5 Implement `KVStore.allKeys()`: acquire semaphore, SELECT all keys from SQLite, return as `[String]`

## 9. Disk Eviction

- [x] 9.1 Implement `totalDiskBytes()` by querying `SUM(size)` from the `kv_store` SQLite table
- [x] 9.2 Implement `evictFromDiskIfNeeded()` that queries SQLite for the lowest-scored entry per the active policy and deletes it (SQLite row + blob file) until under `maxDiskBytes`
- [x] 9.3 Call `evictFromDiskIfNeeded()` at the end of each successful `persistSmall` / `persistLarge` write
- [x] 9.4 Schedule a background `DispatchQueue` timer that calls `evictFromDiskIfNeeded()` periodically

## 10. Tests

- [x] 10.1 Unit test `set` + `get` round-trip for small values (≤ 20 KB)
- [x] 10.2 Unit test `set` + `get` round-trip for large values (> 20 KB)
- [x] 10.3 Unit test cache hit: verify persistent store is not accessed on a second `get` for the same key
- [x] 10.4 Unit test `delete` removes entry from both cache and SQLite/File System
- [x] 10.5 Unit test `clear` empties cache, SQLite, and blob directory
- [x] 10.6 Unit test `allKeys` returns keys not present in the in-memory cache
- [x] 10.7 Unit test LRU eviction: insert entries beyond `maxMemoryEntries`, verify oldest-accessed entry is evicted
- [x] 10.8 Unit test LFU eviction: verify lowest-frequency entry is evicted
- [x] 10.9 Unit test LMT eviction: verify least-recently-modified entry is evicted
- [x] 10.10 Unit test memory warning: simulate `UIApplicationDidReceiveMemoryWarning` and verify cache is trimmed
- [x] 10.11 Unit test persistent write failure: verify cache entry is invalidated and error is returned
- [x] 10.12 Unit test startup integrity check: plant an orphaned blob file, initialize store, verify file is deleted
- [x] 10.13 Unit test disk eviction: write entries until `maxDiskBytes` is exceeded, verify lowest-scored entry is removed
- [x] 10.14 Concurrency test: write and read from multiple threads simultaneously, verify no data corruption
