## ADDED Requirements

### Requirement: Store a key-value pair
The store SHALL provide a `set(key:value:)` API that accepts a `String` key and any encodable value. The write path SHALL write to the in-memory cache first, then persist to the persistent store (SQLite or File System depending on encoded size).

#### Scenario: Set a small value
- **WHEN** a caller invokes `set(key:value:)` with an encoded size ≤ 20 KB
- **THEN** the value SHALL be written to the in-memory cache and stored inline in SQLite

#### Scenario: Set a large value
- **WHEN** a caller invokes `set(key:value:)` with an encoded size > 20 KB
- **THEN** the value SHALL be written to the in-memory cache, its encoded data saved to the File System, and its metadata recorded in SQLite

#### Scenario: Overwrite an existing key
- **WHEN** a caller invokes `set(key:value:)` for a key that already exists
- **THEN** the existing entry SHALL be replaced in both the in-memory cache and persistent storage

---

### Requirement: Retrieve a value by key
The store SHALL provide a `get(key:)` API that returns the value for a given key, or `nil` if the key does not exist. The read path SHALL check the in-memory cache first; on a cache miss it SHALL load from persistent storage, populate the cache, and return the value.

#### Scenario: Cache hit
- **WHEN** a caller invokes `get(key:)` for a key present in the in-memory cache
- **THEN** the value SHALL be returned directly from memory without accessing persistent storage

#### Scenario: Cache miss — small value
- **WHEN** a caller invokes `get(key:)` for a key not in the cache whose data is stored in SQLite
- **THEN** the value SHALL be loaded from SQLite, inserted into the cache, and returned to the caller

#### Scenario: Cache miss — large value
- **WHEN** a caller invokes `get(key:)` for a key not in the cache whose data is stored on the File System
- **THEN** the raw blob SHALL be read from the File System, decoded, inserted into the cache, and returned to the caller

#### Scenario: Key does not exist
- **WHEN** a caller invokes `get(key:)` for a key that has never been set
- **THEN** the store SHALL return `nil`

---

### Requirement: Delete a key-value pair
The store SHALL provide a `delete(key:)` API that removes the entry for a given key from both the in-memory cache and persistent storage.

#### Scenario: Delete an existing key
- **WHEN** a caller invokes `delete(key:)` for an existing key
- **THEN** the entry SHALL be removed from the in-memory cache and from SQLite (and the associated blob file deleted if applicable)

#### Scenario: Delete a non-existent key
- **WHEN** a caller invokes `delete(key:)` for a key that does not exist
- **THEN** the operation SHALL complete without error

---

### Requirement: Clear all entries
The store SHALL provide a `clear()` API that removes all key-value pairs from both the in-memory cache and persistent storage.

#### Scenario: Clear a populated store
- **WHEN** a caller invokes `clear()`
- **THEN** the in-memory cache SHALL be emptied, all rows in SQLite SHALL be deleted, and all blob files in the blob directory SHALL be deleted

#### Scenario: Clear an empty store
- **WHEN** a caller invokes `clear()` on a store with no entries
- **THEN** the operation SHALL complete without error

---

### Requirement: Iterate over all keys
The store SHALL provide an `iterate(handler:)` or `allKeys()` API that enumerates all currently stored keys. Iteration SHALL reflect the state of persistent storage (SQLite) as the source of truth, not only the in-memory cache.

#### Scenario: Iterate a non-empty store
- **WHEN** a caller invokes `allKeys()` on a store with N entries
- **THEN** the store SHALL return all N keys, including those not currently resident in the in-memory cache

#### Scenario: Iterate an empty store
- **WHEN** a caller invokes `allKeys()` on an empty store
- **THEN** the store SHALL return an empty collection
