import Foundation

/// The modifiers held for every tiling key. The stored form is the case name.
public enum TileModifierBase: String, Codable, Sendable, CaseIterable {
    case controlOption
    case optionCommand
    case controlOptionCommand

    /// Reads a stored string, or the wording a settings row shows ("Control-Option"). Case, spaces and
    /// punctuation do not matter. Anything unknown is `controlOption`.
    public init(label: String) {
        switch label.lowercased().filter(\.isLetter) {
        case "optioncommand": self = .optionCommand
        case "controloptioncommand": self = .controlOptionCommand
        default: self = .controlOption
        }
    }

    public var modifiers: ShortcutModifiers {
        switch self {
        case .controlOption: [.control, .option]
        case .optionCommand: [.option, .command]
        case .controlOptionCommand: [.control, .option, .command]
        }
    }
}

public enum TileKeymapError: Error, Equatable, Sendable {
    /// A bare letter, a modifier-only chord, or anything `Shortcut` reports invalid.
    case invalidChord
    /// The chord is already bound.
    case duplicateChord
}

/// Maps a key chord to a `TileAction`. A value: the key tap holds an immutable copy, so a later edit never
/// changes what a running tap matches.
public struct TileKeymap: Equatable, Sendable {
    public struct Binding: Equatable, Sendable {
        public let shortcut: Shortcut
        public let action: TileAction

        public init(shortcut: Shortcut, action: TileAction) {
            self.shortcut = shortcut
            self.action = action
        }
    }

    /// In the order they were bound.
    public private(set) var bindings: [Binding] = []
    private var lookup: [Shortcut: TileAction] = [:]

    public init() {}

    /// Binds `shortcut` to `action`. A chord that is invalid, or only modifiers, or already bound is
    /// rejected and nothing changes. An action may have more than one chord.
    public mutating func bind(_ shortcut: Shortcut, to action: TileAction) throws {
        let chord = Self.normalized(shortcut)
        guard chord.isValid, !chord.isModifierOnly else { throw TileKeymapError.invalidChord }
        guard lookup[chord] == nil else { throw TileKeymapError.duplicateChord }
        lookup[chord] = action
        bindings.append(Binding(shortcut: chord, action: action))
    }

    public func action(for shortcut: Shortcut) -> TileAction? {
        lookup[Self.normalized(shortcut)]
    }

    /// The first chord bound to `action`, for a key list.
    public func shortcut(for action: TileAction) -> Shortcut? {
        bindings.first { $0.action == action }?.shortcut
    }

    /// The bound chords that appear in `reserved`, in table order.
    public func conflicts<S: Sequence>(with reserved: S) -> [Shortcut] where S.Element == Shortcut {
        let taken = Set(reserved.map(Self.normalized))
        return bindings.map(\.shortcut).filter { taken.contains($0) }
    }

    // MARK: Defaults

    /// Actions the default table leaves unbound: the vertical nudges (only the two bracket keys nudge) and
    /// the maximize toggle, which waits for the Spaces slice.
    public static let unboundByDefault: [TileAction] = [.nudge(.up), .nudge(.down), .maximizeToggle]

    /// The one place the default table is built, for the base `base`. With B the base:
    /// B + arrow focuses, B + Shift + arrow swaps, B + J flips, B + T floats, B + P pauses, B + R retiles,
    /// B + Shift + [ and ] nudge the split, and B + K shows the keys. Number keys stay free.
    public static func defaults(base: TileModifierBase) -> TileKeymap {
        let plain = base.modifiers
        let shifted = plain.union(.shift)
        let arrows: [(TileDirection, UInt16)] = [(.left, 123), (.right, 124), (.up, 126), (.down, 125)]
        var rows: [(Shortcut, TileAction)] = []
        for (direction, code) in arrows { rows.append((Shortcut(keyCode: code, modifiers: plain), .focus(direction))) }
        for (direction, code) in arrows { rows.append((Shortcut(keyCode: code, modifiers: shifted), .swap(direction))) }
        rows += [
            (Shortcut(keyCode: 38, modifiers: plain), .flipSplit),
            (Shortcut(keyCode: 17, modifiers: plain), .toggleFloat),
            (Shortcut(keyCode: 35, modifiers: plain), .togglePause),
            (Shortcut(keyCode: 15, modifiers: plain), .retile),
            (Shortcut(keyCode: 33, modifiers: shifted), .nudge(.left)),
            (Shortcut(keyCode: 30, modifiers: shifted), .nudge(.right)),
            (Shortcut(keyCode: 40, modifiers: plain), .showKeys),
        ]
        var map = TileKeymap()
        for (shortcut, action) in rows { try? map.bind(shortcut, to: action) }
        return map
    }

    // MARK: Storage

    private struct StoredEntry: Codable {
        var shortcut: Shortcut
        var action: String
    }

    private struct Stored: Encodable {
        var version: Int
        var bindings: [StoredEntry]
    }

    /// One entry that may not read: a bad entry becomes nil instead of failing the whole file.
    private struct LossyEntry: Decodable {
        let entry: StoredEntry?
        init(from decoder: any Decoder) throws { entry = try? StoredEntry(from: decoder) }
    }

    private struct StoredRead: Decodable {
        var bindings: [LossyEntry]
    }

    /// A stable JSON form: the same keymap always gives the same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let entries = bindings.map { StoredEntry(shortcut: $0.shortcut, action: $0.action.id) }
        return try encoder.encode(Stored(version: 1, bindings: entries))
    }

    /// The keymap in `data`, or nil when it is not a keymap file. Entries with an action this build does not
    /// know, an invalid or repeated chord, or a shape it cannot read are skipped, so a newer file does not
    /// break an older build.
    public static func decode(_ data: Data) -> TileKeymap? {
        guard let stored = try? JSONDecoder().decode(StoredRead.self, from: data) else { return nil }
        var map = TileKeymap()
        for item in stored.bindings {
            guard let entry = item.entry, let action = TileAction(id: entry.action) else { continue }
            try? map.bind(entry.shortcut, to: action)
        }
        return map
    }

    /// A key chord always matches on any side of its modifiers, whatever a stored file says.
    private static func normalized(_ shortcut: Shortcut) -> Shortcut {
        Shortcut(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    }
}
