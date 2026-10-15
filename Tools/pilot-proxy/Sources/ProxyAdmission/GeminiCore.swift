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

enum GeminiRequestBuilder {
    private struct Body: Encodable {
        struct Text: Encodable { let text: String }
        struct Inline: Encodable {
            struct Data: Encodable { let mimeType: String; let data: String }
            let inlineData: Data
        }
        enum Part: Encodable {
            case text(String), png(Foundation.Data)
            func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let text): try Text(text: text).encode(to: encoder)
                case .png(let data):
                    try Inline(inlineData: .init(mimeType: "image/png", data: data.base64EncodedString()))
                        .encode(to: encoder)
                }
            }
        }
        struct Content: Encodable { let role: String?; let parts: [Part] }
        struct Config: Encodable {
            let temperature: Int
            let maxOutputTokens: Int
            let responseMimeType: String
        }
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: Config
    }

    /// The instruction is trusted prompt text; the transcript and images are untrusted user content
    /// and travel only in `contents`.
    static func body(for request: AdmittedRequest, instruction: String) throws -> Data {
        guard !instruction.isEmpty, (1...GeminiPilot.maxOutputTokens).contains(request.maxOutputTokens),
            !request.cropPNG.isEmpty, !request.neighborhoodPNG.isEmpty
        else { throw GeminiError.invalidRequest }
        let body = Body(
            systemInstruction: .init(role: nil, parts: [.text(instruction)]),
            contents: [
                .init(
                    role: "user",
                    parts: [
                        .text("Selected handwriting (image):"), .png(request.cropPNG),
                        .text("Nearby page context (image):"), .png(request.neighborhoodPNG),
                        .text("Rough transcript of the selection, may be wrong: \(request.transcript)"),
                    ]
                )
            ],
            generationConfig: .init(
                temperature: 0, maxOutputTokens: request.maxOutputTokens, responseMimeType: "application/json"
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }
}

enum GeminiResponseParser {
    private static let maxReplyBytes = 65_536

    private struct Reply: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct Feedback: Decodable { let blockReason: String? }
        struct Usage: Decodable {
            let promptTokenCount: Int?
            let candidatesTokenCount: Int?
            let thoughtsTokenCount: Int?
        }
        let candidates: [Candidate]?
        let promptFeedback: Feedback?
        let usageMetadata: Usage?
    }

    static func parse(_ data: Data) throws -> GeminiReply {
        guard data.count <= 4 * maxReplyBytes, let reply = try? JSONDecoder().decode(Reply.self, from: data)
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
