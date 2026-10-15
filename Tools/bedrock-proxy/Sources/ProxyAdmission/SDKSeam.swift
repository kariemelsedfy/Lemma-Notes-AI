import AWSBedrock
import AWSBedrockRuntime
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
