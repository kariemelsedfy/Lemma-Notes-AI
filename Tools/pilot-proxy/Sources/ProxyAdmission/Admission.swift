import CoreGraphics
import Foundation
import ImageIO
import zlib

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

    init(normalizing request: AdmittedRequest, cropPNG: Data, neighborhoodPNG: Data) {
        requestID = request.requestID
        self.cropPNG = cropPNG
        self.neighborhoodPNG = neighborhoodPNG
        transcript = request.transcript
        intent = request.intent
        maxOutputTokens = request.maxOutputTokens
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
        let crop = try PNG.normalized(request.cropPNG, maxBytes: 1_000_000, maxPixels: 1_500_000)
        let neighborhood = try PNG.normalized(request.neighborhoodPNG, maxBytes: 500_000, maxPixels: 500_000)
        return (AdmittedRequest(normalizing: request, cropPNG: crop, neighborhoodPNG: neighborhood), identity)
    }
}

private enum PNG {
    private static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    private static let ihdr: [UInt8] = [73, 72, 68, 82]
    private static let idat: [UInt8] = [73, 68, 65, 84]
    private static let iend: [UInt8] = [73, 69, 78, 68]
    private static let srgb: [UInt8] = [115, 82, 71, 66]
    private static let exif: [UInt8] = [101, 88, 73, 102]

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
        try checkChunks(bytes, width: width, height: height)
    }

    static func normalized(_ data: Data, maxBytes: Int, maxPixels: Int) throws -> Data {
        try check(data, maxBytes: maxBytes, maxPixels: maxPixels)
        try inflate(data)
        let bytes = [UInt8](data)
        let width = Int(number(bytes, at: 16))
        let height = Int(number(bytes, at: 20))
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) == 1,
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width == width, image.height == height,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw AdmissionError.malformed }
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(frame)
        context.draw(image, in: frame)
        guard let opaque = context.makeImage() else { throw AdmissionError.malformed }
        let encoded = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                encoded as CFMutableData, "public.png" as CFString, 1, nil
            )
        else { throw AdmissionError.malformed }
        CGImageDestinationAddImage(destination, opaque, nil)
        guard CGImageDestinationFinalize(destination) else { throw AdmissionError.malformed }
        let final = try stripAncillary(encoded as Data, maxBytes: maxBytes, maxPixels: maxPixels)
        try check(final, maxBytes: maxBytes, maxPixels: maxPixels)
        return final
    }

    private static func stripAncillary(_ data: Data, maxBytes: Int, maxPixels: Int) throws -> Data {
        guard data.count <= maxBytes * 8 else { throw AdmissionError.oversized }
        try check(data, maxBytes: maxBytes * 8, maxPixels: maxPixels)
        let bytes = [UInt8](data)
        var output = Data(bytes.prefix(8))
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(number(bytes, at: offset))
            let kind = Array(bytes[(offset + 4)..<(offset + 8)])
            if kind == ihdr || kind == idat || kind == iend {
                output.append(contentsOf: bytes[offset..<(offset + 12 + length)])
            }
            offset += 12 + length
        }
        guard offset == bytes.count else { throw AdmissionError.malformed }
        return output
    }

    private static func inflate(_ data: Data) throws {
        let bytes = [UInt8](data)
        let width = Int(number(bytes, at: 16))
        let height = Int(number(bytes, at: 20))
        let channels: Int
        switch bytes[25] {
        case 0: channels = 1
        case 2: channels = 3
        case 4: channels = 2
        case 6: channels = 4
        default: throw AdmissionError.malformed
        }
        let rowBytes = width * channels + 1
        let expected = rowBytes * height
        var compressedData = Data()
        var offset = 8
        while offset <= bytes.count - 12 {
            let length = Int(number(bytes, at: offset))
            if Array(bytes[(offset + 4)..<(offset + 8)]) == idat {
                compressedData.append(contentsOf: bytes[(offset + 8)..<(offset + 8 + length)])
            }
            offset += 12 + length
        }
        var decoded = [UInt8](repeating: 0, count: expected + 1)
        var decodedCount = uLongf(decoded.count)
        let result = decoded.withUnsafeMutableBufferPointer { output in
            compressedData.withUnsafeBytes { input in
                uncompress(
                    output.baseAddress, &decodedCount,
                    input.bindMemory(to: UInt8.self).baseAddress, uLong(input.count)
                )
            }
        }
        guard result == Z_OK, Int(decodedCount) == expected else { throw AdmissionError.malformed }
        for row in 0..<height where decoded[row * rowBytes] > 4 { throw AdmissionError.malformed }
    }

    private static func checkChunks(_ bytes: [UInt8], width: UInt32, height: UInt32) throws {
        var offset = 8
        var hasImageData = false
        var seenSRGB = false
        var seenExif = false
        while offset <= bytes.count - 12 {
            let length = Int(number(bytes, at: offset))
            guard length <= bytes.count - offset - 12 else { throw AdmissionError.malformed }
            let kind = Array(bytes[(offset + 4)..<(offset + 8)])
            let validColor = kind == srgb && !seenSRGB && !hasImageData && length == 1 && bytes[offset + 8] <= 3
            let validExif =
                kind == exif && !seenExif && !hasImageData && length == 56
                && dimensionsOnlyExif(bytes, offset: offset, width: width, height: height)
            guard kind == ihdr || kind == idat || kind == iend || validColor || validExif
            else { throw AdmissionError.malformed }
            guard kind != ihdr || offset == 8 else { throw AdmissionError.malformed }
            if kind == idat, length > 0 { hasImageData = true }
            if kind == srgb { seenSRGB = true }
            if kind == exif { seenExif = true }
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

    private static func dimensionsOnlyExif(_ data: [UInt8], offset: Int, width: UInt32, height: UInt32) -> Bool {
        var expected: [UInt8] = [
            0x4D, 0x4D, 0, 0x2A, 0, 0, 0, 8,
            0, 1, 0x87, 0x69, 0, 4, 0, 0, 0, 1, 0, 0, 0, 26,
            0, 0, 0, 0, 0, 2, 0xA0, 0x02, 0, 4, 0, 0, 0, 1,
        ]
        expected += bigEndianBytes(width)
        expected += [0xA0, 0x03, 0, 4, 0, 0, 0, 1]
        expected += bigEndianBytes(height)
        expected += [0, 0, 0, 0]
        return Array(data[(offset + 8)..<(offset + 64)]) == expected
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
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
