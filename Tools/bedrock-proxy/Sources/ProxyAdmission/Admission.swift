import Foundation

enum AdmissionError: Error, Equatable {
    case unauthorized, malformed, oversized, unsupported, retentionUnavailable, busy
}

struct PilotIdentity: Sendable {
    let subjectID: String
}

struct RetentionEvidence: Sendable {
    let modelID: String
    let region: String
    let effectiveMode: String
    let allowedModes: Set<String>
    let verifiedAt: Date
}

struct AdmittedRequest: Decodable, Sendable {
    let requestID: UUID
    let cropPNG: Data
    let neighborhoodPNG: Data
    let transcript: String
    let intent: String
    let maxOutputTokens: Int

    private enum Fields: String, CodingKey {
        case requestID, cropPNG, neighborhoodPNG, transcript, intent, maxOutputTokens
    }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: RequestKey.self).allKeys.map(\.stringValue)
        guard Set(keys) == Set(["requestID", "cropPNG", "neighborhoodPNG", "transcript", "intent", "maxOutputTokens"])
        else { throw AdmissionError.malformed }
        let values = try decoder.container(keyedBy: Fields.self)
        requestID = try values.decode(UUID.self, forKey: .requestID)
        cropPNG = try values.decode(Data.self, forKey: .cropPNG)
        neighborhoodPNG = try values.decode(Data.self, forKey: .neighborhoodPNG)
        transcript = try values.decode(String.self, forKey: .transcript)
        intent = try values.decode(String.self, forKey: .intent)
        maxOutputTokens = try values.decode(Int.self, forKey: .maxOutputTokens)
    }
}

private struct RequestKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

protocol ProxyTransport: Sendable {
    func send(_ request: AdmittedRequest) async throws
}

actor AdmissionGate {
    private let modelID: String
    private let region: String
    private let authorize: @Sendable (String?) async -> PilotIdentity?
    private let retention: @Sendable () async -> RetentionEvidence?
    private let maxInFlight: Int
    private var inFlight = 0

    init(
        modelID: String,
        region: String,
        authorize: @escaping @Sendable (String?) async -> PilotIdentity? = { _ in nil },
        retention: @escaping @Sendable () async -> RetentionEvidence? = { nil },
        maxInFlight: Int = 1
    ) {
        self.modelID = modelID
        self.region = region
        self.authorize = authorize
        self.retention = retention
        self.maxInFlight = min(max(maxInFlight, 1), 2)
    }

    func invoke(_ body: Data, proof: String?, transport: any ProxyTransport) async throws {
        let validated = try await validate(body, proof: proof)
        guard inFlight < maxInFlight else { throw AdmissionError.busy }
        try Task.checkCancellation()
        inFlight += 1
        defer { inFlight -= 1 }
        try await transport.send(validated.request)
    }

    func validate(_ body: Data, proof: String?) async throws -> (request: AdmittedRequest, identity: PilotIdentity) {
        guard body.count <= 3_000_000 else { throw AdmissionError.oversized }
        try Task.checkCancellation()
        let identity = await authorize(proof)
        try Task.checkCancellation()
        guard let identity, !identity.subjectID.isEmpty else { throw AdmissionError.unauthorized }
        let evidence = await retention()
        try Task.checkCancellation()
        guard let evidence, evidence.modelID == modelID, evidence.region == region,
            evidence.effectiveMode == "none", evidence.allowedModes.contains("none"),
            (0...300).contains(Date().timeIntervalSince(evidence.verifiedAt))
        else { throw AdmissionError.retentionUnavailable }
        let request: AdmittedRequest
        do {
            request = try JSONDecoder().decode(AdmittedRequest.self, from: body)
        } catch {
            throw AdmissionError.malformed
        }
        guard request.intent == "answer" else { throw AdmissionError.unsupported }
        guard (1...512).contains(request.maxOutputTokens), request.transcript.utf8.count <= 256 else {
            throw AdmissionError.oversized
        }
        try PNG.check(request.cropPNG, maxBytes: 1_000_000, maxPixels: 1_500_000)
        try PNG.check(request.neighborhoodPNG, maxBytes: 500_000, maxPixels: 500_000)
        return (request, identity)
    }
}

private enum PNG {
    private static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    private static let ihdr: [UInt8] = [73, 72, 68, 82]
    private static let idat: [UInt8] = [73, 68, 65, 84]
    private static let iend: [UInt8] = [73, 69, 78, 68]

    static func check(_ data: Data, maxBytes: Int, maxPixels: Int) throws {
        guard data.count <= maxBytes else { throw AdmissionError.oversized }
        let bytes = [UInt8](data)
        guard bytes.count >= 45, Array(bytes.prefix(8)) == signature,
            number(bytes, at: 8) == 13, Array(bytes[12..<16]) == ihdr
        else { throw AdmissionError.malformed }
        let width = number(bytes, at: 16)
        let height = number(bytes, at: 20)
        guard width > 0, height > 0, bytes[24] == 8, [0, 2, 4, 6].contains(bytes[25]),
            bytes[26] == 0, bytes[27] == 0, bytes[28] == 0
        else { throw AdmissionError.malformed }
        guard width <= 4_096, height <= 4_096, UInt64(width) * UInt64(height) <= maxPixels else {
            throw AdmissionError.oversized
        }
        try checkChunks(bytes)
    }

    private static func checkChunks(_ bytes: [UInt8]) throws {
        var offset = 8
        var hasImageData = false
        while offset <= bytes.count - 12 {
            let length = Int(number(bytes, at: offset))
            guard length <= bytes.count - offset - 12 else { throw AdmissionError.malformed }
            let kind = Array(bytes[(offset + 4)..<(offset + 8)])
            guard kind == ihdr || kind == idat || kind == iend else { throw AdmissionError.malformed }
            guard kind != ihdr || offset == 8 else { throw AdmissionError.malformed }
            if kind == idat, length > 0 { hasImageData = true }
            let actualCRC = crc(bytes[(offset + 4)..<(offset + 8 + length)])
            guard number(bytes, at: offset + 8 + length) == actualCRC else { throw AdmissionError.malformed }
            offset += 12 + length
            if kind == iend {
                guard length == 0, hasImageData, offset == bytes.count else { throw AdmissionError.malformed }
                return
            }
        }
        throw AdmissionError.malformed
    }

    private static func number(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func crc(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var result: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            var part = (result ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 { part = (part >> 1) ^ (part & 1 == 1 ? 0xEDB8_8320 : 0) }
            result = (result >> 8) ^ part
        }
        return ~result
    }
}
