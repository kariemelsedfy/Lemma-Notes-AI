import Foundation

/// What the user has bought, or been given. The free tier is the whole notebook; hosted Ask is the paid part
/// (ADR-029, `PREMIUM_AND_ONBOARDING_PLAN.md`).
public enum Plan: String, Equatable, Sendable {
    /// No subscription: everything except hosted Ask.
    case free
    /// The 3-day introductory offer. Hosted Ask works, under the same cost allowance as a paying user.
    case trial
    case premium
    /// The heavy-use tier: the same hosted Ask with a much larger monthly allowance (still capped on the server).
    case pro
    /// A build provisioned with the owner's access token (the pilot). Replaced by App Attest before anyone else
    /// receives a build.
    case pilot

    public var includesHostedAsk: Bool { self != .free }
}

/// Whether a hosted Ask may leave the iPad right now, and if not, what to show instead.
public enum HostedAskAccess: Equatable, Sendable {
    case allowed
    /// A free user inside the guided tour, using one of its few asks.
    case onboardingAsk(remaining: Int)
    /// Show the subscribe screen. Never an error.
    case subscribeRequired
    /// The monthly cost allowance is used up; local plots and arithmetic still work.
    case allowanceUsedUp
}

/// The single question the app asks before a hosted call. The provider layer still refuses on its own
/// (invariant 8); this decides what the UI says.
public struct HostedAskPolicy: Equatable, Sendable {
    /// Free asks the guided tour grants a non-subscriber. Server-enforced once App Attest exists.
    public static let onboardingAsks = 3

    public var plan: Plan
    public var isInOnboarding: Bool
    public var onboardingAsksUsed: Int
    public var allowanceUsedUp: Bool

    public init(
        plan: Plan, isInOnboarding: Bool = false, onboardingAsksUsed: Int = 0, allowanceUsedUp: Bool = false
    ) {
        self.plan = plan
        self.isInOnboarding = isInOnboarding
        self.onboardingAsksUsed = onboardingAsksUsed
        self.allowanceUsedUp = allowanceUsedUp
    }

    public var access: HostedAskAccess {
        if plan.includesHostedAsk { return allowanceUsedUp ? .allowanceUsedUp : .allowed }
        let remaining = max(Self.onboardingAsks - onboardingAsksUsed, 0)
        if isInOnboarding, remaining > 0 { return .onboardingAsk(remaining: remaining) }
        return .subscribeRequired
    }

    public var mayTransmit: Bool {
        switch access {
        case .allowed, .onboardingAsk: true
        case .subscribeRequired, .allowanceUsedUp: false
        }
    }
}

/// Where the current plan comes from. Two implementations: today's pilot token, and StoreKit 2 (M6).
public protocol EntitlementProviding: Sendable {
    var plan: Plan { get }
}

public struct FixedEntitlement: EntitlementProviding {
    public let plan: Plan
    public init(_ plan: Plan) { self.plan = plan }
}
