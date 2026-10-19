import Foundation

/// Gives a model call a second chance when the first failed in a way a second try usually fixes, so a paying person is
/// not turned away by one slow or cut-off reply.
///
/// - A reply cut off at the output limit (the model's own thinking counts against it) or that was not JSON is tried
///   again with twice the room, up to the pilot's ceiling.
/// - A rate limit, a server error or a dropped connection is tried again after a short pause.
///
/// One retry only. The tokens of a failed first try that Google billed are added to the cost of the second, so the
/// ledger records one observation that is the true total (and the fixed hold covers both many times over).
struct RetryingModelTransport: PilotModelTransport {
    let base: any PilotModelTransport
    var pause: @Sendable () async -> Void = { try? await Task.sleep(for: .milliseconds(400)) }

    func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
        do {
            return try await base.complete(request)
        } catch let billed as GeminiBilledFailure where Self.isWorthRetrying(billed.reason) {
            return try await retry(after: billed, request)
        } catch let failure as GeminiTransportError where Self.isTransient(failure) {
            await pause()
            return try await base.complete(request)
        }
    }

    private func retry(after first: GeminiBilledFailure, _ request: AdmittedRequest) async throws -> GeminiReply {
        let room = min(GeminiPilot.maxOutputTokens, request.maxOutputTokens * 2)
        do {
            let reply = try await base.complete(request.withMaxOutputTokens(room))
            return GeminiReply(
                specJSON: reply.specJSON, promptTokens: reply.promptTokens + first.promptTokens,
                outputTokens: reply.outputTokens + first.outputTokens)
        } catch let second as GeminiBilledFailure {
            throw GeminiBilledFailure(
                reason: second.reason, promptTokens: second.promptTokens + first.promptTokens,
                outputTokens: second.outputTokens + first.outputTokens)
        }
    }

    private static func isWorthRetrying(_ reason: GeminiError) -> Bool {
        reason == .truncated || reason == .malformed
    }

    private static func isTransient(_ failure: GeminiTransportError) -> Bool {
        switch failure {
        case .network: true
        case .status(let code): [429, 500, 502, 503, 504].contains(code)
        case .keyUnavailable, .notHTTP: false
        }
    }
}

extension AdmittedRequest {
    func withMaxOutputTokens(_ tokens: Int) -> AdmittedRequest {
        var copy = AdmittedRequest(normalizing: self, cropPNG: cropPNG, neighborhoodPNG: neighborhoodPNG)
        copy.maxOutputTokens = tokens
        return copy
    }
}
