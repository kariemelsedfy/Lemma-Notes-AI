import XCTest

@testable import Margin

final class AskAccessTests: XCTestCase {
    func testAFreeUserIsLockedOutOfAllOfAsk() {
        XCTAssertTrue(AskAccess.isLocked(offersUpgrade: true, inTour: false, hasPilotToken: false))
    }

    func testPremiumUsersAreNeverLocked() {
        XCTAssertFalse(AskAccess.isLocked(offersUpgrade: false, inTour: false, hasPilotToken: false))
    }

    func testTheGuidedTourLetsAFreeUserTryAsk() {
        XCTAssertFalse(AskAccess.isLocked(offersUpgrade: true, inTour: true, hasPilotToken: false))
    }

    func testTheOwnersTokenBuildIsNotLocked() {
        XCTAssertFalse(AskAccess.isLocked(offersUpgrade: true, inTour: false, hasPilotToken: true))
    }
}
