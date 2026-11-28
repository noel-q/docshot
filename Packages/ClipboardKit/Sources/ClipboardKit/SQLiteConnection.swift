import Foundation
import SQLite3

/// SQLite's "copy the bytes now" destructor.
private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin wrapper over the system SQLite library: one connection, used by one actor.
final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw ClipboardStoreError.openFailed(message)
        }
        handle = db
        sqlite3_busy_timeout(db, 2000)
        // Journal mode and secure delete are set by the store only after it has checked the
        // schema version, so a database from a newer version is never changed.
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }

    /// Rows changed by the last INSERT, UPDATE or DELETE.
    func changes() -> Int {
        Int(sqlite3_changes(handle))
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw ClipboardStoreError.sqlite(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ClipboardStoreError.sqlite(errorMessage)
        }
        return SQLiteStatement(statement: statement, connection: self)
    }

    func userVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        return try statement.step() ? Int32(statement.int(0)) : 0
    }
}

final class SQLiteStatement {
    private let statement: OpaquePointer
    private let connection: SQLiteConnection

    init(statement: OpaquePointer, connection: SQLiteConnection) {
        self.statement = statement
        self.connection = connection
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ index: Int32, _ value: String?) throws {
        let result: Int32
        if let value {
            // Bind with an explicit byte length, so text containing NUL is stored whole.
            if value.isEmpty {
                result = sqlite3_bind_text(statement, index, "", 0, transientDestructor)
            } else {
                let bytes = Array(value.utf8)
                result = bytes.withUnsafeBytes { buffer in
                    sqlite3_bind_text(statement, index, buffer.baseAddress!.assumingMemoryBound(to: CChar.self),
                                      Int32(buffer.count), transientDestructor)
                }
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try check(result)
    }

    func bind(_ index: Int32, _ value: Double) throws {
        try check(sqlite3_bind_double(statement, index, value))
    }

    func bind(_ index: Int32, _ value: Int) throws {
        try check(sqlite3_bind_int64(statement, index, Int64(value)))
    }

    func bind(_ index: Int32, _ value: Data?) throws {
        guard let value else {
            try check(sqlite3_bind_null(statement, index))
            return
        }
        let result = value.withUnsafeBytes { buffer in
            // An empty blob still needs a non-null pointer to be stored as a blob, not NULL.
            sqlite3_bind_blob(statement, index, buffer.baseAddress ?? UnsafeRawPointer(bitPattern: 1),
                              Int32(buffer.count), transientDestructor)
        }
        try check(result)
    }

    /// Runs a statement that returns no rows.
    func run() throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw ClipboardStoreError.sqlite(connection.errorMessage) }
    }

    /// Advances to the next row. False when there are no more rows.
    func step() throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw ClipboardStoreError.sqlite(connection.errorMessage)
        }
    }

    func text(_ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let pointer = sqlite3_column_text(statement, column) else { return "" }
        // Read by byte count, not up to the first NUL, so stored text comes back whole.
        return String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
    }

    func blob(_ column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: count)
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw ClipboardStoreError.sqlite(connection.errorMessage) }
    }
}
