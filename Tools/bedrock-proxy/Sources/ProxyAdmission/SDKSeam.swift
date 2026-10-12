import AWSBedrock
import AWSBedrockRuntime
import AWSPricing
import AWSSDKIdentity
import AWSSTS
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
    var configuredEndpoint: String? { get }

    func getAccountDataRetention(input: GetAccountDataRetentionInput) async throws -> GetAccountDataRetentionOutput
    func getFoundationModelAvailability(
        input: GetFoundationModelAvailabilityInput
    ) async throws -> GetFoundationModelAvailabilityOutput
}

extension BedrockClient: BedrockMetadataReader {
    var configuredRegion: String? { config.region }
    var configuredEndpoint: String? { config.endpoint }
}

struct ReadOnlyBedrockObservation: Sendable {
    let modelID: String
    let requestedModelID: String
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
            guard let reportedID = availability.modelId,
                reportedID == "amazon.nova-lite-v1:0" || reportedID == "amazon.nova-lite-v1",
                availability.authorizationStatus == .authorized,
                availability.entitlementAvailability == .available,
                availability.regionAvailability == .available,
                availability.agreementAvailability?.status == .available,
                availability.agreementAvailability?.errorMessage == nil
            else { return nil }
            return ReadOnlyBedrockObservation(
                modelID: reportedID, requestedModelID: "amazon.nova-lite-v1:0",
                requestedRegion: "us-east-1", accountMode: .none, checkedAt: now()
            )
        } catch {
            return nil
        }
    }
}

protocol PricingCatalogReader: Sendable {
    var configuredRegion: String? { get }
    var configuredEndpoint: String? { get }
    func getProducts(input: GetProductsInput) async throws -> GetProductsOutput
}

extension PricingClient: PricingCatalogReader {
    var configuredRegion: String? { config.region }
    var configuredEndpoint: String? { config.endpoint }
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

protocol PilotCallerReader: Sendable {
    var configuredRegion: String? { get }
    var configuredEndpoint: String? { get }
    func getCallerIdentity(input: GetCallerIdentityInput) async throws -> GetCallerIdentityOutput
}

extension STSClient: PilotCallerReader {
    var configuredRegion: String? { config.region }
    var configuredEndpoint: String? { config.endpoint }
}

struct ScopedPilotCaller: Sendable {
    let caller: any PilotCallerReader
    let expectedAccount: String

    func verify() async -> Bool {
        do {
            try Task.checkCancellation()
            guard expectedAccount.count == 12, expectedAccount.utf8.allSatisfy({ (48...57).contains($0) }),
                caller.configuredRegion == "us-east-1",
                caller.configuredEndpoint == "https://sts.us-east-1.amazonaws.com"
            else { return false }
            let identity = try await caller.getCallerIdentity(input: GetCallerIdentityInput())
            try Task.checkCancellation()
            return identity.account == expectedAccount
                && identity.arn == "arn:aws:iam::\(expectedAccount):user/MarginPilot"
                && identity.userId?.isEmpty == false
        } catch {
            return false
        }
    }
}

struct ScopedPilotCredentials {
    let credential: AWSCredentialIdentity
    let resolver: StaticAWSCredentialIdentityResolver
    let caller: STSClient

    static func resolve(expectedAccount: String) async throws -> ScopedPilotCredentials? {
        try Task.checkCancellation()
        guard expectedAccount.count == 12, expectedAccount.utf8.allSatisfy({ (48...57).contains($0) })
        else { return nil }
        let awsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws")
        let login = try LoginAWSCredentialIdentityResolver(
            profileName: "margin-pilot",
            configFilePath: awsDirectory.appendingPathComponent("config").path,
            credentialsFilePath: awsDirectory.appendingPathComponent("credentials").path
        )
        let credential = try await login.getIdentity(identityProperties: nil)
        try Task.checkCancellation()
        guard
            ScopedPricingSession.isTemporary(
                accountID: credential.accountID, sessionToken: credential.sessionToken,
                expiration: credential.expiration, expectedAccount: expectedAccount, now: Date()
            )
        else { return nil }
        let resolver = StaticAWSCredentialIdentityResolver(credential)
        let config = try await STSClient.STSClientConfig(
            awsCredentialIdentityResolver: resolver, maxAttempts: 1, ignoreConfiguredEndpointURLs: true,
            region: "us-east-1", signingRegion: "us-east-1",
            endpoint: "https://sts.us-east-1.amazonaws.com"
        )
        return ScopedPilotCredentials(credential: credential, resolver: resolver, caller: STSClient(config: config))
    }
}

struct ScopedPricingSession: Sendable {
    private let caller: any PilotCallerReader
    private let client: any PricingCatalogReader
    private let expectedAccount: String

