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
