import Foundation

/// Sends one request to the hosted pilot proxy over HTTPS (ADR-028). Carries only the bounded
/// `ProxyClientRequest` fields; the token travels in the `Authorization` header and never appears in an error,
/// a log line or the URL. Every failure reduces to a `ProxyTransportFailure` so nothing server-side leaks.
public struct HTTPSProxyTransport: ProxyClientTransport {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let path = "/v1/answer"
    public static let maxReplyBytes = 70_000

    /// Produces the credential headers for one request body: a bearer token, or an App Attest assertion over the
    /// body (ADR-031). Throws `ProxyTransportFailure.unauthorized` when there is nothing to present.
    public typealias Authorizer = @Sendable (_ body: Data) async throws -> [String: String]

    private let baseURL: URL
    private let authorizer: Authorizer
    private let send: Send
    private let timeout: TimeInterval

    /// `baseURL` must be `https`. `token` is read at call time (Keychain-backed in the app) and may be nil.
    public init?(
        baseURL: URL, token: @escaping @Sendable () -> String?, timeout: TimeInterval = 45,
        send: @escaping Send = { try await URLSession(configuration: .ephemeral).data(for: $0) }
    ) {
        self.init(
            baseURL: baseURL,
            authorizer: { _ in
                guard let token = token(), !token.isEmpty else { throw ProxyTransportFailure.unauthorized }
                return ["Authorization": "Bearer \(token)"]
            }, timeout: timeout, send: send)
    }

    public init?(
        baseURL: URL, authorizer: @escaping Authorizer, timeout: TimeInterval = 45,
        send: @escaping Send = { try await URLSession(configuration: .ephemeral).data(for: $0) }
    ) {
        guard baseURL.scheme == "https", baseURL.host?.isEmpty == false else { return nil }
        self.baseURL = baseURL
        self.authorizer = authorizer
        self.timeout = timeout
        self.send = send
    }

    public func response(to request: ProxyClientRequest) async throws -> Data {
        let body = try JSONEncoder().encode(request)
        let credentials: [String: String]
        do {
            credentials = try await authorizer(body)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProxyTransportFailure {
            throw failure
        } catch {
            throw ProxyTransportFailure.unauthorized
        }
        var http = URLRequest(url: baseURL.appendingPathComponent(Self.path), timeoutInterval: timeout)
        http.httpMethod = "POST"
        http.httpBody = body
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in credentials { http.setValue(value, forHTTPHeaderField: name) }
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
        return try Self.outcome(of: response, data: data)
    }

    /// The reply's body when it succeeded; otherwise why it did not.
    private static func outcome(of response: URLResponse, data: Data) throws -> Data {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ProxyTransportFailure.refused }
        if status == 200 {
            guard data.count <= maxReplyBytes else { throw ProxyTransportFailure.refused }
            return data
        }
        // A refusal says why, as a short code (`model_http_400`); an older server sends none.
        if status == 422, let code = refusalCode(in: data) { throw ProxyRefusal(code: code) }
        throw failure(forStatus: status)
    }

    /// The `reason` of `{"reason":"…"}`, only if it is a short snake_case code (so nothing else can be shown).
    static func refusalCode(in data: Data) -> String? {
        guard data.count <= 200,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = object["reason"] as? String, (1...48).contains(code.count),
            code.allSatisfy({ ($0.isASCII && $0.isLowercase) || $0.isNumber || $0 == "_" })
        else { return nil }
        return code
    }

    private static func failure(forStatus status: Int) -> ProxyTransportFailure {
        switch status {
        case 401, 403: return .unauthorized
        case 402: return .paymentRequired
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
