import Intelligence
import XCTest

@testable import Margin

@MainActor
final class PremiumStoreTests: XCTestCase {
    private final class FakeBackend: StoreBackend, @unchecked Sendable {
        var facts: [EntitlementFact] = []
        var purchaseResult: Result<PurchaseOutcome, Error> = .success(.purchased)
        var grantOnPurchase: EntitlementFact?
        var restoreGrants: EntitlementFact?
        var loadedOffers = [
            PremiumOffer(product: .yearly, displayPrice: "$39.99", hasFreeTrial: true),
            PremiumOffer(product: .monthly, displayPrice: "$4.99", hasFreeTrial: true),
        ]
        private let stream = AsyncStream<Void>.makeStream()

        func offers() async throws -> [PremiumOffer] { loadedOffers }
        func purchase(_ product: PremiumProduct) async throws -> PurchaseOutcome {
            let outcome = try purchaseResult.get()
            if outcome == .purchased, let grantOnPurchase { facts.append(grantOnPurchase) }
            return outcome
        }
        func currentFacts() async -> [EntitlementFact] { facts }
        var signed: [String] = []
        func signedTransactions() async -> [String] { signed }
        func changes() -> AsyncStream<Void> { stream.stream }
        func restore() async throws { if let restoreGrants { facts.append(restoreGrants) } }
        func announceChange() { stream.continuation.yield() }
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fact(
        _ product: PremiumProduct = .yearly, expires: TimeInterval = 86_400, trial: Bool = false, revoked: Bool = false
    ) -> EntitlementFact {
        EntitlementFact(
            productID: product.rawValue, expiresAt: Self.now.addingTimeInterval(expires),
            isIntroductoryTrial: trial, isRevoked: revoked)
    }

    func testNoEntitlementsIsTheFreePlan() {
        XCTAssertEqual(PlanResolver.plan(from: [], now: Self.now), .free)
    }

    func testALiveSubscriptionIsPremiumAndALiveTrialIsATrial() {
        XCTAssertEqual(PlanResolver.plan(from: [fact()], now: Self.now), .premium)
        XCTAssertEqual(PlanResolver.plan(from: [fact(trial: true)], now: Self.now), .trial)
        XCTAssertEqual(PlanResolver.plan(from: [fact(trial: true), fact(.monthly)], now: Self.now), .premium)
    }

    func testALiveProSubscriptionIsProAndWinsOverPremium() {
        XCTAssertEqual(PlanResolver.plan(from: [fact(.pro)], now: Self.now), .pro)
        XCTAssertEqual(PlanResolver.plan(from: [fact(.yearly), fact(.pro)], now: Self.now), .pro)
        XCTAssertEqual(PlanResolver.plan(from: [fact(.yearly), fact(.pro, revoked: true)], now: Self.now), .premium)
        XCTAssertEqual(PlanResolver.plan(from: [fact(.pro, expires: -1)], now: Self.now), .free)
    }

    func testOnlyAPremiumSubscriberIsOfferedPro() async {
        for (facts, expected) in [([fact(.yearly)], true), ([fact(.pro)], false), ([], false)] {
            let backend = FakeBackend()
            backend.facts = facts
            let store = PremiumStore(backend: backend)
            await store.refresh()
            XCTAssertEqual(store.offersPro, expected)
        }
    }

    func testExpiredRevokedAndForeignEntitlementsCountForNothing() {
        XCTAssertEqual(PlanResolver.plan(from: [fact(expires: -1)], now: Self.now), .free)
        XCTAssertEqual(PlanResolver.plan(from: [fact(revoked: true)], now: Self.now), .free)
        let foreign = EntitlementFact(
            productID: "someone.elses.product", expiresAt: nil, isIntroductoryTrial: false, isRevoked: false)
        XCTAssertEqual(PlanResolver.plan(from: [foreign], now: Self.now), .free)
    }

    func testStartLoadsOffersAndTheCurrentPlan() async {
        let backend = FakeBackend()
        backend.facts = [fact(expires: 1_000_000_000_000)]
        let store = PremiumStore(backend: backend)
        await store.start()
        XCTAssertEqual(store.plan, .premium)
        XCTAssertEqual(store.offer(for: .yearly)?.displayPrice, "$39.99")
        XCTAssertEqual(store.phase, .idle)
    }

    func testAPurchaseMovesTheUserToPremium() async {
        let backend = FakeBackend()
        backend.grantOnPurchase = fact(expires: 1_000_000_000_000)
        let store = PremiumStore(backend: backend)
        await store.start()
        XCTAssertEqual(store.plan, .free)
        let outcome = await store.purchase(.yearly)
        XCTAssertEqual(outcome, .purchased)
        XCTAssertEqual(store.plan, .premium)
    }

    func testACancelledOrPendingPurchaseChangesNothing() async {
        let backend = FakeBackend()
        let store = PremiumStore(backend: backend)
        backend.purchaseResult = .success(.cancelled)
        let cancelled = await store.purchase(.monthly)
        XCTAssertEqual(cancelled, .cancelled)
        backend.purchaseResult = .success(.pending)
        let pending = await store.purchase(.monthly)
        XCTAssertEqual(pending, .pending)
        XCTAssertEqual(store.plan, .free)
    }

    func testAFailedPurchaseIsReportedNotThrown() async {
        let backend = FakeBackend()
        backend.purchaseResult = .failure(URLError(.notConnectedToInternet))
        let store = PremiumStore(backend: backend)
        let outcome = await store.purchase(.yearly)
        XCTAssertNil(outcome)
        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(store.plan, .free)
    }

    func testRestoreFindsAnEarlierPurchaseOrSaysThereWasNone() async {
        let backend = FakeBackend()
        let store = PremiumStore(backend: backend)
        await store.restore()
        XCTAssertTrue(store.restoreFoundNothing)
        backend.restoreGrants = fact(expires: 1_000_000_000_000)
        await store.restore()
        XCTAssertFalse(store.restoreFoundNothing)
        XCTAssertEqual(store.plan, .premium)
    }

    func testASubscribersTransactionIsUploadedOncePerDistinctTransaction() async {
        let backend = FakeBackend()
        backend.facts = [fact(expires: 1_000_000_000_000)]
        backend.signed = ["jws-one"]
        let uploads = UploadLog()
        let store = PremiumStore(
            backend: backend,
            uploadTransaction: {
                await uploads.add($0)
                return true
            })
        await store.start()
        await store.refresh()
        backend.signed = ["jws-one", "jws-two"]
        await store.refresh()
        let seen = await uploads.items
        XCTAssertEqual(seen, ["jws-one", "jws-two"])
    }

    func testAFreeUserUploadsNothing() async {
        let backend = FakeBackend()
        backend.signed = ["jws"]
        let uploads = UploadLog()
        let store = PremiumStore(
            backend: backend,
            uploadTransaction: {
                await uploads.add($0)
                return true
            })
        await store.start()
        let seen = await uploads.items
        XCTAssertTrue(seen.isEmpty)
    }

    func testARenewalOrRefundAnnouncedByTheStoreIsPickedUp() async throws {
        let backend = FakeBackend()
        let store = PremiumStore(backend: backend)
        await store.start()
        backend.facts = [fact(expires: 1_000_000_000_000)]
        backend.announceChange()
        for _ in 0..<50 where store.plan == .free { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.plan, .premium)
    }
}

private actor UploadLog {
    private(set) var items: [String] = []
    func add(_ item: String) { items.append(item) }
}
