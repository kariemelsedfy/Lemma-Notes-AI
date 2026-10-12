import AWSPricing
import AWSSTS
import Foundation
import XCTest

@testable import ProxyAdmission

final class PricingSDKPageTests: XCTestCase {
    func testExactPublicFiltersProduceOnlyTokenObservations() async throws {
        let checkedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z"))
        let inputRow = Self.row(kind: "Input tokens", usd: "0.0000600000")
        let outputRow = Self.row(kind: "Output tokens", usd: "0.0002400000")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(inputRow.utf8)))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(outputRow.utf8)))
        let parsed = CatalogTokenRates.parse(
            [inputRow, outputRow], formatVersion: "aws_v1", fetchedAt: checkedAt, now: checkedAt
        )
        XCTAssertNotNil(parsed)
        let client = FakePricingCatalogClient(responses: Self.standardPages())
        let result = await ReadOnlyPricingCatalog(client: client, now: { checkedAt }).observe()
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        let rates = try XCTUnwrap(result)
        XCTAssertEqual(rates.modelLabel, "Nova Lite")
        XCTAssertEqual(rates.inputMicrosPerMillion, 60_000)
        XCTAssertEqual(rates.outputMicrosPerMillion, 240_000)
        for (index, kind) in ["Input tokens", "Output tokens"].enumerated() {
            let request = requests[index]
            XCTAssertEqual(request.serviceCode, "AmazonBedrock")
            XCTAssertEqual(request.formatVersion, "aws_v1")
            XCTAssertEqual(request.maxResults, 2)
            XCTAssertNil(request.nextToken)
            let filters = try XCTUnwrap(request.filters)
            XCTAssertEqual(filters.count, 4)
            XCTAssertTrue(filters.allSatisfy { $0.type == .termMatch })
            var values: [String: String] = [:]
            for filter in filters {
                let field = try XCTUnwrap(filter.field)
                let value = try XCTUnwrap(filter.value)
                values[field] = value
            }
            XCTAssertEqual(values.count, 4)
            XCTAssertEqual(values["model"], "Nova Lite")
            XCTAssertEqual(values["regionCode"], "us-east-1")
            XCTAssertEqual(values["feature"], "On-demand Inference")
            XCTAssertEqual(values["inferenceType"], kind)
        }
        XCTAssertThrowsError(try PilotPriceEnvelope.quote(maxOutputTokens: 512)) { error in
            XCTAssertEqual(error as? PilotPriceError, .unavailable)
        }
    }

    func testWrongPricingEndpointRegionStopsBeforeSDKRead() async {
        let client = FakePricingCatalogClient(configuredRegion: "eu-west-3", responses: Self.standardPages())
        let result = await ReadOnlyPricingCatalog(client: client).observe()
        XCTAssertNil(result)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testRepeatedOrEmptyPaginationTokensFailClosed() async {
        let input = Self.row(kind: "Input tokens", usd: "0.0000600000")
        let output = Self.row(kind: "Output tokens", usd: "0.0002400000")
        let repeated = FakePricingCatalogClient(responses: [
            "Input tokens": [
                GetProductsOutput(formatVersion: "aws_v1", nextToken: "again", priceList: [input]),
                GetProductsOutput(formatVersion: "aws_v1", nextToken: "again", priceList: [input]),
            ],
            "Output tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: [output])],
        ])
        let repeatedResult = await ReadOnlyPricingCatalog(client: repeated).observe()
        XCTAssertNil(repeatedResult)
        let repeatedRequests = await repeated.requests
        XCTAssertEqual(repeatedRequests.count, 2)
        XCTAssertEqual(repeatedRequests[1].nextToken, "again")

        let empty = FakePricingCatalogClient(responses: [
            "Input tokens": [GetProductsOutput(formatVersion: "aws_v1", nextToken: "", priceList: [input])],
            "Output tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: [output])],
        ])
        let emptyResult = await ReadOnlyPricingCatalog(client: empty).observe()
        XCTAssertNil(emptyResult)
        let emptyRequests = await empty.requests
        XCTAssertEqual(emptyRequests.count, 1)
    }

    func testMissingExtraOrAmbiguousPagesDecline() async {
        let input = Self.row(kind: "Input tokens", usd: "0.0000600000")
        let output = Self.row(kind: "Output tokens", usd: "0.0002400000")
        let pages: [[String: [GetProductsOutput]]] = [
            [
                "Input tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: [input])],
                "Output tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: nil)],
            ],
            [
                "Input tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: [input, input])],
                "Output tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: [output])],
            ],
            [
                "Input tokens": [GetProductsOutput(formatVersion: "aws_v2", priceList: [input])],
                "Output tokens": [GetProductsOutput(formatVersion: "aws_v1", priceList: [output])],
            ],
        ]
        for responses in pages {
            let client = FakePricingCatalogClient(responses: responses)
            let result = await ReadOnlyPricingCatalog(client: client).observe()
            XCTAssertNil(result)
        }
    }

    func testCancelledTaskAndSDKFailureDoNotReturnRates() async {
        let client = FakePricingCatalogClient(responses: Self.standardPages())
        let reader = ReadOnlyPricingCatalog(client: client)
        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await reader.observe()
        }.value
        XCTAssertNil(cancelled)
        let cancelledRequests = await client.requests
        XCTAssertTrue(cancelledRequests.isEmpty)

        let failing = FakePricingCatalogClient(responses: Self.standardPages(), fails: true)
        let result = await ReadOnlyPricingCatalog(client: failing).observe()
        XCTAssertNil(result)
        let failedRequests = await failing.requests
        XCTAssertEqual(failedRequests.count, 1)
    }

    func testScopedSessionVerifiesExactIdentityBeforePricing() async throws {
        let account = "123456789012"
        let caller = FakePilotCaller(
            identity: GetCallerIdentityOutput(
                account: account, arn: "arn:aws:iam::\(account):user/MarginPilot", userId: "pilot-id"
            )
        )
        let client = FakePricingCatalogClient(responses: Self.standardPages())
        let rates = await ScopedPricingSession(caller: caller, client: client, expectedAccount: account).observe()
        XCTAssertNotNil(rates)
        let calls = await caller.calls
        let requests = await client.requests
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(requests.count, 2)
        XCTAssertThrowsError(try PilotPriceEnvelope.quote(maxOutputTokens: 512))
    }

    func testScopedSessionDeniesWrongAccountRootRoleAndEndpointBeforePricing() async {
        let account = "123456789012"
        let identities = [
            GetCallerIdentityOutput(account: account, arn: "arn:aws:iam::\(account):root", userId: "root"),
            GetCallerIdentityOutput(
                account: account, arn: "arn:aws:sts::\(account):assumed-role/Admin/pilot", userId: "role"
            ),
            GetCallerIdentityOutput(
                account: "999999999999", arn: "arn:aws:iam::\(account):user/MarginPilot", userId: "pilot"
            ),
            GetCallerIdentityOutput(account: account, arn: "arn:aws:iam::\(account):user/MarginPilot"),
        ]
        for identity in identities {
            let caller = FakePilotCaller(identity: identity)
            let client = FakePricingCatalogClient(responses: Self.standardPages())
            let result = await ScopedPricingSession(caller: caller, client: client, expectedAccount: account).observe()
            XCTAssertNil(result)
            let requests = await client.requests
            XCTAssertTrue(requests.isEmpty)
        }
        for (stsEndpoint, pricingEndpoint) in [
            ("https://sts.us-west-2.amazonaws.com", "https://api.pricing.us-east-1.amazonaws.com"),
            ("https://sts.us-east-1.amazonaws.com", "https://untrusted.example.com"),
        ] {
            let caller = FakePilotCaller(
                endpoint: stsEndpoint,
                identity: GetCallerIdentityOutput(
                    account: account, arn: "arn:aws:iam::\(account):user/MarginPilot", userId: "pilot"
                )
            )
            let client = FakePricingCatalogClient(endpoint: pricingEndpoint, responses: Self.standardPages())
            let result = await ScopedPricingSession(caller: caller, client: client, expectedAccount: account).observe()
            XCTAssertNil(result)
            let requests = await client.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testMissingExpectedAccountCallerErrorAndCancellationNeverReadPrices() async {
        let identity = GetCallerIdentityOutput(
            account: "123456789012", arn: "arn:aws:iam::123456789012:user/MarginPilot", userId: "pilot"
        )
        let caller = FakePilotCaller(identity: identity, fails: true)
        let client = FakePricingCatalogClient(responses: Self.standardPages())
        let invalid = await ScopedPricingSession(caller: caller, client: client, expectedAccount: "").observe()
        XCTAssertNil(invalid)
        let session = ScopedPricingSession(caller: caller, client: client, expectedAccount: "123456789012")
        let failed = await session.observe()
        XCTAssertNil(failed)
        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await session.observe()
        }.value
        XCTAssertNil(cancelled)
        let calls = await caller.calls
        let requests = await client.requests
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(requests.isEmpty)
    }

    func testTemporaryCredentialsRequireExactAccountSessionAndFutureExpiration() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(
            ScopedPricingSession.isTemporary(
                accountID: "123456789012", sessionToken: "session", expiration: now.addingTimeInterval(600),
                expectedAccount: "123456789012", now: now
            )
        )
        for (account, token, expiration) in [
            ("123456789012", nil, now.addingTimeInterval(600)),
            ("123456789012", "session", now.addingTimeInterval(299)),
            ("999999999999", "session", now.addingTimeInterval(600)),
        ] {
            XCTAssertFalse(
                ScopedPricingSession.isTemporary(
                    accountID: account, sessionToken: token, expiration: expiration,
                    expectedAccount: "123456789012", now: now
                )
            )
        }
    }

    private static func standardPages() -> [String: [GetProductsOutput]] {
        let input = GetProductsOutput(
            formatVersion: "aws_v1", priceList: [row(kind: "Input tokens", usd: "0.0000600000")]
        )
        let output = GetProductsOutput(
            formatVersion: "aws_v1", priceList: [row(kind: "Output tokens", usd: "0.0002400000")]
        )
        return ["Input tokens": [input], "Output tokens": [output]]
    }

    private static func row(kind: String, usd: String) -> String {
        let input = kind == "Input tokens"
        let sku = input ? "QRGWJ3P8FT28EYX2" : "CBZ6A6U7XK8WJ3KA"
        let usage = input ? "USE1-NovaLite-input-tokens" : "USE1-NovaLite-output-tokens"
        return """
            {"serviceCode":"AmazonBedrock","version":"20261010182242","publicationDate":"2026-10-10T18:22:42Z",
             "product":{"sku":"\(sku)","productFamily":"Amazon Bedrock","attributes":{
               "model":"Nova Lite","regionCode":"us-east-1","servicecode":"AmazonBedrock",
               "feature":"On-demand Inference","inferenceType":"\(kind)","usagetype":"\(usage)",
               "location":"US East (N. Virginia)","locationType":"AWS Region",
               "servicename":"Amazon Bedrock","operation":""}},
             "terms":{"OnDemand":{"\(sku).JRTCKXETXF":{"sku":"\(sku)","offerTermCode":"JRTCKXETXF",
               "effectiveDate":"2026-10-01T00:00:00Z","termAttributes":{},"priceDimensions":{
                 "\(sku).JRTCKXETXF.6YS6EN2CT7":{"unit":"1K tokens","beginRange":"0","endRange":"Inf",
                   "rateCode":"\(sku).JRTCKXETXF.6YS6EN2CT7","description":"Nova Lite on-demand tokens",
                   "appliesTo":[],"pricePerUnit":{"USD":"\(usd)"}}}}}}}
            """
    }
}

