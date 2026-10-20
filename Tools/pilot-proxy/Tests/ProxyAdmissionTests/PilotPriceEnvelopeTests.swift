import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotPriceEnvelopeTests: XCTestCase {
    func testQuoteBoundsTheWholeContextAndHoldsFiveCents() throws {
        let quote = try PilotPriceEnvelope.quote(maxOutputTokens: 512)
        XCTAssertEqual(quote.worstCaseMicros, 5_768)  // 20,000 input tokens plus 512 output tokens
        XCTAssertEqual(quote.reservationMicros, 50_000)
    }

    func testOutputBoundsAreEnforced() {
        for tokens in [0, -1, 1025] {
            XCTAssertThrowsError(try PilotPriceEnvelope.quote(maxOutputTokens: tokens)) { error in
                XCTAssertEqual(error as? PilotPriceError, .invalidOutput)
            }
        }
        XCTAssertNoThrow(try PilotPriceEnvelope.quote(maxOutputTokens: 1))
    }

    func testWorstCaseNeverExceedsTheHold() throws {
        for tokens in [1, 128, 256, 512] {
            let quote = try PilotPriceEnvelope.quote(maxOutputTokens: tokens)
            XCTAssertLessThanOrEqual(quote.worstCaseMicros, quote.reservationMicros)
        }
    }
}
