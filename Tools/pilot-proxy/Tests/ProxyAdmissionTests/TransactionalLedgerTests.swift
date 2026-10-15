import Foundation
import XCTest

@testable import ProxyAdmission

final class TransactionalLedgerTests: XCTestCase {
    private let pilot = UUID()

    func testReserveHoldsAndRemainingShrinks() async throws {
        let ledger = try await ready(limit: 100_000)
        let left = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 50_000)
        XCTAssertEqual(left, 50_000)
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(remaining, 50_000)
    }

    func testOverBudgetDuplicateAndInvalidPilotNeverChangeSpend() async throws {
        let ledger = try await ready(limit: 100_000)
        let id = UUID()
        _ = try await ledger.reserve(requestID: id, pilotID: pilot, maximumMicros: 50_000)
        await expect(.duplicate) { _ = try await ledger.reserve(requestID: id, pilotID: pilot, maximumMicros: 1) }
        await expect(.overBudget) {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 60_000)
        }
        await expect(.invalidPilot) {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: UUID(uuid: UUID_NULL), maximumMicros: 1)
        }
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(remaining, 50_000)
    }

    func testRateLimitDeniesFortyFirstReservationInAnHourAndRecovers() async throws {
        let clock = Clock(1_000)
        let ledger = try await ready(limit: 10_000_000, clock: clock)
        for _ in 0..<40 { _ = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 10) }
        await expect(.rateLimited) {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 10)
        }
        await clock.advance(3_601)
        _ = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 10)
    }

    func testObservedCostIsRecordedOnceAndAnOverrunHaltsTheLedger() async throws {
        let ledger = try await ready(limit: 100_000)
        let first = UUID()
        _ = try await ledger.reserve(requestID: first, pilotID: pilot, maximumMicros: 10_000)
        try await ledger.recordObservedCost(requestID: first, observedMicros: 1_250)
        let observed = try await ledger.observedTotalMicros()
        XCTAssertEqual(observed, 1_250)
        await expect(.duplicate) { try await ledger.recordObservedCost(requestID: first, observedMicros: 1) }
        await expect(.unknownRequest) { try await ledger.recordObservedCost(requestID: UUID(), observedMicros: 1) }
        let second = UUID()
        _ = try await ledger.reserve(requestID: second, pilotID: pilot, maximumMicros: 1_000)
        await expect(.costExceeded) { try await ledger.recordObservedCost(requestID: second, observedMicros: 1_001) }
        await expect(.costExceeded) { _ = try await ledger.remainingMicros() }
        await expect(.costExceeded) {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 1)
        }
    }

    func testTwoLedgersOnOneStoreAllowOnlyOneOfTwoHalfBudgetReserves() async throws {
        let store = MemoryStore()
        let first = try TransactionalLedger(store: store, limitMicros: 100_000)
        let second = try TransactionalLedger(store: store, limitMicros: 100_000)
        try await first.bootstrap()
        await store.forceConflicts(3)
        let id = pilot
        async let firstTry = Self.attempt(first, id, 60_000)
        async let secondTry = Self.attempt(second, id, 60_000)
        let results = await [firstTry, secondTry]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let remaining = try await first.remainingMicros()
        XCTAssertEqual(remaining, 40_000)
    }

    func testPersistentConflictsFailClosedAndNothingIsHeld() async throws {
        let store = MemoryStore()
        let ledger = try TransactionalLedger(store: store, limitMicros: 100_000)
        try await ledger.bootstrap()
        await store.forceConflicts(100)
        await expect(.storageUnavailable) {
            _ = try await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: 10)
        }
        await store.forceConflicts(0)
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(remaining, 100_000)
    }

    func testBootstrapNeverResetsAndALimitMismatchIsRefused() async throws {
        let store = MemoryStore()
        let ledger = try TransactionalLedger(store: store, limitMicros: 100_000)
        try await ledger.bootstrap()
        await expect(.storageUnavailable) { try await ledger.bootstrap() }
        let other = try TransactionalLedger(store: store, limitMicros: 200_000)
        await expect(.configurationMismatch) { _ = try await other.remainingMicros() }
        let missing = try TransactionalLedger(store: MemoryStore(), limitMicros: 100_000)
        await expect(.storageUnavailable) { _ = try await missing.remainingMicros() }
    }

    private static func attempt(_ ledger: TransactionalLedger, _ pilot: UUID, _ micros: Int64) async -> Bool {
        (try? await ledger.reserve(requestID: UUID(), pilotID: pilot, maximumMicros: micros)) != nil
    }

    private func ready(limit: Int64, clock: Clock = Clock(1_000)) async throws -> TransactionalLedger {
        let ledger = try TransactionalLedger(store: MemoryStore(), limitMicros: limit) { clock.now }
        try await ledger.bootstrap()
        return ledger
    }

    private func expect(_ failure: LedgerError, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("Expected \(failure)")
        } catch let error as LedgerError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free ledger error")
        }
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ value: Int64) { self.value = value }
    var now: Int64 { lock.withLock { value } }
    func advance(_ seconds: Int64) async { lock.withLock { value += seconds } }
}

/// Mimics Firestore's conditional writes: a state commit needs the version it read, and per-request
/// documents are create-only.
private actor MemoryStore: LedgerDocumentStore {
    private var state: LedgerState?
    private var version = 0
    private var holds: [UUID: Int64] = [:]
    private var observations: Set<UUID> = []
    private var conflicts = 0

    func forceConflicts(_ count: Int) { conflicts = count }

    func load() -> (state: LedgerState, version: String)? {
        state.map { ($0, String(version)) }
    }

    func create(_ state: LedgerState) { self.state = state }

    func hold(for requestID: UUID) -> Int64? { holds[requestID] }

    func commitReservation(requestID: UUID, hold: Int64, state: LedgerState, version: String) throws {
        try checkVersion(version)
        guard holds[requestID] == nil else { throw LedgerError.duplicate }
        holds[requestID] = hold
        write(state)
    }

    func commitObservation(requestID: UUID, observed: Int64, state: LedgerState, version: String) throws {
        try checkVersion(version)
        guard observations.insert(requestID).inserted else { throw LedgerError.duplicate }
        write(state)
    }

    private func checkVersion(_ presented: String) throws {
        if conflicts > 0 {
            conflicts -= 1
            self.version += 1
            throw LedgerStoreError.conflict
        }
        guard presented == String(version) else { throw LedgerStoreError.conflict }
    }

    private func write(_ newState: LedgerState) {
        state = newState
        version += 1
    }
}
