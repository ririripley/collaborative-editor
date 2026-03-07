## ADDED Requirements

### Requirement: Store small values inline in SQLite
The persistent store SHALL store values whose encoded `Data` size is ≤ 20 KB as a BLOB inline in the SQLite `kv_store` table alongside their metadata (key, size, content-type, created-at, last-modified-at, last-accessed-at, access-frequency).

#### Scenario: Write a small value to SQLite
- **WHEN** a value's encoded size is ≤ 20 KB
- **THEN** the store SHALL insert or replace a row in SQLite containing both the metadata and the encoded data BLOB within a single transaction

#### Scenario: Read a small value from SQLite
- **WHEN** a cache miss occurs for a key whose metadata indicates inline SQLite storage
- **THEN** the store SHALL execute a single SELECT on the SQLite `kv_store` table to retrieve the BLOB and decode it

---

### Requirement: Store large values on the File System with SQLite metadata
The persistent store SHALL store values whose encoded `Data` size is > 20 KB on the File System under `<Documents>/kv-blobs/<sha256-prefix>/<key-hash>`, recording only metadata in SQLite.

#### Scenario: Write a large value atomically
- **WHEN** a value's encoded size is > 20 KB
- **THEN** the store SHALL:
  1. Write the encoded blob to a `.tmp` path
  2. Atomically rename the `.tmp` file to its `final_path`
  3. Begin a SQLite transaction
  4. Insert or update the metadata row with `blob_path = final_path`
  5. Commit the transaction

#### Scenario: Crash after rename, before SQLite commit
- **WHEN** the process terminates after the file rename but before the SQLite commit
- **THEN** on next startup the store SHALL detect the orphaned blob (file exists but no matching SQLite row) and delete it

#### Scenario: Read a large value from the File System
- **WHEN** a cache miss occurs for a key whose SQLite metadata has a non-null `blob_path`
- **THEN** the store SHALL read the file at `blob_path`, decode it, and return the value

---

### Requirement: SQLite WAL mode
The SQLite database SHALL be opened with `PRAGMA journal_mode=WAL` to enable non-blocking concurrent reads alongside write operations.

#### Scenario: Open database in WAL mode
- **WHEN** the store is initialized
- **THEN** the SQLite connection SHALL execute `PRAGMA journal_mode=WAL` and confirm the result is `wal`

---

### Requirement: Startup integrity check
On initialization the persistent store SHALL scan the blob directory and remove any orphaned blob files that have no corresponding row in SQLite.

#### Scenario: Orphaned blob detected on startup
- **WHEN** the store initializes and finds a file in `<Documents>/kv-blobs/` with no matching `blob_path` in SQLite
- **THEN** the store SHALL delete the orphaned file

#### Scenario: No orphaned blobs
- **WHEN** the store initializes and all files in the blob directory have matching SQLite rows
- **THEN** the store SHALL complete initialization without deleting any files

---

### Requirement: Disk eviction
The persistent store SHALL evict entries when total stored bytes exceed the configured `maxDiskBytes` limit. The eviction policy (LRU, LFU, or LMT) SHALL be the same family as configured for the in-memory cache and SHALL be scored from SQLite metadata fields (`last-accessed-at` for LRU, `access-frequency` for LFU, `last-modified-at` for LMT).

#### Scenario: Disk eviction triggered on write
- **WHEN** a write causes total disk usage to exceed `maxDiskBytes`
- **THEN** the store SHALL evict the lowest-scored entry (per the active policy) from both SQLite and the File System before completing the write

#### Scenario: Disk eviction on background timer
- **WHEN** the background eviction timer fires and total disk usage exceeds `maxDiskBytes`
- **THEN** the store SHALL evict entries until disk usage is within the limit
