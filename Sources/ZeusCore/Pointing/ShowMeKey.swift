import Foundation

extension Shortcut {
    /// The show-me hold ("draw on screen"): the left Control key on its own. One place for the key.
    public static let showMe = Shortcut(modifiers: .control, side: .left)
}

/// The rules of the show-me hold, pure so they are tested without the app.
/// Control-click is a right click on macOS, so the hold only takes the mouse after `holdDelayMilliseconds`
/// and only while no mouse button is down: a quick Control-click reaches the app underneath.
public enum ShowMeKey {
    /// Virtual key code of the left Control key.
    public static let keyCode: UInt16 = 59
    /// The name used in settings and warnings.
    public static let displayName = "left Control"
    /// Hold this long before the overlay takes the mouse.
    public static let holdDelayMilliseconds = 350

    /// A modifiers-changed event that begins the hold: left Control pressed with no other modifier.
    public static func startsHold(modifiers: ShortcutModifiers, keyCode: UInt16) -> Bool {
        keyCode == Self.keyCode && modifiers == Shortcut.showMe.modifiers
    }

    /// Checked when the delay is up: Control alone is still held and no mouse button is down.
    public static func mayArm(modifiers: ShortcutModifiers, pressedMouseButtons: Int) -> Bool {
        modifiers == Shortcut.showMe.modifiers && pressedMouseButtons == 0
    }

    /// Control let go: a drawing in progress is finished.
    public static func endsHold(modifiers: ShortcutModifiers) -> Bool {
        !modifiers.contains(Shortcut.showMe.modifiers)
    }

    /// Control with another modifier (the talk chord, a shortcut): not a drawing.
    public static func cancelsHold(modifiers: ShortcutModifiers) -> Bool {
        modifiers.contains(Shortcut.showMe.modifiers) && modifiers != Shortcut.showMe.modifiers
    }
}
