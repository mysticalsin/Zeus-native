import Foundation

/// The "..." menu row that hides or shows Zeus in screen shares.
///
/// AppKit menu tracking drops the mouse-up on a row the pointer is already over:
/// the first click often lands, and a later click with the pointer left on the
/// row does nothing. The row's action can also arrive for that same mouse-up.
/// One physical click must flip once. The next click, still on the row, must flip again.
public struct ScreenShareClickLedger: Equatable, Sendable {
    /// A mouse-up on the row already flipped this menu. The item action for that
    /// same click must not flip a second time. Cleared when the menu closes so a
    /// later key press still works.
    public private(set) var suppressingDuplicateAction = false
    public private(set) var flips = 0

    public init() {}

    /// The pointer went up on the row. A hover does not call this. Every such
    /// mouse-up flips, including a second click that never leaves the row.
    public mutating func pointerUpOnRow() {
        suppressingDuplicateAction = true
        flips += 1
    }

    /// AppKit or the keyboard performed the item. False when this delivery is the
    /// mouse-up already counted above.
    public mutating func action() -> Bool {
        if suppressingDuplicateAction { return false }
        flips += 1
        return true
    }

    public mutating func menuClosed() {
        suppressingDuplicateAction = false
    }
}

/// What to assign for one window, in order. `true` is hidden (`.none`).
/// The last value is the one that must stick.
///
/// `NSWindow.sharingType`'s getter sticks at hidden after the second change, so a
/// write that skips when the getter already equals the target never hides again.
/// A write made while the pointer is inside a window that accepts the mouse can
/// also be dropped. Assigning the other value first makes the wanted value a real change.
public struct CaptureExclusionUpdate: Equatable, Sendable {
    public var wantHidden: Bool
    /// Nil until this window has been written by us. Not the getter.
    public var rememberedHidden: Bool?
    /// Nil when the getter is neither hidden nor visible.
    public var getterHidden: Bool?
    /// The pointer is inside this window and the window is accepting the mouse.
    public var pointerOnWindow: Bool
    /// Tracking just ended. Write again even if we already remembered this value.
    public var force: Bool

    public init(wantHidden: Bool, rememberedHidden: Bool?, getterHidden: Bool?, pointerOnWindow: Bool, force: Bool) {
        self.wantHidden = wantHidden
        self.rememberedHidden = rememberedHidden
        self.getterHidden = getterHidden
        self.pointerOnWindow = pointerOnWindow
        self.force = force
    }

    public var steps: [Bool]? {
        // Nil memory means this window has never been written: that is a change.
        let changing = rememberedHidden.map { $0 != wantHidden } ?? true
        if !changing && !force { return nil }
        // A retry after the menu closes only needs the window under the pointer.
        // The others were written on the click itself.
        if !changing && force && !pointerOnWindow { return nil }
        let getterAlreadyWant = getterHidden == wantHidden
        // The getter sticks at hidden, and a same-value assign does nothing. The pointer
        // being on the window can drop a single write. The other value first makes
        // the wanted value a change. The first write to a window is one assignment.
        if rememberedHidden != nil && (getterAlreadyWant || pointerOnWindow) {
            return [!wantHidden, wantHidden]
        }
        return [wantHidden]
    }
}

public enum ScreenShareQuickToggleLogic {
    public static let rowMarker = "zeus.screen-share-toggle"

    public static func isToggleRow(_ represented: String?) -> Bool { represented == rowMarker }

    public static func title(shown: Bool) -> String {
        shown ? "Hide Zeus from screen shares" : "Show Zeus in screen shares"
    }

    public static func nextShown(_ shown: Bool) -> Bool { !shown }

    public static func storedValue(shown: Bool) -> String { shown ? "true" : "false" }
}
