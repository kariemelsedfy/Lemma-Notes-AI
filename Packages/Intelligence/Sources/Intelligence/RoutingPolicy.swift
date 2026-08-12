import Foundation

/// Whether the on-device model can run **on this device**, and if not, why.
///
/// Mirrors the shape of `SystemLanguageModel.Availability` without importing the framework:
/// `Intelligence` builds and tests on macOS, and the dependency rule keeps platform SDKs at the
/// app boundary. The app maps the framework's value onto this at one place.
///
/// **This is what the policy asks instead of asking where the user is** (ADR-017). A region
/// table would have been wrong twice in the six weeks around that decision; this is right on
/// the day Apple changes something.
public enum OnDeviceAvailability: Equatable, Sendable {
    case available
    /// The hardware cannot run it. Permanent for this device.
    case deviceNotEligible
    /// The user has Apple Intelligence switched off. Their choice, and reversible.
    case appleIntelligenceNotEnabled
    /// Assets are still downloading. Temporary, and worth retrying rather than escalating.
    case modelNotReady

    public var canRun: Bool { self == .available }
}

/// What the user has paid for and consented to.
public struct RoutingEntitlement: Equatable, Sendable {
    /// AI actions remain in this period's allowance (`BUSINESS.md`).
    public let hasCredits: Bool
    /// App Store 5.1.2(i) consent for sending content to a third party. Asserted again in the
    /// provider layer (invariant 8); this only decides whether it is worth routing there.
    public let hasThirdPartyConsent: Bool
    /// The user asked for nothing to leave the device (`BUSINESS.md` Private Mode).
    public let prefersOnDeviceOnly: Bool

    public init(hasCredits: Bool, hasThirdPartyConsent: Bool, prefersOnDeviceOnly: Bool) {
        self.hasCredits = hasCredits
        self.hasThirdPartyConsent = hasThirdPartyConsent
        self.prefersOnDeviceOnly = prefersOnDeviceOnly
    }
}

/// How hard the content is, as judged locally before anything is sent.
public enum ContentComplexity: Int, Equatable, Sendable, CaseIterable, Comparable {
    /// Arithmetic, unit conversion, a short read, spelling (`AI_PIPELINE.md` §5).
    case simple = 0
    /// Algebra, a short derivation, prose continuation.
    case moderate = 1
    /// Multi-step reasoning, unusual notation, a plot with an awkward domain.
    case hard = 2

    public static func < (lhs: ContentComplexity, rhs: ContentComplexity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Everything the routing decision is allowed to depend on.
public struct RoutingInputs: Equatable, Sendable {
    public let intent: SpecIntent?
    public let complexity: ContentComplexity
    /// The local reading's confidence. A poor read is a reason to escalate: a better model can
    /// often decipher what Vision could not.
    public let readConfidence: Double
    public let isOnline: Bool
    public let availability: OnDeviceAvailability
    /// Whether this build can reach Apple's server model at all. **False on iPadOS 26**, where
    /// `PrivateCloudComputeLanguageModel` does not exist (M4-01, `AI_PIPELINE.md` §5.1).
    public let supportsPrivateCloudCompute: Bool
    public let entitlement: RoutingEntitlement

    public init(
        intent: SpecIntent?,
        complexity: ContentComplexity,
        readConfidence: Double,
        isOnline: Bool,
        availability: OnDeviceAvailability,
        supportsPrivateCloudCompute: Bool,
        entitlement: RoutingEntitlement
    ) {
        self.intent = intent
        self.complexity = complexity
        self.readConfidence = readConfidence
        self.isOnline = isOnline
        self.availability = availability
        self.supportsPrivateCloudCompute = supportsPrivateCloudCompute
        self.entitlement = entitlement
    }
}

/// Where a request should go, and why it went there.
public struct RoutingDecision: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case route(ModelTier)
        /// Nothing can serve this request. The caller turns this into the matching §8 failure.
        case unavailable(AskFailure)
    }

    public let outcome: Outcome
    /// Why, as a name safe to log. Carries no page content, no transcription, no answer
    /// (`AGENTS.md` §7) — it names the rule, not the request.
    public let reason: String

    public var tier: ModelTier? {
        if case .route(let tier) = outcome { return tier }
        return nil
    }
}

