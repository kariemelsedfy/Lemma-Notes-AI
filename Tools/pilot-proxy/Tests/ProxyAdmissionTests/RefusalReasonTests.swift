import Foundation
import XCTest

@testable import ProxyAdmission

final class RefusalReasonTests: XCTestCase {
    func testEveryKindOfFailureHasAShortContentFreeCode() {
        let cases: [(Error, String)] = [
            (GeminiTransportError.status(400), "model_http_400"), (GeminiTransportError.status(503), "model_http_503"),
            (GeminiTransportError.network, "model_network"),
            (GeminiTransportError.keyUnavailable, "model_keyunavailable"),
            (GeminiError.blocked, "model_blocked"), (GeminiError.truncated, "model_truncated"),
            (GeminiBilledFailure(reason: .malformed, promptTokens: 1, outputTokens: 1), "model_malformed"),
            (AdmissionError.unsupported, "admission_unsupported"), (AdmissionError.oversized, "admission_oversized"),
            (LedgerError.invalidCost, "ledger_invalidcost"), (CancellationError(), "server_error"),
        ]
        for (error, code) in cases {
            XCTAssertEqual(PilotService.reasonCode(for: error), code)
            XCTAssertLessThanOrEqual(PilotService.reasonCode(for: error).count, 48)
        }
    }

    func testARefusalCarriesItsCodeInTheBodyAndNothingElseDoes() throws {
        let refused = PilotService.refused(GeminiTransportError.status(400))
        XCTAssertEqual(refused.status, .refused)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: refused.body) as? [String: String])
        XCTAssertEqual(object, ["reason": "model_http_400"])
        let reply = PilotRouter.reply(for: refused)
        XCTAssertEqual(reply.status, 422)
        XCTAssertEqual(reply.body, refused.body)
        for error in [
            AdmissionError.unauthorized as Error, LedgerError.overBudget, AllowanceError.subscriptionRequired,
        ] {
            XCTAssertTrue(PilotService.refused(error).body.isEmpty, "only a refusal explains itself: \(error)")
        }
    }
}
