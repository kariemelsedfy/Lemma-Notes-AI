// The other half of M4-01: two symbols `AI_PIPELINE.md` §5 assumed, which **do not exist** on
// the iOS 26.5 SDK. This file is expected to FAIL type-checking, and the check script asserts
// that it does.
//
// When it starts compiling, the iOS 27 surface has arrived and M4-07 (Apple PCC) and M4-08
// (frontier providers behind one protocol) become possible as §5 originally described them.
// That is a milestone, not a build break — read the errors before "fixing" anything.

import FoundationModels

// The two things AI_PIPELINE.md §5 assumes exist. Expected to FAIL on this SDK.
@available(iOS 26.0, *)
enum NegativeProbe {
    static func pcc() {
        let model = PrivateCloudComputeLanguageModel()
        _ = LanguageModelSession(model: model)
    }

    static func anyModel(_ model: any LanguageModel) {
        _ = LanguageModelSession(model: model)
    }
}
