import Analytics
import Intelligence

/// Translates pipeline vocabulary into analytics vocabulary.
///
/// `Analytics` and `Intelligence` cannot see each other — the dependency rule gives both
/// an empty internal import list and an `InkCore`/`Handwriting` one respectively — so the
/// app is the only place the two can meet. Keeping the translation in one file, total and
/// tested, is what stops a new verb from being silently unreportable.
extension AIIntent {
    /// Every spec intent maps to exactly one analytics intent. There is no default case:
    /// adding a verb to `SpecIntent` must fail to compile here rather than be dropped.
    init(_ intent: SpecIntent) {
        switch intent {
        case .answer: self = .answer
        case .continuation: self = .continuation
        case .plot: self = .plot
        case .check: self = .check
        case .ask: self = .ask
        }
    }
}

extension AIModelTier {
    /// Nil for the mock tier, which must never be reported.
    ///
    /// A mocked action is not a real one; counting it would corrupt the acceptance-rate
    /// and cost metrics in `PROJECT_PLAN.md` §8 with runs that never touched a model.
    init?(_ tier: ModelTier) {
        switch tier {
        case .onDevice: self = .onDevice
        case .privateCloudCompute: self = .privateCloudCompute
        case .frontierCloud: self = .frontierCloud
        case .mock: return nil
        }
    }
}

/// Builds the analytics event for an invoked AI action, or nil when it must not be
/// reported.
enum AIInvocationReport {
    static func event(intent: SpecIntent, tier: ModelTier) -> AnalyticsEvent? {
        guard let reportableTier = AIModelTier(tier) else { return nil }
        return .aiInvoked(intent: AIIntent(intent), tier: reportableTier)
    }
}
