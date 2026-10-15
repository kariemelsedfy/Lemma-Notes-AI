import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import ProxyAdmission

final class PNGNormalizationTests: XCTestCase {
    func testImageIOEncodedSelectionKeepsOpaqueInkAndFlattensTransparentContext() async throws {
        let crop = try Self.png(width: 12, height: 7, opaque: true)
        let neighborhood = try Self.png(width: 4, height: 4, opaque: false)
        let allowedInputChunks = ["IHDR", "sRGB", "eXIf", "IDAT", "IEND"]
        XCTAssertTrue(Self.chunkKinds(crop).allSatisfy(allowedInputChunks.contains))
        XCTAssertTrue(Self.chunkKinds(neighborhood).allSatisfy(allowedInputChunks.contains))
        let transport = RecordedImageTransport()
        try await gate().invoke(try body(crop: crop, neighborhood: neighborhood), proof: "pilot", transport: transport)
        let recorded = await transport.request
        let received = try XCTUnwrap(recorded)

        XCTAssertEqual(try Self.dimensions(received.cropPNG), [12, 7])
        XCTAssertEqual(try Self.dimensions(received.neighborhoodPNG), [4, 4])
        XCTAssertEqual(try Self.firstPixel(received.cropPNG), [0, 0, 0, 255])
        XCTAssertEqual(try Self.firstPixel(received.neighborhoodPNG), [255, 255, 255, 255])
        XCTAssertEqual(Self.chunkKinds(received.cropPNG), ["IHDR", "IDAT", "IEND"])
        XCTAssertEqual(Self.chunkKinds(received.neighborhoodPNG), ["IHDR", "IDAT", "IEND"])
    }

    func testBrokenIDATWithCorrectCRCIsRejectedBeforeFakeTransport() async throws {
        var bytes = [UInt8](try Self.png(width: 12, height: 7, opaque: true))
        let offset = try XCTUnwrap(Self.chunkOffset("IDAT", in: bytes))
        let length = Self.chunkLength(bytes, at: offset)
        XCTAssertGreaterThan(length, 2)
        bytes[offset + 8] = 0xFF
        bytes[offset + 9] = 0xFF
        Self.putCRC(&bytes, at: offset, length: length)
        let transport = RecordedImageTransport()
        await expect(.malformed, crop: Data(bytes), transport: transport)
        let sends = await transport.sends
        XCTAssertEqual(sends, 0)
    }

    func testMetadataAndTruncationRemainDeniedBeforeNormalizedDispatch() async throws {
        let original = [UInt8](try Self.png(width: 4, height: 4, opaque: true))
        let end = try XCTUnwrap(Self.chunkOffset("IEND", in: original))
        let metadata = Self.chunk(kind: "tEXt", payload: Array("note\0private".utf8))
        var inserted = original
        inserted.insert(contentsOf: metadata, at: end)
        let transport = RecordedImageTransport()
        await expect(.malformed, crop: Data(inserted), transport: transport)
        await expect(.malformed, crop: Data(original.dropLast(4)), transport: transport)
        let sends = await transport.sends
        XCTAssertEqual(sends, 0)
    }

    func testByteAndPixelCapsRejectBeforeNormalizedDispatch() async throws {
        let transport = RecordedImageTransport()
        await expect(.oversized, crop: Data(repeating: 0xFF, count: 1_000_001), transport: transport)
        var bytes = [UInt8](try Self.png(width: 4, height: 4, opaque: true))
        bytes[16...19] = [0, 0, 16, 0]
        bytes[20...23] = [0, 0, 16, 0]
        Self.putCRC(&bytes, at: 8, length: 13)
        await expect(.oversized, crop: Data(bytes), transport: transport)
        let sends = await transport.sends
        XCTAssertEqual(sends, 0)
    }

