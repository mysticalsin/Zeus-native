import Foundation

/// Open and quit reuse `FastIntent.parse`. This file does not add a recognizer.
public enum ExplainFastIntentBridge {
    public static func openOrQuit(_ text: String) -> ExplainCommand? {
        switch FastIntent.parse(text) {
        case .openApp(let name, _)?:
            return .openApp(name)
        case .quitApp(let name)?:
            return .quitApp(name)
        default:
            return nil
        }
    }
}
