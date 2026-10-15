import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotSocketServerTests: XCTestCase {
    private static let token = "loopback-token-for-tests"
    private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
    )!

    func testLoopbackHealthAnswerAndRefusals() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let health = try await send("GET /healthz HTTP/1.1\r\nHost: t\r\n\r\n", port: port)
        XCTAssertTrue(health.hasPrefix("HTTP/1.1 200 OK"))
        let body = try requestBody()
        let answered = try await send(post(body, token: Self.token), port: port)
        XCTAssertTrue(answered.hasPrefix("HTTP/1.1 200 OK"))
        XCTAssertTrue(answered.hasSuffix(#"{"version":1}"#))
        let denied = try await send(post(body, token: "nope"), port: port)
        XCTAssertTrue(denied.hasPrefix("HTTP/1.1 401 "))
        let junk = try await send("POST /v1/answer HTTP/1.1\r\nContent-Length: abc\r\n\r\n", port: port)
        XCTAssertTrue(junk.hasPrefix("HTTP/1.1 400 "))
        let huge = try await send("POST /v1/answer HTTP/1.1\r\nContent-Length: 9000000\r\n\r\n", port: port)
        XCTAssertTrue(huge.hasPrefix("HTTP/1.1 413 "))
        XCTAssertFalse((answered + denied + junk + huge).contains(Self.token))
    }

    func testSplitWritesAreReassembled() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let body = try requestBody()
        let request = post(body, token: Self.token)
        let reply = try await send(request, port: port, chunk: 7)
        XCTAssertTrue(reply.hasPrefix("HTTP/1.1 200 OK"))
    }

    private func startServer() async throws -> (PilotSocketServer, UInt16) {
        let root = FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        let ledger = try SpendLedger.bootstrap(
            databaseURL: folder.appendingPathComponent("spend.sqlite"), limitMicros: 1_000_000
        )
        let gate = AdmissionGate(authorize: PilotRouter.authorizer(token: Self.token, subjectID: UUID().uuidString))
        let service = PilotService(pilot: PilotAdmission(admission: gate, ledger: ledger), transport: FixedTransport())
        let server = PilotSocketServer(router: PilotRouter(service: service), host: "127.0.0.1", port: 0)
        return (server, try server.start())
    }

    private func requestBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString, "cropPNG": Self.pixel.base64EncodedString(),
            "neighborhoodPNG": Self.pixel.base64EncodedString(), "transcript": "2+3=",
            "intent": "answer", "maxOutputTokens": 256,
        ])
    }

    private func post(_ body: Data, token: String) -> String {
        let text = String(bytes: body, encoding: .utf8) ?? ""
        return "POST /v1/answer HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer \(token)\r\n"
            + "Content-Length: \(body.count)\r\n\r\n\(text)"
    }

    /// A tiny blocking client; the server under test is the only thing being exercised.
    private func send(_ request: String, port: UInt16, chunk: Int = 65_536) async throws -> String {
        try await Task.detached {
            let stream = try Loopback.open(port: port)
            defer { stream.close() }
            let bytes = Array(request.utf8)
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + chunk, bytes.count)
                try stream.write(Array(bytes[offset..<end]))
                offset = end
            }
            return String(bytes: try stream.readToEnd(), encoding: .utf8) ?? ""
        }.value
    }
}

private struct FixedTransport: PilotModelTransport {
    func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
        GeminiReply(specJSON: Data(#"{"version":1}"#.utf8), promptTokens: 100, outputTokens: 10)
    }
}

#if canImport(Glibc)
    import Glibc
#else
    import Darwin
#endif

private struct Loopback {
    let descriptor: Int32

    static func open(port: UInt16) throws -> Loopback {
        #if canImport(Glibc)
            let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard descriptor >= 0, result == 0 else { throw SocketServerError.socket }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return Loopback(descriptor: descriptor)
    }

    func write(_ bytes: [UInt8]) throws {
        guard Foundation.send(descriptor, bytes, bytes.count, 0) == bytes.count else { throw SocketServerError.socket }
    }

    func readToEnd() throws -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = recv(descriptor, &chunk, chunk.count, 0)
            if count <= 0 { return data }
            data.append(contentsOf: chunk.prefix(count))
        }
    }

    func close() { _ = Foundation.close(descriptor) }
}
