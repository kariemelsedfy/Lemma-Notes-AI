import Foundation

/// Sends one admitted request to the model and returns its validated-shape reply. The real
/// implementation is the Gemini HTTPS client; tests use fakes.
protocol PilotModelTransport: Sendable {
    func complete(_ request: AdmittedRequest) async throws -> GeminiReply
}

struct PilotAnswer: Sendable {
    let requestID: UUID
    let specJSON: Data
    let heldMicros: Int64
    let remainingMicros: Int64
    let observedMicros: Int64
}

actor PilotAdmission {
    private let admission: AdmissionGate
    private let ledger: SpendLedger
    private var inFlight = false

    init(admission: AdmissionGate, ledger: SpendLedger) {
        self.admission = admission
        self.ledger = ledger
    }

    func invoke(_ body: Data, proof: String?, transport: any PilotModelTransport) async throws -> PilotAnswer {
        let validated = try await admission.validate(body, proof: proof)
        guard let pilotID = UUID(uuidString: validated.identity.subjectID) else {
            throw AdmissionError.unauthorized
        }
        let quote = try PilotPriceEnvelope.quote(maxOutputTokens: validated.request.maxOutputTokens)
        guard !inFlight else { throw AdmissionError.busy }
        try Task.checkCancellation()
        inFlight = true
        defer { inFlight = false }
        let remaining = try await ledger.reserve(
            requestID: validated.request.requestID, pilotID: pilotID,
            maximumMicros: quote.reservationMicros
        )
        try Task.checkCancellation()
        // A failure after this point keeps the hold: the request may have been billed.
        let reply: GeminiReply
        do {
            reply = try await transport.complete(validated.request)
        } catch let billed as GeminiBilledFailure {
            // Google billed a reply we refuse to use: record the real charge, then fail with the reason.
            if let cost = billed.costMicros {
                try await ledger.recordObservedCost(requestID: validated.request.requestID, observedMicros: cost)
            }
            throw billed.reason
        }
        guard let observed = reply.costMicros else { throw LedgerError.invalidCost }
        try await ledger.recordObservedCost(requestID: validated.request.requestID, observedMicros: observed)
        return PilotAnswer(
            requestID: validated.request.requestID, specJSON: reply.specJSON,
            heldMicros: quote.reservationMicros, remainingMicros: remaining, observedMicros: observed
        )
    }
}
