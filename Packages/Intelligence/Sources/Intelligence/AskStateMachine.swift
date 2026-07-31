import Foundation

/// One recorded transition.
///
/// Names only. A transition record is the thing most likely to end up in a log or an
/// analytics payload, so it is built so that it *cannot* carry a crop, a transcription,
/// or an answer (`AGENTS.md` §7).
public struct AskTransition: Equatable, Sendable {
    public let from: String
    public let event: String
    public let destination: String
    /// True when the event did not apply and the state was left alone.
    public let wasRejected: Bool

    public init(from: String, event: String, destination: String, wasRejected: Bool) {
        self.from = from
        self.event = event
        self.destination = destination
        self.wasRejected = wasRejected
    }
}

/// Drives one Ask from selection to ink, or to a designed failure.
///
/// A value type on purpose: the transition rules are the interesting part and they are
/// pure, so they can be tested exhaustively without a canvas, a provider, or an actor.
public struct AskStateMachine: Equatable, Sendable {
    public private(set) var state: AskState
    /// Every transition attempt in order, including rejected ones.
    public private(set) var transcript: [AskTransition]

    public init(state: AskState = .idle) {
        self.state = state
        transcript = []
    }

    /// Applies an event. Returns false when the event does not apply in this state, in
    /// which case the state is unchanged and the attempt is still recorded.
    ///
    /// Ignoring an impossible event rather than trapping matters because these arrive
    /// from async work: a response landing after the user already cancelled is normal,
    /// not a programmer error.
    @discardableResult
    public mutating func apply(_ event: AskEvent) -> Bool {
        let from = state
        guard let next = Self.next(from: from, event: event) else {
            transcript.append(
                AskTransition(from: from.name, event: event.name, destination: from.name, wasRejected: true)
            )
            return false
        }
        state = next
        transcript.append(AskTransition(from: from.name, event: event.name, destination: next.name, wasRejected: false))
        return true
    }

    /// The transition table.
    public static func next(from state: AskState, event: AskEvent) -> AskState? {
        // Abandonment and failure apply at any point where work is in flight, which is
        // what makes "cancellation must work at every stage" true by construction.
        switch event {
        case .cancel(let reason):
            return state.isCancellable ? .discarded(reason) : nil
        case .fail(let failure):
            return state.isCancellable ? .failed(failure) : nil
        case .begin:
            // A finished Ask can start another; one in flight must be cancelled first.
            return state.isCancellable ? nil : .extracting
        default:
            break
        }

        return advance(from: state, event: event)
    }

    /// The ordered part of the lifecycle, once abandonment has been ruled out.
    private static func advance(from state: AskState, event: AskEvent) -> AskState? {
        switch (state, event) {
        case (.extracting, .contextExtracted(let context)):
            return .classifying(context)
        case (.classifying, .intentClassified(let request)):
            return .requesting(request)
        case (.requesting(let request), .responseStarted):
            return .streaming(request)
        case (.requesting, .specValidated(let spec)), (.streaming, .specValidated(let spec)):
            // A decline is a valid answer, not a crash: the caller shows the read back
            // and lets the user correct it (`AI_PIPELINE.md` §8).
            return spec.isDecline ? .failed(.unreadable) : .rendering(spec)
        case (.rendering(let spec), .placed(let result)):
            return result.placements.isEmpty ? .failed(.noRoom) : .awaitingDecision(spec, result)
        case (.awaitingDecision(let spec, let result), .accept):
            return .committed(spec, result)
        case (.awaitingDecision, .reject):
            return .discarded(.rejected)
        default:
            return nil
        }
    }
}
