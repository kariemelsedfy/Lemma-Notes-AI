/// First-party analytics primitives with no internal package dependency.
public enum AnalyticsModule {}

/// The only AI intents that can be recorded. User input is intentionally not representable.
///
/// These deliberately mirror the five verbs of the spec contract (`AI_PIPELINE.md` §3),
/// case for case and raw value for raw value. The dependency rule stops `Analytics` from
/// importing `Intelligence`, so the two enums cannot be one type — but they can be kept
/// in step, and `Apps/Margin` has a test that fails if they drift.
public enum AIIntent: String, Sendable, Equatable, CaseIterable {
    case answer
    /// Spelled `continue` on the wire; `continue` is a Swift keyword.
    case continuation = "continue"
    case plot
    case check
    case ask
}

/// The model-routing tier used for an AI action.
///
/// There is deliberately no mock case. A mocked action is not a real one and must never
/// reach analytics, so the type makes reporting one impossible rather than relying on a
/// caller to remember.
public enum AIModelTier: String, Sendable, Equatable, CaseIterable {
    case onDevice
    case privateCloudCompute
    case frontierCloud
}

/// A closed analytics vocabulary that cannot carry note content or user identifiers.
public enum AnalyticsEvent: Sendable, Equatable {
    case appOpened
    case noteCreated
    case strokeSessionEnded(strokeCount: Int)
    case aiInvoked(intent: AIIntent, tier: AIModelTier)
    case aiAccepted
    case aiRejected
    case paywallShown
    case purchaseCompleted
}

/// The only boundary allowed to transmit analytics events.
public protocol AnalyticsTransport: Sendable {
    func send(_ event: AnalyticsEvent) async
}

/// Applies the privacy opt-out before an event reaches any transport.
public actor AnalyticsClient {
    private let transport: any AnalyticsTransport
    private var isTrackingEnabled: Bool

    public init(transport: any AnalyticsTransport, isTrackingEnabled: Bool = true) {
        self.transport = transport
        self.isTrackingEnabled = isTrackingEnabled
    }

    public func setTrackingEnabled(_ isEnabled: Bool) {
        isTrackingEnabled = isEnabled
    }

    public func record(_ event: AnalyticsEvent) async {
        guard isTrackingEnabled else { return }
        await transport.send(event)
    }
}
