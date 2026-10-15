import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

#if canImport(Glibc)
    private let streamSocket = Int32(SOCK_STREAM.rawValue)
    private let shutdownBoth = Int32(SHUT_RDWR)
#else
    private let streamSocket = SOCK_STREAM
    private let shutdownBoth = SHUT_RDWR
#endif

enum SocketServerError: Error, Equatable {
    case socket, bind, listen
}

/// A small blocking HTTP/1.1 server over POSIX sockets: one request per connection, hard read deadlines,
/// a connection cap, and no logging of anything a client sent. Cloud Run terminates TLS in front of it.
final class PilotSocketServer: @unchecked Sendable {
    static let readDeadline: TimeInterval = 20

    private let router: PilotRouter
    private let host: String
    private let port: UInt16
    private let maxConnections: Int
    private let lock = NSLock()
    private var active = 0
    private var listener: Int32 = -1

    init(router: PilotRouter, host: String = "0.0.0.0", port: UInt16, maxConnections: Int = 8) {
        self.router = router
        self.host = host
        self.port = port
        self.maxConnections = maxConnections
    }

    /// Binds, then accepts on a background thread. Returns the bound port (useful when `port` is 0).
    func start() throws -> UInt16 {
        let descriptor = socket(AF_INET, streamSocket, 0)
        guard descriptor >= 0 else { throw SocketServerError.socket }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close(descriptor)
            throw SocketServerError.bind
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw SocketServerError.listen
        }
        lock.withLock { listener = descriptor }
        let thread = Thread { [self] in acceptLoop(descriptor) }
        thread.start()
        return Self.localPort(descriptor)
    }

    func stop() {
        let descriptor = lock.withLock { () -> Int32 in
            defer { listener = -1 }
            return listener
        }
        guard descriptor >= 0 else { return }
        shutdown(descriptor, shutdownBoth)
        close(descriptor)
    }

    private static func localPort(_ descriptor: Int32) -> UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return UInt16(bigEndian: address.sin_port)
    }

    private func acceptLoop(_ descriptor: Int32) {
        while true {
            let client = accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard reserveSlot() else {
                send(HTTPReply(status: 429), on: client)
                close(client)
                continue
            }
            Self.configure(client)
            Task.detached { [self] in
                await serve(client)
                close(client)
                releaseSlot()
            }
        }
    }

    private func reserveSlot() -> Bool {
        lock.withLock {
            guard active < maxConnections else { return false }
            active += 1
            return true
        }
    }

    private func releaseSlot() { lock.withLock { active -= 1 } }

    private static func configure(_ client: Int32) {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #if canImport(Darwin)
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    private func serve(_ client: Int32) async {
        let deadline = Date().addingTimeInterval(Self.readDeadline)
        do {
            var buffer = Data()
            var end = try HTTPHeadParser.headEnd(in: buffer)
            while end == nil {
                guard try read(client, into: &buffer, before: deadline) else { return }
                end = try HTTPHeadParser.headEnd(in: buffer)
            }
            let headEnd = end ?? 0
            let head = try HTTPHeadParser.parse(buffer.prefix(headEnd))
            var body = Data(buffer.dropFirst(headEnd))
            while body.count < head.contentLength {
                guard try read(client, into: &body, before: deadline) else { return }
            }
            let reply = await router.route(head, body: body.prefix(head.contentLength))
            send(reply, on: client)
        } catch HTTPParseError.tooLarge {
            send(HTTPReply(status: 413), on: client)
        } catch is HTTPParseError {
            send(HTTPReply(status: 400), on: client)
        } catch {
            return
        }
    }

    /// Reads one chunk. Returns false if the peer closed; throws if the deadline passed or the read failed.
    private func read(_ client: Int32, into buffer: inout Data, before deadline: Date) throws -> Bool {
        guard Date() < deadline else { throw SocketServerError.socket }
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = recv(client, &chunk, chunk.count, 0)
        if count == 0 { return false }
        guard count > 0 else { throw SocketServerError.socket }
        buffer.append(contentsOf: chunk.prefix(count))
        return true
    }

    private func send(_ reply: HTTPReply, on client: Int32) {
        let bytes = [UInt8](reply.encoded())
        var offset = 0
        #if canImport(Glibc)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags: Int32 = 0
        #endif
        while offset < bytes.count {
            let written = bytes.withUnsafeBufferPointer {
                Foundation.send(client, $0.baseAddress! + offset, bytes.count - offset, flags)
            }
            if written <= 0 { return }
            offset += written
        }
    }
}
