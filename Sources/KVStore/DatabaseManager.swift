import Foundation
import SQLite

// MARK: - Table & column definitions

let kvTable = Table("kv_store")

let colKey:            SQLite.Expression<String>  = SQLite.Expression("key")
let colSize:           SQLite.Expression<Int>     = SQLite.Expression("size")
let colContentType:    SQLite.Expression<String?> = SQLite.Expression("content_type")
let colCreatedAt:      SQLite.Expression<Int64>   = SQLite.Expression("created_at")
let colLastModifiedAt: SQLite.Expression<Int64>   = SQLite.Expression("last_modified_at")
let colLastAccessedAt: SQLite.Expression<Int64>   = SQLite.Expression("last_accessed_at")
let colAccessFreq:     SQLite.Expression<Int>     = SQLite.Expression("access_frequency")
let colBlobPath:       SQLite.Expression<String?> = SQLite.Expression("blob_path")
let colData:           SQLite.Expression<Data?>   = SQLite.Expression("data")

// MARK: - DatabaseManager

final class DatabaseManager {

    let db: Connection
    let blobDirectory: URL

    init(blobDirectory: URL) throws {
        // Place the SQLite file in the Documents directory
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let dbURL = documents.appendingPathComponent("kv_store.sqlite")

        db = try Connection(dbURL.path)

        // Task 3.2 — Enable WAL mode
        let result = try db.scalar("PRAGMA journal_mode=WAL") as? String
        assert(result == "wal", "Expected WAL journal mode, got \(result ?? "nil")")

        // Task 3.1 — Create table
        try db.run(kvTable.create(ifNotExists: true) { t in
            t.column(colKey, primaryKey: true)
            t.column(colSize)
            t.column(colContentType)
            t.column(colCreatedAt)
            t.column(colLastModifiedAt)
            t.column(colLastAccessedAt)
            t.column(colAccessFreq)
            t.column(colBlobPath)
            t.column(colData)
        })

        // Task 3.3 — Create blob directory
        self.blobDirectory = blobDirectory
        try FileManager.default.createDirectory(
            at: blobDirectory,
            withIntermediateDirectories: true
        )
    }
}
