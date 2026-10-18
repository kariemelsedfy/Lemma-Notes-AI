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

    /// The strings-table keys. Built as `String`s and then wrapped: `LocalizedStringKey("a.\(x)")` is an
    /// interpolation, looked up as the format `a.%@`, which is never found and shows the raw key on screen.
    var titleName: String { "ask.verb.\(rawValue)" }
    var subtitleName: String { "ask.verb.\(rawValue).subtitle" }
    var titleKey: LocalizedStringKey { LocalizedStringKey(titleName) }
    var subtitleKey: LocalizedStringKey { LocalizedStringKey(subtitleName) }
}

/// The recovery copy for each designed failure (`AI_PIPELINE.md` §8).
extension AskFailure {
    var messageName: String { "ask.failure.\(rawValue)" }
    var messageKey: LocalizedStringKey { LocalizedStringKey(messageName) }

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
    var failureOverride: String?
    var failureDetail: String?
    var onVerb: (AskVerb) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onAccept: () -> Void = {}
    var onReject: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}
    /// Set when the answer is a plot: lets the writer correct the formula that was read.
    var onEditReading: (() -> Void)?

    @State private var showsDetail = false

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
                    .tourTarget(.verb(verb))
                    .accessibilityLabel(verb.titleKey)
                    .accessibilityHint(verb.subtitleKey)
                }
            }
        }
    }

    private var working: some View {
        HStack(spacing: 12) {
            ProgressView().tint(MarginColor.accent)
            Text("ask.state.working")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MarginColor.primaryText.opacity(0.85))
            decisionButton("ask.cancel", tint: MarginColor.accent, action: onCancel)
        }
        .padding(.leading, 6)
    }

    private var decision: some View {
        HStack(spacing: 10) {
            // Never the answer or the model's explanation of it: that is on the page. Only a short status
            // (what a plot read, which characters were typeset) ever appears here.
            if let status = Self.shortStatus(explanation) {
                Text(verbatim: status)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MarginColor.primaryText.opacity(0.85))
                    .lineLimit(1)
            }
            if let renderingNotice {
                renderingNotice.message
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MarginColor.secondaryText)
                    .lineLimit(1)
            }
            if let onEditReading {
                decisionButton("ask.edit", tint: MarginColor.secondaryText, action: onEditReading)
            }
            decisionButton("ask.discard", tint: .red, action: onReject)
            decisionButton("ask.keep", tint: MarginColor.accent, action: onAccept)
                .tourTarget(.keep)
        }
    }

    /// A one-line status, or nil when the text is long enough to be an explanation rather than a status.
    static func shortStatus(_ text: String?, limit: Int = 36) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= limit,
            !text.contains("\n")
        else { return nil }
        return text
    }

    private func decisionButton(_ title: LocalizedStringKey, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.16)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func failure(_ failure: AskFailure) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(MarginColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                failureText(failure)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MarginColor.primaryText.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    // The technical line is for whoever is debugging, so it stays hidden until the message is
                    // long-pressed, and exists only in debug builds.
                    .onLongPressGesture { showsDetail.toggle() }
                #if DEBUG
                    if showsDetail, let failureDetail {
                        Text(verbatim: failureDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(MarginColor.secondaryText)
                    }
                #endif
            }
            if failure.isRetryable {
                decisionButton("ask.retry", tint: MarginColor.accent, action: onRetry)
            }
            decisionButton("ask.dismiss", tint: MarginColor.secondaryText, action: onDismiss)
        }
        .padding(.leading, 6)
    }

    @ViewBuilder
    private func failureText(_ failure: AskFailure) -> some View {
        if let failureOverride {
            Text(verbatim: failureOverride)
        } else {
            Text(failure.messageKey)
        }
    }
}
