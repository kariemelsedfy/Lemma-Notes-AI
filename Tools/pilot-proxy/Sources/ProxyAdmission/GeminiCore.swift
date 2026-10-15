import Foundation

/// Published pilot terms for the Gemini route (ADR-027). Rates are USD micros per million tokens
/// from Google's pricing page, reviewed 2026-10-15; image input is billed at the text rate.
enum GeminiPilot {
    static let model = "gemini-3.1-flash-lite"
    static let inputMicrosPerMillion: Int64 = 250_000
    static let outputMicrosPerMillion: Int64 = 1_500_000
    /// Conservative ceiling for one crop plus neighborhood and a short prompt. Measured in M4-15.
    static let worstCaseInputTokens: Int64 = 20_000
    static let maxOutputTokens = 512

    /// Price of a usage report, rounded up to a whole micro-dollar. Thought tokens bill as output.
    static func costMicros(promptTokens: Int, outputTokens: Int) -> Int64? {
        guard promptTokens >= 0, outputTokens >= 0 else { return nil }
        let (input, inputOverflow) = Int64(promptTokens).multipliedReportingOverflow(by: inputMicrosPerMillion)
        let (output, outputOverflow) = Int64(outputTokens).multipliedReportingOverflow(by: outputMicrosPerMillion)
        let (sum, sumOverflow) = input.addingReportingOverflow(output)
        guard !inputOverflow, !outputOverflow, !sumOverflow else { return nil }
        return sum / 1_000_000 + (sum % 1_000_000 == 0 ? 0 : 1)
    }

    /// Largest charge one admitted request can incur, before the per-call hold is applied.
    static func worstCaseMicros(maxOutputTokens requested: Int) -> Int64? {
        guard (1...maxOutputTokens).contains(requested) else { return nil }
        return costMicros(promptTokens: Int(worstCaseInputTokens), outputTokens: requested)
    }
}

enum GeminiError: Error, Equatable {
    case invalidRequest, blocked, truncated, malformed, usageMissing
}

struct GeminiReply: Equatable, Sendable {
    let specJSON: Data
    let promptTokens: Int
    let outputTokens: Int

    var costMicros: Int64? { GeminiPilot.costMicros(promptTokens: promptTokens, outputTokens: outputTokens) }
}

private struct WireText: Encodable { let text: String }

private struct WireInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct WireInline: Encodable { let inlineData: WireInlineData }

private enum WirePart: Encodable {
    case text(String)
    case png(Data)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text): try WireText(text: text).encode(to: encoder)
        case .png(let data):
            let inline = WireInlineData(mimeType: "image/png", data: data.base64EncodedString())
            try WireInline(inlineData: inline).encode(to: encoder)
        }
    }
}

private struct WireContent: Encodable {
    let role: String?
    let parts: [WirePart]
}

private struct WireConfig: Encodable {
    let temperature: Int
    let maxOutputTokens: Int
    let responseMimeType: String
}

private struct WireBody: Encodable {
    let systemInstruction: WireContent
    let contents: [WireContent]
    let generationConfig: WireConfig
}

enum GeminiRequestBuilder {
    /// The instruction is trusted prompt text; the transcript and images are untrusted user content
    /// and travel only in `contents`.
    static func body(for request: AdmittedRequest, instruction: String) throws -> Data {
        guard !instruction.isEmpty, (1...GeminiPilot.maxOutputTokens).contains(request.maxOutputTokens),
            !request.cropPNG.isEmpty, !request.neighborhoodPNG.isEmpty
        else { throw GeminiError.invalidRequest }
        let body = WireBody(
            systemInstruction: WireContent(role: nil, parts: [.text(instruction)]),
            contents: [
                WireContent(
                    role: "user",
                    parts: [
                        .text("Selected handwriting (image):"), .png(request.cropPNG),
                        .text("Nearby page context (image):"), .png(request.neighborhoodPNG),
                        .text("Rough transcript of the selection, may be wrong: \(request.transcript)"),
                    ]
                )
            ],
            generationConfig: WireConfig(
                temperature: 0, maxOutputTokens: request.maxOutputTokens, responseMimeType: "application/json"
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }
}

private struct ReplyPart: Decodable { let text: String? }

private struct ReplyContent: Decodable { let parts: [ReplyPart]? }

private struct ReplyCandidate: Decodable {
    let content: ReplyContent?
    let finishReason: String?
}

private struct ReplyFeedback: Decodable { let blockReason: String? }

private struct ReplyUsage: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let thoughtsTokenCount: Int?
}

private struct ReplyEnvelope: Decodable {
    let candidates: [ReplyCandidate]?
    let promptFeedback: ReplyFeedback?
    let usageMetadata: ReplyUsage?
}

enum GeminiResponseParser {
    private static let maxReplyBytes = 65_536

    static func parse(_ data: Data) throws -> GeminiReply {
        guard data.count <= 4 * maxReplyBytes, let reply = try? JSONDecoder().decode(ReplyEnvelope.self, from: data)
        else { throw GeminiError.malformed }
        if reply.promptFeedback?.blockReason != nil { throw GeminiError.blocked }
        guard let usage = reply.usageMetadata, let prompt = usage.promptTokenCount, prompt >= 0 else {
            throw GeminiError.usageMissing
        }
        let output = (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0)
        guard output >= 0, let candidate = reply.candidates?.first else { throw GeminiError.malformed }
        switch candidate.finishReason {
        case "STOP": break
        case "MAX_TOKENS": throw GeminiError.truncated
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": throw GeminiError.blocked
        default: throw GeminiError.malformed
        }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        let json = Data(text.utf8)
        guard !json.isEmpty, json.count <= maxReplyBytes,
            (try? JSONSerialization.jsonObject(with: json)) is [String: Any]
        else { throw GeminiError.malformed }
        return GeminiReply(specJSON: json, promptTokens: prompt, outputTokens: output)
    }
}
