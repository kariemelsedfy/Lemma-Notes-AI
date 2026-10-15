import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotServiceTests: XCTestCase {
    private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
    )!

    func testRequestFramesRoundTripAndWaitForTheWholeBody() throws {
        let body = Data("hello".utf8)
        let frame = PilotFrame.encodeRequest(body)
        XCTAssertNil(try PilotFrame.requestLength(in: frame.prefix(3)))
        XCTAssertNil(try PilotFrame.requestBody(from: frame.dropLast()))
        XCTAssertEqual(try PilotFrame.requestBody(from: frame), body)
    }

    func testOversizedOrEmptyDeclaredLengthIsRejectedBeforeBuffering() {
        XCTAssertThrowsError(try PilotFrame.requestLength(in: Data([0xFF, 0xFF, 0xFF, 0xFF])))
        XCTAssertThrowsError(try PilotFrame.requestLength(in: Data([0, 0, 0, 0])))
        XCTAssertThrowsError(try PilotFrame.requestLength(in: Data([0x00, 0x2D, 0xC6, 0xC1])))
    }

    func testReplyFramesRoundTripAndRejectTrailingOrUnknownBytes() throws {
        let frame = PilotFrame.encodeReply(status: .success, body: Data("{}".utf8))
        let decoded = try XCTUnwrap(PilotFrame.decodeReply(frame))
        XCTAssertEqual(decoded.status, .success)
        XCTAssertEqual(decoded.body, Data("{}".utf8))
        XCTAssertNil(PilotFrame.decodeReply(frame + Data([0])))
        XCTAssertNil(PilotFrame.decodeReply(Data([9, 0, 0, 0, 0])))
        XCTAssertNil(PilotFrame.decodeReply(Data([0, 0, 0])))
    }

    func testErrorsReduceToFourWireStatuses() {
        XCTAssertEqual(PilotService.status(for: AdmissionError.unauthorized), .unauthorized)
        XCTAssertEqual(PilotService.status(for: LedgerError.overBudget), .overBudget)
        XCTAssertEqual(PilotService.status(for: LedgerError.rateLimited), .overBudget)
        XCTAssertEqual(PilotService.status(for: AdmissionError.malformed), .refused)
        XCTAssertEqual(PilotService.status(for: GeminiError.truncated), .refused)
        XCTAssertEqual(PilotService.status(for: GeminiTransportError.status(500)), .refused)
    }

    func testHandleReturnsSpecOnSuccessAndEmptyBodyOnFailure() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100_000)
        let id = UUID().uuidString
        let gate = AdmissionGate(authorize: { $0 == "psk" ? PilotIdentity(subjectID: id) : nil })
        let service = PilotService(
            pilot: PilotAdmission(admission: gate, ledger: ledger), transport: FixedTransport()
        )
        let good = await service.handle(body: try body(), proof: "psk")
        XCTAssertEqual(PilotFrame.decodeReply(good)?.status, .success)
        XCTAssertEqual(PilotFrame.decodeReply(good)?.body, Data(#"{"version":1}"#.utf8))
        let denied = await service.handle(body: try body(), proof: nil)
        XCTAssertEqual(PilotFrame.decodeReply(denied)?.status, .unauthorized)
        XCTAssertEqual(PilotFrame.decodeReply(denied)?.body, Data())
        let junk = await service.handle(body: Data("nope".utf8), proof: "psk")
        XCTAssertEqual(PilotFrame.decodeReply(junk)?.status, .refused)
    }

    private func body() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString, "cropPNG": Self.pixel.base64EncodedString(),
            "neighborhoodPNG": Self.pixel.base64EncodedString(), "transcript": "2+3=",
            "intent": "answer", "maxOutputTokens": 256,
        ])
    }

    private func temporaryDatabase() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("spend.sqlite")
    }
}

private struct FixedTransport: PilotModelTransport {
    func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
        GeminiReply(specJSON: Data(#"{"version":1}"#.utf8), promptTokens: 100, outputTokens: 10)
    }
}