/// Picks the tier for one request.
///
/// `AI_PIPELINE.md` §5: three tiers, route up only when necessary, and **do not scatter routing
/// decisions**. One pure function, so the whole policy can be read in one sitting and tested
/// without a network, a device, or a model.
///
/// The order of the rules is the policy. Privacy and availability come before capability,
/// because a rule that can send content somewhere the user forbade is not a routing bug, it is
/// a broken promise.
public enum RoutingPolicy {
    public static func decide(_ inputs: RoutingInputs) -> RoutingDecision {
        // 1. Intent classification never leaves the device (§5). It is cheap, constant, and
        //    happens before the user has agreed to anything.
        if inputs.intent == nil {
            return onDeviceOrNothing(inputs, reason: "intentClassificationIsAlwaysLocal")
        }

        // 2. Private Mode is absolute. Not "prefer", not "unless it would be better".
        if inputs.entitlement.prefersOnDeviceOnly {
            return onDeviceOrNothing(inputs, reason: "privateModeIsOnDeviceOnly")
        }

        // 3. Offline. Queuing is deliberately wrong here — a stale answer to a question the
        //    user has moved past is worthless (§8) — so it is the on-device model or nothing.
        if !inputs.isOnline {
            return onDeviceOrNothing(inputs, reason: "offline")
        }

        // 4. The on-device model handles simple work, and handles it for free. Escalating it
        //    would spend money and latency to produce the same `4`.
        if inputs.availability.canRun, inputs.complexity == .simple, inputs.readConfidence >= confidentRead {
            return RoutingDecision(outcome: .route(.onDevice), reason: "simpleAndConfident")
        }

        // 5. A poor local read escalates even when the content looks easy: what makes it look
        //    easy is a transcript we do not trust.
        let reason =
            inputs.readConfidence < confidentRead
            ? "lowReadConfidence" : (inputs.availability.canRun ? "beyondOnDevice" : "onDeviceUnavailable")

        return escalate(inputs, reason: reason)
    }

    /// Above this, the local reading is trusted enough to answer from.
    ///
    /// Deliberately above `SpecValidator`'s 0.6 fail-closed floor: 0.6 is "do not render this",
    /// which is a different and much lower bar than "this is good enough not to ask a better
    /// model". Between the two, escalating costs money; below 0.6 nothing renders anyway.
    static let confidentRead = 0.75

    private static func escalate(_ inputs: RoutingInputs, reason: String) -> RoutingDecision {
        // T1 first: it is free to us under the Small Business Program and it does not hand
        // content to a third party, so it needs no consent gate.
        if inputs.supportsPrivateCloudCompute, inputs.complexity < .hard {
            return RoutingDecision(outcome: .route(.privateCloudCompute), reason: reason)
        }

        // T2 is the only tier that leaves Apple's world, so it is the only one that can be
        // refused on consent — and the only one that costs the user an action.
        guard inputs.entitlement.hasThirdPartyConsent else {
            return fallBackOnDevice(inputs, ifNothingElse: .unreadable, reason: "noThirdPartyConsent")
        }
        guard inputs.entitlement.hasCredits else {
            return fallBackOnDevice(inputs, ifNothingElse: .outOfCredits, reason: "outOfCredits")
        }
        return RoutingDecision(outcome: .route(.frontierCloud), reason: reason)
    }

    /// The on-device model is the floor the product degrades to. It is worse at hard content
    /// than the tier we wanted, and it is infinitely better than a failure the user cannot act
    /// on — so a blocked escalation lands here whenever the device can run it at all.
    private static func fallBackOnDevice(
        _ inputs: RoutingInputs,
        ifNothingElse failure: AskFailure,
        reason: String
    ) -> RoutingDecision {
        guard inputs.availability.canRun else {
            return RoutingDecision(outcome: .unavailable(failure), reason: reason)
        }
        return RoutingDecision(outcome: .route(.onDevice), reason: reason + "FellBackOnDevice")
    }

    /// For the rules where escalation is not permitted at all: local, or an honest failure.
    ///
    /// `modelNotReady` is temporary — assets are still downloading — so it maps to `timeout`,
    /// which is the one failure state §8 makes retryable. The other two are not the user's
    /// fault and not fixable by retrying, so they read as `unreadable`: we could not answer.
    private static func onDeviceOrNothing(_ inputs: RoutingInputs, reason: String) -> RoutingDecision {
        switch inputs.availability {
        case .available:
            return RoutingDecision(outcome: .route(.onDevice), reason: reason)
        case .modelNotReady:
            return RoutingDecision(outcome: .unavailable(.timeout), reason: reason + "ModelNotReady")
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            return RoutingDecision(outcome: .unavailable(.unreadable), reason: reason + "NoOnDeviceModel")
        }
    }
}
