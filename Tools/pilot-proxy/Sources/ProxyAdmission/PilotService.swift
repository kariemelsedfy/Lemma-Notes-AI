import Foundation

/// Outcome codes on the wire. They map one-to-one onto the app's `ProxyTransportFailure` cases, so the
/// client never sees a reason (cost, model text or ledger detail) beyond these.
enum PilotStatus: UInt8, Sendable {
    case success = 0
    case unauthorized = 1
    case refused = 2
    case overBudget = 3
    /// A free install has used its guided-tour asks: the app shows Premium (HTTP 402).
    case paymentRequired = 4
}

struct PilotOutcome: Equatable, Sendable {
    let status: PilotStatus
    let body: Data
}

/// One request in, one outcome out. Everything past admission is reduced to a `PilotStatus`; the detailed
/// error stays in the process.
struct PilotService: Sendable {
    let pilot: PilotAdmission
    let transport: any PilotModelTransport

    /// `proof` is the bearer token the caller presented; the admission gate decides whether it is valid.
    func handle(body: Data, proof: String?) async -> PilotOutcome {
        do {
            let answer = try await pilot.invoke(body, proof: proof, transport: transport)
            return PilotOutcome(status: .success, body: answer.specJSON)
        } catch {
            return Self.refused(error)
        }
    }

    /// The outcome for a failed ask, with the reason's name (never its content) written to the server log so a
    /// refusal the app can only call "couldn't answer" can be told apart: a cut-off reply, a block, a dropped call.
    ///
    /// A refusal also carries the reason's short code in its body (`{"reason":"model_http_400"}`), which the app shows
    /// in place of a guess. The code names the kind of failure and never holds a prompt, a reply or a price.
    static func refused(_ error: Error) -> PilotOutcome {
        let status = status(for: error)
        PilotServer.log("pilot-proxy: ask not served: \(status) (\(reasonName(for: error)))")
        let body = status == .refused ? Data(#"{"reason":"\#(reasonCode(for: error))"}"#.utf8) : Data()
        return PilotOutcome(status: status, body: body)
    }

    /// A short snake_case code for a failure: `model_http_400`, `model_truncated`, `admission_unsupported`.
    static func reasonCode(for error: Error) -> String {
        let raw: String
        switch error {
        case let billed as GeminiBilledFailure: raw = "model_\(billed.reason)"
        case let model as GeminiError: raw = "model_\(model)"
        case GeminiTransportError.status(let code): raw = "model_http_\(code)"
        case let transport as GeminiTransportError: raw = "model_\(transport)"
        case let admission as AdmissionError: raw = "admission_\(admission)"
        case let ledger as LedgerError: raw = "ledger_\(ledger)"
        case let allowance as AllowanceError: raw = "allowance_\(allowance)"
        default: raw = "server_error"
        }
        return String(raw.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(48))
    }

    static func reasonName(for error: Error) -> String {
        switch error {
        case let billed as GeminiBilledFailure: "model reply \(billed.reason) after \(billed.outputTokens) tokens"
        case let model as GeminiError: "model \(model)"
        case let transport as GeminiTransportError: "model call \(transport)"
        case let admission as AdmissionError: "admission \(admission)"
        case let ledger as LedgerError: "ledger \(ledger)"
        case let allowance as AllowanceError: "allowance \(allowance)"
        default: "other \(type(of: error))"
        }
    }

    static func status(for error: Error) -> PilotStatus {
        switch error {
        case AdmissionError.unauthorized: return .unauthorized
        case LedgerError.overBudget, LedgerError.rateLimited, LedgerError.costExceeded: return .overBudget
        case AllowanceError.subscriptionRequired: return .paymentRequired
        case AllowanceError.allowanceUsedUp: return .overBudget
        case is AppAttestError, is InstallTrustError: return .unauthorized
        default: return .refused
        }
    }
}
