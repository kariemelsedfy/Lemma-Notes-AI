/// First-party analytics primitives with no internal package dependency.
public enum AnalyticsModule {}

/// The only AI intents that can be recorded. User input is intentionally not representable.
public enum AIIntent: String, Sendable, Equatable, CaseIterable {
    case solve
    case explain
    case check
    case continueWork
}

/// The model-routing tier used for an AI action.
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
