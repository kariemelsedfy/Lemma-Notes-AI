import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotPriceEnvelopeTests: XCTestCase {
    func testAbsentPriceEvidenceDeclinesWithoutAReservation() {
        expect(.unavailable, evidence: nil)
    }

    func testSyntheticStandardQuoteBoundsTheWholeContextAndHoldsFiveCents() throws {
        let quote = try PilotPriceEnvelope.quote(maxOutputTokens: 512, evidence: evidence())
        XCTAssertEqual(quote.worstCaseMicros, 19_123)
        XCTAssertEqual(quote.reservationMicros, 50_000)
    }

    func testWrongModelRegionTierOrAgeDeclines() {
        let current = Date()
        expect(.unavailable, evidence: evidence(modelID: "unknown"), now: current)
        expect(.unavailable, evidence: evidence(region: "eu-west-3"), now: current)
        expect(.unavailable, evidence: evidence(tier: "priority"), now: current)
        expect(.unavailable, evidence: evidence(verifiedAt: current.addingTimeInterval(-301)), now: current)
        expect(.unavailable, evidence: evidence(verifiedAt: current.addingTimeInterval(10)), now: current)
    }

    func testUnknownOrInvalidComponentsDecline() {
        expect(.unavailable, evidence: evidence(otherMaximumMicros: nil))
        expect(.unavailable, evidence: evidence(otherMaximumMicros: -1))
        expect(.unavailable, evidence: evidence(inputMicrosPerMillion: 0))
        expect(.unavailable, evidence: evidence(outputMicrosPerMillion: -1))
    }

    func testOutputCountAndExpensiveOrOverflowingQuotesDecline() {
        expect(.invalidOutput, evidence: evidence(), output: 0)
        expect(.invalidOutput, evidence: evidence(), output: 513)
        expect(.tooExpensive, evidence: evidence(inputMicrosPerMillion: 200_000))
        expect(.unavailable, evidence: evidence(inputMicrosPerMillion: .max))
        expect(.unavailable, evidence: evidence(outputMicrosPerMillion: .max))
        expect(.unavailable, evidence: evidence(otherMaximumMicros: .max))
    }

    func testTinyFractionalTokenCostsRoundUpInsteadOfDown() throws {
        let quote = try PilotPriceEnvelope.quote(
            maxOutputTokens: 1,
            evidence: evidence(inputMicrosPerMillion: 1, outputMicrosPerMillion: 1, otherMaximumMicros: 0)
        )
        XCTAssertEqual(quote.worstCaseMicros, 2)
        XCTAssertEqual(quote.reservationMicros, 50_000)
    }

    private func evidence(
        modelID: String = "amazon.nova-lite-v1:0",
        region: String = "us-east-1",
        tier: String = "standard",
        inputMicrosPerMillion: Int64 = 60_000,
        outputMicrosPerMillion: Int64 = 240_000,
        otherMaximumMicros: Int64? = 1_000,
        verifiedAt: Date = Date()
    ) -> PilotPriceEvidence {
        PilotPriceEvidence(
            modelID: modelID, region: region, tier: tier,
            inputMicrosPerMillion: inputMicrosPerMillion,
            outputMicrosPerMillion: outputMicrosPerMillion,
            otherMaximumMicros: otherMaximumMicros, verifiedAt: verifiedAt
        )
    }

    private func expect(
        _ failure: PilotPriceError,
        evidence: PilotPriceEvidence?,
        output: Int = 512,
        now: Date = Date()
    ) {
        do {
            _ = try PilotPriceEnvelope.quote(maxOutputTokens: output, evidence: evidence, now: now)
            XCTFail("Unverified or expensive price was accepted")
        } catch let error as PilotPriceError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free price error")
        }
    }
}
