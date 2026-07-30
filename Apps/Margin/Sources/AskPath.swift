/// Tracks the explicit Ask entry point independently of Pencil hardware.
///
/// M2-02 only arms the lasso; a later selection task supplies the selected content.
struct AskPathState: Equatable {
    private(set) var isArmed = false
    private(set) var invocationCount = 0

    mutating func invoke() {
        isArmed = true
        invocationCount += 1
    }

    mutating func selectionDidComplete() {
        isArmed = false
    }
}
