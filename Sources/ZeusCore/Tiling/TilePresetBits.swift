import Foundation

/// Carbon modifier bits on a tiling preset, as `ShortcutModifiers`. The app passes the numeric mask in.
public enum TilePresetBits {
    /// `cmdKey`, `shiftKey`, `optionKey`, and `controlKey`.
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    /// Nil when the preset is off. A set bit becomes the matching shortcut modifier.
    public static func shortcut(keyCode: UInt32?, mask: UInt32) -> Shortcut? {
        guard let keyCode else { return nil }
        var modifiers: ShortcutModifiers = []
        if mask & control != 0 { modifiers.insert(.control) }
        if mask & option != 0 { modifiers.insert(.option) }
        if mask & shift != 0 { modifiers.insert(.shift) }
        if mask & command != 0 { modifiers.insert(.command) }
        return Shortcut(keyCode: UInt16(keyCode), modifiers: modifiers)
    }
}
