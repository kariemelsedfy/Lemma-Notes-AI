import Foundation
import SQLite3
import XCTest

@testable import ProxyAdmission

final class RateLedgerTests: XCTestCase {
    private static let pilotID = UUID()

    func testFortyActionsPerHourSurviveRestartWithoutLimitingAnotherPilot() async throws {
        let database = try temporaryDatabase()
        let ledger = try SpendLedger.bootstrap(databaseURL: database)
        let firstRequest = UUID()
        _ = try await ledger.reserve(requestID: firstRequest, pilotID: Self.pilotID, maximumMicros: 1)
        for _ in 1..<40 {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 1)
        }
        await expect(.duplicate, ledger, requestID: firstRequest, pilotID: Self.pilotID)
        await expect(.rateLimited, ledger, requestID: UUID(), pilotID: Self.pilotID)

        let secondPilot = UUID()
        _ = try await ledger.reserve(requestID: UUID(), pilotID: secondPilot, maximumMicros: 1)
        let reopened = try SpendLedger(databaseURL: database)
        await expect(.rateLimited, reopened, requestID: UUID(), pilotID: Self.pilotID)
        let remaining = try await reopened.remainingMicros()
        XCTAssertEqual(remaining, 10_000_000 - 41)
    }

    func testRollingHourReopensAfterPreviousSyntheticRequestsAgeOut() async throws {
        let database = try temporaryDatabase()
        let ledger = try SpendLedger.bootstrap(databaseURL: database)
        for _ in 0..<40 {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 1)
        }
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else {
            return XCTFail("Could not open synthetic ledger clock fixture")
        }
        XCTAssertEqual(
            sqlite3_exec(connection, "UPDATE reservations SET created_at = unixepoch() - 3601", nil, nil, nil),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_close(connection), SQLITE_OK)
        let remaining = try await ledger.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 1)
        XCTAssertEqual(remaining, 10_000_000 - 41)
    }

    func testConcurrentFortiethAndFortyFirstActionsAreAtomicAcrossConnections() async throws {
        let database = try temporaryDatabase()
        let first = try SpendLedger.bootstrap(databaseURL: database)
        let second = try SpendLedger(databaseURL: database)
        for _ in 0..<39 {
            _ = try await first.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 1)
        }
        let actions = [
            Task { try await first.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 1) },
            Task { try await second.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 1) },
        ]
        var accepted = 0
        var refused = 0
        for action in actions {
            do {
                _ = try await action.value
                accepted += 1
            } catch let error as LedgerError {
                XCTAssertEqual(error, .rateLimited)
                refused += 1
            }
        }
        XCTAssertEqual(accepted, 1)
        XCTAssertEqual(refused, 1)
        let remaining = try await second.remainingMicros()
        XCTAssertEqual(remaining, 10_000_000 - 40)
    }

    func testInvalidPilotIdentifierFailsBeforeItConsumesMoney() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100)
        let zero = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        await expect(.invalidPilot, ledger, requestID: UUID(), pilotID: zero)
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(remaining, 100)
    }

    func testOverBudgetAttemptsNeverConsumeHourlyAllowance() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100)
        _ = try await ledger.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 100)
        for _ in 0..<41 {
            await expect(.overBudget, ledger, requestID: UUID(), pilotID: Self.pilotID)
        }
    }

    func testPreRateLedgerSchemaFailsClosedRatherThanResettingReservations() throws {
        let database = try temporaryDatabase()
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else {
            return XCTFail("Could not construct synthetic older ledger")
        }
        let legacy = """
            CREATE TABLE policy (id INTEGER PRIMARY KEY, limit_micros INTEGER, halted INTEGER);
            INSERT INTO policy VALUES (1, 100, 0);
            CREATE TABLE reservations (request_id TEXT PRIMARY KEY, max_micros INTEGER);
            INSERT INTO reservations VALUES ('synthetic-request', 80);
            CREATE TABLE observations (request_id TEXT PRIMARY KEY, observed_micros INTEGER);
            """
        XCTAssertEqual(sqlite3_exec(connection, legacy, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(connection), SQLITE_OK)
        XCTAssertThrowsError(try SpendLedger(databaseURL: database, limitMicros: 100)) {
            XCTAssertEqual($0 as? LedgerError, .storageUnavailable)
        }
    }

    private func temporaryDatabase() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("spend.sqlite")
    }

    private func expect(_ failure: LedgerError, _ ledger: SpendLedger, requestID: UUID, pilotID: UUID) async {
        do {
            _ = try await ledger.reserve(requestID: requestID, pilotID: pilotID, maximumMicros: 1)
            XCTFail("Invalid pilot or hourly request was accepted")
        } catch let error as LedgerError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free rate error")
        }
    }
}
