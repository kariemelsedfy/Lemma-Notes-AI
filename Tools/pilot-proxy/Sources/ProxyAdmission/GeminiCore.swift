import Foundation

/// Published pilot terms for the Gemini route (ADR-027). Rates are USD micros per million tokens
/// from Google's pricing page, reviewed 2026-10-15; image input is billed at the text rate.
enum GeminiPilot {
    static let model = "gemini-3.1-flash-lite"
    static let inputMicrosPerMillion: Int64 = 250_000
    static let outputMicrosPerMillion: Int64 = 1_500_000
    /// Conservative ceiling for one crop plus neighborhood and a short prompt. Measured in M4-15.
    static let worstCaseInputTokens: Int64 = 20_000
    static let maxOutputTokens = 1024

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
    /// The instruction and schema are trusted; the transcript and images are untrusted user content
    /// and travel only in `contents`.
    static func body(for request: AdmittedRequest, instruction override: String? = nil) throws -> Data {
        let instruction = override ?? GeminiPrompt.instruction(for: request.intent)
        guard !instruction.isEmpty, (1...GeminiPilot.maxOutputTokens).contains(request.maxOutputTokens),
            !request.cropPNG.isEmpty, !request.neighborhoodPNG.isEmpty
        else { throw GeminiError.invalidRequest }
        func png(_ data: Data) -> [String: Any] {
            ["inlineData": ["mimeType": "image/png", "data": data.base64EncodedString()]]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instruction]]],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "IMAGE 1, the selected handwriting:"], png(request.cropPNG),
                        ["text": "IMAGE 2, the surrounding page (context only):"], png(request.neighborhoodPNG),
                        ["text": "Rough transcript of the selection, may be wrong: \(request.transcript)"],
                    ],
                ]
            ],
            "generationConfig": [
                "temperature": 0, "maxOutputTokens": request.maxOutputTokens,
                "responseMimeType": "application/json",
                "responseJsonSchema": GeminiPrompt.responseSchema(intent: request.intent),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
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

/// A refused reply that Google still billed: the usage it reported, so the ledger records the real charge.
struct GeminiBilledFailure: Error, Equatable {
    let reason: GeminiError
    let promptTokens: Int
    let outputTokens: Int

    var costMicros: Int64? { GeminiPilot.costMicros(promptTokens: promptTokens, outputTokens: outputTokens) }
}

enum GeminiResponseParser {
    private static let maxReplyBytes = 65_536

    /// Reported usage, if the envelope has a sane one. Used to bill refused replies.
    static func usage(_ data: Data) -> (promptTokens: Int, outputTokens: Int)? {
        guard data.count <= 4 * maxReplyBytes, let reply = try? JSONDecoder().decode(ReplyEnvelope.self, from: data),
            let usage = reply.usageMetadata, let prompt = usage.promptTokenCount, prompt >= 0,
            let output = outputTokens(usage)
        else { return nil }
        return (prompt, output)
    }

    private static func outputTokens(_ usage: ReplyUsage) -> Int? {
        let candidates = usage.candidatesTokenCount ?? 0
        let thoughts = usage.thoughtsTokenCount ?? 0
        let (sum, overflow) = candidates.addingReportingOverflow(thoughts)
        guard candidates >= 0, thoughts >= 0, !overflow else { return nil }
        return sum
    }

    /// A model sometimes wraps JSON in a markdown fence or pads it with blank lines despite being asked for JSON only.
    static func unfenced(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["\u{FEFF}"]))
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed = String(trimmed.drop(while: { $0 == "`" }))
        if trimmed.lowercased().hasPrefix("json") { trimmed = String(trimmed.dropFirst(4)) }
        while trimmed.hasSuffix("`") { trimmed.removeLast() }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The JSON object a reply cut off mid-way would have been, if its start can be closed into one: unfinished
    /// strings and brackets are closed and the last few characters dropped until it parses.
    private static func salvaged(_ candidate: ReplyCandidate) -> Data? {
        let text = unfenced((candidate.content?.parts ?? []).compactMap(\.text).joined())
        guard text.hasPrefix("{"), text.count > 20 else { return nil }
        for cut in 0..<240 where text.count - cut > 20 {
            let head = String(text.dropLast(cut))
            guard let closed = closing(head) else { continue }
            let data = Data(closed.utf8)
            if (try? JSONSerialization.jsonObject(with: data)) is [String: Any], data.count <= maxReplyBytes {
                return data
            }
        }
        return nil
    }

    /// `text` followed by whatever closes its open string, arrays and objects; nil if it is not an open JSON object.
    private static func closing(_ text: String) -> String? {
        var tail = OpenJSON()
        for character in text where !tail.consume(character) { return nil }
        guard !tail.escaped else { return nil }
        var result = text + (tail.inString ? "\"" : "")
        // A dangling comma or a key with no value cannot be closed over; the caller drops characters and retries.
        while let last = result.last, last == "," || last == ":" { result.removeLast() }
        return result + String(tail.stack.reversed())
    }

    static func parse(_ data: Data) throws -> GeminiReply {
        guard data.count <= 4 * maxReplyBytes, let reply = try? JSONDecoder().decode(ReplyEnvelope.self, from: data)
        else { throw GeminiError.malformed }
        if reply.promptFeedback?.blockReason != nil { throw GeminiError.blocked }
        guard let usage = reply.usageMetadata, let prompt = usage.promptTokenCount, prompt >= 0 else {
            throw GeminiError.usageMissing
        }
        guard let output = outputTokens(usage), let candidate = reply.candidates?.first else {
            throw GeminiError.malformed
        }
        switch candidate.finishReason {
        case "STOP": break
        case "MAX_TOKENS":
            // Cut off, but the start is usually a whole answer: close what is open and use it rather than fail.
            guard let salvaged = salvaged(candidate), output > 0 else { throw GeminiError.truncated }
            return GeminiReply(specJSON: salvaged, promptTokens: prompt, outputTokens: output)
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": throw GeminiError.blocked
        default: throw GeminiError.malformed
        }
        let text = unfenced((candidate.content?.parts ?? []).compactMap(\.text).joined())
        let json = Data(text.utf8)
        guard !json.isEmpty, json.count <= maxReplyBytes,
            (try? JSONSerialization.jsonObject(with: json)) is [String: Any]
        else { throw GeminiError.malformed }
        return GeminiReply(specJSON: json, promptTokens: prompt, outputTokens: output)
    }
}

/// What a JSON text has left open: its brackets and whether it stopped inside a string.
private struct OpenJSON {
    var stack: [Character] = []
    var inString = false
    var escaped = false

    /// False when a closing bracket does not match the one that is open.
    mutating func consume(_ character: Character) -> Bool {
        if inString {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString = false
            }
            return true
        }
        switch character {
        case "\"": inString = true
        case "{": stack.append("}")
        case "[": stack.append("]")
        case "}", "]": return stack.popLast() == character
        default: break
        }
        return true
    }
}
