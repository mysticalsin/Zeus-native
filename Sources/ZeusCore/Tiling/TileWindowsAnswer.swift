import Foundation

/// What an app said when asked for its window list. Pure.
public enum TileWindowsAnswer: Equatable, Sendable {
    case answered
    case noWindows
    case unread

    /// The Accessibility error codes that matter, as the system numbers them (`AXError.rawValue`). ZeusCore does not
    /// import the framework; a test in the app target checks these against it.
    public static let cannotCompleteCode: Int32 = -25204
    public static let attributeUnsupportedCode: Int32 = -25205
    public static let noValueCode: Int32 = -25212

    public static func classify(axError code: Int32) -> TileWindowsAnswer {
        .unread
    }
}
