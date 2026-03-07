## Context

The collaborative editor runs on iOS (minimum deployment target: iOS 12), written entirely in Swift. It needs to persist documents, assets, and operational history locally — data that can range from a few bytes (settings, cursors) to tens of megabytes (binary assets, long document histories). A new, unified key-value store is needed to provide a single, well-defined abstraction for all local persistence needs.

The store is entirely client-side. There is no server synchronization in scope for this change. Browser primitives (SharedWorker, BroadcastChannel, IndexedDB, localStorage) are not applicable; all storage and concurrency mechanisms must be native Swift/iOS APIs.

## Goals / Non-Goals

**Goals:**
- Provide a typed `get / set / delete / clear / iterate` API usable by all client modules
- Store small values (≤ 20 KB) entirely in SQLite for low overhead
- Store large values (> 20 KB) with metadata in SQLite and raw data on the File System (hybrid model)
- Use SQLite as the single source of truth for disk metadata; do not pre-load key metadata into memory at startup
- Serve hot keys with minimal latency via a size-bounded in-memory LRU/LFU/LMT cache
- Guarantee write consistency via SQLite WAL mode and atomic file+metadata commits
- Support configurable eviction policies (LRU, LFU, last-modified-time) for both the in-memory cache and the disk store, set at initialization
- Read path: always check in-memory cache first; on a cache miss, load from persistent storage (SQLite or File System), populate the cache, and return the value
- Write path: write to in-memory storage first, then write to persistent storage
- For in-memory storage, store the object in the dictionary directly (no serialization); for persistent storage, encode the object to `Data` before writing to SQLite or the File System
- Store frequently used data in the in-memory cache and the remainder on persistent storage; eviction policy determines what stays hot
- In a multithreaded environment, use `OSAllocatedUnfairLock` to synchronize access to the in-memory store, and a `DispatchSemaphore` to serialize access to the persistent store (SharedWorker is not available on iOS/Swift)

**Non-Goals:**
- Server-side or cross-device synchronization
- Encryption at rest (can be layered on later)
- Multi-process concurrent writers outside of the Swift concurrency model
- Full ACID transactions spanning multiple keys (single-key atomicity only)

## Decisions

### 1. SQLite as the metadata and small-value store

