import Foundation

/// Who may use Ask. Solve, Explain and Plot are all part of Premium, so a free user is not offered any of them: the
/// Ask button opens the Premium screen instead of a lasso, and nothing can be started and then refused.
enum AskAccess {
    /// True when Ask should open Premium instead of working.
    ///
    /// - Parameters:
    ///   - offersUpgrade: the user has no Premium (`PremiumStore.offersUpgrade`).
    ///   - inTour: the guided tour's practice note, where a free user is meant to try Ask.
    ///   - hasPilotToken: the owner's own build, which reaches the hosted model with its token.
    static func isLocked(offersUpgrade: Bool, inTour: Bool, hasPilotToken: Bool) -> Bool {
        offersUpgrade && !inTour && !hasPilotToken
    }
}
