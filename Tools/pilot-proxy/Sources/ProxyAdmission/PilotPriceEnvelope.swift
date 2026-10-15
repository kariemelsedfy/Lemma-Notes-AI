import Foundation

enum PilotPriceError: Error, Equatable {
    case unavailable, invalidOutput, tooExpensive
}

struct PilotCostEnvelope: Sendable {
    let worstCaseMicros: Int64
    let reservationMicros: Int64
}

/// Quotes one request against the published Gemini rates in `GeminiPilot` (ADR-027).
enum PilotPriceEnvelope {
    private static let perCallMaximumMicros: Int64 = 50_000

    static func quote(maxOutputTokens: Int) throws -> PilotCostEnvelope {
        guard (1...GeminiPilot.maxOutputTokens).contains(maxOutputTokens) else { throw PilotPriceError.invalidOutput }
        guard let worstCase = GeminiPilot.worstCaseMicros(maxOutputTokens: maxOutputTokens) else {
            throw PilotPriceError.unavailable
        }
        guard worstCase <= perCallMaximumMicros else { throw PilotPriceError.tooExpensive }
        return PilotCostEnvelope(worstCaseMicros: worstCase, reservationMicros: perCallMaximumMicros)
    }
}
