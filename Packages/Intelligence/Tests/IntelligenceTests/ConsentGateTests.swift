import InkCore
import XCTest

@testable import Intelligence

/// App Store 5.1.2(i) consent, asserted in the provider layer (invariant 8, M4-09).
final class ConsentGateTests: XCTestCase {
    // MARK: - The gate

    func testATransmittingProviderIsRefusedWithoutConsent() async {
        let spy = SpyProvider(tier: .frontierCloud)
        let gated = spy.gated(by: { false })

        do {
            _ = try await gated.spec(for: try Self.request())
            XCTFail("A frontier request without consent must not reach the provider.")
        } catch {
            XCTAssertEqual(error as? ProviderError, .thirdPartyConsentRequired)
        }

        // The point is not the error, it is that nothing was sent.
        let calls = await spy.callCount
        XCTAssertEqual(calls, 0, "The request reached the provider anyway.")
    }

    func testATransmittingProviderRunsWithConsent() async throws {
        let spy = SpyProvider(tier: .frontierCloud)
        let gated = spy.gated(by: { true })

        _ = try await gated.spec(for: try Self.request())

        let calls = await spy.callCount
        XCTAssertEqual(calls, 1)
    }

    func testLocalTiersNeedNoConsentAtAll() async throws {
        for tier in ModelTier.allCases where !tier.transmitsContentToThirdParty {
            let spy = SpyProvider(tier: tier)

            _ = try await spy.gated(by: { false }).spec(for: try Self.request())

            let calls = await spy.callCount
            XCTAssertEqual(calls, 1, "\(tier) never leaves Apple's world; gating it would be theatre.")
        }
    }

    /// Consent is read per request, not captured once, so withdrawing it takes effect on the
    /// next Ask rather than the next launch.
    func testWithdrawingConsentStopsTheNextRequest() async throws {
        let spy = SpyProvider(tier: .frontierCloud)
        let granted = Flag(value: true)
        let gated = spy.gated(by: { granted.value })

        _ = try await gated.spec(for: try Self.request())
        granted.value = false
        _ = try? await gated.spec(for: try Self.request())

        let calls = await spy.callCount
        XCTAssertEqual(calls, 1, "The second request went out after consent was withdrawn.")
    }

    // MARK: - The classification itself

    /// Every tier states whether it transmits. This is the switch that decides whether a
    /// user's homework leaves their iPad, so a new tier must not be able to default to "no".
    func testEveryTierDeclaresWhetherItTransmits() {
        XCTAssertFalse(ModelTier.onDevice.transmitsContentToThirdParty)
        XCTAssertFalse(ModelTier.privateCloudCompute.transmitsContentToThirdParty)
        XCTAssertFalse(ModelTier.mock.transmitsContentToThirdParty)
        XCTAssertTrue(ModelTier.frontierCloud.transmitsContentToThirdParty)

        // If this fails, a tier was added: decide what it does with content, then update it.
        XCTAssertEqual(ModelTier.allCases.count, 4)
    }

    /// The routing policy refuses to *route* there without consent (M4-03) and the gate refuses
    /// to *send* without it. Neither is redundant: routing decides where a request should go,
    /// and a request can reach a provider without having been routed — a retry, a cached
    /// pipeline, or M4-10's speculative prefetch.
    func testRoutingAndTheGateAgree() {
        let refused = RoutingPolicy.decide(
            RoutingInputs(
                intent: .answer,
                complexity: .hard,
                readConfidence: 0.9,
                isOnline: true,
                availability: .deviceNotEligible,
                supportsPrivateCloudCompute: false,
                entitlement: RoutingEntitlement(
                    hasCredits: true, hasThirdPartyConsent: false, prefersOnDeviceOnly: false)
            )
        )

        XCTAssertNotEqual(refused.tier, .frontierCloud)
    }

    // MARK: - Fixtures

    private static func request() throws -> SpecRequest {
        let strokes = (0..<2).map { index -> InkStroke in
            let left = CGFloat(100 + index * 40)
            return InkStroke(points: [
                InkPoint(location: CGPoint(x: left, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(
                    location: CGPoint(x: left + 20, y: 160), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
            ])
        }
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: strokes,
                loop: [
                    CGPoint(x: 80, y: 80), CGPoint(x: 420, y: 80),
                    CGPoint(x: 420, y: 210), CGPoint(x: 80, y: 210),
                ],
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
        )
        return SpecRequest(context: context, intent: .answer)
    }

    /// Records whether it was reached. A gate that throws *after* sending would pass a test
    /// that only checked the error.
    private actor SpyProvider: SpecProvider {
        nonisolated let tier: ModelTier
        private(set) var callCount = 0

        init(tier: ModelTier) {
            self.tier = tier
        }

        func spec(for request: SpecRequest) async throws -> ValidatedSpec {
            callCount += 1
            return try SpecValidator.validate(
                Spec(
                    read: "2+2=",
                    readConfidence: 0.9,
                    intent: .answer,
                    blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: "4")))]
                )
            )
        }
    }

    private final class Flag: @unchecked Sendable {
        var value: Bool
        init(value: Bool) { self.value = value }
    }
}
