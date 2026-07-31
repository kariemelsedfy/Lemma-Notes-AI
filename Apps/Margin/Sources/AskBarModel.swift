import Intelligence
import SwiftUI

/// Owns the Ask lifecycle for one canvas.
///
/// `Intelligence` deliberately does not import SwiftUI, so the observable wrapper around
/// `AskStateMachine` lives here. This type holds no pipeline logic of its own — every
/// transition goes through the machine, so the legal orderings stay in one place.
@MainActor
final class AskBarModel: ObservableObject {
    @Published private(set) var state: AskState = .idle
    @Published private(set) var hasSelection = false

    /// Kept so a retry can reissue the same verb without asking the user again.
    private(set) var lastVerb: AskVerb?
    private var machine = AskStateMachine()

    var phase: AskBarPhase { AskBarPhase(state: state, hasSelection: hasSelection) }

    /// The model's own words about the answer, shown in the bar and never inked.
    var explanation: String? {
        switch state {
        case .awaitingDecision(let spec, _): spec.explanation
        default: nil
        }
    }

    /// The frames the answer will occupy, for the canvas to outline while the user decides.
    var pendingFrames: [CGRect] {
        switch state {
        case .awaitingDecision(_, let result): result.placements.map(\.frame)
        default: []
        }
    }

    func selectionChanged(hasSelection: Bool) {
        self.hasSelection = hasSelection
        // A new selection abandons whatever the last one was doing; a stale answer
        // pointing at ink the user is no longer looking at is worse than no answer.
        if !hasSelection || state.isCancellable {
            apply(.cancel(.superseded))
        }
    }

    /// The user picked a verb. Returns false when an Ask is already in flight.
    @discardableResult
    func begin(_ verb: AskVerb) -> Bool {
        guard hasSelection else { return false }
        lastVerb = verb
        return apply(.begin)
    }

    @discardableResult
    func retry() -> Bool {
        guard let lastVerb else { return false }
        return begin(lastVerb)
    }

    func cancel() {
        apply(.cancel(.cancelled))
    }

    func userResumedWriting() {
        apply(.cancel(.userResumedWriting))
    }

    func accept() {
        apply(.accept)
    }

    func reject() {
        apply(.reject)
    }

    /// Clears a failure without starting anything new.
    func dismissFailure() {
        guard case .failed = state else { return }
        machine = AskStateMachine()
        state = machine.state
    }

    /// Forwards a pipeline event from whatever is driving the request.
    @discardableResult
    func apply(_ event: AskEvent) -> Bool {
        let applied = machine.apply(event)
        state = machine.state
        return applied
    }

    /// The transition log, names only, safe to hand to a logger (`AGENTS.md` §7).
    var transcript: [AskTransition] { machine.transcript }
}
