import AppKit
import ApplicationServices
import ZeusCore

/// Reaches the running dictation controller from places that are not handed one
/// (deep links, the history window, Settings).
@MainActor
final class DictationHub {
    static let shared = DictationHub()
    weak var controller: DictationController?
}

extension TextInserter {
    /// Types the text with synthetic key events, for apps that ignore ⌘V. The clipboard is
    /// never touched. Needs Accessibility; without it the text is copied instead.
    /// `deliveryCheck` is asked before every piece (see `TextInserter.runType`); nil is ungated.
    static func type(_ text: String, pressReturn: Bool = false,
                     deliveryCheck: DeliveryCheck? = nil) async -> Outcome {
        let copy = {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        guard AXIsProcessTrusted() else {
            copy()
            return .copiedOnly
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let steps = SinkSteps(
            sleep: { try? await Task.sleep(for: .milliseconds($0)) },
            typeChunk: { units in
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.flags = []
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    event?.post(tap: .cghidEventTap)
                }
            },
            newline: { post(key: 36, source: source) },
            copyText: copy)
        let result = await runType(pieces: KeystrokeTyping.pieces(text), pressReturn: pressReturn,
                                   steps: steps, check: deliveryCheck)
        return result == .typed ? .pasted : .copiedOnly
    }

    private static func post(key: CGKeyCode, source: CGEventSource?) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }
}
