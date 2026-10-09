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
