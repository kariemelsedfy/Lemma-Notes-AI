import Foundation

/// A parsed request head. Only what the pilot proxy needs; anything unusual is refused rather than guessed at.
struct HTTPHead: Equatable, Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let contentLength: Int
}

enum HTTPParseError: Error, Equatable {
    case malformed, tooLarge, unsupported
}

enum HTTPHeadParser {
    static let maxHeadBytes = 16_384
    static let maxBodyBytes = 6_000_000
    static let terminator = Data("\r\n\r\n".utf8)

    /// Index just past the blank line, or nil if the head is not complete yet. Throws once the head exceeds the cap.
    static func headEnd(in buffer: Data) throws -> Int? {
        if let range = buffer.range(of: terminator) {
            let end = buffer.distance(from: buffer.startIndex, to: range.upperBound)
            guard end <= maxHeadBytes else { throw HTTPParseError.tooLarge }
            return end
        }
        guard buffer.count <= maxHeadBytes else { throw HTTPParseError.tooLarge }
        return nil
    }

    static func parse(_ head: Data) throws -> HTTPHead {
        guard let text = String(data: head, encoding: .utf8) else { throw HTTPParseError.malformed }
        let lines = text.components(separatedBy: "\r\n").dropLast(2)
        guard let requestLine = lines.first else { throw HTTPParseError.malformed }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else {
            throw HTTPParseError.malformed
        }
        let method = String(parts[0])
        let path = String(parts[1])
        guard ["GET", "POST"].contains(method), path.hasPrefix("/"), !path.contains("?"), path.count <= 64 else {
            throw HTTPParseError.unsupported
        }
        let headers = try headerFields(lines.dropFirst())
        guard headers["transfer-encoding"] == nil else { throw HTTPParseError.unsupported }
        var length = 0
        if let declared = headers["content-length"] {
            guard let value = Int(declared), value >= 0 else { throw HTTPParseError.malformed }
            guard value <= maxBodyBytes else { throw HTTPParseError.tooLarge }
            length = value
        } else if method == "POST" {
            throw HTTPParseError.malformed
        }
        return HTTPHead(method: method, path: path, headers: headers, contentLength: length)
    }

    private static func headerFields(_ lines: ArraySlice<String>) throws -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex, headers.count < 50 else {
                throw HTTPParseError.malformed
            }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.contains(" "), headers[name] == nil else { throw HTTPParseError.malformed }
            headers[name] = value
        }
        return headers
    }
}

struct HTTPReply: Equatable, Sendable {
    let status: Int
    let body: Data
    let contentType: String

    init(status: Int, body: Data = Data(), contentType: String = "application/json") {
        self.status = status
        self.body = body
        self.contentType = contentType
    }

    func encoded() -> Data {
        let reasons = [
            200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed",
            402: "Payment Required", 409: "Conflict", 411: "Length Required", 413: "Payload Too Large",
            422: "Unprocessable Content",
            429: "Too Many Requests", 500: "Internal Server Error",
        ]
        let head =
            "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\nContent-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// Routes one request. `GET /status` is open; `POST /v1/answer` needs the pilot bearer token.
struct PilotRouter: Sendable {
    static let answerPath = "/v1/answer"
    static let healthPath = "/status"

    let service: PilotService
    /// Nil on a pilot-token-only deployment; the install routes then do not exist.
    var installs: InstallGate?

    func route(_ head: HTTPHead, body: Data) async -> HTTPReply {
        switch head.path {
        case Self.healthPath:
            return head.method == "GET"
                ? HTTPReply(status: 200, body: Data(#"{"ok":true}"#.utf8)) : HTTPReply(status: 405)
        case Self.answerPath:
            guard head.method == "POST" else { return HTTPReply(status: 405) }
            guard body.count == head.contentLength else { return HTTPReply(status: 400) }
            if let installs, let credentials = installs.credentials(in: head.headers) {
                return Self.reply(for: await service.handle(body: body, install: credentials, gate: installs))
            }
            let proof = Self.bearer(head.headers["authorization"])
            let outcome = await service.handle(body: body, proof: proof)
            return Self.reply(for: outcome)
        case InstallGate.challengePath, InstallGate.registerPath, InstallGate.entitlementPath:
            return await routeInstall(head, body: body)
        default:
            return HTTPReply(status: 404)
        }
    }

    private func routeInstall(_ head: HTTPHead, body: Data) async -> HTTPReply {
        guard let installs else { return HTTPReply(status: 404) }
        if head.path == InstallGate.challengePath {
            return head.method == "GET" ? installs.challenge() : HTTPReply(status: 405)
        }
        guard head.method == "POST" else { return HTTPReply(status: 405) }
        guard body.count == head.contentLength else { return HTTPReply(status: 400) }
        return head.path == InstallGate.registerPath
            ? await installs.register(body: body) : await installs.entitlement(headers: head.headers, body: body)
    }

    /// Admission authorizer for the single pilot device: the presented bearer token must equal the configured
    /// one (compared in constant time) and the configured token must be non-empty.
    static func authorizer(token: String, subjectID: String) -> @Sendable (String?) async -> PilotIdentity? {
        { presented in
            guard let presented, !token.isEmpty, constantTimeEqual(presented, token) else { return nil }
            return PilotIdentity(subjectID: subjectID)
        }
    }

    static func reply(for outcome: PilotOutcome) -> HTTPReply {
        switch outcome.status {
        case .success: return HTTPReply(status: 200, body: outcome.body)
        case .unauthorized: return HTTPReply(status: 401)
        case .refused: return HTTPReply(status: 422, body: outcome.body)
        case .overBudget: return HTTPReply(status: 429)
        case .paymentRequired: return HTTPReply(status: 402)
        }
    }

    static func bearer(_ header: String?) -> String? {
        guard let header, header.lowercased().hasPrefix("bearer ") else { return nil }
        let value = header.dropFirst(7).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(truncatingIfNeeded: left.count ^ right.count)
        for index in 0..<max(left.count, right.count) {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }
}
