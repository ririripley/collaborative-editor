import Foundation
import os

// MARK: - UnfairLock

/// A low-overhead lock backed by `os_unfair_lock` on iOS 12–15
/// and `OSAllocatedUnfairLock` on iOS 16+, exposing a unified API.
final class UnfairLock {
    private let _lock: AnyObject

    init() {
        if #available(iOS 16, *) {
            _lock = OSAllocatedUnfairLockBox()
        } else {
            _lock = LegacyUnfairLockBox()
        }
    }

    func lock() {
        (_lock as! Lockable).lock()
    }

    func unlock() {
        (_lock as! Lockable).unlock()
    }

    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - Internal helpers

private protocol Lockable: AnyObject {
    func lock()
    func unlock()
}

private final class LegacyUnfairLockBox: Lockable {
    var underlying = os_unfair_lock()

    func lock() {
        os_unfair_lock_lock(&underlying)
    }

    func unlock() {
        os_unfair_lock_unlock(&underlying)
    }
}

@available(iOS 16, *)
private final class OSAllocatedUnfairLockBox: Lockable {
    let underlying = OSAllocatedUnfairLock()

    func lock() {
        underlying.lock()
    }

    func unlock() {
        underlying.unlock()
    }
}

// MARK: - PersistentStoreSemaphore

/// Serializes all access to the persistent store (SQLite + File System).
final class PersistentStoreSemaphore {
    private let semaphore = DispatchSemaphore(value: 1)

    func wait() {
        semaphore.wait()
    }

    func signal() {
        semaphore.signal()
    }

    @discardableResult
    func withAccess<T>(_ body: () throws -> T) rethrows -> T {
        wait()
        defer { signal() }
        return try body()
    }
}
