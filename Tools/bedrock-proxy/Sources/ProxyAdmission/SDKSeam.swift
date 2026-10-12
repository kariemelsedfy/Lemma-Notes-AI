import AWSBedrock
import AWSBedrockRuntime
import AWSPricing
import Foundation

enum SDKTransportError: Error, Equatable {
    case disabled
}

struct DisabledBedrockTransport: ProxyTransport {
    func send(_ request: AdmittedRequest) async throws {
        throw SDKTransportError.disabled
    }
}

enum SyntheticNovaProbe {
    static func request() -> ConverseInput {
        let message = BedrockRuntimeClientTypes.Message(content: [.text("2+3=")], role: .user)
        return ConverseInput(
            inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration(maxTokens: 32),
            messages: [message], modelId: "amazon.nova-lite-v1:0"
        )
    }
}

protocol BedrockMetadataReader: Sendable {
    var configuredRegion: String? { get }

    func getAccountDataRetention(input: GetAccountDataRetentionInput) async throws -> GetAccountDataRetentionOutput
    func getFoundationModelAvailability(
        input: GetFoundationModelAvailabilityInput
    ) async throws -> GetFoundationModelAvailabilityOutput
}

extension BedrockClient: BedrockMetadataReader {
    var configuredRegion: String? { config.region }
}

struct ReadOnlyBedrockObservation: Sendable {
    let modelID: String
    let requestedRegion: String
    let accountMode: BedrockClientTypes.DataRetentionMode
    let checkedAt: Date

    func isFresh(at now: Date = Date()) -> Bool {
        (0...300).contains(now.timeIntervalSince(checkedAt))
    }
}

struct ReadOnlyBedrockObserver: Sendable {
    private let client: any BedrockMetadataReader
    private let now: @Sendable () -> Date

    init(client: any BedrockMetadataReader, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func observe() async -> ReadOnlyBedrockObservation? {
        do {
            try Task.checkCancellation()
            guard client.configuredRegion == "us-east-1" else { return nil }
            let retention = try await client.getAccountDataRetention(input: GetAccountDataRetentionInput())
            try Task.checkCancellation()
            guard retention.mode == BedrockClientTypes.DataRetentionMode.none else { return nil }
            let availability = try await client.getFoundationModelAvailability(
                input: GetFoundationModelAvailabilityInput(modelId: "amazon.nova-lite-v1:0")
            )
            try Task.checkCancellation()
            guard availability.modelId == "amazon.nova-lite-v1:0",
                availability.authorizationStatus == .authorized,
                availability.entitlementAvailability == .available,
                availability.regionAvailability == .available,
                availability.agreementAvailability?.status == .available,
                availability.agreementAvailability?.errorMessage == nil
            else { return nil }
            return ReadOnlyBedrockObservation(
                modelID: "amazon.nova-lite-v1:0", requestedRegion: "us-east-1",
                accountMode: .none, checkedAt: now()
            )
        } catch {
            return nil
        }
    }
}

protocol PricingCatalogReader: Sendable {
    var configuredRegion: String? { get }
    func getProducts(input: GetProductsInput) async throws -> GetProductsOutput
}

extension PricingClient: PricingCatalogReader {
    var configuredRegion: String? { config.region }
}

struct ReadOnlyPricingCatalog: Sendable {
    private let client: any PricingCatalogReader
    private let now: @Sendable () -> Date

    init(client: any PricingCatalogReader, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func observe() async -> CatalogTokenRates? {
        do {
            try Task.checkCancellation()
            guard client.configuredRegion == "us-east-1" else { return nil }
            var rows: [String] = []
            for kind in ["Input tokens", "Output tokens"] {
                let filters = [
                    PricingClientTypes.Filter(field: "model", type: .termMatch, value: "Nova Lite"),
                    PricingClientTypes.Filter(field: "regionCode", type: .termMatch, value: "us-east-1"),
                    PricingClientTypes.Filter(field: "feature", type: .termMatch, value: "On-demand Inference"),
                    PricingClientTypes.Filter(field: "inferenceType", type: .termMatch, value: kind),
                ]
                var nextToken: String?
                var seenTokens = Set<String>()
                var pageCount = 0
                repeat {
                    try Task.checkCancellation()
                    guard pageCount < 3 else { return nil }
                    pageCount += 1
                    let input = GetProductsInput(
                        filters: filters, formatVersion: "aws_v1", maxResults: 2,
                        nextToken: nextToken, serviceCode: "AmazonBedrock"
                    )
                    let result = try await client.getProducts(input: input)
                    try Task.checkCancellation()
                    guard result.formatVersion == "aws_v1", let page = result.priceList,
                        !page.isEmpty, page.count <= 2, rows.count + page.count <= 2,
                        page.allSatisfy({ $0.utf8.count <= 50_000 })
                    else { return nil }
                    rows.append(contentsOf: page)
                    nextToken = result.nextToken
                    if let nextToken {
                        guard !nextToken.isEmpty, nextToken.utf8.count <= 4_096,
                            seenTokens.insert(nextToken).inserted
                        else { return nil }
                    }
                } while nextToken != nil
            }
            let fetchedAt = now()
            return CatalogTokenRates.parse(rows, formatVersion: "aws_v1", fetchedAt: fetchedAt, now: fetchedAt)
        } catch {
            return nil
        }
    }
}
