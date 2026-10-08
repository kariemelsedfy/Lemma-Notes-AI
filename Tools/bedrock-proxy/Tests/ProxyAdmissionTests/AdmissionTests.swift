import Foundation
import XCTest

@testable import ProxyAdmission

final class AdmissionTests: XCTestCase {
    func testAuthorizedSyntheticRequestCallsOnlyTheFakeTransport() async throws {
        let transport = CountingTransport()
        try await gate().invoke(try body(), proof: "pilot", transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    func testUnverifiedPilotAndExtraPageOrBankFieldsNeverReachTransport() async throws {
        let transport = CountingTransport()
        let defaultDeny = AdmissionGate(modelID: "amazon.nova-lite-v1:0", region: "us-east-1")
        await expect(.unauthorized, defaultDeny, try body(), transport: transport)
        let admission = gate()
        await expect(.unauthorized, admission, try body(), proof: nil, transport: transport)
        await expect(.malformed, admission, try body(extra: ["glyphBank": "not allowed"]), transport: transport)
        await expect(.malformed, admission, try body(extra: ["pagePNG": "not allowed"]), transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func testUnsupportedIntentAndMalformedOrOversizedImagesNeverReachTransport() async throws {
        let transport = CountingTransport()
        let admission = gate()
        await expect(.unsupported, admission, try body(intent: "plot"), transport: transport)
        await expect(.malformed, admission, try body(crop: Data([0, 1, 2])), transport: transport)
        var inflated = Self.pixelPNG
        inflated.replaceSubrange(16..<20, with: [0, 0, 32, 0])
        await expect(.oversized, admission, try body(crop: inflated), transport: transport)
        let bytes = Data(repeating: 0, count: 1_000_001)
        await expect(.oversized, admission, try body(crop: bytes), transport: transport)
        await expect(.oversized, admission, Data(repeating: 0, count: 3_000_001), transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func testPNGMetadataAndCorruptChecksumsNeverReachTransport() async throws {
        let transport = CountingTransport()
        let admission = gate()
        let encoded =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9o8cRcwAAAAO"
            + "dEVYdG5vdGU9c3ludGhldGljaZOn3QAAAABJRU5ErkJggg=="
        let tagged = try XCTUnwrap(Data(base64Encoded: encoded))
        await expect(.malformed, admission, try body(crop: tagged), transport: transport)
        var corrupt = Self.pixelPNG
        corrupt[45] ^= 0x01
        await expect(.malformed, admission, try body(crop: corrupt), transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func testTranscriptAndTokenLimitsRejectBeforeTransport() async throws {
        let transport = CountingTransport()
        let admission = gate()
        await expect(
            .oversized, admission, try body(transcript: String(repeating: "a", count: 257)),
            transport: transport
        )
        await expect(.oversized, admission, try body(maxOutputTokens: 513), transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func testUnverifiedOrWrongModelRetentionNeverReachesTransport() async throws {
        let transport = CountingTransport()
        let input = try body()
        await expect(.retentionUnavailable, gate(evidence: nil), input, transport: transport)
        await expect(.retentionUnavailable, gate(mode: "default"), input, transport: transport)
        await expect(.retentionUnavailable, gate(allowed: ["default"]), input, transport: transport)
        await expect(.retentionUnavailable, gate(region: "eu-west-1"), input, transport: transport)
        await expect(.retentionUnavailable, gate(model: "unknown-model"), input, transport: transport)
        await expect(.retentionUnavailable, gate(verifiedAt: .distantPast), input, transport: transport)
        await expect(.retentionUnavailable, gate(verifiedAt: .distantFuture), input, transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func testCancellationBeforeAuthorizationReturnsCannotInvokeTransport() async throws {
        let transport = CountingTransport()
        let admission = AdmissionGate(
            modelID: "amazon.nova-lite-v1:0", region: "us-east-1",
            authorize: { _ in
                try? await Task.sleep(for: .milliseconds(100))
                return PilotIdentity(subjectID: "test-pilot")
            },
            retention: {
                RetentionEvidence(
                    modelID: "amazon.nova-lite-v1:0", region: "us-east-1", effectiveMode: "none",
                    allowedModes: ["none"], verifiedAt: Date()
                )
            }
        )
        let input = try body()
        let request = Task { try await admission.invoke(input, proof: "pilot", transport: transport) }
        try await Task.sleep(for: .milliseconds(10))
        request.cancel()
        do {
            try await request.value
            XCTFail("A cancelled request reached the fake transport")
        } catch is CancellationError {
            XCTAssertTrue(request.isCancelled)
        } catch {
            XCTFail("Expected cancellation rather than an admission error")
        }
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func testOnlyOneFakeTransportCallCanBeInFlight() async throws {
        let transport = BlockingTransport()
        let admission = gate()
        let input = try body()
        let first = Task { try await admission.invoke(input, proof: "pilot", transport: transport) }
        var started = false
        for _ in 0..<200 {
            if await transport.calls > 0 {
                started = true
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        if started { await expect(.busy, admission, input, transport: transport) }
        await transport.finish()
        try await first.value
        XCTAssertTrue(started, "The first request never reached the fake transport")
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    private func gate(
        evidence: Bool? = true,
        mode: String = "none",
        allowed: Set<String> = ["none"],
        region: String = "us-east-1",
        model: String = "amazon.nova-lite-v1:0",
        verifiedAt: Date = Date()
    ) -> AdmissionGate {
        let attestation: RetentionEvidence?
        if evidence == nil {
            attestation = nil
        } else {
            attestation = RetentionEvidence(
                modelID: model, region: region, effectiveMode: mode,
                allowedModes: allowed, verifiedAt: verifiedAt
            )
        }
        return AdmissionGate(
            modelID: "amazon.nova-lite-v1:0",
            region: "us-east-1",
            authorize: { proof in proof == "pilot" ? PilotIdentity(subjectID: "test-pilot") : nil },
            retention: { attestation },
            maxInFlight: 1
        )
    }

    private func body(
        crop: Data = pixelPNG,
        neighborhood: Data = pixelPNG,
        transcript: String = "2+3=",
        intent: String = "answer",
        maxOutputTokens: Int = 256,
        extra: [String: Any] = [:]
    ) throws -> Data {
        var request: [String: Any] = [
            "requestID": UUID().uuidString,
            "cropPNG": crop.base64EncodedString(),
            "neighborhoodPNG": neighborhood.base64EncodedString(),
            "transcript": transcript,
            "intent": intent,
            "maxOutputTokens": maxOutputTokens,
        ]
        for (key, value) in extra { request[key] = value }
        return try JSONSerialization.data(withJSONObject: request)
    }

    private func expect(
        _ failure: AdmissionError,
        _ gate: AdmissionGate,
        _ request: Data,
        proof: String? = "pilot",
        transport: any ProxyTransport
    ) async {
        do {
            try await gate.invoke(request, proof: proof, transport: transport)
            XCTFail("Expected admission to decline")
        } catch let error as AdmissionError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free admission error")
        }
    }

    private static let pixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9o8cRcwAAAAASUVORK5CYII="
    )!
}

private actor CountingTransport: ProxyTransport {
    private(set) var calls = 0

    func send(_ request: AdmittedRequest) async throws {
        calls += 1
    }
}

private actor BlockingTransport: ProxyTransport {
    private(set) var calls = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var released = false

    func send(_ request: AdmittedRequest) async throws {
        calls += 1
        guard !released else { return }
        await withCheckedContinuation { pending = $0 }
    }

    func finish() {
        released = true
        pending?.resume()
        pending = nil
    }
}
