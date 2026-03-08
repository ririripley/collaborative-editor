# Collaborative Editor — Project Context

## Platform & Language

- **Platform:** iOS (minimum deployment target: iOS 12)
- **Language:** Swift (no web/browser APIs — SharedWorker, IndexedDB, localStorage are not applicable)

## KVStore Module

Location: `Sources/KVStore/`

### Architecture Overview

A client-side key-value store with three layers:

1. **In-memory cache** (`MemoryCache`) — `Dictionary<String, Node>`, holds full deserialized objects
2. **Persistent store** (`PersistentStore`) — SQLite (small values) + File System (large values)
3. **Disk eviction** (`DiskEviction`) — background cleanup when disk exceeds `maxDiskBytes`

### Key Design Decisions

| Decision | Choice |
|---|---|
| Persistent store | SQLite via `SQLite.swift` or `libsqlite3` |
| Small/large threshold | **20 KB** (fixed) |
| Small values | Stored inline as BLOB in SQLite `kv_store` table |
| Large values | Metadata in SQLite, raw data at `<Documents>/kv-blobs/<sha256-prefix>/<key-hash>` |
| In-memory store | `Dictionary<String, Node>` — stores full deserialized objects (no serialization in memory) |
| Persistent store serialization | Encode to `Data` (JSON) before writing to SQLite or File System |
| SQLite mode | WAL (`PRAGMA journal_mode=WAL`) |
| Eviction policies | LRU, LFU, LMT — selected at initialization, not changeable at runtime |
| In-memory concurrency | `OSAllocatedUnfairLock` (iOS 16+) / `os_unfair_lock` wrapper (iOS 12–15) |
| Persistent store concurrency | Single shared `PersistentStoreSemaphore` (`DispatchSemaphore(value: 1)`) injected into both `PersistentStore` and `DiskEviction` |
| Blob directory | `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]/kv-blobs/` |

### Read / Write Path

**Read:** in-memory cache → (miss) → persistent store → populate cache → return
**Write:** in-memory cache first → persistent store; on persistent failure, invalidate cache entry and throw

### Large Value Write Sequence (atomic)

1. Write encoded blob to `.tmp` path
2. Atomically rename `.tmp` → `final_path`
3. Begin SQLite transaction
4. Insert/update metadata row with `blob_path = final_path`
5. Commit

On failure: roll back SQLite transaction; `.tmp` file left for startup integrity check to clean up.

### Startup Integrity Check

On every `KVStore.init`, `IntegrityChecker` scans all files recursively under the blob directory and deletes any not referenced by a `blob_path` in SQLite.

### `Node` Class

Each cache entry is a `Node` with: `key`, `value: Any`, `lastAccessedAt`, `lastModifiedAt`, `accessFrequency`, `estimatedSize`.

### Memory Limits

Configurable via `KVStoreConfiguration`: `maxMemoryBytes` and `maxMemoryEntries`. Either limit triggers eviction. Memory warning (`UIApplicationDidReceiveMemoryWarning`) also triggers a trim pass.

### SQLite Schema

Table: `kv_store`

| Column | Type | Notes |
|---|---|---|
| `key` | TEXT PRIMARY KEY | |
| `size` | INTEGER | Encoded byte size |
| `content_type` | TEXT | Swift type name |
| `created_at` | INTEGER | Unix ms |
| `last_modified_at` | INTEGER | Unix ms |
| `last_accessed_at` | INTEGER | Unix ms |
| `access_frequency` | INTEGER | For LFU scoring |
| `blob_path` | TEXT | NULL for small values |
| `data` | BLOB | NULL for large values |

### Source Files

| File | Responsibility |
|---|---|
| `KVStoreConfiguration.swift` | `KVStoreConfiguration` struct, `EvictionPolicy` enum |
| `Concurrency.swift` | `UnfairLock` (iOS 12/16 compat), `PersistentStoreSemaphore` |
| `DatabaseManager.swift` | SQLite connection, WAL setup, table DDL, blob directory creation |
| `IntegrityChecker.swift` | Startup orphaned-blob cleanup |
| `MemoryCache.swift` | `Node` class, `MemoryCache` with LRU/LFU/LMT eviction |
| `PersistentStore.swift` | Small + large value read/write, atomic rename, delete, allKeys |
| `KVStore.swift` | Public API: `set`, `get`, `delete`, `clear`, `allKeys` |
| `DiskEviction.swift` | Disk size tracking, eviction loop, background timer |

### Known Suggestions (not yet addressed)

- `readAccessCount` on `PersistentStore` and `persistentStore` on `KVStore` are test-only hooks; wrap in `#if DEBUG` for release builds
- `DiskEviction._lowestScoredRow()` is always called while holding the semaphore — extract a `_totalDiskBytesLocked()` variant to make the contract explicit and avoid accidental deadlock from `totalDiskBytes()`
- `readAccessCount += 1` in `PersistentStore` is not thread-safe; access only from the main thread in tests or protect with the semaphore
