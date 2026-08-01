import Analytics
import Intelligence
import XCTest

@testable import Margin

final class AnalyticsMappingTests: XCTestCase {
    func testEverySpecIntentIsReportable() {
        for intent in SpecIntent.allCases {
            let event = AIInvocationReport.event(intent: intent, tier: .onDevice)
            XCTAssertNotNil(event, "\(intent) cannot be reported")
        }
    }

    func testTheTwoVocabulariesHaveNotDrifted() {
        // If a verb is added to one enum and not the other, this fails before anyone
        // discovers it as a hole in the metrics months later.
        XCTAssertEqual(
            Set(SpecIntent.allCases.map(\.rawValue)),
            Set(AIIntent.allCases.map(\.rawValue))
        )
    }

    func testIntentsMapCaseForCase() {
        XCTAssertEqual(AIIntent(.answer), .answer)
        XCTAssertEqual(AIIntent(.continuation), .continuation)
        XCTAssertEqual(AIIntent(.plot), .plot)
        XCTAssertEqual(AIIntent(.check), .check)
        XCTAssertEqual(AIIntent(.ask), .ask)
    }

    func testTheContinueVerbKeepsItsWireSpelling() {
        XCTAssertEqual(AIIntent(.continuation).rawValue, "continue")
        XCTAssertEqual(SpecIntent.continuation.rawValue, "continue")
    }

    func testEveryRealTierIsReportable() {
        for tier in ModelTier.allCases where tier != .mock {
            XCTAssertNotNil(AIModelTier(tier), "\(tier) cannot be reported")
        }
    }

    func testMockActionsAreNeverReported() {
        XCTAssertNil(AIModelTier(.mock))
        XCTAssertNil(AIInvocationReport.event(intent: .answer, tier: .mock))
    }

    func testAReportedInvocationCarriesBothIntentAndTier() {
        let event = AIInvocationReport.event(intent: .plot, tier: .frontierCloud)

        XCTAssertEqual(event, .aiInvoked(intent: .plot, tier: .frontierCloud))
    }
}
