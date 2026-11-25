import Foundation

/// A repeated flags event while both sides of a modifier are down.
///
/// The event stream cannot tell that repeat from "the right key went up and the left key
/// is still holding the flag". The hardware key state can. When it says the key is still
/// down, the event must not clear the hold.
public enum ModifierFlagsRepeat {
    /// True when `keyCode` is a modifier that is still physically down, its flag is set,
    /// and the other side is tracked down. A lone key is never this case.
    public static func isHardwareStillDown(
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        deviceKeys: Set<UInt16>,
        hardwareDown: (UInt16) -> Bool
    ) -> Bool {
        guard let entry = entry(for: keyCode), modifiers.contains(entry.flag) else { return false }
        guard deviceKeys.contains(keyCode) else { return false }
        let sibling = entry.left == keyCode ? entry.right : entry.left
        guard sibling != keyCode, deviceKeys.contains(sibling) else { return false }
        return hardwareDown(keyCode)
    }

    /// Flags events for modifier keys the picture still holds and the hardware has released.
    /// The flag stays while the other side is still down.
    public static func missedReleases(
        deviceKeys: Set<UInt16>,
        flagModifiers: ShortcutModifiers,
        hardwareDown: (UInt16) -> Bool
    ) -> [ShortcutEvent] {
        var events: [ShortcutEvent] = []
        var seen: Set<UInt16> = []
        for entry in entries {
            for code in [entry.left, entry.right] where seen.insert(code).inserted {
                guard deviceKeys.contains(code), !hardwareDown(code) else { continue }
                var mods = flagModifiers
                let sibling = code == entry.left ? entry.right : entry.left
                let siblingHeld = sibling != code && deviceKeys.contains(sibling) && hardwareDown(sibling)
                if !siblingHeld { mods.remove(entry.flag) }
                events.append(.flags(keyCode: code, modifiers: mods))
            }
        }
        return events
    }

    private struct Entry {
        var flag: ShortcutModifiers
        var left: UInt16
        var right: UInt16
    }

    private static let entries: [Entry] = [
        Entry(flag: .control, left: 59, right: 62),
        Entry(flag: .option, left: 58, right: 61),
        Entry(flag: .shift, left: 56, right: 60),
        Entry(flag: .command, left: 55, right: 54),
        Entry(flag: .function, left: 63, right: 63),
    ]

    private static func entry(for keyCode: UInt16) -> Entry? {
        entries.first { $0.left == keyCode || $0.right == keyCode }
    }
}
