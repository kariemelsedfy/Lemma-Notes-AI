import DesignSystem
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

enum AskRenderingNotice: Equatable {
    /// These characters of the answer have no sample in the writer's hand and are drawn typeset;
    /// everything else in the answer is their own writing.
    case substitutedCharacters(String)

    var message: Text {
        switch self {
        case .substitutedCharacters(let characters):
            Text("ask.notice.substituted-characters \(characters)")
        }
    }
}

/// The choices offered for a selection, in the order they are shown.
///
/// Three, each a different kind of help: `answer` solves arithmetic and equations, `explain` answers a
/// question, defines a term or carries a thought on (it is the old "continue" and "ask" merged; on the wire
/// it is still the `continue` intent), and `plot` draws a function locally, with no model at all.
enum AskVerb: String, CaseIterable, Identifiable {
    case answer
    case explain
    case plot

    var id: Self { self }

    var intent: SpecIntent {
        switch self {
        case .answer: .answer
        case .explain: .continuation
        case .plot: .plot
        }
    }

    var symbolName: String {
        switch self {
        case .answer: "equal.square"
        case .explain: "text.bubble"
        case .plot: "chart.xyaxis.line"
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey("ask.verb.\(rawValue)") }
    var subtitleKey: LocalizedStringKey { LocalizedStringKey("ask.verb.\(rawValue).subtitle") }
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
    var renderingNotice: AskRenderingNotice?
    var failureOverride: LocalizedStringKey?
    var failureDetail: String?
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ask.bar")
    }

    private var verbs: some View {
        VStack(spacing: 8) {
            Text("ask.verbs.prompt")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MarginColor.secondaryText)
            HStack(spacing: 8) {
                ForEach(AskVerb.allCases) { verb in
                    Button {
                        onVerb(verb)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: verb.symbolName)
                                .font(.system(size: 22, weight: .regular))
                            Text(verb.titleKey)
                                .font(.subheadline.weight(.semibold))
                            Text(verb.subtitleKey)
                                .font(.caption2)
                                .foregroundStyle(MarginColor.secondaryText)
                        }
                        .foregroundStyle(MarginColor.accent)
                        .frame(width: 112, height: 78)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(MarginColor.accent.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(verb.titleKey)
                    .accessibilityHint(verb.subtitleKey)
                }
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
            if (explanation?.isEmpty == false) || renderingNotice != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let explanation, !explanation.isEmpty {
                        // The explanation is shown, never inked, unless the user asks for it
                        // (`AI_PIPELINE.md` §3).
                        Text(explanation)
                            .lineLimit(2)
                            .accessibilityLabel(explanation)
                    }
                    if let renderingNotice {
                        renderingNotice.message
                            .font(.caption)
                            .foregroundStyle(MarginColor.secondaryText)
                            .lineLimit(2)
                    }
                }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(failureOverride ?? failure.messageKey)
                    .lineLimit(2)
                #if DEBUG
                    if let failureDetail {
                        Text(verbatim: failureDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(MarginColor.secondaryText)
                    }
                #endif
            }
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
