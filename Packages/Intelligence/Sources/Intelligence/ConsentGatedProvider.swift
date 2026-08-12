import Foundation

extension ModelTier {
    /// Whether answering at this tier hands the user's work to someone else.
    ///
    /// **Exhaustive on purpose.** Adding a tier without deciding this is a compile error, which
    /// is the only kind of reminder that survives a busy afternoon. `AGENTS.md` §7 and App Store
    /// 5.1.2(i) both hang off this one boolean.
    public var transmitsContentToThirdParty: Bool {
        switch self {
        case .onDevice:
            // Never leaves the iPad. This is the tier Private Mode and offline both rely on.
            false
        case .privateCloudCompute:
            // Leaves the device, but not Apple's world: PCC is covered by the user's existing
            // relationship with Apple rather than by a third-party disclosure. If that reading
            // ever changes, this is the line to change and every gate follows.
            false
        case .frontierCloud:
            true
        case .mock:
            // CI only, and it answers from fixtures without a network. Treated as local so the
            // test suite does not need a consent fixture to exercise the pipeline.
            false
        }
    }
}

/// Wraps a provider so that content cannot reach a third party without recorded consent.
///
/// **Invariant 8: the assertion lives here, not in the UI.** A check in a view protects the one
/// path that view owns; the next call site — a retry, a speculative prefetch (M4-10), a batch
/// re-render — does not go through it. A wrapper around the provider protocol is the only place
/// every request must pass, so it is the only place the check is worth making.
///
/// It deliberately fails **closed**: an unknown consent state refuses, because the cost of
/// wrongly refusing is an error message and the cost of wrongly permitting is a policy breach
/// with someone's homework in it.
public struct ConsentGatedProvider: SpecProvider {
    private let wrapped: any SpecProvider
    private let isConsentGranted: @Sendable () -> Bool

    public var tier: ModelTier { wrapped.tier }

    /// - Parameter isConsentGranted: read at request time rather than captured as a value, so a
    ///   consent withdrawn mid-session takes effect on the next request instead of the next
    ///   launch.
    public init(wrapping provider: any SpecProvider, isConsentGranted: @escaping @Sendable () -> Bool) {
        wrapped = provider
        self.isConsentGranted = isConsentGranted
    }

    public func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        guard !wrapped.tier.transmitsContentToThirdParty || isConsentGranted() else {
            throw ProviderError.thirdPartyConsentRequired
        }
        return try await wrapped.spec(for: request)
    }
}

extension SpecProvider {
    /// The one supported way to build a provider that may transmit content.
    ///
    /// Named as an instruction rather than a utility: a transmitting provider that is *not*
    /// gated is a bug, and `ProviderRegistryTests` asserts that every transmitting tier is
    /// refused without consent.
    public func gated(by isConsentGranted: @escaping @Sendable () -> Bool) -> ConsentGatedProvider {
        ConsentGatedProvider(wrapping: self, isConsentGranted: isConsentGranted)
    }
}