**Decision:** Use SQLite (via [SQLite.swift](https://github.com/stephencelis/SQLite.swift) or direct `libsqlite3` binding) as the primary persistent store.

**Rationale:** SQLite provides ACID semantics, efficient indexed key lookup, and WAL mode for non-blocking concurrent reads. It handles small values natively and stores structured metadata (key, size, content-type, created-at, last-modified-at, eviction score) alongside data in a single row for small payloads. SQLite ships with iOS and requires no additional binary.

**Alternatives considered:**
- *Core Data*: Higher-level ORM overhead; no benefit for a simple key-value schema.
- *Realm*: Third-party dependency; adds binary size; no advantage over SQLite for this use case.

---

### 2. Hybrid storage threshold: SQLite for small, File System for large

**Decision:** Values ≤ 20 KB are stored inline in SQLite. Values > 20 KB store only metadata in SQLite; the raw value is written to a content-addressed file under a dedicated data directory (e.g., `<app-documents>/kv-blobs/<sha256-prefix>/<key-hash>`).

**Rationale:** Storing large BLOBs in SQLite inflates the database file, increases WAL pressure, and slows down index scans. The File System is more efficient for sequential large reads/writes. The 20 KB threshold is fixed based on iOS storage benchmarks.

**Alternatives considered:**
- *Always SQLite*: Degrades for large values; tested acceptable only up to ~1 MB.
- *Always File System*: Loses SQL query capability for metadata; harder to implement consistent transactions.

---

### 3. In-memory cache

**Decision:** The in-memory store is a `Dictionary<String, Any>` that holds full key-value pairs (not just metadata) for fast retrieval. SQLite is the single source of truth for all disk metadata; nothing is pre-loaded from SQLite into memory at startup. The cache has a configurable memory limit (max total byte size and max entry count); when either limit is exceeded, the active eviction policy (LRU, LFU, or LMT — selected at initialization) trims entries until the cache is within bounds.

**Rationale:** Holding full values in memory for hot keys eliminates deserialization on repeated reads. Treating SQLite as the authoritative metadata store avoids the cost and complexity of keeping a separate in-memory index in sync. A memory limit with eviction prevents unbounded growth on memory-constrained iOS devices.

**Alternatives considered:**

- *Pre-load all key metadata on startup*: Adds startup latency and wastes memory on keys that are never accessed in a session.
- *No memory limit*: Leads to unbounded growth; unacceptable on iOS where memory pressure causes app termination.
- *Runtime-switchable eviction policy*: Adds complexity and race conditions during transitions; construction-time policy is simpler and predictable.

---

### 4. In-memory LRU/LFU/LMT eviction policy

**Decision:** The eviction policy — LRU (least recently used), LFU (least frequently used), or LMT (least recently modified on disk) — is selected at store initialization and cannot be changed at runtime. Eviction is triggered whenever the cache exceeds either the max byte size or max entry count configured in Decision 3.

**Rationale:** Hot keys (e.g., current document state, recent cursor positions) are accessed repeatedly. Serving them from memory avoids disk I/O entirely. Making the policy a construction-time choice keeps the cache implementation simple and predictable.

**Alternatives considered:**

- *Runtime-switchable policy*: Adds complexity and race conditions during policy transitions; deferred.
- *Single hardcoded LRU*: Loses flexibility; LFU is better for skewed access patterns (assets), LMT is useful for time-sensitive collaborative data.

---

### 5. Write consistency via SQLite WAL + atomic blob write

**Decision:** SQLite is opened in WAL mode. For a write operation, the full sequence is:

1. **Cache write:** Insert or update the key-value pair in the in-memory cache (acquiring the `OSAllocatedUnfairLock`).
2. **Persist (small values):** Encode the value to `Data` and write it inline to SQLite within a transaction.
3. **Persist (large values):**
   - **Write:** Save the encoded blob to a `.tmp` path on disk.
   - **Rename:** Atomically rename the `.tmp` file to its `final_path`.
   - **Transaction:** Begin a SQLite transaction.
   - **Update:** Insert or update the metadata row pointing to `final_path`.
   - **Commit:** Commit the SQLite transaction.

On failure at the persistent step, the SQLite transaction is rolled back and any `.tmp` file is deleted; the in-memory cache entry is also invalidated.

**Rationale:** Writing to the in-memory cache first satisfies the write-path goal (Goal: "write to in-memory storage first, then write to persistent storage"). File rename is atomic on POSIX systems (`rename(2)`). Completing the rename before opening the SQLite transaction means a crash can only leave an orphaned blob (cleanable on startup) but never a committed metadata row pointing to a missing file.

---

### 6. Concurrency and thread safety (iOS/Swift)

**Decision:** Access to the in-memory store (key index + cache) is protected by `OSAllocatedUnfairLock` (available from iOS 16; falls back to `os_unfair_lock` wrapped in a Swift struct for iOS 12+). Access to the persistent store (SQLite + File System) is serialized via a `DispatchSemaphore(value: 1)`, ensuring only one thread performs a read or write at a time.

**Rationale:** `OSAllocatedUnfairLock` is the recommended low-level lock for protecting short critical sections in Swift on Apple platforms — lower overhead than `NSLock` or `DispatchQueue` barriers for in-memory operations. A semaphore for the persistent layer is simple, avoids deadlocks from reentrant calls, and is compatible back to iOS 12.

**Alternatives considered:**

- *Serial `DispatchQueue` for everything*: Simpler but serializes in-memory reads unnecessarily; higher latency for concurrent cache hits.
- *`NSLock`*: Functionally equivalent to `OSAllocatedUnfairLock` but slightly higher overhead.
- *Actor (Swift 5.5+)*: Clean model but requires iOS 15+; out of scope for iOS 12 minimum target.

---

### 7. Eviction in the disk store

**Decision:** The disk store supports eviction when its total byte size exceeds a configured `maxDiskBytes` limit. The same policy family (LRU/LFU/LMT) is applied, with eviction scores derived from metadata stored in SQLite (created-at, last-accessed-at, access-frequency). Eviction runs synchronously on write and asynchronously on a background timer.

**Rationale:** Without disk eviction, the store grows unboundedly. Reusing the same policy family as the in-memory cache keeps the mental model consistent for callers.

---

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| Large blob directory grows without bound if eviction is misconfigured | Startup integrity check: scan blob directory, delete orphaned files not referenced in SQLite |
| WAL file grows if readers hold long transactions | Set `PRAGMA wal_autocheckpoint` and run periodic checkpoints on a background queue |
| In-memory cache grows beyond the memory limit | Eviction policy trims entries on every write; additionally run a trim pass when the app receives a `UIApplicationDidReceiveMemoryWarning` notification |
| Policy mismatch between cache and disk store if configured differently | Document that using different policies is allowed but may produce non-intuitive eviction behavior; same policy is recommended |
| `OSAllocatedUnfairLock` unavailable on iOS 12–15 | Wrap `os_unfair_lock` in a Swift struct providing the same API; swap to `OSAllocatedUnfairLock` on iOS 16+ |

## Open Questions

- TTL-based expiry is deferred to a follow-on change; metadata tracks TTL but expiry enforcement is not in scope here.
- Blob files are stored under the app's `/Documents` directory (`FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)`), ensuring they persist across app restarts and are not cleared by OS storage pressure.
