import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(Security)
    import Security
#endif

/// Failures of the HTTPS call itself. Content-free: no body, no URL, no key.
enum GeminiTransportError: Error, Equatable {
    case keyUnavailable, network
    case status(Int)
    case notHTTP
}

/// Reads the Gemini key from the macOS Keychain (account `margin-pilot`, service `gemini-api-key`).
/// The key is returned to the caller and never logged, stored or put in an error.
enum PilotKeychain {
    static func geminiKey() throws -> String {
        #if canImport(Security)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "margin-pilot",
                kSecAttrService as String: "gemini-api-key",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                let data = item as? Data,
                let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !key.isEmpty
            else { throw GeminiTransportError.keyUnavailable }
            return key
        #else
            throw GeminiTransportError.keyUnavailable
        #endif
    }
}

/// One POST to `generateContent`. The network and key lookup are injected so tests never touch either.
struct GeminiHTTPTransport: PilotModelTransport {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let endpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiPilot.model):generateContent"
    )!
    static let timeout: TimeInterval = 30

    let key: @Sendable () throws -> String
    let send: Send

    init(
        key: @escaping @Sendable () throws -> String = PilotKeychain.geminiKey,
        send: @escaping Send = { try await URLSession(configuration: .ephemeral).data(for: $0) }
    ) {
        self.key = key
        self.send = send
    }

    func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
        var http = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        http.httpMethod = "POST"
        http.httpBody = try GeminiRequestBuilder.body(for: request)
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue(try key(), forHTTPHeaderField: "x-goog-api-key")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(http)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeminiTransportError.network
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw GeminiTransportError.notHTTP }
        guard status == 200 else { throw GeminiTransportError.status(status) }
        do {
            return try GeminiResponseParser.parse(data)
        } catch let reason as GeminiError {
            guard let used = GeminiResponseParser.usage(data) else { throw reason }
            throw GeminiBilledFailure(reason: reason, promptTokens: used.promptTokens, outputTokens: used.outputTokens)
        }
    }
}
