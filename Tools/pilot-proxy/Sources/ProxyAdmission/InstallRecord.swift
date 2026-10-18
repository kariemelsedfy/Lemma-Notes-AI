import Foundation

public enum InstallPlan: String, Sendable, Equatable {
    case free
    case trial
    case premium
}

/// Everything the server knows about one attested install (ADR-031): its key and assertion counter, the plan its
/// latest verified App Store transaction grants, and what it has used. One small document, changed with one
/// compare-and-set write.
public struct InstallRecord: Equatable, Sendable {
    public var key: AttestedKey
    public var plan: InstallPlan
    /// When the plan lapses if the transaction is not renewed. Nil for the free plan.
    public var planExpiresAt: Date?
    public var originalTransactionID: String?
    /// Hosted asks a free install has spent from its guided-tour allowance. Never reset.
    public var tourAsksUsed: Int
    /// `yyyy-MM` (UTC) of the month `usageMicros` belongs to.
    public var usageMonth: String
    /// Inference cost spent this month, in millionths of a dollar (reserved at the worst case, settled to actual).
    public var usageMicros: Int64
    public let createdAt: Date

    public init(
        key: AttestedKey, plan: InstallPlan = .free, planExpiresAt: Date? = nil, originalTransactionID: String? = nil,
        tourAsksUsed: Int = 0, usageMonth: String = "", usageMicros: Int64 = 0, createdAt: Date = Date()
    ) {
        self.key = key
        self.plan = plan
        self.planExpiresAt = planExpiresAt
        self.originalTransactionID = originalTransactionID
        self.tourAsksUsed = tourAsksUsed
        self.usageMonth = usageMonth
        self.usageMicros = usageMicros
        self.createdAt = createdAt
    }

    /// The plan in force at `now`: a lapsed paid plan counts as free.
    public func effectivePlan(at now: Date) -> InstallPlan {
        guard plan != .free, let planExpiresAt, planExpiresAt > now else { return .free }
        return plan
    }
}

public enum AllowanceError: Error, Equatable, Sendable {
    /// A free install has spent its guided-tour asks: show Premium (HTTP 402).
    case subscriptionRequired
    /// A paid install has spent this month's cost allowance (HTTP 429).
    case allowanceUsedUp
}

/// The server-enforced limits (`PREMIUM_AND_ONBOARDING_PLAN.md`): three hosted asks for a free install's tour, and
/// a monthly cost allowance for a paid one. Pure functions over an `InstallRecord`, so every rule is testable.
public enum InstallAllowance {
    public static let tourAsks = 3
    /// $1.50 a month of inference per paid install. A starting value, tuned from measured cost.
    public static let monthlyMicros: Int64 = 1_500_000

    static func month(of date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Holds `micros` for one hosted request, or throws without changing the record.
    public static func reserve(_ record: inout InstallRecord, micros: Int64, at now: Date) throws {
        guard micros > 0 else { return }
        switch record.effectivePlan(at: now) {
        case .free:
            guard record.tourAsksUsed < tourAsks else { throw AllowanceError.subscriptionRequired }
            record.tourAsksUsed += 1
        case .trial, .premium:
            let thisMonth = month(of: now)
            let spent = record.usageMonth == thisMonth ? record.usageMicros : 0
            let (total, overflow) = spent.addingReportingOverflow(micros)
            guard !overflow, total <= monthlyMicros else { throw AllowanceError.allowanceUsedUp }
            record.usageMonth = thisMonth
            record.usageMicros = total
        }
    }

    /// Replaces the hold with what the request actually cost. Free installs spend asks, not money.
    public static func settle(_ record: inout InstallRecord, reserved: Int64, observed: Int64, at now: Date) {
        guard record.effectivePlan(at: now) != .free, record.usageMonth == month(of: now) else { return }
        record.usageMicros = max(0, record.usageMicros - reserved + max(0, observed))
    }
}

extension InstallRecord {
    /// Folds a verified App Store transaction into the record. The transaction that grants the longest live plan
    /// wins; a revoked or lapsed one leaves the install on the free plan. Never lowers a plan that a different,
    /// later-expiring transaction already granted.
    public mutating func apply(_ transaction: VerifiedTransaction, at now: Date) {
        guard transaction.revokedAt == nil, let expiresAt = transaction.expiresAt, expiresAt > now else {
            // A revocation of the transaction we are on ends it; anything else has nothing to grant.
            if transaction.revokedAt != nil, originalTransactionID == transaction.originalTransactionID {
                plan = .free
                planExpiresAt = nil
            }
            return
        }
        if let current = planExpiresAt, current > expiresAt, originalTransactionID != transaction.originalTransactionID
        {
            return
        }
        plan = transaction.isIntroductoryTrial ? .trial : .premium
        planExpiresAt = expiresAt
        originalTransactionID = transaction.originalTransactionID
    }
}

extension InstallAllowance {
    /// Gives back a hold for a request that was not served: the ask or the money was never spent.
    public static func refund(_ record: inout InstallRecord, reserved: Int64, at now: Date) {
        switch record.effectivePlan(at: now) {
        case .free: record.tourAsksUsed = max(0, record.tourAsksUsed - 1)
        case .trial, .premium:
            guard record.usageMonth == month(of: now) else { return }
            record.usageMicros = max(0, record.usageMicros - reserved)
        }
    }
}
