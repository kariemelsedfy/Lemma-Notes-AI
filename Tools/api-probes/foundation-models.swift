// Probes the Foundation Models API this project intends to build M4-02 on.
//
// **Type-checked, not run.** It exists because `AGENTS.md` §2 names a fabricated Apple API as
// this codebase's most common failure mode, and because M4-01 found two claims in
// `AI_PIPELINE.md` §5 that were wrong for the SDK we actually build against. Re-run it after
// every Xcode bump; it costs five seconds and it is the difference between a doc and a fact.
//
//     ./scripts/check-foundation-models-api.sh
//
// Everything below compiled clean against the iOS 26.5 simulator SDK (Xcode 26.6) on
// 2026-08-12.

import FoundationModels

// Everything a T0 provider (M4-02) would need, type-checked against the real SDK.
@available(iOS 26.0, *)
enum Probe {
    @Generable
    struct SpecDraft {
        @Guide(description: "Literal transcription of the selected handwriting")
        var read: String
        @Guide(.range(0...1))
        var readConfidence: Double
        var answer: String
    }

    static func availability() -> String {
        switch SystemLanguageModel.default.availability {
        case .available: "available"
        case .unavailable(.deviceNotEligible): "deviceNotEligible"
        case .unavailable(.appleIntelligenceNotEnabled): "appleIntelligenceNotEnabled"
        case .unavailable(.modelNotReady): "modelNotReady"
        case .unavailable: "unknown"
        }
    }

    static func ask(_ text: String) async throws -> SpecDraft {
        let session = LanguageModelSession(model: .default, instructions: "Transcribe, then answer.")
        let response = try await session.respond(
            to: text,
            generating: SpecDraft.self,
            options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 512)
        )
        return response.content
    }

    static func classify(_ error: any Error) -> String {
        switch error {
        case LanguageModelSession.GenerationError.guardrailViolation: "guardrail"
        case LanguageModelSession.GenerationError.exceededContextWindowSize: "context"
        case LanguageModelSession.GenerationError.decodingFailure: "decoding"
        case LanguageModelSession.GenerationError.rateLimited: "rateLimited"
        case LanguageModelSession.GenerationError.concurrentRequests: "concurrent"
        case LanguageModelSession.GenerationError.assetsUnavailable: "assetsUnavailable"
        default: "other"
        }
    }
}
