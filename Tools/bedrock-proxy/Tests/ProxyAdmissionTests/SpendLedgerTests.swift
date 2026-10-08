import Foundation
import XCTest

@testable import ProxyAdmission

final class SpendLedgerTests: XCTestCase {
    private static let pilotID = UUID()

    func testReservationPersistsAfterReopeningWithoutAResult() async throws {
        let database = try temporaryDatabase()
        let first = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)
        let remaining = try await first.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 30)
        XCTAssertEqual(remaining, 70)

        let reopened = try SpendLedger(databaseURL: database, limitMicros: 100)
        let stillReserved = try await reopened.remainingMicros()
        XCTAssertEqual(stillReserved, 70, "An unknown model charge must not be refunded by a restart")
    }

    func testLowerObservedCostIsAuditedButNeverRefundsTheReservation() async throws {
        let database = try temporaryDatabase()
        let ledger = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)
        let requestID = UUID()
        _ = try await ledger.reserve(requestID: requestID, pilotID: Self.pilotID, maximumMicros: 70)
        try await ledger.recordObservedCost(requestID: requestID, observedMicros: 20)
        let observed = try await ledger.observedTotalMicros()
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(observed, 20)
        XCTAssertEqual(remaining, 30)

        let reopened = try SpendLedger(databaseURL: database, limitMicros: 100)
        let persistedObserved = try await reopened.observedTotalMicros()
        let persistedRemaining = try await reopened.remainingMicros()
        XCTAssertEqual(persistedObserved, 20)
        XCTAssertEqual(persistedRemaining, 30)
    }

    func testUnknownDuplicateAndInvalidObservationsDoNotReleaseBudget() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100)
        let requestID = UUID()
        _ = try await ledger.reserve(requestID: requestID, pilotID: Self.pilotID, maximumMicros: 60)
        await expectObservation(.unknownRequest, ledger, requestID: UUID(), cost: 10)
        await expectObservation(.invalidCost, ledger, requestID: requestID, cost: -1)
        try await ledger.recordObservedCost(requestID: requestID, observedMicros: 20)
        await expectObservation(.duplicate, ledger, requestID: requestID, cost: 20)
        await expectObservation(.duplicate, ledger, requestID: requestID, cost: 21)
        let observed = try await ledger.observedTotalMicros()
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(observed, 20)
        XCTAssertEqual(remaining, 40)
    }

    func testCostAboveReservationLocksEveryConnectionAndSurvivesReopen() async throws {
        let database = try temporaryDatabase()
        let first = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)
        let second = try SpendLedger(databaseURL: database, limitMicros: 100)
        let requestID = UUID()
        _ = try await first.reserve(requestID: requestID, pilotID: Self.pilotID, maximumMicros: 30)
        await expectObservation(.costExceeded, first, requestID: requestID, cost: 31)
        let observed = try await second.observedTotalMicros()
        XCTAssertEqual(observed, 31)
        await expect(.costExceeded, second, requestID: UUID(), maximumMicros: 1)
        let reopened = try SpendLedger(databaseURL: database, limitMicros: 100)
        await expect(.costExceeded, reopened, requestID: UUID(), maximumMicros: 1)
        do {
            _ = try await reopened.remainingMicros()
            XCTFail("A locked ledger advertised spendable headroom")
        } catch let error as LedgerError {
            XCTAssertEqual(error, .costExceeded)
        }
    }

    func testDuplicateIDsAndRequestsOverTheCeilingAreDenied() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100)
        let first = UUID()
        _ = try await ledger.reserve(requestID: first, pilotID: Self.pilotID, maximumMicros: 70)
        await expect(.duplicate, ledger, requestID: first, maximumMicros: 1)
        let lastAllowed = try await ledger.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 30)
        XCTAssertEqual(lastAllowed, 0)
        await expect(.overBudget, ledger, requestID: UUID(), maximumMicros: 1)
    }

    func testTwoIndependentConnectionsCannotBothReserveTheLastBudget() async throws {
        let database = try temporaryDatabase()
        let first = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)
        let second = try SpendLedger(databaseURL: database, limitMicros: 100)
        let pilotID = Self.pilotID
        let operations = [
            Task { try await first.reserve(requestID: UUID(), pilotID: pilotID, maximumMicros: 60) },
            Task { try await second.reserve(requestID: UUID(), pilotID: pilotID, maximumMicros: 60) },
        ]
        var accepted = 0
        var denied = 0
        for operation in operations {
            do {
                _ = try await operation.value
                accepted += 1
            } catch let error as LedgerError {
                XCTAssertEqual(error, .overBudget)
                denied += 1
            }
        }
        XCTAssertEqual(accepted, 1)
        XCTAssertEqual(denied, 1)
        let remaining = try await first.remainingMicros()
        XCTAssertEqual(remaining, 40)
    }

    func testInvalidCostsCapsAndUnavailableStorageFailClosed() async throws {
        let database = try temporaryDatabase()
        XCTAssertThrowsError(try SpendLedger(databaseURL: database, limitMicros: 10_000_001)) {
            XCTAssertEqual($0 as? LedgerError, .invalidCost)
        }
        let ledger = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 10_000_000)
        for invalid in [Int64(0), -1, .max] {
            await expect(.invalidCost, ledger, requestID: UUID(), maximumMicros: invalid)
        }
        let missingParent = database.deletingLastPathComponent().appendingPathComponent("missing/spend.sqlite")
        XCTAssertThrowsError(try SpendLedger(databaseURL: missingParent)) {
            XCTAssertEqual($0 as? LedgerError, .storageUnavailable)
        }
    }

    func testReopeningWithAChangedCeilingFailsClosed() async throws {
        let database = try temporaryDatabase()
        let first = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)
        _ = try await first.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 80)

        XCTAssertThrowsError(try SpendLedger(databaseURL: database, limitMicros: 10_000_000)) {
            XCTAssertEqual($0 as? LedgerError, .configurationMismatch)
        }
        XCTAssertThrowsError(try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)) {
            XCTAssertEqual($0 as? LedgerError, .storageUnavailable)
        }
    }

    func testMissingLedgerCannotBeSilentlyRecreated() async throws {
        let database = try temporaryDatabase()
        let first = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 100)
        _ = try await first.reserve(requestID: UUID(), pilotID: Self.pilotID, maximumMicros: 80)
        let saved = database.deletingLastPathComponent().appendingPathComponent("saved.sqlite")
        try FileManager.default.moveItem(at: database, to: saved)

        XCTAssertThrowsError(try SpendLedger(databaseURL: database, limitMicros: 100)) {
            XCTAssertEqual($0 as? LedgerError, .storageUnavailable)
        }
    }

    func testNewLedgerFileIsPrivateToTheLocalMacUser() throws {
        let database = try temporaryDatabase()
        _ = try SpendLedger.bootstrap(databaseURL: database)
        let attributes = try FileManager.default.attributesOfItem(atPath: database.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    private func temporaryDatabase() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("spend.sqlite")
    }

    private func expectObservation(_ failure: LedgerError, _ ledger: SpendLedger, requestID: UUID, cost: Int64) async {
        do {
            try await ledger.recordObservedCost(requestID: requestID, observedMicros: cost)
            XCTFail("Invalid observation was accepted")
        } catch let error as LedgerError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free observation error")
        }
    }

    private func expect(_ failure: LedgerError, _ ledger: SpendLedger, requestID: UUID, maximumMicros: Int64) async {
        do {
            _ = try await ledger.reserve(requestID: requestID, pilotID: Self.pilotID, maximumMicros: maximumMicros)
            XCTFail("Invalid reservation was accepted")
        } catch let error as LedgerError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free ledger error")
        }
    }
}
