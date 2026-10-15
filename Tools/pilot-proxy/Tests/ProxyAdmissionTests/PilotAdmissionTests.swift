import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotAdmissionTests: XCTestCase {
    private static let pilotID = UUID()
    private static let modelID = "amazon.nova-lite-v1:0"
    private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
    )!

    func testValidatedRequestReservesBeforeItReachesFakeTransport() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100_000)
        let transport = FakePilotTransport()
        let gate = PilotAdmission(admission: admission(), ledger: ledger, price: { Self.quote() })
        let requestID = UUID()

        let receipt = try await gate.invoke(try body(requestID: requestID), proof: "pilot", transport: transport)

        XCTAssertEqual(receipt.requestID, requestID)
        XCTAssertEqual(receipt.heldMicros, 50_000)
        XCTAssertEqual(receipt.remainingMicros, 50_000)
        try await ledger.recordObservedCost(requestID: requestID, observedMicros: 19_123)
        let observed = try await ledger.observedTotalMicros()
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(observed, 19_123)
        XCTAssertEqual(remaining, 50_000)
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    func testUnverifiedIdentityRetentionAndMalformedPayloadNeverReserveOrSend() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100_000)
        let transport = FakePilotTransport()
        let allowed = PilotAdmission(admission: admission(), ledger: ledger, price: { Self.quote() })
        let wrongRetention = PilotAdmission(
            admission: admission(mode: "default"), ledger: ledger, price: { Self.quote() }
        )
        await expect(.unauthorized, allowed, try body(), proof: nil, transport: transport)
        await expect(.retentionUnavailable, wrongRetention, try body(), transport: transport)
        await expect(.malformed, allowed, try body(extra: ["glyphBank": "forbidden"]), transport: transport)
        await expect(.malformed, allowed, try body(crop: Data([0, 1, 2])), transport: transport)
        let remaining = try await ledger.remainingMicros()
        let calls = await transport.calls
        XCTAssertEqual(remaining, 100_000)
        XCTAssertEqual(calls, 0)
    }

    func testAbsentOrExpensivePriceNeverReachesFakeTransport() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100_000)
        let transport = FakePilotTransport()
        let missing = PilotAdmission(admission: admission(), ledger: ledger)
        let expensive = PilotAdmission(
            admission: admission(), ledger: ledger, price: { Self.quote(inputRate: 200_000) }
        )
        await expectPrice(.unavailable, missing, try body(), transport: transport)
        await expectPrice(.tooExpensive, expensive, try body(), transport: transport)
        let remaining = try await ledger.remainingMicros()
        let calls = await transport.calls
        XCTAssertEqual(remaining, 100_000)
        XCTAssertEqual(calls, 0)
    }

    func testBadPilotIDOrDuplicateOrOverBudgetStopsBeforeFakeTransport() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 50_000)
        let transport = FakePilotTransport()
        let invalidID = PilotAdmission(
            admission: admission(subjectID: "not-a-uuid"), ledger: ledger, price: { Self.quote() }
        )
        let allowed = PilotAdmission(admission: admission(), ledger: ledger, price: { Self.quote() })
        await expect(.unauthorized, invalidID, try body(), transport: transport)
        let input = try body()
        _ = try await allowed.invoke(input, proof: "pilot", transport: transport)
        await expectLedger(.duplicate, allowed, input, transport: transport)
        await expectLedger(.overBudget, allowed, try body(), transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    func testRateLimitDeniesFortyFirstFakeSend() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase())
        let transport = FakePilotTransport()
        let gate = PilotAdmission(admission: admission(), ledger: ledger, price: { Self.quote() })
        for _ in 0..<40 {
            _ = try await gate.invoke(try body(), proof: "pilot", transport: transport)
        }
        await expectLedger(.rateLimited, gate, try body(), transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 40)
    }

    func testCompetingLedgerInstancesAllowOnlyOneFakeSend() async throws {
        let database = try temporaryDatabase()
        let firstLedger = try SpendLedger.bootstrap(databaseURL: database, limitMicros: 50_000)
        let secondLedger = try SpendLedger(databaseURL: database, limitMicros: 50_000)
        let transport = FakePilotTransport()
        let first = PilotAdmission(admission: admission(), ledger: firstLedger, price: { Self.quote() })
        let second = PilotAdmission(admission: admission(), ledger: secondLedger, price: { Self.quote() })
        let inputs = [try body(), try body()]
        let tasks = [
            Task { try await first.invoke(inputs[0], proof: "pilot", transport: transport) },
            Task { try await second.invoke(inputs[1], proof: "pilot", transport: transport) },
        ]
        var accepted = 0
        var denied = 0
        for task in tasks {
            do {
                _ = try await task.value
                accepted += 1
            } catch let error as LedgerError {
                XCTAssertEqual(error, .overBudget)
                denied += 1
            }
        }
        XCTAssertEqual(accepted, 1)
        XCTAssertEqual(denied, 1)
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    func testFakeTransportFailureKeepsTheHoldAndCannotReplay() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100_000)
        let transport = FakePilotTransport(fails: true)
        let gate = PilotAdmission(admission: admission(), ledger: ledger, price: { Self.quote() })
        let input = try body()
        do {
            _ = try await gate.invoke(input, proof: "pilot", transport: transport)
            XCTFail("Expected a fake transport failure")
        } catch let error as FakePilotTransportError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error boundary")
        }
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(remaining, 50_000)
        await expectLedger(.duplicate, gate, input, transport: transport)
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
    }

    func testCancellationBeforeDelayedQuoteCannotSendOrReserve() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 50_000)
        let transport = FakePilotTransport()
        let gate = PilotAdmission(admission: admission(), ledger: ledger) {
            try? await Task.sleep(for: .milliseconds(100))
            return Self.quote()
        }
        let input = try body()
        let task = Task { try await gate.invoke(input, proof: "pilot", transport: transport) }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled request reached fake transport")
        } catch is CancellationError {
            XCTAssertTrue(task.isCancelled)
        } catch {
            XCTFail("Expected cancellation")
        }
        let calls = await transport.calls
        let remaining = try await ledger.remainingMicros()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(remaining, 50_000)
    }

    private func admission(subjectID: String = pilotID.uuidString, mode: String = "none") -> AdmissionGate {
        AdmissionGate(
            modelID: Self.modelID, region: "us-east-1",
            authorize: { proof in proof == "pilot" ? PilotIdentity(subjectID: subjectID) : nil },
            retention: {
                RetentionEvidence(
                    modelID: Self.modelID, region: "us-east-1", effectiveMode: mode,
                    allowedModes: ["none"], verifiedAt: Date()
                )
            }
        )
    }

    private static func quote(inputRate: Int64 = 60_000) -> PilotPriceEvidence {
        PilotPriceEvidence(
            modelID: modelID, region: "us-east-1", tier: "standard",
            inputMicrosPerMillion: inputRate, outputMicrosPerMillion: 240_000,
            otherMaximumMicros: 1_000, verifiedAt: Date()
        )
    }

    private func body(requestID: UUID = UUID(), crop: Data = pixel, extra: [String: Any] = [:]) throws -> Data {
        var fields: [String: Any] = [
            "requestID": requestID.uuidString,
            "cropPNG": crop.base64EncodedString(),
            "neighborhoodPNG": Self.pixel.base64EncodedString(),
            "transcript": "2+3=", "intent": "answer", "maxOutputTokens": 256,
        ]
        for (key, value) in extra { fields[key] = value }
        return try JSONSerialization.data(withJSONObject: fields)
    }

    private func temporaryDatabase() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("spend.sqlite")
    }

    private func expect(
        _ failure: AdmissionError, _ gate: PilotAdmission, _ input: Data,
        proof: String? = "pilot", transport: FakePilotTransport
    ) async {
        do {
            _ = try await gate.invoke(input, proof: proof, transport: transport)
            XCTFail("Admission failure still sent the request")
        } catch let error as AdmissionError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free admission error")
        }
    }

    private func expectPrice(
        _ failure: PilotPriceError, _ gate: PilotAdmission, _ input: Data, transport: FakePilotTransport
    ) async {
        do {
            _ = try await gate.invoke(input, proof: "pilot", transport: transport)
            XCTFail("Invalid price still sent the request")
        } catch let error as PilotPriceError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free price error")
        }
    }

    private func expectLedger(
        _ failure: LedgerError, _ gate: PilotAdmission, _ input: Data, transport: FakePilotTransport
    ) async {
        do {
            _ = try await gate.invoke(input, proof: "pilot", transport: transport)
            XCTFail("Ledger denial still sent the request")
        } catch let error as LedgerError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free ledger error")
        }
    }
}

private enum FakePilotTransportError: Error, Equatable {
    case unavailable
}

private actor FakePilotTransport: ProxyTransport {
    private(set) var calls = 0
    let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func send(_ request: AdmittedRequest) async throws {
        calls += 1
        if fails { throw FakePilotTransportError.unavailable }
    }
}
