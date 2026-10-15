import Foundation

/// Sends one request to the hosted pilot proxy over HTTPS (ADR-028). Carries only the bounded
/// `ProxyClientRequest` fields; the token travels in the `Authorization` header and never appears in an error,
/// a log line or the URL. Every failure reduces to a `ProxyTransportFailure` so nothing server-side leaks.
public struct HTTPSProxyTransport: ProxyClientTransport {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let path = "/v1/answer"
    public static let maxReplyBytes = 70_000

    private let baseURL: URL
    private let token: @Sendable () -> String?
    private let send: Send
    private let timeout: TimeInterval

    /// `baseURL` must be `https`. `token` is read at call time (Keychain-backed in the app) and may be nil.
    public init?(
        baseURL: URL, token: @escaping @Sendable () -> String?, timeout: TimeInterval = 45,
        send: @escaping Send = { try await URLSession(configuration: .ephemeral).data(for: $0) }
    ) {
        guard baseURL.scheme == "https", baseURL.host?.isEmpty == false else { return nil }
        self.baseURL = baseURL
        self.token = token
        self.timeout = timeout
        self.send = send
    }

    public func response(to request: ProxyClientRequest) async throws -> Data {
        guard let token = token(), !token.isEmpty else { throw ProxyTransportFailure.unauthorized }
        var http = URLRequest(url: baseURL.appendingPathComponent(Self.path), timeoutInterval: timeout)
        http.httpMethod = "POST"
        http.httpBody = try JSONEncoder().encode(request)
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.failure(for: error)
        } catch {
            throw ProxyTransportFailure.offline
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ProxyTransportFailure.refused }
        if status == 200 {
            guard data.count <= Self.maxReplyBytes else { throw ProxyTransportFailure.refused }
            return data
        }
        throw Self.failure(forStatus: status)
    }

    private static func failure(forStatus status: Int) -> ProxyTransportFailure {
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .overBudget
        case 408, 504: return .timeout
        default: return .refused
        }
    }

    private static func failure(for error: URLError) -> ProxyTransportFailure {
        switch error.code {
        case .timedOut: return .timeout
        case .cancelled: return .offline
        default: return .offline
        }
    }
}
