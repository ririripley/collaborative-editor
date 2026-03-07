## ADDED Requirements

### Requirement: In-memory store protected by OSAllocatedUnfairLock
Access to the in-memory cache (`Dictionary<String, Any>`) SHALL be protected by `OSAllocatedUnfairLock` on iOS 16+ and by `os_unfair_lock` wrapped in a Swift struct on iOS 12–15. All reads and writes to the dictionary SHALL acquire this lock.

#### Scenario: Concurrent cache reads
- **WHEN** multiple threads concurrently invoke `get(key:)` for keys present in the in-memory cache
- **THEN** each thread SHALL acquire the lock, read the value, and release the lock without data corruption

#### Scenario: Concurrent cache write and read
- **WHEN** one thread invokes `set(key:value:)` while another invokes `get(key:)` for the same key
- **THEN** the lock SHALL serialize the operations so the reader sees either the old value or the fully written new value, never a partial state

---

### Requirement: Persistent store access serialized with DispatchSemaphore
Access to the persistent store (SQLite + File System) SHALL be serialized using a `DispatchSemaphore(value: 1)`, ensuring only one thread performs a persistent read or write at a time.

#### Scenario: Concurrent persistent writes
- **WHEN** two threads concurrently invoke `set(key:value:)` requiring a persistent write
- **THEN** the semaphore SHALL ensure the writes are executed sequentially, preventing SQLite corruption

#### Scenario: Concurrent persistent read and write
- **WHEN** one thread is performing a persistent write while another requests a persistent read (cache miss)
- **THEN** the semaphore SHALL block the read until the write completes

---

### Requirement: iOS 12 lock compatibility
The `OSAllocatedUnfairLock` wrapper SHALL be available on iOS 12+ by falling back to `os_unfair_lock` on iOS 12–15. The calling code SHALL use the same API regardless of OS version.

#### Scenario: Running on iOS 12
- **WHEN** the store initializes on a device running iOS 12
- **THEN** the lock implementation SHALL use `os_unfair_lock` internally and expose the same `lock()` / `unlock()` / `withLock(_:)` interface

#### Scenario: Running on iOS 16+
- **WHEN** the store initializes on a device running iOS 16 or later
- **THEN** the lock implementation SHALL use `OSAllocatedUnfairLock` directly
