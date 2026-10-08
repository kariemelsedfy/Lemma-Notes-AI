import Foundation

struct PilotReservation: Sendable {
    let requestID: UUID
    let heldMicros: Int64
    let remainingMicros: Int64
}

actor PilotAdmission {
    private let admission: AdmissionGate
    private let ledger: SpendLedger
    private let price: @Sendable () async -> PilotPriceEvidence?
    private var inFlight = false

    init(
        admission: AdmissionGate,
        ledger: SpendLedger,
        price: @escaping @Sendable () async -> PilotPriceEvidence? = { nil }
    ) {
        self.admission = admission
        self.ledger = ledger
        self.price = price
    }

    func invoke(_ body: Data, proof: String?, transport: any ProxyTransport) async throws -> PilotReservation {
        let validated = try await admission.validate(body, proof: proof)
        guard let pilotID = UUID(uuidString: validated.identity.subjectID) else {
            throw AdmissionError.unauthorized
        }
        let evidence = await price()
        try Task.checkCancellation()
        let quote = try PilotPriceEnvelope.quote(
            maxOutputTokens: validated.request.maxOutputTokens, evidence: evidence
        )
        guard !inFlight else { throw AdmissionError.busy }
        try Task.checkCancellation()
        inFlight = true
        defer { inFlight = false }
        let remaining = try await ledger.reserve(
            requestID: validated.request.requestID, pilotID: pilotID,
            maximumMicros: quote.reservationMicros
        )
        try Task.checkCancellation()
        try await transport.send(validated.request)
        return PilotReservation(
            requestID: validated.request.requestID,
            heldMicros: quote.reservationMicros,
            remainingMicros: remaining
        )
    }
}
