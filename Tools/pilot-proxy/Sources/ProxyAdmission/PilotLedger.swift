import Foundation

/// The spend ledger the pilot proxy relies on. `SpendLedger` (SQLite, Apple platforms and tests) and
/// `TransactionalLedger` (Firestore on Cloud Run) both satisfy it, so admission never knows the storage.
protocol PilotLedger: Sendable {
    func reserve(requestID: UUID, pilotID: UUID, maximumMicros: Int64) async throws -> Int64
    func recordObservedCost(requestID: UUID, observedMicros: Int64) async throws
    func observedTotalMicros() async throws -> Int64
    func remainingMicros() async throws -> Int64
}

/// Everything the ledger knows, in one small value so a single conditional write can change it atomically.
struct LedgerState: Equatable, Sendable {
    static let requestsPerHour = 40
    static let window: Int64 = 3_600

    var limitMicros: Int64
    var halted = false
    var reservedMicros: Int64 = 0
    var observedMicros: Int64 = 0
    /// Reservation timestamps (epoch seconds) per pilot, pruned to the rate window.
    var recent: [String: [Int64]] = [:]

    /// Applies one reservation or throws without changing anything the caller may commit.
    mutating func reserve(pilot: UUID, maximumMicros: Int64, now: Int64) throws -> Int64 {
        guard !halted else { throw LedgerError.costExceeded }
        var times = (recent[pilot.uuidString] ?? []).filter { $0 > now - Self.window }
        times.append(now)
        guard times.count <= Self.requestsPerHour else { throw LedgerError.rateLimited }
        let (total, overflow) = reservedMicros.addingReportingOverflow(maximumMicros)
        guard !overflow, total >= 0, total <= limitMicros else { throw LedgerError.overBudget }
        reservedMicros = total
        recent[pilot.uuidString] = times
        return limitMicros - total
    }

    /// Records a charge. Returns true when it exceeded its hold, which also halts the ledger.
    mutating func observe(_ observed: Int64, hold: Int64) -> Bool {
        let (total, overflow) = observedMicros.addingReportingOverflow(observed)
        observedMicros = overflow ? Int64.max : total
        let exceeded = observed > hold || overflow
        if exceeded { halted = true }
        return exceeded
    }
}

enum LedgerStoreError: Error, Equatable {
    /// Another writer changed the state after it was read; retry from a fresh read.
    case conflict
}

/// Minimal conditional-write storage. A real implementation must make each commit atomic: the state write
/// succeeds only if `version` is still current, and the per-request document is created only if absent
/// (throwing `LedgerError.duplicate` otherwise).
protocol LedgerDocumentStore: Sendable {
    func load() async throws -> (state: LedgerState, version: String)?
    func create(_ state: LedgerState) async throws
    func hold(for requestID: UUID) async throws -> Int64?
    func commitReservation(
        requestID: UUID, hold: Int64, state: LedgerState, version: String
    ) async throws
    func commitObservation(
        requestID: UUID, observed: Int64, state: LedgerState, version: String
    ) async throws
}

actor TransactionalLedger: PilotLedger {
    private static let attempts = 6
    private let store: any LedgerDocumentStore
    private let limitMicros: Int64
    private let clock: @Sendable () -> Int64

    init(
        store: any LedgerDocumentStore, limitMicros: Int64 = 10_000_000,
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    ) throws {
        guard (1...10_000_000).contains(limitMicros) else { throw LedgerError.invalidCost }
        self.store = store
        self.limitMicros = limitMicros
        self.clock = clock
    }

    /// Creates the ledger once. Throws if one already exists, so a restart never resets spend.
    func bootstrap() async throws {
        guard try await store.load() == nil else { throw LedgerError.storageUnavailable }
        try await store.create(LedgerState(limitMicros: limitMicros))
    }

    func reserve(requestID: UUID, pilotID: UUID, maximumMicros: Int64) async throws -> Int64 {
        guard maximumMicros > 0, maximumMicros <= limitMicros else { throw LedgerError.invalidCost }
        guard pilotID.uuidString != "00000000-0000-0000-0000-000000000000" else { throw LedgerError.invalidPilot }
        for _ in 0..<Self.attempts {
            var (state, version) = try await current()
            let remaining = try state.reserve(pilot: pilotID, maximumMicros: maximumMicros, now: clock())
            do {
                try await store.commitReservation(
                    requestID: requestID, hold: maximumMicros, state: state, version: version
                )
                return remaining
            } catch LedgerStoreError.conflict {
                continue
            }
        }
        throw LedgerError.storageUnavailable
    }

    func recordObservedCost(requestID: UUID, observedMicros: Int64) async throws {
        guard observedMicros >= 0 else { throw LedgerError.invalidCost }
        for _ in 0..<Self.attempts {
            var (state, version) = try await current()
            guard let hold = try await store.hold(for: requestID) else { throw LedgerError.unknownRequest }
            let exceeded = state.observe(observedMicros, hold: hold)
            do {
                try await store.commitObservation(
                    requestID: requestID, observed: observedMicros, state: state, version: version
                )
                if exceeded { throw LedgerError.costExceeded }
                return
            } catch LedgerStoreError.conflict {
                continue
            }
        }
        throw LedgerError.storageUnavailable
    }

    func observedTotalMicros() async throws -> Int64 {
        try await current().state.observedMicros
    }

    func remainingMicros() async throws -> Int64 {
        let state = try await current().state
        guard !state.halted else { throw LedgerError.costExceeded }
        return limitMicros - state.reservedMicros
    }

    private func current() async throws -> (state: LedgerState, version: String) {
        guard let loaded = try await store.load() else { throw LedgerError.storageUnavailable }
        guard loaded.state.limitMicros == limitMicros else { throw LedgerError.configurationMismatch }
        return loaded
    }
}
