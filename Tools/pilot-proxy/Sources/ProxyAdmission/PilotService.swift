import Foundation

/// Outcome codes on the wire. They map one-to-one onto the app's `ProxyTransportFailure` cases, so the
/// client never sees a reason (cost, model text or ledger detail) beyond these.
enum PilotStatus: UInt8, Sendable {
    case success = 0
    case unauthorized = 1
    case refused = 2
    case overBudget = 3
}

/// Length-prefixed frames carried inside the encrypted LAN channel. A request frame is a 4-byte big-endian
/// length and a JSON body; a reply frame is a status byte, a 4-byte length and the body (spec JSON on
/// success, empty otherwise).
enum PilotFrame {
    static let maxRequestBytes = 3_000_000
    static let maxReplyBytes = 70_000

    /// Total bytes the frame needs once its header is present, or nil if the header is incomplete.
    /// Throws if the declared length is over the limit, so a hostile peer cannot make us buffer it.
    static func requestLength(in buffer: Data) throws -> Int? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= maxRequestBytes else { throw AdmissionError.oversized }
        return 4 + length
    }

    static func requestBody(from buffer: Data) throws -> Data? {
        guard let total = try requestLength(in: buffer), buffer.count >= total else { return nil }
        return buffer.subdata(in: buffer.startIndex + 4..<buffer.startIndex + total)
    }

    static func encodeRequest(_ body: Data) -> Data {
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    static func encodeReply(status: PilotStatus, body: Data = Data()) -> Data {
        var length = UInt32(body.count).bigEndian
        return Data([status.rawValue]) + Data(bytes: &length, count: 4) + body
    }

    static func decodeReply(_ data: Data) -> (status: PilotStatus, body: Data)? {
        guard data.count >= 5, let status = PilotStatus(rawValue: data[data.startIndex]) else { return nil }
        let length = data.dropFirst().prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length <= maxReplyBytes, data.count == 5 + length else { return nil }
        return (status, data.suffix(length))
    }
}

/// One request in, one frame out. Everything past admission is reduced to a `PilotStatus`; the detailed
/// error stays in the process.
struct PilotService: Sendable {
    let pilot: PilotAdmission
    let transport: any PilotModelTransport

    /// `proof` is what the channel already established (a completed pre-shared-key handshake).
    func handle(body: Data, proof: String?) async -> Data {
        do {
            let answer = try await pilot.invoke(body, proof: proof, transport: transport)
            return PilotFrame.encodeReply(status: .success, body: answer.specJSON)
        } catch {
            return PilotFrame.encodeReply(status: Self.status(for: error))
        }
    }

    static func status(for error: Error) -> PilotStatus {
        switch error {
        case AdmissionError.unauthorized: return .unauthorized
        case LedgerError.overBudget, LedgerError.rateLimited, LedgerError.costExceeded: return .overBudget
        default: return .refused
        }
    }
}
