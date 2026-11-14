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

    /// `success` is a list. "No value" and "unsupported" are definitive: an app that closed its last window answers
    /// them, and it has no windows. A timeout, or any other failure, is no answer, and the caller keeps what it
    /// knew about that app.
    public static func classify(axError code: Int32) -> TileWindowsAnswer {
        switch code {
        case 0: .answered
        case noValueCode, attributeUnsupportedCode: .noWindows
        default: .unread
        }
    }

    /// Whether one window's attribute read completed. Only `success` did. A busy app times out on one window while it
    /// answered the list, and every fact of that window is then missing: the window is slow, not closed, so the caller
    /// counts the whole app as unread for the pass and keeps what it knew. Any other failure is treated the same.
    public static func windowRead(axError code: Int32) -> Bool {
        code == 0
    }
}
