import Foundation
import Handwriting
import Intelligence

/// Which of `HANDWRITING.md` §8's three styles generated ink is drawn in.
enum HandwritingStyleChoice: String, CaseIterable, Identifiable, Sendable {
    /// The glyph bank at the writer's own measured variance.
    case mine
    /// The same bank with variance cut by roughly 60%. §8 expects several early testers to
    /// prefer this *over* their real hand for answers, which would itself be a finding.
    case neat
    /// Clean letterforms nobody will mistake for their own hand. The honest fallback, and
    /// the right default in Exam Mode.
    case typeset

    var id: String { rawValue }

    var localizedNameKey: String { "style.\(rawValue)" }

    /// Whether this choice needs a calibrated bank to mean anything.
    var needsBank: Bool { self != .typeset }

    var variation: Synthesizer.Variation {
        switch self {
        case .mine: .natural
        case .neat: .neat
        case .typeset: .natural
        }
    }
}

/// Content-free state recorded when an Ask starts, so device diagnostics can identify
/// style-selection failures without logging handwriting, transcription, or answers.
struct HandwritingStyleStatus: Equatable, Sendable {
    let bankMissing: Bool
    let characterCount: Int
    let canRenderCannedAnswer: Bool
    let selected: HandwritingStyleChoice
    let resolved: HandwritingStyleChoice

    static let defaultTypeset = HandwritingStyleStatus(
        bankMissing: true,
        characterCount: 0,
        canRenderCannedAnswer: false,
        selected: .typeset,
        resolved: .typeset
    )
}

/// The selected style, remembered across launches.
@MainActor
final class HandwritingStylePreference: ObservableObject {
    private static let key = "handwriting.style"

    private let defaults: UserDefaults

    @Published var choice: HandwritingStyleChoice {
        didSet { defaults.set(choice.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Typeset is the default because ADR-014 lets a user never calibrate. Once a bank
        // exists, `resolved(for:)` promotes them to their own hand without asking — having
        // just spent three minutes writing, being shown a typeface would be baffling.
        choice =
            defaults.string(forKey: Self.key)
            .flatMap(HandwritingStyleChoice.init(rawValue:)) ?? .typeset
    }

    /// Whether the user has ever chosen a style themselves, as opposed to being defaulted.
    var isExplicit: Bool { defaults.string(forKey: Self.key) != nil }

    /// The style to actually draw in, given what is available.
    ///
    /// A stored preference for "my handwriting" with no bank behind it must not produce
    /// blank ink, so it degrades to typeset rather than failing.
    func resolved(bank: GlyphBank?) -> HandwritingStyleChoice {
        // Do not require an unrelated complete alphabet here. Calibration deliberately
        // permits missing characters, and `HandwritingInkRenderer` already falls back per
        // block when an answer uses one. The old alphabet gate made a missing `z` force a
        // known `4` into typeset, so a nearly complete calibration appeared not to work.
        guard let bank, bank.characterCount > 0 else { return .typeset }
        return isExplicit ? choice : .mine
    }

    func status(bank: GlyphBank?) -> HandwritingStyleStatus {
        HandwritingStyleStatus(
            bankMissing: bank == nil,
            characterCount: bank?.characterCount ?? 0,
            canRenderCannedAnswer: bank?.canRender("4") ?? false,
            selected: choice,
            resolved: resolved(bank: bank)
        )
    }

    /// The renderer for the resolved style.
    func renderer(bank: GlyphBank?) -> any SuggestionInkRendering {
        let style = resolved(bank: bank)
        guard style.needsBank, let bank else { return TypesetInkRenderer() }
        return HandwritingInkRenderer(bank: bank, variation: style.variation)
    }
}
