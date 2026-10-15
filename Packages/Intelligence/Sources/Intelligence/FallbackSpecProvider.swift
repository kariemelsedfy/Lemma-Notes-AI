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

    public var tier: ModelTier { primary.tier }

    /// - Parameters:
    ///   - shouldEscalate: whether a primary failure is "I cannot answer this" (escalate) rather than a
    ///     real fault. Cancellation never escalates.
    public init(
        primary: any SpecProvider,
        fallback: any SpecProvider,
        shouldEscalate: @escaping @Sendable (any Error) -> Bool
    ) {
        self.primary = primary
        self.fallback = fallback
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
                // Nothing was sent. The user still gets the primary's own, more specific, explanation.
                throw primaryError
            }
        }
    }
}
