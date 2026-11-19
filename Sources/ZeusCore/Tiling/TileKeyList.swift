import Foundation

/// One line of the key list: what the keys do, the chord as glyphs, and the same chord in words for VoiceOver.
public struct TileKeyRow: Equatable, Sendable {
    public var title: String
    public var keys: String
    public var spoken: String

    public init(title: String, keys: String, spoken: String) {
        self.title = title
        self.keys = keys
        self.spoken = spoken
    }
}

/// The key list the section and the key sheet show, built from the same `TileKeymap` the key tap matches, so
/// the list cannot drift from the keys. Pure.
public enum TileKeyList {
    private static let definitions: [(title: String, actions: [TileAction])] = [
        // `TileDirection.allCases` is left, right, up, down: the order the keys are bound and read in.
        ("Move focus", TileDirection.allCases.map { TileAction.focus($0) }),
        ("Swap windows", TileDirection.allCases.map { TileAction.swap($0) }),
        ("Flip the split", [.flipSplit]),
        ("Float or tile", [.toggleFloat]),
        ("Pause or resume", [.togglePause]),
        ("Retile", [.retile]),
        ("Resize the split", [.nudge(.left), .nudge(.right)]),
        ("Show these keys", [.showKeys]),
    ]

    /// One row for each group of actions that has at least one key bound, in a fixed order. Actions with no key
    /// (the vertical nudges, the maximize toggle) are not listed.
    public static func rows(keymap: TileKeymap) -> [TileKeyRow] {
        definitions.compactMap { definition in
            let shortcuts = definition.actions.compactMap { keymap.shortcut(for: $0) }
            guard !shortcuts.isEmpty else { return nil }
            return TileKeyRow(title: definition.title, keys: glyphs(shortcuts), spoken: words(shortcuts))
        }
    }

    /// "⌃⌥ ← → ↑ ↓" when every chord shares its modifiers, otherwise each chord on its own.
    private static func glyphs(_ shortcuts: [Shortcut]) -> String {
        let keyed = shortcuts.filter { $0.keyCode != nil }
        guard let first = keyed.first else { return "" }
        if keyed.allSatisfy({ $0.modifiers == first.modifiers }) {
            let keys = keyed.compactMap(\.keyCode).map(Shortcut.keyName).joined(separator: " ")
            let modifiers = Shortcut(modifiers: first.modifiers).symbol
            return modifiers.isEmpty ? keys : modifiers + " " + keys
        }
        return keyed.map(\.symbol).joined(separator: " ")
    }

    /// "Control + Option with Left Arrow, Right Arrow" when the modifiers are shared.
    private static func words(_ shortcuts: [Shortcut]) -> String {
        let keyed = shortcuts.filter { $0.keyCode != nil }
        guard let first = keyed.first else { return "" }
        if keyed.allSatisfy({ $0.modifiers == first.modifiers }) {
            let keys = keyed.compactMap(\.keyCode).map(spokenKey).joined(separator: ", ")
            let modifiers = Shortcut(modifiers: first.modifiers).title
            return modifiers.isEmpty ? keys : modifiers + " with " + keys
        }
        return keyed.map { chord in
            let keyName = spokenKey(chord.keyCode ?? 0)
            let modifiers = Shortcut(modifiers: chord.modifiers).title
            return modifiers.isEmpty ? keyName : modifiers + " with " + keyName
        }.joined(separator: ", ")
    }

    private static func spokenKey(_ code: UInt16) -> String {
        switch code {
        case 123: "Left Arrow"
        case 124: "Right Arrow"
        case 125: "Down Arrow"
        case 126: "Up Arrow"
        case 33: "Left Bracket"
        case 30: "Right Bracket"
        default: Shortcut.keyName(code)
        }
    }
}
