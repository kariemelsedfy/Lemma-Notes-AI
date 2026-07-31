import Intelligence
import SwiftUI

/// What the Ask bar is showing, derived from the request state machine.
///
/// The bar has four appearances, not one per `AskState`: several pipeline stages look
/// identical to the user (`AI_PIPELINE.md` §7 — the whole point is that they feel like
/// one wait), and collapsing them here keeps the view free of pipeline vocabulary.
enum AskBarPhase: Equatable {
    /// A selection exists and is waiting for a verb.
    case offeringVerbs
    /// Work is in flight and can be cancelled.
    case working
    /// Ink is on the page unaccepted, waiting for keep or discard.
    case awaitingDecision
    case failed(AskFailure)
    /// Nothing to show.
    case hidden

    init(state: AskState, hasSelection: Bool) {
        switch state {
        case .idle:
            self = hasSelection ? .offeringVerbs : .hidden
        case .extracting, .classifying, .requesting, .streaming, .rendering:
            self = .working
        case .awaitingDecision:
            self = .awaitingDecision
        case .failed(let failure):
            self = .failed(failure)
        case .committed, .discarded:
            self = hasSelection ? .offeringVerbs : .hidden
        }
    }
}

/// The verbs offered for a selection, in the order they are shown.
enum AskVerb: String, CaseIterable, Identifiable {
    case answer
    case continuation
    case plot
    case check
    case ask

    var id: Self { self }

    var intent: SpecIntent {
        switch self {
        case .answer: .answer
        case .continuation: .continuation
        case .plot: .plot
        case .check: .check
        case .ask: .ask
        }
    }

    var symbolName: String {
        switch self {
        case .answer: "equal.square"
        case .continuation: "arrow.turn.down.right"
        case .plot: "chart.xyaxis.line"
        case .check: "checkmark.circle"
        case .ask: "questionmark.circle"
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey("ask.verb.\(rawValue)") }
}

/// The recovery copy for each designed failure (`AI_PIPELINE.md` §8).
extension AskFailure {
    var messageKey: LocalizedStringKey { LocalizedStringKey("ask.failure.\(rawValue)") }

    /// Whether retrying the same request could plausibly work.
    var isRetryable: Bool {
        switch self {
        case .invalidSpec, .offline, .timeout, .transport: true
        case .unreadable, .outOfCredits, .noRoom: false
        }
    }
}

/// The floating bar that turns a selection into an answer.
///
/// It never issues a request itself: every control calls back out, so the request
/// lifecycle stays in one place instead of being spread across a view.
struct AskBar: View {
    let phase: AskBarPhase
    let explanation: String?
    var onVerb: (AskVerb) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onAccept: () -> Void = {}
    var onReject: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        Group {
            switch phase {
            case .hidden:
                EmptyView()
            case .offeringVerbs:
                verbs
            case .working:
                working
            case .awaitingDecision:
                decision
            case .failed(let failure):
                self.failure(failure)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ask.bar")
    }

    private var verbs: some View {
        HStack(spacing: 8) {
            ForEach(AskVerb.allCases) { verb in
                Button {
                    onVerb(verb)
                } label: {
                    Label(verb.titleKey, systemImage: verb.symbolName)
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(verb.titleKey)
                .buttonStyle(.bordered)
            }
        }
    }

    private var working: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("ask.state.working")
            Button("ask.cancel", role: .cancel, action: onCancel)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var decision: some View {
        HStack(spacing: 12) {
            if let explanation, !explanation.isEmpty {
                // The explanation is shown, never inked, unless the user asks for it
                // (`AI_PIPELINE.md` §3).
                Text(explanation)
                    .lineLimit(2)
                    .accessibilityLabel(explanation)
            }
            Button("ask.keep", action: onAccept)
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 44, minHeight: 44)
            Button("ask.discard", role: .destructive, action: onReject)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private func failure(_ failure: AskFailure) -> some View {
        HStack(spacing: 12) {
            Text(failure.messageKey)
                .lineLimit(2)
            if failure.isRetryable {
                Button("ask.retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Button("ask.dismiss", action: onDismiss)
                .frame(minWidth: 44, minHeight: 44)
        }
    }
}
