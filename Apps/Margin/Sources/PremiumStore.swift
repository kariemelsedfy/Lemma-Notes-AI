import Foundation
import Intelligence
import StoreKit

/// The two Premium subscriptions (one group, ADR-031 / `PREMIUM_AND_ONBOARDING_PLAN.md`). The ids are created in
/// App Store Connect with these exact strings, and mirrored in `Apps/Margin/StoreKit/Margin.storekit` for local
/// testing.
enum PremiumProduct: String, CaseIterable, Identifiable {
    case yearly = "lemmanotesai.premium.yearly"
    case monthly = "lemmanotesai.premium.monthly"

    var id: String { rawValue }
}

/// One thing the user is entitled to, reduced to what the plan needs. Kept free of StoreKit types so the
/// resolver is a plain function and tests need no store.
struct EntitlementFact: Equatable, Sendable {
    let productID: String
    let expiresAt: Date?
    let isIntroductoryTrial: Bool
    let isRevoked: Bool
}

enum PlanResolver {
    /// `.trial` while any live entitlement is the introductory free trial, `.premium` for any other live one,
    /// otherwise `.free`. A revoked or expired entitlement counts for nothing, and so does a product that is not ours.
    static func plan(from facts: [EntitlementFact], now: Date = .now) -> Plan {
        let live = facts.filter { fact in
            PremiumProduct(rawValue: fact.productID) != nil && !fact.isRevoked
                && (fact.expiresAt.map { $0 > now } ?? true)
        }
        if live.isEmpty { return .free }
        return live.contains { !$0.isIntroductoryTrial } ? .premium : .trial
    }
}

/// A Premium plan as the store offers it.
struct PremiumOffer: Equatable, Identifiable {
    let product: PremiumProduct
    let displayPrice: String
    let hasFreeTrial: Bool

    var id: String { product.rawValue }
}

enum PurchaseOutcome: Equatable {
    case purchased
    /// Waiting on Ask to Buy or a payment method.
    case pending
    case cancelled
}

/// What `PremiumStore` needs from the App Store. The real one is `StoreKitBackend`; tests use a fake, because a
/// purchase cannot be made in a unit test.
protocol StoreBackend: Sendable {
    func offers() async throws -> [PremiumOffer]
    func purchase(_ product: PremiumProduct) async throws -> PurchaseOutcome
    func currentFacts() async -> [EntitlementFact]
    /// The signed transactions behind the current entitlements, which the server verifies for itself (ADR-031).
    func signedTransactions() async -> [String]
    /// Yields whenever the entitlement may have changed (a renewal, a refund, a purchase on another device).
    func changes() -> AsyncStream<Void>
    func restore() async throws
}

/// Premium state for the whole app: the plan, the offers, and the purchase and restore actions.
@MainActor
final class PremiumStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingOffers
        case purchasing
        case restoring
        case failed
    }

    @Published private(set) var plan: Plan = .free
    @Published private(set) var offers: [PremiumOffer] = []
    @Published private(set) var phase = Phase.idle
    /// Set after a restore that found nothing, so the paywall can say so.
    @Published private(set) var restoreFoundNothing = false
    /// The Premium screen is showing. One cover at the root of the app presents it, so any view that wants it
    /// calls `showPaywall()` instead of carrying its own.
    @Published var paywallPresented = false

    /// Whether to invite the user to upgrade (every upgrade prompt in the app reads this).
    var offersUpgrade: Bool { plan == .free }

    func showPaywall() { paywallPresented = true }

    private let backend: any StoreBackend
    private let uploadTransaction: @Sendable (String) async -> Void
    private var uploaded: Set<String> = []
    private var listener: Task<Void, Never>?

    /// - Parameter uploadTransaction: tells the server about a signed transaction so it grants hosted answers. It
    ///   is called once per distinct transaction, and a failure is simply retried on the next refresh.
    init(
        backend: any StoreBackend = StoreKitBackend(),
        uploadTransaction: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.backend = backend
        self.uploadTransaction = uploadTransaction
        listener = Task { [weak self] in
            guard let changes = self?.backend.changes() else { return }
            for await _ in changes { await self?.refresh() }
        }
    }

    deinit { listener?.cancel() }

    func offer(for product: PremiumProduct) -> PremiumOffer? { offers.first { $0.product == product } }

    /// Reads the current entitlements and the offers. Safe to call often; the App Store caches.
    func start() async {
        await refresh()
        guard offers.isEmpty else { return }
        phase = .loadingOffers
        do {
            offers = try await backend.offers()
            phase = .idle
        } catch {
            phase = .failed
        }
    }

    func refresh() async {
        plan = PlanResolver.plan(from: await backend.currentFacts())
        PaidPlanFlag.shared.isPaid = plan != .free
        guard plan != .free else { return }
        for signed in await backend.signedTransactions() where !uploaded.contains(signed) {
            await uploadTransaction(signed)
            uploaded.insert(signed)
        }
    }

    @discardableResult
    func purchase(_ product: PremiumProduct) async -> PurchaseOutcome? {
        phase = .purchasing
        defer { if phase == .purchasing { phase = .idle } }
        do {
            let outcome = try await backend.purchase(product)
            await refresh()
            return outcome
        } catch {
            phase = .failed
            return nil
        }
    }

    func restore() async {
        phase = .restoring
        restoreFoundNothing = false
        do {
            try await backend.restore()
            await refresh()
            restoreFoundNothing = plan == .free
            phase = .idle
        } catch {
            phase = .failed
        }
    }
}

/// The App Store, through StoreKit 2.
struct StoreKitBackend: StoreBackend {
    func offers() async throws -> [PremiumOffer] {
        let products = try await Product.products(for: PremiumProduct.allCases.map(\.rawValue))
        return PremiumProduct.allCases.compactMap { wanted in
            guard let product = products.first(where: { $0.id == wanted.rawValue }) else { return nil }
            return PremiumOffer(
                product: wanted, displayPrice: product.displayPrice,
                hasFreeTrial: product.subscription?.introductoryOffer?.paymentMode == .freeTrial)
        }
    }

    func purchase(_ product: PremiumProduct) async throws -> PurchaseOutcome {
        guard let store = try await Product.products(for: [product.rawValue]).first else { return .cancelled }
        switch try await store.purchase() {
        case .success(let verification):
            // An unverified result is not an entitlement: StoreKit could not prove Apple signed it.
            guard case .verified(let transaction) = verification else { return .cancelled }
            await transaction.finish()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }

    func currentFacts() async -> [EntitlementFact] {
        var facts: [EntitlementFact] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            facts.append(
                EntitlementFact(
                    productID: transaction.productID,
                    expiresAt: transaction.expirationDate,
                    isIntroductoryTrial: transaction.offer?.paymentMode == .freeTrial,
                    isRevoked: transaction.revocationDate != nil))
        }
        return facts
    }

    func signedTransactions() async -> [String] {
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified = result { signed.append(result.jwsRepresentation) }
        }
        return signed
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in Transaction.updates { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func restore() async throws { try await AppStore.sync() }
}