private enum PricingReadFailure: Error {
    case unavailable
}

private actor FakePilotCaller: PilotCallerReader {
    nonisolated let configuredRegion: String? = "us-east-1"
    nonisolated let configuredEndpoint: String?
    let identity: GetCallerIdentityOutput
    let fails: Bool
    private(set) var calls = 0

    init(
        endpoint: String = "https://sts.us-east-1.amazonaws.com",
        identity: GetCallerIdentityOutput, fails: Bool = false
    ) {
        configuredEndpoint = endpoint
        self.identity = identity
        self.fails = fails
    }

    func getCallerIdentity(input: GetCallerIdentityInput) async throws -> GetCallerIdentityOutput {
        calls += 1
        if fails { throw PricingReadFailure.unavailable }
        return identity
    }
}

private actor FakePricingCatalogClient: PricingCatalogReader {
    nonisolated let configuredRegion: String?
    nonisolated let configuredEndpoint: String?
    private var responses: [String: [GetProductsOutput]]
    private let fails: Bool
    private(set) var requests: [GetProductsInput] = []

    init(
        configuredRegion: String? = "us-east-1",
        endpoint: String? = "https://api.pricing.us-east-1.amazonaws.com",
        responses: [String: [GetProductsOutput]], fails: Bool = false
    ) {
        self.configuredRegion = configuredRegion
        configuredEndpoint = endpoint
        self.responses = responses
        self.fails = fails
    }

    func getProducts(input: GetProductsInput) async throws -> GetProductsOutput {
        requests.append(input)
        if fails { throw PricingReadFailure.unavailable }
        let kind = input.filters?.first(where: { $0.field == "inferenceType" })?.value ?? "unknown"
        guard var pages = responses[kind], !pages.isEmpty else { return GetProductsOutput() }
        let first = pages.removeFirst()
        responses[kind] = pages
        return first
    }
}
