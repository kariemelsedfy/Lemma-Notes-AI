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
            return PilotOutcome(status: Self.status(for: error), body: Data())
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
