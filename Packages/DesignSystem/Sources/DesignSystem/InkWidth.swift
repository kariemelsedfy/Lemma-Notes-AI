import CoreGraphics

/// How thick the pen draws, in points of nib width. Four steps are enough to cover fine note-taking through
/// emphasis; the default is the pen's long-standing width of 5.
public enum InkWidth: Int, CaseIterable, Codable, Sendable, Identifiable {
    case fine
    case medium
    case bold
    case heavy

    public var id: Int { rawValue }

    public static let `default` = InkWidth.medium

    public var points: CGFloat {
        switch self {
        case .fine: 3
        case .medium: 5
        case .bold: 8
        case .heavy: 12
        }
    }
}
