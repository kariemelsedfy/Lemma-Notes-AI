import Foundation
import SQLite3

enum LedgerError: Error, Equatable {
    case invalidCost, duplicate, overBudget, storageUnavailable, configurationMismatch
    case unknownRequest, costExceeded
}

actor SpendLedger {
    private let databaseURL: URL
    private let limitMicros: Int64

    init(databaseURL: URL, limitMicros: Int64 = 10_000_000) throws {
        guard (1...10_000_000).contains(limitMicros) else { throw LedgerError.invalidCost }
        self.databaseURL = databaseURL
        self.limitMicros = limitMicros
        try Self.withDatabase(at: databaseURL) { database in
            guard try Self.persistedLimit(database) == limitMicros else { throw LedgerError.configurationMismatch }
            let total = try Self.total(database)
            guard total >= 0, total <= limitMicros else { throw LedgerError.overBudget }
            _ = try Self.observedTotal(database)
            _ = try Self.halted(database)
        }
    }

    static func bootstrap(databaseURL: URL, limitMicros: Int64 = 10_000_000) throws -> SpendLedger {
        guard (1...10_000_000).contains(limitMicros) else { throw LedgerError.invalidCost }
        guard !FileManager.default.fileExists(atPath: databaseURL.path) else { throw LedgerError.storageUnavailable }
        try withDatabase(at: databaseURL, creating: true) { database in
            try execute(database, "PRAGMA journal_mode=WAL")
            try execute(database, "PRAGMA synchronous=FULL")
            try execute(
                database,
                """
                CREATE TABLE policy (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    limit_micros INTEGER NOT NULL,
                    halted INTEGER NOT NULL DEFAULT 0 CHECK(halted IN (0, 1))
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE reservations (
                    request_id TEXT PRIMARY KEY,
                    max_micros INTEGER NOT NULL CHECK(max_micros > 0)
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE observations (
                    request_id TEXT PRIMARY KEY,
                    observed_micros INTEGER NOT NULL CHECK(observed_micros >= 0)
                )
                """
            )
            let statement = try prepare(database, "INSERT INTO policy (id, limit_micros) VALUES (1, ?)")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, limitMicros) == SQLITE_OK,
                sqlite3_step(statement) == SQLITE_DONE
            else { throw LedgerError.storageUnavailable }
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
            } catch {
                throw LedgerError.storageUnavailable
            }
        }
        return try SpendLedger(databaseURL: databaseURL, limitMicros: limitMicros)
    }

    func reserve(requestID: UUID, maximumMicros: Int64) throws -> Int64 {
        guard maximumMicros > 0, maximumMicros <= limitMicros else { throw LedgerError.invalidCost }
        return try Self.withDatabase(at: databaseURL) { database in
            try Self.execute(database, "PRAGMA synchronous=FULL")
            try Self.execute(database, "BEGIN IMMEDIATE")
            do {
                guard try Self.persistedLimit(database) == limitMicros else { throw LedgerError.configurationMismatch }
                guard try !Self.halted(database) else { throw LedgerError.costExceeded }
                try Self.insert(requestID: requestID, maximumMicros: maximumMicros, into: database)
                let total = try Self.total(database)
                guard total >= 0, total <= limitMicros else { throw LedgerError.overBudget }
                try Self.execute(database, "COMMIT")
                return limitMicros - total
            } catch {
                guard sqlite3_exec(database, "ROLLBACK", nil, nil, nil) == SQLITE_OK else {
                    throw LedgerError.storageUnavailable
                }
                throw error
            }
        }
    }

    func recordObservedCost(requestID: UUID, observedMicros: Int64) throws {
        guard observedMicros >= 0 else { throw LedgerError.invalidCost }
        let exceeded = try Self.withDatabase(at: databaseURL) { database in
            try Self.execute(database, "PRAGMA synchronous=FULL")
            try Self.execute(database, "BEGIN IMMEDIATE")
            do {
                guard try Self.persistedLimit(database) == limitMicros else { throw LedgerError.configurationMismatch }
                guard let maximum = try Self.maximum(for: requestID, in: database) else {
                    throw LedgerError.unknownRequest
                }
                try Self.insertObservation(requestID: requestID, observedMicros: observedMicros, into: database)
                let exceeded = observedMicros > maximum
                if exceeded { try Self.execute(database, "UPDATE policy SET halted = 1 WHERE id = 1") }
                try Self.execute(database, "COMMIT")
                return exceeded
            } catch {
                guard sqlite3_exec(database, "ROLLBACK", nil, nil, nil) == SQLITE_OK else {
                    throw LedgerError.storageUnavailable
                }
                throw error
            }
        }
        if exceeded { throw LedgerError.costExceeded }
    }

    func observedTotalMicros() throws -> Int64 {
        try Self.withDatabase(at: databaseURL) { database in
            guard try Self.persistedLimit(database) == limitMicros else { throw LedgerError.configurationMismatch }
            return try Self.observedTotal(database)
        }
    }

    func remainingMicros() throws -> Int64 {
        try Self.withDatabase(at: databaseURL) { database in
            guard try Self.persistedLimit(database) == limitMicros else { throw LedgerError.configurationMismatch }
            guard try !Self.halted(database) else { throw LedgerError.costExceeded }
            let total = try Self.total(database)
            guard total >= 0, total <= limitMicros else { throw LedgerError.overBudget }
            return limitMicros - total
        }
    }

    private static func withDatabase<T>(
        at url: URL, creating: Bool = false, _ operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (creating ? SQLITE_OPEN_CREATE : 0)
        let result = sqlite3_open_v2(url.path, &connection, flags, nil)
        guard result == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw LedgerError.storageUnavailable
        }
        guard let database = connection else { throw LedgerError.storageUnavailable }
        defer { sqlite3_close(database) }
        guard sqlite3_busy_timeout(database, 5_000) == SQLITE_OK else { throw LedgerError.storageUnavailable }
        return try operation(database)
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw LedgerError.storageUnavailable }
    }

    private static func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LedgerError.storageUnavailable
        }
        return statement
    }

    private static func insert(requestID: UUID, maximumMicros: Int64, into database: OpaquePointer) throws {
        let statement = try prepare(database, "INSERT INTO reservations (request_id, max_micros) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try requestID.uuidString.withCString { identifier in
            guard sqlite3_bind_text(statement, 1, identifier, -1, nil) == SQLITE_OK,
                sqlite3_bind_int64(statement, 2, maximumMicros) == SQLITE_OK
            else { throw LedgerError.storageUnavailable }
            let result = sqlite3_step(statement)
            if result & 0xFF == SQLITE_CONSTRAINT { throw LedgerError.duplicate }
            guard result == SQLITE_DONE else { throw LedgerError.storageUnavailable }
        }
    }

    private static func maximum(for requestID: UUID, in database: OpaquePointer) throws -> Int64? {
        let statement = try prepare(database, "SELECT max_micros FROM reservations WHERE request_id = ?")
        defer { sqlite3_finalize(statement) }
        return try requestID.uuidString.withCString { identifier -> Int64? in
            guard sqlite3_bind_text(statement, 1, identifier, -1, nil) == SQLITE_OK else {
                throw LedgerError.storageUnavailable
            }
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw LedgerError.storageUnavailable }
            return sqlite3_column_int64(statement, 0)
        }
    }

    private static func insertObservation(requestID: UUID, observedMicros: Int64, into database: OpaquePointer) throws {
        let statement = try prepare(database, "INSERT INTO observations (request_id, observed_micros) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try requestID.uuidString.withCString { identifier in
            guard sqlite3_bind_text(statement, 1, identifier, -1, nil) == SQLITE_OK,
                sqlite3_bind_int64(statement, 2, observedMicros) == SQLITE_OK
            else { throw LedgerError.storageUnavailable }
            let result = sqlite3_step(statement)
            if result & 0xFF == SQLITE_CONSTRAINT { throw LedgerError.duplicate }
            guard result == SQLITE_DONE else { throw LedgerError.storageUnavailable }
        }
    }

    private static func halted(_ database: OpaquePointer) throws -> Bool {
        let statement = try prepare(database, "SELECT halted FROM policy WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.storageUnavailable }
        let value = sqlite3_column_int(statement, 0)
        guard value == 0 || value == 1 else { throw LedgerError.storageUnavailable }
        return value == 1
    }

    private static func observedTotal(_ database: OpaquePointer) throws -> Int64 {
        let statement = try prepare(database, "SELECT COALESCE(SUM(observed_micros), 0) FROM observations")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.storageUnavailable }
        return sqlite3_column_int64(statement, 0)
    }

    private static func persistedLimit(_ database: OpaquePointer) throws -> Int64 {
        let statement = try prepare(database, "SELECT limit_micros FROM policy WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.storageUnavailable }
        let value = sqlite3_column_int64(statement, 0)
        guard (1...10_000_000).contains(value) else { throw LedgerError.storageUnavailable }
        return value
    }

    private static func total(_ database: OpaquePointer) throws -> Int64 {
        let statement = try prepare(database, "SELECT COALESCE(SUM(max_micros), 0) FROM reservations")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.storageUnavailable }
        return sqlite3_column_int64(statement, 0)
    }
}