    init(caller: any PilotCallerReader, client: any PricingCatalogReader, expectedAccount: String) {
        self.caller = caller
        self.client = client
        self.expectedAccount = expectedAccount
    }

    static func isTemporary(
        accountID: String?, sessionToken: String?, expiration: Date?, expectedAccount: String, now: Date
    ) -> Bool {
        accountID == expectedAccount && sessionToken?.isEmpty == false
            && (expiration.map { $0.timeIntervalSince(now) > 300 } ?? false)
    }

    func observe() async -> CatalogTokenRates? {
        guard client.configuredRegion == "us-east-1",
            client.configuredEndpoint == "https://api.pricing.us-east-1.amazonaws.com",
            await ScopedPilotCaller(caller: caller, expectedAccount: expectedAccount).verify()
        else { return nil }
        return await ReadOnlyPricingCatalog(client: client).observe()
    }
}

struct ScopedBedrockSession: Sendable {
    private let caller: any PilotCallerReader
    private let client: any BedrockMetadataReader
    private let expectedAccount: String

    init(caller: any PilotCallerReader, client: any BedrockMetadataReader, expectedAccount: String) {
        self.caller = caller
        self.client = client
        self.expectedAccount = expectedAccount
    }

    func observe() async -> ReadOnlyBedrockObservation? {
        guard client.configuredRegion == "us-east-1",
            client.configuredEndpoint == "https://bedrock.us-east-1.amazonaws.com",
            await ScopedPilotCaller(caller: caller, expectedAccount: expectedAccount).verify()
        else { return nil }
        return await ReadOnlyBedrockObserver(client: client).observe()
    }
}

public struct PilotCatalogSnapshot: Sendable {
    public let modelLabel: String
    public let inputMicrosPerMillion: Int64
    public let outputMicrosPerMillion: Int64
    public let fetchedAt: Date
}

public enum PilotPricingObservation {
    public static func observe(expectedAccount: String) async -> PilotCatalogSnapshot? {
        do {
            guard let session = try await ScopedPilotCredentials.resolve(expectedAccount: expectedAccount)
            else { return nil }
            let config = try await PricingClient.PricingClientConfig(
                awsCredentialIdentityResolver: session.resolver, maxAttempts: 1, ignoreConfiguredEndpointURLs: true,
                region: "us-east-1", signingRegion: "us-east-1",
                endpoint: "https://api.pricing.us-east-1.amazonaws.com"
            )
            guard
                let rates = await ScopedPricingSession(
                    caller: session.caller, client: PricingClient(config: config), expectedAccount: expectedAccount
                ).observe(),
                ScopedPricingSession.isTemporary(
                    accountID: session.credential.accountID, sessionToken: session.credential.sessionToken,
                    expiration: session.credential.expiration, expectedAccount: expectedAccount, now: Date()
                )
            else { return nil }
            return PilotCatalogSnapshot(
                modelLabel: rates.modelLabel, inputMicrosPerMillion: rates.inputMicrosPerMillion,
                outputMicrosPerMillion: rates.outputMicrosPerMillion, fetchedAt: rates.fetchedAt
            )
        } catch {
            return nil
        }
    }
}

public struct PilotBedrockSnapshot: Sendable {
    public let requestedModelID: String
    public let reportedModelID: String
    public let requestedRegion: String
    public let accountMode: String
    public let checkedAt: Date
}

public enum PilotBedrockObservation {
    public static func observe(expectedAccount: String) async -> PilotBedrockSnapshot? {
        do {
            guard let session = try await ScopedPilotCredentials.resolve(expectedAccount: expectedAccount)
            else { return nil }
            let config = try await BedrockClient.BedrockClientConfig(
                awsCredentialIdentityResolver: session.resolver, maxAttempts: 1, ignoreConfiguredEndpointURLs: true,
                region: "us-east-1", signingRegion: "us-east-1",
                endpoint: "https://bedrock.us-east-1.amazonaws.com"
            )
            guard
                let observed = await ScopedBedrockSession(
                    caller: session.caller, client: BedrockClient(config: config), expectedAccount: expectedAccount
                ).observe(),
                ScopedPricingSession.isTemporary(
                    accountID: session.credential.accountID, sessionToken: session.credential.sessionToken,
                    expiration: session.credential.expiration, expectedAccount: expectedAccount, now: Date()
                ), observed.isFresh()
            else { return nil }
            return PilotBedrockSnapshot(
                requestedModelID: observed.requestedModelID, reportedModelID: observed.modelID,
                requestedRegion: observed.requestedRegion, accountMode: "none", checkedAt: observed.checkedAt
            )
        } catch {
            return nil
        }
    }
}