    func testExtraExifMetadataWithCorrectCRCNeverReachesTransport() async throws {
        let original = try Self.png(width: 4, height: 4, opaque: true)
        let baseline = RecordedImageTransport()
        try await gate().invoke(try body(crop: original, neighborhood: original), proof: "pilot", transport: baseline)
        let recorded = await baseline.request
        var bytes = [UInt8](try XCTUnwrap(recorded).cropPNG)
        let imageData = try XCTUnwrap(Self.chunkOffset("IDAT", in: bytes))
        let dimensionsOnlyExif: [UInt8] = [
            0x4D, 0x4D, 0, 0x2A, 0, 0, 0, 8,
            0, 1, 0x87, 0x69, 0, 4, 0, 0, 0, 1, 0, 0, 0, 26,
            0, 0, 0, 0, 0, 2, 0xA0, 0x02, 0, 4, 0, 0, 0, 1,
            0, 0, 0, 4, 0xA0, 0x03, 0, 4, 0, 0, 0, 1,
            0, 0, 0, 4, 0, 0, 0, 0,
        ]
        bytes.insert(contentsOf: Self.chunk(kind: "eXIf", payload: dimensionsOnlyExif), at: imageData)
        let accepted = RecordedImageTransport()
        try await gate().invoke(
            try body(crop: Data(bytes), neighborhood: original), proof: "pilot", transport: accepted
        )
        let acceptedSends = await accepted.sends
        XCTAssertEqual(acceptedSends, 1)

        let exif = try XCTUnwrap(Self.chunkOffset("eXIf", in: bytes))
        bytes[exif + 8 + 52] = 0x41
        Self.putCRC(&bytes, at: exif, length: dimensionsOnlyExif.count)
        let rejected = RecordedImageTransport()
        await expect(.malformed, crop: Data(bytes), transport: rejected)
        let rejectedSends = await rejected.sends
        XCTAssertEqual(rejectedSends, 0)
    }

    private func gate() -> AdmissionGate {
        let identity = PilotIdentity(subjectID: UUID().uuidString)
        return AdmissionGate(
            modelID: "amazon.nova-lite-v1:0", region: "us-east-1",
            authorize: { proof in proof == "pilot" ? identity : nil },
            retention: {
                RetentionEvidence(
                    modelID: "amazon.nova-lite-v1:0", region: "us-east-1", effectiveMode: "none",
                    allowedModes: ["none"], verifiedAt: Date()
                )
            }
        )
    }

    private func body(crop: Data, neighborhood: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString,
            "cropPNG": crop.base64EncodedString(),
            "neighborhoodPNG": neighborhood.base64EncodedString(),
            "transcript": "2+3=", "intent": "answer", "maxOutputTokens": 32,
        ])
    }

    private func expect(_ error: AdmissionError, crop: Data, transport: RecordedImageTransport) async {
        do {
            try await gate().invoke(
                try body(crop: crop, neighborhood: Self.png(width: 4, height: 4, opaque: true)),
                proof: "pilot", transport: transport
            )
            XCTFail("Rejected image reached the fake transport")
        } catch let observed as AdmissionError {
            XCTAssertEqual(observed, error)
        } catch {
            XCTFail("Expected a content-free image error")
        }
    }

    private static func png(width: Int, height: Int, opaque: Bool) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        if opaque {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(frame)
        } else {
            context.clear(frame)
        }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output as CFMutableData, "public.png" as CFString, 1, nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func dimensions(_ data: Data) throws -> [Int] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return [image.width, image.height]
    }

    private static func firstPixel(_ data: Data) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        return try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Array(buffer.bindMemory(to: UInt8.self))
        }
    }

    private static func chunkKinds(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        var offset = 8
        var result: [String] = []
        while offset + 12 <= bytes.count {
            let length = chunkLength(bytes, at: offset)
            guard offset + 12 + length <= bytes.count else { break }
            result.append(String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? "invalid")
            offset += 12 + length
        }
        return result
    }

    private static func chunkOffset(_ kind: String, in bytes: [UInt8]) -> Int? {
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = chunkLength(bytes, at: offset)
            guard offset + 12 + length <= bytes.count else { return nil }
            if String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) == kind { return offset }
            offset += 12 + length
        }
        return nil
    }

    private static func chunkLength(_ bytes: [UInt8], at offset: Int) -> Int {
        bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }

    private static func chunk(kind: String, payload: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4) + Array(kind.utf8) + payload + [0, 0, 0, 0]
        let length = payload.count
        for index in 0..<4 { bytes[index] = UInt8(truncatingIfNeeded: length >> (24 - index * 8)) }
        putCRC(&bytes, at: 0, length: length)
        return bytes
    }

    private static func putCRC(_ bytes: inout [UInt8], at offset: Int, length: Int) {
        let end = offset + 8 + length
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes[(offset + 4)..<end] {
            var part = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 { part = (part >> 1) ^ (part & 1 == 1 ? 0xEDB8_8320 : 0) }
            crc = (crc >> 8) ^ part
        }
        for index in 0..<4 {
            bytes[end + index] = UInt8(truncatingIfNeeded: ~crc >> (24 - index * 8))
        }
    }
}

private actor RecordedImageTransport: ProxyTransport {
    private(set) var sends = 0
    private(set) var request: AdmittedRequest?

    func send(_ request: AdmittedRequest) async throws {
        sends += 1
        self.request = request
    }
}
