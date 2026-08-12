import XCTest

@testable import Intelligence

/// The routing policy (M4-03, `AI_PIPELINE.md` §5).
///
/// Pure input to pure output, so this can be exhaustive rather than representative — and it
/// should be, because the rules that matter most here are the ones that must *never* fire.
final class RoutingPolicyTests: XCTestCase {
    // MARK: - The promises

    /// Private Mode is a promise, not a preference. No input combination may break it.
    func testPrivateModeNeverLeavesTheDevice() {
        for complexity in ContentComplexity.allCases {
            for confidence in [0.0, 0.5, 0.74, 0.75, 1.0] {
                for online in [true, false] {
                    for pcc in [true, false] {
                        let decision = RoutingPolicy.decide(
                            Self.inputs(
                                complexity: complexity,
                                readConfidence: confidence,
                                isOnline: online,
                                supportsPrivateCloudCompute: pcc,
                                entitlement: Self.entitlement(prefersOnDeviceOnly: true)
                            )
                        )

                        XCTAssertNotEqual(decision.tier, .frontierCloud, "\(complexity) \(confidence)")
                        XCTAssertNotEqual(decision.tier, .privateCloudCompute, "\(complexity) \(confidence)")
                    }
                }
            }
        }
    }

    /// Content reaches a third party only with consent. The provider layer asserts this too
    /// (invariant 8) — belt and braces, because this one is a legal obligation.
    func testNothingReachesAThirdPartyWithoutConsent() {
        for complexity in ContentComplexity.allCases {
            for confidence in [0.0, 0.5, 0.9] {
                let decision = RoutingPolicy.decide(
                    Self.inputs(
                        complexity: complexity,
                        readConfidence: confidence,
                        supportsPrivateCloudCompute: false,
                        entitlement: Self.entitlement(hasThirdPartyConsent: false)
                    )
                )

                XCTAssertNotEqual(decision.tier, .frontierCloud, "\(complexity) at \(confidence)")
            }
        }
    }

    func testOfflineNeverRoutesToANetworkTier() {
        for complexity in ContentComplexity.allCases {
            let decision = RoutingPolicy.decide(
                Self.inputs(complexity: complexity, isOnline: false, supportsPrivateCloudCompute: true))

            XCTAssertEqual(decision.tier, .onDevice, "\(complexity)")
            XCTAssertEqual(decision.reason, "offline")
        }
    }

    /// Classifying the verb happens before the user has agreed to anything (§5).
    func testIntentClassificationIsAlwaysLocal() {
        let decision = RoutingPolicy.decide(
            Self.inputs(intent: nil, complexity: .hard, supportsPrivateCloudCompute: true))

        XCTAssertEqual(decision.tier, .onDevice)
    }

    /// The mock tier is for CI, and a shipping routing decision must never produce it.
    func testNoInputRoutesToTheMockTier() {
        for complexity in ContentComplexity.allCases {
            for availability in Self.everyAvailability {
                for online in [true, false] {
                    for pcc in [true, false] {
                        let decision = RoutingPolicy.decide(
                            Self.inputs(
                                complexity: complexity,
                                isOnline: online,
                                availability: availability,
                                supportsPrivateCloudCompute: pcc
                            )
                        )

                        XCTAssertNotEqual(decision.tier, .mock)
                    }
                }
            }
        }
    }

    // MARK: - Routing up

    func testSimpleConfidentWorkStaysOnDevice() {
        let decision = RoutingPolicy.decide(
            Self.inputs(complexity: .simple, readConfidence: 0.95, supportsPrivateCloudCompute: true))

        XCTAssertEqual(decision.tier, .onDevice)
        XCTAssertEqual(decision.reason, "simpleAndConfident")
    }

    func testModerateWorkGoesToPrivateCloudWhenItExists() {
        let decision = RoutingPolicy.decide(
            Self.inputs(complexity: .moderate, supportsPrivateCloudCompute: true))

        XCTAssertEqual(decision.tier, .privateCloudCompute)
    }

    func testHardWorkGoesToTheFrontierEvenWhenPrivateCloudExists() {
        let decision = RoutingPolicy.decide(
            Self.inputs(complexity: .hard, supportsPrivateCloudCompute: true))

        XCTAssertEqual(decision.tier, .frontierCloud)
    }

    /// A read we do not trust escalates even when the content looks easy — what makes it look
    /// easy is a transcript we do not believe.
    func testAPoorLocalReadEscalates() {
        let decision = RoutingPolicy.decide(
            Self.inputs(complexity: .simple, readConfidence: 0.5, supportsPrivateCloudCompute: true))

        XCTAssertEqual(decision.tier, .privateCloudCompute)
        XCTAssertEqual(decision.reason, "lowReadConfidence")
    }

    /// The threshold is above `SpecValidator`'s 0.6 fail-closed floor, deliberately: 0.6 means
    /// "do not render", not "good enough to answer from".
    func testTheConfidenceThresholdSitsAboveTheValidatorsFloor() {
        XCTAssertGreaterThan(RoutingPolicy.confidentRead, 0.6)

        let justUnder = RoutingPolicy.decide(
            Self.inputs(complexity: .simple, readConfidence: RoutingPolicy.confidentRead - 0.01))
        let justOver = RoutingPolicy.decide(
            Self.inputs(complexity: .simple, readConfidence: RoutingPolicy.confidentRead))

        XCTAssertNotEqual(justUnder.tier, .onDevice)
        XCTAssertEqual(justOver.tier, .onDevice)
    }

