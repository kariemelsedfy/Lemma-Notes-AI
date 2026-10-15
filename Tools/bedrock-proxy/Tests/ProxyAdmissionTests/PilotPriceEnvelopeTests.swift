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

final class CatalogTokenRatesTests: XCTestCase {
    func testGroundedInputAndOutputRowsYieldOnlyTokenRateObservation() throws {
        let checkedAt = try date()
        let input = try row(kind: "Input tokens", usd: "0.0000600000")
        let output = try row(kind: "Output tokens", usd: "0.0002400000")
        let rates = try XCTUnwrap(parse([input, output], at: checkedAt))
        XCTAssertEqual(rates.modelLabel, "Nova Lite")
        XCTAssertEqual(rates.regionCode, "us-east-1")
        XCTAssertEqual(rates.inputMicrosPerMillion, 60_000)
        XCTAssertEqual(rates.outputMicrosPerMillion, 240_000)
        XCTAssertThrowsError(try PilotPriceEnvelope.quote(maxOutputTokens: 512)) { error in
            XCTAssertEqual(error as? PilotPriceError, .unavailable)
        }
    }

    func testMissingDuplicateAndExtraChargeRowsFailClosed() throws {
        let checkedAt = try date()
        let input = try row(kind: "Input tokens", usd: "0.0000600000")
        let output = try row(kind: "Output tokens", usd: "0.0002400000")
        XCTAssertNil(parse([input], at: checkedAt))
        XCTAssertNil(parse([input, input, output], at: checkedAt))
        let extraCharge = try row(kind: "Image tokens", usd: "0.01")
        XCTAssertNil(parse([input, output, extraCharge], at: checkedAt))
        let extraDimension = try row(kind: "Output tokens", usd: "0.0002400000", extraDimension: true)
        XCTAssertNil(parse([input, extraDimension], at: checkedAt))
    }

    func testWrongProductScopeUnitCurrencyAndAmountsFailClosed() throws {
        let checkedAt = try date()
        let input = try row(kind: "Input tokens", usd: "0.0000600000")
        let output = try row(kind: "Output tokens", usd: "0.0002400000")
        for attributes in [
            ["model": "Nova 2 Lite"], ["regionCode": "eu-west-3"],
            ["feature": "Batch Inference"], ["service_tier": "priority"],
            ["usagetype": "USE1-NovaLite-input-tokens-batch"],
        ] {
            let wrong = try row(kind: "Input tokens", usd: "0.0000600000", attributes: attributes)
            XCTAssertNil(parse([wrong, output], at: checkedAt))
        }
        for wrong in [
            try row(kind: "Input tokens", usd: "0.0000600000", unit: "tokens"),
            try row(kind: "Input tokens", usd: "0.0000600000", currency: "EUR"),
            try row(kind: "Input tokens", usd: "0"),
            try row(kind: "Input tokens", usd: "bogus"),
            try row(kind: "Input tokens", usd: "9223372036854775808"),
            try row(kind: "Input tokens", usd: String(repeating: "9", count: 100)),
            try row(kind: "Input tokens", usd: "0.0000600000", termSKU: "other"),
        ] {
            XCTAssertNil(parse([wrong, output], at: checkedAt))
        }
        XCTAssertNil(parse(["{", output], at: checkedAt))
        XCTAssertNil(parse([input.replacingOccurrences(of: "20261010182242", with: "future"), output], at: checkedAt))
        let futurePublication = input.replacingOccurrences(of: "2026-10-10T18:22:42Z", with: "2026-10-12T18:22:42Z")
        XCTAssertNil(parse([futurePublication, output], at: checkedAt))
        XCTAssertNil(parse([input, output], at: checkedAt, formatVersion: "aws_v2"))
    }

    func testSourceAgeAndTinyFractionalPriceAreConservative() throws {
        let checkedAt = try date()
        let output = try row(kind: "Output tokens", usd: "0.0002400000")
        let tiny = try row(kind: "Input tokens", usd: "0.0000000001")
        let rates = try XCTUnwrap(parse([tiny, output], at: checkedAt))
        XCTAssertEqual(rates.inputMicrosPerMillion, 1)
        XCTAssertNil(parse([tiny, output], at: checkedAt.addingTimeInterval(-301), now: checkedAt))
        XCTAssertNil(parse([tiny, output], at: checkedAt.addingTimeInterval(1), now: checkedAt))
    }

    private func date() throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z"))
    }

    private func parse(
        _ rows: [String], at fetchedAt: Date, now: Date? = nil, formatVersion: String = "aws_v1"
    ) -> CatalogTokenRates? {
        CatalogTokenRates.parse(rows, formatVersion: formatVersion, fetchedAt: fetchedAt, now: now ?? fetchedAt)
    }

    private func row(
        kind: String, usd: String, attributes overrides: [String: String] = [:],
        unit: String = "1K tokens", currency: String = "USD", termSKU: String? = nil,
        extraDimension: Bool = false
    ) throws -> String {
        let sku: String
        let usage: String
        switch kind {
        case "Input tokens":
            sku = "QRGWJ3P8FT28EYX2"
            usage = "USE1-NovaLite-input-tokens"
        case "Output tokens":
            sku = "CBZ6A6U7XK8WJ3KA"
            usage = "USE1-NovaLite-output-tokens"
        default:
            sku = "OTHER"
            usage = "USE1-NovaLite-image-tokens"
        }
        var attributes = [
            "model": "Nova Lite", "regionCode": "us-east-1", "servicecode": "AmazonBedrock",
            "feature": "On-demand Inference", "inferenceType": kind, "usagetype": usage,
            "location": "US East (N. Virginia)", "locationType": "AWS Region",
            "servicename": "Amazon Bedrock", "operation": "",
        ]
        for (key, value) in overrides { attributes[key] = value }
        let termCode = "JRTCKXETXF"
        let termKey = "\(sku).\(termCode)"
        let rateKey = "\(termKey).6YS6EN2CT7"
        let dimension: [String: Any] = [
            "unit": unit, "beginRange": "0", "endRange": "Inf", "rateCode": rateKey,
            "description": "Nova Lite on-demand tokens", "appliesTo": [], "pricePerUnit": [currency: usd],
        ]
        var dimensions: [String: Any] = [rateKey: dimension]
        if extraDimension { dimensions["\(termKey).OTHER"] = dimension }
        let product: [String: Any] = [
            "sku": sku, "productFamily": "Amazon Bedrock", "attributes": attributes,
        ]
        let term: [String: Any] = [
            "sku": termSKU ?? sku, "offerTermCode": termCode,
            "effectiveDate": "2026-10-01T00:00:00Z", "termAttributes": [:],
            "priceDimensions": dimensions,
        ]
        let catalog: [String: Any] = [
            "serviceCode": "AmazonBedrock", "version": "20261010182242",
            "publicationDate": "2026-10-10T18:22:42Z", "product": product,
            "terms": ["OnDemand": [termKey: term]],
        ]
        return try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: catalog), encoding: .utf8))
    }
}
