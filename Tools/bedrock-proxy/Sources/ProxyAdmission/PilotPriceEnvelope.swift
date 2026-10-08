import Foundation

enum PilotPriceError: Error, Equatable {
    case unavailable, invalidOutput, tooExpensive
}

struct PilotPriceEvidence: Sendable {
    let modelID: String
    let region: String
    let tier: String
    let inputMicrosPerMillion: Int64
    let outputMicrosPerMillion: Int64
    let otherMaximumMicros: Int64?
    let verifiedAt: Date
}

struct PilotCostEnvelope: Sendable {
    let worstCaseMicros: Int64
    let reservationMicros: Int64
}

enum PilotPriceEnvelope {
    private static let contextTokens: Int64 = 300_000
    private static let perCallMaximumMicros: Int64 = 50_000

    static func quote(
        maxOutputTokens: Int,
        evidence: PilotPriceEvidence? = nil,
        now: Date = Date()
    ) throws -> PilotCostEnvelope {
        guard (1...512).contains(maxOutputTokens) else { throw PilotPriceError.invalidOutput }
        guard let evidence,
            evidence.modelID == "amazon.nova-lite-v1:0", evidence.region == "us-east-1",
            evidence.tier == "standard", evidence.inputMicrosPerMillion > 0,
            evidence.outputMicrosPerMillion > 0,
            let otherMaximumMicros = evidence.otherMaximumMicros, otherMaximumMicros >= 0,
            (0...300).contains(now.timeIntervalSince(evidence.verifiedAt))
        else { throw PilotPriceError.unavailable }

        let input = try roundedMicros(contextTokens, rate: evidence.inputMicrosPerMillion)
        let output = try roundedMicros(Int64(maxOutputTokens), rate: evidence.outputMicrosPerMillion)
        let (modelCost, firstOverflow) = input.addingReportingOverflow(output)
        guard !firstOverflow else { throw PilotPriceError.unavailable }
        let (worstCase, secondOverflow) = modelCost.addingReportingOverflow(otherMaximumMicros)
        guard !secondOverflow else { throw PilotPriceError.unavailable }
        guard worstCase <= perCallMaximumMicros else { throw PilotPriceError.tooExpensive }
        return PilotCostEnvelope(worstCaseMicros: worstCase, reservationMicros: perCallMaximumMicros)
    }

    private static func roundedMicros(_ tokens: Int64, rate: Int64) throws -> Int64 {
        let (product, overflow) = tokens.multipliedReportingOverflow(by: rate)
        guard !overflow else { throw PilotPriceError.unavailable }
        let quotient = product / 1_000_000
        return quotient + (product % 1_000_000 == 0 ? 0 : 1)
    }
}
