import Foundation
import XCTest

@testable import ProxyAdmission

final class InstallRecordTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15

    private func record(
        plan: InstallPlan = .free, expires: TimeInterval? = nil, tourAsks: Int = 0, month: String = "",
        micros: Int64 = 0
    ) -> InstallRecord {
        InstallRecord(
            key: AttestedKey(
                keyID: Data(repeating: 1, count: 32), publicKeyX963: Data(repeating: 2, count: 65), counter: 0),
            plan: plan, planExpiresAt: expires.map { Self.now.addingTimeInterval($0) }, tourAsksUsed: tourAsks,
            usageMonth: month, usageMicros: micros, createdAt: Self.now)
    }

    private func transaction(
        trial: Bool = false, expires: TimeInterval = 86_400, revoked: Bool = false, original: String = "tx1",
        product: String = "p"
    ) -> VerifiedTransaction {
        VerifiedTransaction(
            bundleID: "b", productID: product, originalTransactionID: original,
            expiresAt: Self.now.addingTimeInterval(expires), isIntroductoryTrial: trial,
            revokedAt: revoked ? Self.now.addingTimeInterval(-10) : nil, environment: "Production")
    }

    // MARK: - Free installs: three asks, ever

    func testAFreeInstallHasExactlyThreeHostedAsksAndThenNeedsASubscription() throws {
        var free = record()
        for _ in 0..<InstallAllowance.tourAsks { try InstallAllowance.reserve(&free, micros: 4_000, at: Self.now) }
        XCTAssertEqual(free.tourAsksUsed, 3)
        XCTAssertThrowsError(try InstallAllowance.reserve(&free, micros: 4_000, at: Self.now)) {
            XCTAssertEqual($0 as? AllowanceError, .subscriptionRequired)
        }
        XCTAssertEqual(free.tourAsksUsed, 3, "a refused ask changes nothing")
    }

    func testAFreeInstallNeverSpendsMoneyAllowance() throws {
        var free = record()
        try InstallAllowance.reserve(&free, micros: 4_000, at: Self.now)
        XCTAssertEqual(free.usageMicros, 0)
    }

    // MARK: - Paid installs: a monthly cost allowance

    func testAPaidInstallSpendsItsAllowanceAndIsStoppedAtTheCap() throws {
        var paid = record(plan: .premium, expires: 86_400)
        try InstallAllowance.reserve(&paid, micros: 1_000_000, at: Self.now)
        try InstallAllowance.reserve(&paid, micros: 500_000, at: Self.now)
        XCTAssertEqual(paid.usageMicros, 1_500_000)
        XCTAssertThrowsError(try InstallAllowance.reserve(&paid, micros: 1, at: Self.now)) {
            XCTAssertEqual($0 as? AllowanceError, .allowanceUsedUp)
        }
        XCTAssertEqual(paid.usageMicros, 1_500_000)
    }

    func testTheAllowanceRenewsWithTheMonth() throws {
        var paid = record(plan: .premium, expires: 86_400 * 90, month: "2026-12", micros: 1_500_000)
        try InstallAllowance.reserve(&paid, micros: 10_000, at: Self.now)
        XCTAssertEqual(paid.usageMonth, "2027-01")
        XCTAssertEqual(paid.usageMicros, 10_000)
    }

    func testSettlingReplacesTheHoldWithTheActualCost() throws {
        var paid = record(plan: .trial, expires: 86_400)
        try InstallAllowance.reserve(&paid, micros: 40_000, at: Self.now)
        InstallAllowance.settle(&paid, reserved: 40_000, observed: 1_500, at: Self.now)
        XCTAssertEqual(paid.usageMicros, 1_500)
        InstallAllowance.settle(&paid, reserved: 5_000_000, observed: 0, at: Self.now)
        XCTAssertEqual(paid.usageMicros, 0, "never negative")
    }

    func testALapsedPaidPlanIsTreatedAsFree() throws {
        var lapsed = record(plan: .premium, expires: -60)
        XCTAssertEqual(lapsed.effectivePlan(at: Self.now), .free)
        try InstallAllowance.reserve(&lapsed, micros: 4_000, at: Self.now)
        XCTAssertEqual(lapsed.tourAsksUsed, 1)
    }

    func testOverflowIsRefusedNotWrapped() {
        var paid = record(plan: .premium, expires: 86_400, month: "2027-01", micros: Int64.max - 1)
        XCTAssertThrowsError(try InstallAllowance.reserve(&paid, micros: 10, at: Self.now))
    }

    // MARK: - Applying a transaction

    func testAVerifiedTransactionGrantsItsPlan() {
        var free = record()
        free.apply(transaction(trial: true), at: Self.now)
        XCTAssertEqual(free.plan, .trial)
        free.apply(transaction(trial: false, expires: 86_400 * 30), at: Self.now)
        XCTAssertEqual(free.plan, .premium)
        XCTAssertEqual(free.originalTransactionID, "tx1")
    }

    func testAnExpiredTransactionGrantsNothing() {
        var free = record()
        free.apply(transaction(expires: -1), at: Self.now)
        XCTAssertEqual(free.plan, .free)
    }

    func testRevokingTheCurrentTransactionEndsThePlanButAnotherOneDoesNot() {
        var paid = record(plan: .premium, expires: 86_400)
        paid.originalTransactionID = "tx1"
        paid.apply(transaction(revoked: true, original: "other"), at: Self.now)
        XCTAssertEqual(paid.plan, .premium)
        paid.apply(transaction(revoked: true, original: "tx1"), at: Self.now)
        XCTAssertEqual(paid.plan, .free)
    }

    func testAnOlderTransactionCannotShortenALongerPlan() {
        var paid = record()
        paid.apply(transaction(expires: 86_400 * 300, original: "long"), at: Self.now)
        paid.apply(transaction(expires: 86_400 * 2, original: "short"), at: Self.now)
        XCTAssertEqual(paid.planExpiresAt, Self.now.addingTimeInterval(86_400 * 300))
    }

    // MARK: - Pro

    func testAProInstallHasTheLargerAllowanceAndIsStoppedAtItsOwnCap() throws {
        var pro = record(plan: .pro, expires: 86_400 * 30, month: "2027-01", micros: 6_950_000)
        XCTAssertEqual(InstallAllowance.proMonthlyMicros, 7_000_000)
        try InstallAllowance.reserve(&pro, micros: 50_000, at: Self.now)
        XCTAssertThrowsError(try InstallAllowance.reserve(&pro, micros: 1, at: Self.now)) { error in
            XCTAssertEqual(error as? AllowanceError, .allowanceUsedUp)
        }
        var premium = record(plan: .premium, expires: 86_400 * 30, month: "2027-01", micros: 1_500_000)
        XCTAssertThrowsError(try InstallAllowance.reserve(&premium, micros: 1, at: Self.now))
    }

    func testAProProductGrantsProAndAPremiumReceiptNeverReplacesALiveOne() {
        var install = record()
        install.apply(
            transaction(expires: 86_400 * 30, original: "pro1", product: "lemmanotesai.pro.monthly"), at: Self.now)
        XCTAssertEqual(install.plan, .pro)
        install.apply(
            transaction(expires: 86_400 * 365, original: "yearly1", product: "lemmanotesai.premium.yearly"),
            at: Self.now)
        XCTAssertEqual(install.plan, .pro, "a longer Premium receipt must not downgrade a live Pro one")
        XCTAssertEqual(install.originalTransactionID, "pro1")
    }

    func testUpgradingWithinTheSameSubscriptionMovesToProAndBackToPremium() {
        var install = record()
        install.apply(transaction(original: "sub", product: "lemmanotesai.premium.monthly"), at: Self.now)
        XCTAssertEqual(install.plan, .premium)
        install.apply(transaction(original: "sub", product: "lemmanotesai.pro.monthly"), at: Self.now)
        XCTAssertEqual(install.plan, .pro)
        install.apply(transaction(original: "sub", product: "lemmanotesai.premium.monthly"), at: Self.now)
        XCTAssertEqual(install.plan, .premium)
    }
}
