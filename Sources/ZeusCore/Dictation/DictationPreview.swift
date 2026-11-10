import CoreGraphics
import Foundation

/// Where the correctable dictation preview appears: just under the text caret when ZEUS can
/// see it, else under the pointer; flipped above when there is no room, always on screen.
/// AppKit coordinates (origin bottom-left).
public enum DictationPreviewLayout {
    public static let gap: CGFloat = 10

    public static func frame(size: CGSize, caret: CGRect?, pointer: CGPoint, visible: CGRect) -> CGRect {
        let anchor = caret ?? CGRect(x: pointer.x, y: pointer.y, width: 0, height: 0)
        var x = anchor.minX - 16
        var y = anchor.minY - gap - size.height
        if y < visible.minY { y = anchor.maxY + gap }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// What a key does in the preview card.
public enum DictationPreviewKey: Equatable, Sendable {
    case insert
    case cancel
    /// Let the text field handle it (typing, Shift+Return for a new line).
    case edit

    public static func action(keyCode: UInt16, shift: Bool, command: Bool) -> DictationPreviewKey {
        switch keyCode {
        case 36, 76: return shift && !command ? .edit : .insert  // Return, Enter
        case 53: return .cancel                                   // Escape
        default: return .edit
        }
    }
}

/// Hands focus back to the app you dictated into before the text goes in. The preview card
/// briefly takes focus, so ZEUS reactivates the target and waits until it is really in front;
/// if it never comes back, the text is only copied, never typed into the wrong app.
public enum FrontmostHandoff {
    @MainActor
    public static func waitUntilFrontmost(target: String?, current: () -> String?, attempts: Int = 12,
                                          sleep: () async -> Void) async -> Bool {
        guard let target else { return false }
        for _ in 0..<max(attempts, 1) {
            if current() == target { return true }
            await sleep()
        }
        return current() == target
    }
}

/// The text that goes in after review: trimmed; nothing when it was emptied.
public enum DictationPreviewResult {
    public static func finalText(_ edited: String) -> String? {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
