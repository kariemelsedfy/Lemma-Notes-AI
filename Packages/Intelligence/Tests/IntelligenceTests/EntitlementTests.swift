import XCTest

@testable import Intelligence

final class EntitlementTests: XCTestCase {
    func testPaidPlansMayAsk() {
        for plan in [Plan.trial, .premium, .pilot] {
            XCTAssertEqual(HostedAskPolicy(plan: plan).access, .allowed)
        }
    }

    func testAFreeUserMustSubscribeOutsideTheTour() {
        let policy = HostedAskPolicy(plan: .free)
        XCTAssertEqual(policy.access, .subscribeRequired)
        XCTAssertFalse(policy.mayTransmit)
    }

    func testTheTourGrantsAFewAsksThenStops() {
        var policy = HostedAskPolicy(plan: .free, isInOnboarding: true)
        XCTAssertEqual(policy.access, .onboardingAsk(remaining: HostedAskPolicy.onboardingAsks))
        policy.onboardingAsksUsed = HostedAskPolicy.onboardingAsks - 1
        XCTAssertEqual(policy.access, .onboardingAsk(remaining: 1))
        policy.onboardingAsksUsed = HostedAskPolicy.onboardingAsks
        XCTAssertEqual(policy.access, .subscribeRequired)
    }

    func testTheOnboardingAllowanceIsUnreachableOnceTheTourIsOver() {
        let policy = HostedAskPolicy(plan: .free, isInOnboarding: false, onboardingAsksUsed: 0)
        XCTAssertEqual(policy.access, .subscribeRequired)
    }

    func testAUsedUpAllowanceStopsPaidAsksButNeverTheFreeNotebook() {
        let policy = HostedAskPolicy(plan: .premium, allowanceUsedUp: true)
        XCTAssertEqual(policy.access, .allowanceUsedUp)
        XCTAssertFalse(policy.mayTransmit)
    }

    func testOnlyTheFreePlanLacksHostedAsk() {
        XCTAssertFalse(Plan.free.includesHostedAsk)
        XCTAssertTrue(Plan.trial.includesHostedAsk)
    }
}
