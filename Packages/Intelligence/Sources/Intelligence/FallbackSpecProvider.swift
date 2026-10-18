import Foundation

/// Asks `primary` first and only escalates to `fallback` when the primary could not answer.
///
/// This is how the mini-6 pilot routes (ADR-027/028): the free, offline arithmetic evaluator answers what it
/// can, and everything else may go to the hosted proxy. **The fallback must already be wrapped in
/// `ConsentGatedProvider`**; this type adds no consent logic of its own and never sends anything itself, so
/// invariant 8 still lives in the provider layer.
///
/// `tier` reports the primary's tier on purpose: wrapping this composite in a consent gate would wrongly
/// pass or block the local path. Gate the fallback, not the composite.
public struct FallbackSpecProvider: SpecProvider {
    private let primary: any SpecProvider
    private let fallback: any SpecProvider
    private let shouldEscalate: @Sendable (any Error) -> Bool
    private let surfacesConsentRequirement: @Sendable (any Error) -> Bool

    public var tier: ModelTier { primary.tier }

    /// - Parameters:
    ///   - shouldEscalate: whether a primary failure is "I cannot answer this" (escalate) rather than a
    ///     real fault. Cancellation never escalates.
    ///   - surfacesConsentRequirement: for a primary failure it returns true for, a refusal by the gated
    ///     fallback (nothing was sent) is thrown instead of the primary's own error. The app uses it to offer
    ///     Premium to an install that is not entitled to the hosted model; the default keeps the primary's more
    ///     specific explanation.
    public init(
        primary: any SpecProvider,
        fallback: any SpecProvider,
        surfacesConsentRequirement: @escaping @Sendable (any Error) -> Bool = { _ in false },
        shouldEscalate: @escaping @Sendable (any Error) -> Bool
    ) {
        self.primary = primary
        self.fallback = fallback
        self.surfacesConsentRequirement = surfacesConsentRequirement
        self.shouldEscalate = shouldEscalate
    }

    public func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        do {
            return try await primary.spec(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let primaryError where shouldEscalate(primaryError) {
            do {
                return try await fallback.spec(for: request)
            } catch ProviderError.thirdPartyConsentRequired {
                // Nothing was sent.
                if surfacesConsentRequirement(primaryError) { throw ProviderError.thirdPartyConsentRequired }
                // Otherwise the user still gets the primary's own, more specific, explanation.
                throw primaryError
            }
        }
    }
}
