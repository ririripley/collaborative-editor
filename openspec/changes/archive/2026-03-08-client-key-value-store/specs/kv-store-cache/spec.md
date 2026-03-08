## ADDED Requirements

### Requirement: In-memory cache holds full values
The in-memory cache SHALL be a `Dictionary<String, Any>` that stores full deserialized objects (not encoded `Data`) for direct retrieval without deserialization overhead.

#### Scenario: Cache populated on write
- **WHEN** a caller invokes `set(key:value:)`
- **THEN** the deserialized object SHALL be inserted into the in-memory dictionary before writing to persistent storage

#### Scenario: Cache populated on cache miss read
- **WHEN** a value is loaded from persistent storage due to a cache miss
- **THEN** the deserialized object SHALL be inserted into the in-memory dictionary before returning to the caller

---

### Requirement: Configurable memory limits
The in-memory cache SHALL enforce two configurable limits set at store initialization: a maximum total byte size (`maxMemoryBytes`) and a maximum entry count (`maxMemoryEntries`). Either limit being exceeded SHALL trigger eviction.

#### Scenario: Byte limit exceeded
- **WHEN** inserting an entry causes total estimated cache size to exceed `maxMemoryBytes`
- **THEN** the cache SHALL evict entries per the active policy until total size is within `maxMemoryBytes`

#### Scenario: Entry count limit exceeded
- **WHEN** inserting an entry causes the total entry count to exceed `maxMemoryEntries`
- **THEN** the cache SHALL evict entries per the active policy until count is within `maxMemoryEntries`

---

### Requirement: Configurable eviction policy
The cache SHALL support three eviction policies selectable at initialization: LRU (least recently used), LFU (least frequently used), and LMT (least recently modified on disk). The policy SHALL NOT be changeable at runtime.

#### Scenario: LRU eviction
- **WHEN** eviction is triggered and the policy is LRU
- **THEN** the entry with the oldest `last-accessed-at` timestamp SHALL be evicted first

#### Scenario: LFU eviction
- **WHEN** eviction is triggered and the policy is LFU
- **THEN** the entry with the lowest `access-frequency` count SHALL be evicted first

#### Scenario: LMT eviction
- **WHEN** eviction is triggered and the policy is LMT
- **THEN** the entry with the oldest `last-modified-at` timestamp SHALL be evicted first

---

### Requirement: Memory warning eviction
The cache SHALL register for `UIApplicationDidReceiveMemoryWarning` notifications and perform an eviction trim pass when the notification is received.

#### Scenario: Memory warning received
- **WHEN** the app receives a `UIApplicationDidReceiveMemoryWarning` notification
- **THEN** the cache SHALL evict entries per the active policy until total size is within `maxMemoryBytes` and entry count is within `maxMemoryEntries`

---

### Requirement: Cache invalidation on persistent write failure
If writing to persistent storage fails after the in-memory cache has been updated, the cache entry for the affected key SHALL be invalidated to prevent stale data.

#### Scenario: Persistent write fails
- **WHEN** a `set(key:value:)` call writes to the in-memory cache but the subsequent persistent write fails
- **THEN** the store SHALL remove the key from the in-memory cache and surface an error to the caller