    // MARK: - iPadOS 26, where there is no T1 (M4-01)

    /// The tier the docs assumed does not exist on our SDK, so moderate work has to go
    /// somewhere. It must not silently stay on a model that cannot do it.
    func testWithoutPrivateCloudModerateWorkGoesToTheFrontier() {
        let decision = RoutingPolicy.decide(
            Self.inputs(complexity: .moderate, supportsPrivateCloudCompute: false))

        XCTAssertEqual(decision.tier, .frontierCloud)
    }

    // MARK: - When the device cannot run the model at all (ADR-017)

    /// The normal state for a mainland-China user today, and it must be a route rather than
    /// an error: escalate rather than refuse.
    func testAnIneligibleDeviceEscalatesRatherThanFailing() {
        let decision = RoutingPolicy.decide(
            Self.inputs(complexity: .simple, availability: .deviceNotEligible))

        XCTAssertEqual(decision.tier, .frontierCloud)
        XCTAssertEqual(decision.reason, "onDeviceUnavailable")
    }

    /// Offline, with no on-device model, and nothing else permitted: the honest answer is a
    /// failure the user can act on, not a spinner.
    func testOfflineWithNoOnDeviceModelFailsHonestly() {
        let decision = RoutingPolicy.decide(
            Self.inputs(isOnline: false, availability: .appleIntelligenceNotEnabled))

        XCTAssertEqual(decision.outcome, .unavailable(.unreadable))
        XCTAssertNil(decision.tier)
    }

    /// Assets still downloading is temporary, so it maps to the one failure §8 makes
    /// retryable rather than to a permanent-sounding one.
    func testAModelStillDownloadingIsRetryable() {
        let decision = RoutingPolicy.decide(
            Self.inputs(isOnline: false, availability: .modelNotReady))

        XCTAssertEqual(decision.outcome, .unavailable(.timeout))
    }

    // MARK: - Money

    func testRunningOutOfCreditsFallsBackToTheDeviceRatherThanFailing() {
        let decision = RoutingPolicy.decide(
            Self.inputs(
                complexity: .hard,
                supportsPrivateCloudCompute: false,
                entitlement: Self.entitlement(hasCredits: false)))

        // A worse answer beats no answer, and the bar in the UI explains the difference (§8).
        XCTAssertEqual(decision.tier, .onDevice)
        XCTAssertEqual(decision.reason, "outOfCreditsFellBackOnDevice")
    }

    func testOutOfCreditsWithNoOnDeviceModelReportsTheRealReason() {
        let decision = RoutingPolicy.decide(
            Self.inputs(
                complexity: .hard,
                availability: .deviceNotEligible,
                supportsPrivateCloudCompute: false,
                entitlement: Self.entitlement(hasCredits: false)))

        XCTAssertEqual(decision.outcome, .unavailable(.outOfCredits))
    }

    // MARK: - The log

    /// Every decision is explainable, and no explanation may carry page content (`AGENTS.md` §7).
    func testEveryDecisionCarriesANonEmptyContentFreeReason() {
        for complexity in ContentComplexity.allCases {
            for availability in Self.everyAvailability {
                for online in [true, false] {
                    for credits in [true, false] {
                        let decision = RoutingPolicy.decide(
                            Self.inputs(
                                complexity: complexity,
                                isOnline: online,
                                availability: availability,
                                entitlement: Self.entitlement(hasCredits: credits)))

                        XCTAssertFalse(decision.reason.isEmpty)
                        XCTAssertNil(decision.reason.rangeOfCharacter(from: .whitespaces))
                    }
                }
            }
        }
    }

    // MARK: - Fixtures

    private static let everyAvailability: [OnDeviceAvailability] = [
        .available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady,
    ]

    private static func entitlement(
        hasCredits: Bool = true,
        hasThirdPartyConsent: Bool = true,
        prefersOnDeviceOnly: Bool = false
    ) -> RoutingEntitlement {
        RoutingEntitlement(
            hasCredits: hasCredits,
            hasThirdPartyConsent: hasThirdPartyConsent,
            prefersOnDeviceOnly: prefersOnDeviceOnly
        )
    }

    private static func inputs(
        intent: SpecIntent? = .answer,
        complexity: ContentComplexity = .moderate,
        readConfidence: Double = 0.9,
        isOnline: Bool = true,
        availability: OnDeviceAvailability = .available,
        supportsPrivateCloudCompute: Bool = false,
        entitlement: RoutingEntitlement = entitlement()
    ) -> RoutingInputs {
        RoutingInputs(
            intent: intent,
            complexity: complexity,
            readConfidence: readConfidence,
            isOnline: isOnline,
            availability: availability,
            supportsPrivateCloudCompute: supportsPrivateCloudCompute,
            entitlement: entitlement
        )
    }
}
