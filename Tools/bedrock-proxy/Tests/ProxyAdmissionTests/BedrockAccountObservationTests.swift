import AWSBedrock
import Foundation
import XCTest

@testable import ProxyAdmission

final class BedrockAccountObservationTests: XCTestCase {
    func testExactReadOnlyStatusesAreAnObservationNotRetentionPermission() async throws {
        let client = StubBedrockMetadataReader(
            mode: BedrockClientTypes.DataRetentionMode.none, availability: Self.available()
        )
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let observer = ReadOnlyBedrockObserver(client: client, now: { checkedAt })
        let result = await observer.observe()
        let observation = try XCTUnwrap(result)
        XCTAssertEqual(observation.modelID, "amazon.nova-lite-v1:0")
        XCTAssertEqual(observation.requestedRegion, "us-east-1")
        XCTAssertEqual(observation.accountMode, .none)
        XCTAssertTrue(observation.isFresh(at: checkedAt.addingTimeInterval(300)))
        XCTAssertFalse(observation.isFresh(at: checkedAt.addingTimeInterval(301)))
        XCTAssertFalse(observation.isFresh(at: checkedAt.addingTimeInterval(-1)))
        let calls = await client.calls
        XCTAssertEqual(calls, ["retention", "amazon.nova-lite-v1:0"])

        let pixelBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
        let pixel = try XCTUnwrap(Data(base64Encoded: pixelBase64))
        let body = try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString,
            "cropPNG": pixel.base64EncodedString(),
            "neighborhoodPNG": pixel.base64EncodedString(),
            "transcript": "2+3=", "intent": "answer", "maxOutputTokens": 32,
        ])
        let gate = AdmissionGate(
            modelID: "amazon.nova-lite-v1:0", region: "us-east-1",
            authorize: { _ in PilotIdentity(subjectID: UUID().uuidString) }
        )
        let transport = ObservedFakeTransport()
        do {
            try await gate.invoke(body, proof: "pilot", transport: transport)
            XCTFail("Read-only observation is not model-specific retention eligibility")
        } catch let error as AdmissionError {
            XCTAssertEqual(error, .retentionUnavailable)
        }
        let sends = await transport.sends
        XCTAssertEqual(sends, 0)
    }

    func testMissingOrNonzeroRetentionStopsBeforeAvailabilityLookup() async {
        for mode: BedrockClientTypes.DataRetentionMode? in [nil, .inherit, .default, .sdkUnknown("future")] {
            let client = StubBedrockMetadataReader(mode: mode, availability: Self.available())
            let result = await ReadOnlyBedrockObserver(client: client).observe()
            XCTAssertNil(result)
            let calls = await client.calls
            XCTAssertEqual(calls, ["retention"])
        }
    }

    func testWrongOrMissingClientRegionDeclinesBeforeAnySDKRead() async {
        let configuredRegions: [String?] = [nil, "eu-west-3"]
        for configuredRegion in configuredRegions {
            let client = StubBedrockMetadataReader(
                mode: BedrockClientTypes.DataRetentionMode.none, availability: Self.available(),
                configuredRegion: configuredRegion
            )
            let result = await ReadOnlyBedrockObserver(client: client).observe()
            XCTAssertNil(result)
            let calls = await client.calls
            XCTAssertEqual(calls, [])
        }
    }

    func testWrongModelOrMissingAndUnknownAvailabilityFailsClosed() async {
        var cases: [GetFoundationModelAvailabilityOutput] = []
        var wrongModel = Self.available()
        wrongModel.modelId = "other-model"
        cases.append(wrongModel)
        var missingAgreement = Self.available()
        missingAgreement.agreementAvailability = nil
        cases.append(missingAgreement)
        var denied = Self.available()
        denied.authorizationStatus = .notAuthorized
        cases.append(denied)
        var unknown = Self.available()
        unknown.regionAvailability = .sdkUnknown("future")
        cases.append(unknown)
        var missing = Self.available()
        missing.entitlementAvailability = nil
        cases.append(missing)
        var ambiguous = Self.available()
        ambiguous.agreementAvailability?.errorMessage = "unavailable"
        cases.append(ambiguous)
        for availability in cases {
            let client = StubBedrockMetadataReader(
                mode: BedrockClientTypes.DataRetentionMode.none, availability: availability
            )
            let result = await ReadOnlyBedrockObserver(client: client).observe()
            XCTAssertNil(result)
            let calls = await client.calls
            XCTAssertEqual(calls, ["retention", "amazon.nova-lite-v1:0"])
        }
    }

    func testAlreadyCancelledTaskDoesNotStartAnSDKRead() async {
        let client = StubBedrockMetadataReader(
            mode: BedrockClientTypes.DataRetentionMode.none, availability: Self.available()
        )
        let observer = ReadOnlyBedrockObserver(client: client)
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await observer.observe()
        }.value
        XCTAssertNil(result)
        let calls = await client.calls
        XCTAssertEqual(calls, [])
    }

    func testCancellationOrReadFailureDoesNotFetchModel() async {
        for error in [CancellationError(), TestReadFailure.unavailable] as [any Error] {
            let client = FailingBedrockMetadataReader(error: error)
            let result = await ReadOnlyBedrockObserver(client: client).observe()
            XCTAssertNil(result)
            let calls = await client.calls
            XCTAssertEqual(calls, 1)
        }
    }

    private static func available() -> GetFoundationModelAvailabilityOutput {
        GetFoundationModelAvailabilityOutput(
            agreementAvailability: BedrockClientTypes.AgreementAvailability(status: .available),
            authorizationStatus: .authorized, entitlementAvailability: .available,
            modelId: "amazon.nova-lite-v1:0", regionAvailability: .available
        )
    }
}

private actor StubBedrockMetadataReader: BedrockMetadataReader {
    nonisolated let configuredRegion: String?
    private let retention: GetAccountDataRetentionOutput
    private let availability: GetFoundationModelAvailabilityOutput
    private(set) var calls: [String] = []

    init(
        mode: BedrockClientTypes.DataRetentionMode?,
        availability: GetFoundationModelAvailabilityOutput,
        configuredRegion: String? = "us-east-1"
    ) {
        retention = GetAccountDataRetentionOutput(mode: mode)
        self.availability = availability
        self.configuredRegion = configuredRegion
    }

    func getAccountDataRetention(input: GetAccountDataRetentionInput) async throws -> GetAccountDataRetentionOutput {
        calls.append("retention")
        return retention
    }

    func getFoundationModelAvailability(
        input: GetFoundationModelAvailabilityInput
    ) async throws -> GetFoundationModelAvailabilityOutput {
        calls.append(input.modelId ?? "missing")
        return availability
    }
}

private enum TestReadFailure: Error {
    case unavailable
}

private actor FailingBedrockMetadataReader: BedrockMetadataReader {
    nonisolated let configuredRegion: String? = "us-east-1"
    private let error: any Error
    private(set) var calls = 0

    init(error: any Error) { self.error = error }

    func getAccountDataRetention(input: GetAccountDataRetentionInput) async throws -> GetAccountDataRetentionOutput {
        calls += 1
        throw error
    }

    func getFoundationModelAvailability(
        input: GetFoundationModelAvailabilityInput
    ) async throws -> GetFoundationModelAvailabilityOutput {
        calls += 1
        return GetFoundationModelAvailabilityOutput()
    }
}

private actor ObservedFakeTransport: ProxyTransport {
    private(set) var sends = 0
    func send(_ request: AdmittedRequest) async throws { sends += 1 }
}
