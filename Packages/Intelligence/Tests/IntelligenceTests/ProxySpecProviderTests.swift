import InkCore
import XCTest

@testable import Intelligence

final class ProxySpecProviderTests: XCTestCase {
    func testConsentRefusesBeforeTheFakeTransport() async throws {
        let transport = FakeTransport(responses: [:])
        let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { false })

        do {
            _ = try await provider.spec(for: try Self.request("2+3="))
            XCTFail("A third-party request went out without consent")
        } catch {
            XCTAssertEqual(error as? ProviderError, .thirdPartyConsentRequired)
        }
        let calls = await transport.requests.count
        XCTAssertEqual(calls, 0)
    }

    func testTwoQuestionsReturnDifferentValidatedSpecsAndOnlyPermittedFieldsLeave() async throws {
        let transport = FakeTransport(responses: [
            "2+3=": try Self.answer(read: "2+3=", value: "5"),
            "3+3=": try Self.answer(read: "3+3=", value: "6"),
        ])
        let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { true })
        let first = try await provider.spec(for: Self.request("2+3="))
        let second = try await provider.spec(for: Self.request("3+3="))

        XCTAssertEqual(first.read, "2+3=")
        XCTAssertEqual(second.read, "3+3=")
        XCTAssertNotEqual(first.blocks, second.blocks)
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.map(\.transcript), ["2+3=", "3+3="])
        XCTAssertEqual(sent[0].cropPNG, Data("crop".utf8))
        XCTAssertEqual(sent[0].neighborhoodPNG, Data("near".utf8))
        let encoded = try JSONEncoder().encode(sent[0])
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(
            Set(keys.keys),
            Set(["requestID", "cropPNG", "neighborhoodPNG", "transcript", "intent", "maxOutputTokens"])
        )
    }

    func testUnboundedOrMissingSelectionCannotReachTransport() async throws {
        let transport = FakeTransport(responses: [:])
        let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { true })
        let initial = try Self.request("2+3=")
        let noImage = SpecRequest(context: initial.context, intent: .answer)
        let oversized = try Self.request("2+3=", crop: Data(repeating: 0, count: 1_000_001))
        let longRead = try Self.request(String(repeating: "a", count: 257))
        for request in [noImage, oversized, longRead] {
            do {
                _ = try await provider.spec(for: request)
                XCTFail("Invalid image request reached the transport")
            } catch {
                XCTAssertEqual(error as? ProxyProviderFailure, .invalidRequest)
            }
        }
        let calls = await transport.requests.count
        XCTAssertEqual(calls, 0)
    }

    func testMalformedSpecAndLowConfidenceWithBlocksFailClosed() async throws {
        let invalid = Spec(
            read: "2+3=", readConfidence: 0.2, intent: .answer,
            blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "5")))]
        )
        let wrongIntent = Spec(read: "2+3=", readConfidence: 0.95, intent: .plot, blocks: [])
        for response in [
            Data("not json".utf8), try SpecDecoder.encode(invalid),
            try SpecDecoder.encode(wrongIntent), Data(repeating: 0, count: 65_537),
        ] {
            let transport = FakeTransport(responses: ["2+3=": response])
            let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { true })
            do {
                _ = try await provider.spec(for: Self.request("2+3="))
                XCTFail("Invalid response became ink")
            } catch {
                XCTAssertEqual(error as? ProxyProviderFailure, .invalidResponse)
            }
        }
    }

    func testADeclineRendersNoBlocks() async throws {
        let decline = Spec(read: "unclear", readConfidence: 0.1, intent: .answer, blocks: [])
        let transport = FakeTransport(responses: ["2+3=": try SpecDecoder.encode(decline)])
        let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { true })

        let result = try await provider.spec(for: Self.request("2+3="))

        XCTAssertTrue(result.isDecline)
        XCTAssertTrue(result.blocks.isEmpty)
    }

    func testTransportFailuresHaveContentFreeErrorTypes() async throws {
        for failure in ProxyTransportFailure.allCases {
            let transport = FakeTransport(responses: [:], failure: failure)
            let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { true })
            do {
                _ = try await provider.spec(for: Self.request("2+3="))
                XCTFail("Transport failure was ignored")
            } catch {
                switch failure {
                case .timeout: XCTAssertEqual(error as? ProviderError, .timeout)
                case .offline: XCTAssertEqual(error as? ProxyProviderFailure, .offline)
                case .refused: XCTAssertEqual(error as? ProxyProviderFailure, .refused)
                case .unauthorized: XCTAssertEqual(error as? ProxyProviderFailure, .unauthorized)
                case .overBudget: XCTAssertEqual(error as? ProxyProviderFailure, .budgetExceeded)
                }
            }
        }
    }

    func testCancellationDiscardsLateFakeResponse() async throws {
        let transport = FakeTransport(responses: ["2+3=": try Self.answer(read: "2+3=", value: "5")], delayed: true)
        let provider = ProxySpecProvider.consentGated(transport: transport, isConsentGranted: { true })
        let request = try Self.request("2+3=")
        let task = Task { try await provider.spec(for: request) }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A late response was accepted after cancellation")
        } catch is CancellationError {
            XCTAssertTrue(task.isCancelled)
        } catch {
            XCTFail("Expected a cancellation rather than another error")
        }
    }

    private static func answer(read: String, value: String) throws -> Data {
        try SpecDecoder.encode(
            Spec(
                read: read, readConfidence: 0.95, intent: .answer,
                blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: value)))]
            )
        )
    }

    private static func request(_ read: String, crop: Data = Data("crop".utf8)) throws -> SpecRequest {
        let ink = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 320, y: 126), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [ink],
                loop: [CGPoint(x: 80, y: 80), CGPoint(x: 340, y: 80), CGPoint(x: 340, y: 150), CGPoint(x: 80, y: 150)],
                pageSize: CGSize(width: 768, height: 1_024)
            )
        )
        let rasterized = RasterizedSelection(
            crop: InkRasterImage(data: crop, size: CGSize(width: 10, height: 10), scale: 1),
            neighborhood: InkRasterImage(data: Data("near".utf8), size: CGSize(width: 10, height: 10), scale: 1)
        )
        return SpecRequest(
            context: context, intent: .answer, rasterizedSelection: rasterized,
            selectedAreaReading: SelectionReading(transcript: read, confidence: 0.95)
        )
    }
}

private actor FakeTransport: ProxyClientTransport {
    private(set) var requests: [ProxyClientRequest] = []
    let responses: [String: Data]
    let failure: ProxyTransportFailure?
    let delayed: Bool

    init(responses: [String: Data], failure: ProxyTransportFailure? = nil, delayed: Bool = false) {
        self.responses = responses
        self.failure = failure
        self.delayed = delayed
    }

    func response(to request: ProxyClientRequest) async throws -> Data {
        requests.append(request)
        if delayed { try? await Task.sleep(for: .milliseconds(100)) }
        if let failure { throw failure }
        return responses[request.transcript] ?? Data("not json".utf8)
    }
}
