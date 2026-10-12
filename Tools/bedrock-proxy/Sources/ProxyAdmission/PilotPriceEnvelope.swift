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

struct CatalogTokenRates: Sendable {
    let modelLabel: String
    let regionCode: String
    let inputMicrosPerMillion: Int64
    let outputMicrosPerMillion: Int64
    let fetchedAt: Date

    static func parse(
        _ priceList: [String], formatVersion: String, fetchedAt: Date, now: Date = Date()
    ) -> CatalogTokenRates? {
        guard formatVersion == "aws_v1", priceList.count == 2,
            (0...300).contains(now.timeIntervalSince(fetchedAt))
        else { return nil }
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        var rates: [String: Int64] = [:]
        var version: String?
        var publishedAt: Date?
        var seenSKUs = Set<String>()
        for raw in priceList {
            guard raw.utf8.count <= 50_000,
                let row = try? decoder.decode(CatalogPriceRow.self, from: Data(raw.utf8)),
                row.serviceCode == "AmazonBedrock", row.product.productFamily == "Amazon Bedrock",
                !row.product.sku.isEmpty, row.product.sku.utf8.count <= 64,
                row.product.sku.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }),
                seenSKUs.insert(row.product.sku).inserted,
                let publication = formatter.date(from: row.publicationDate), publication <= fetchedAt,
                row.version.utf8.count == 14, row.version.utf8.allSatisfy({ (48...57).contains($0) })
            else { return nil }
            if let version, version != row.version { return nil }
            if let publishedAt, publishedAt != publication { return nil }
            version = row.version
            publishedAt = publication
            guard let (kind, rate) = quotedRate(row, publication: publication, formatter: formatter),
                rates[kind] == nil
            else { return nil }
            rates[kind] = rate
        }
        guard let input = rates["Input tokens"], let output = rates["Output tokens"], rates.count == 2
        else { return nil }
        return CatalogTokenRates(
            modelLabel: "Nova Lite", regionCode: "us-east-1",
            inputMicrosPerMillion: input, outputMicrosPerMillion: output, fetchedAt: fetchedAt
        )
    }

    private static func quotedRate(
        _ row: CatalogPriceRow, publication: Date, formatter: ISO8601DateFormatter
    ) -> (kind: String, rate: Int64)? {
        let requiredAttributes: Set<String> = [
            "regionCode", "inferenceType", "servicecode", "feature", "usagetype",
            "locationType", "location", "model", "servicename", "operation",
        ]
        let attributes = row.product.attributes
        guard Set(attributes.keys) == requiredAttributes,
            attributes["model"] == "Nova Lite", attributes["regionCode"] == "us-east-1",
            attributes["servicecode"] == "AmazonBedrock",
            attributes["feature"] == "On-demand Inference",
            attributes["location"] == "US East (N. Virginia)",
            attributes["locationType"] == "AWS Region",
            attributes["servicename"] == "Amazon Bedrock", attributes["operation"] == "",
            let kind = attributes["inferenceType"], let usage = attributes["usagetype"],
            (kind == "Input tokens" && usage == "USE1-NovaLite-input-tokens")
                || (kind == "Output tokens" && usage == "USE1-NovaLite-output-tokens"),
            Set(row.terms.keys) == ["OnDemand"], let terms = row.terms["OnDemand"], terms.count == 1,
            let (termKey, term) = terms.first, termKey == "\(row.product.sku).JRTCKXETXF",
            term.sku == row.product.sku, term.offerTermCode == "JRTCKXETXF", term.termAttributes.isEmpty,
            let effective = formatter.date(from: term.effectiveDate), effective <= publication,
            term.priceDimensions.count == 1, let (dimensionKey, dimension) = term.priceDimensions.first,
            dimensionKey.hasPrefix("\(termKey)."), dimension.rateCode == dimensionKey,
            dimension.unit == "1K tokens", dimension.beginRange == "0", dimension.endRange == "Inf",
            dimension.appliesTo.isEmpty, Set(dimension.pricePerUnit.keys) == ["USD"],
            let usd = dimension.pricePerUnit["USD"], let rate = microsPerMillion(usd)
        else { return nil }
        return (kind, rate)
    }

    private static func microsPerMillion(_ usd: String) -> Int64? {
        let parts = usd.split(separator: ".", omittingEmptySubsequences: false)
        guard usd.utf8.count <= 24, parts.count == 2,
            parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
            let price = Decimal(string: usd, locale: Locale(identifier: "en_US_POSIX")), price > 0
        else { return nil }
        var scaled = price * Decimal(1_000_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .up)
        guard rounded > 0, rounded <= Decimal(Int64.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}

private struct CatalogPriceRow: Decodable {
    let serviceCode: String
    let version: String
    let publicationDate: String
    let product: Product
    let terms: [String: [String: Term]]

    struct Product: Decodable {
        let sku: String
        let productFamily: String
        let attributes: [String: String]
    }

    struct Term: Decodable {
        let sku: String
        let offerTermCode: String
        let effectiveDate: String
        let termAttributes: [String: String]
        let priceDimensions: [String: Dimension]
    }

    struct Dimension: Decodable {
        let unit: String
        let beginRange: String
        let endRange: String
        let rateCode: String
        let appliesTo: [String]
        let pricePerUnit: [String: String]
    }
}
