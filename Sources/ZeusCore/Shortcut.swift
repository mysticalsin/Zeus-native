import Foundation

/// The modifier keys a shortcut can use. Raw values are stored, so never renumber them.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = ShortcutModifiers(rawValue: 1)
    public static let option = ShortcutModifiers(rawValue: 2)
    public static let shift = ShortcutModifiers(rawValue: 4)
    public static let command = ShortcutModifiers(rawValue: 8)
    public static let function = ShortcutModifiers(rawValue: 16)

    /// Virtual key codes of the physical modifier keys: (left, right).
    static let keyCodes: [(ShortcutModifiers, left: UInt16, right: UInt16)] = [
        (.control, 59, 62), (.option, 58, 61), (.shift, 56, 60), (.command, 55, 54), (.function, 63, 63),
    ]

    /// The modifier a key code belongs to, if it is a modifier key.
    static func modifier(forKeyCode code: UInt16) -> ShortcutModifiers? {
        keyCodes.first { $0.left == code || $0.right == code }?.0
    }

    var count: Int { rawValue.nonzeroBitCount }
}

/// One user-chosen shortcut: a modifier-only chord (Control+Option, Right Command, Fn) or a key
/// with modifiers (⌥Space, ⌃⌥Z). Pure data; `ShortcutState` decides whether it is held.
public struct Shortcut: Codable, Hashable, Sendable {
    public enum Side: String, Codable, Sendable { case any, left, right }

    /// nil for a modifier-only chord.
    public var keyCode: UInt16?
    public var modifiers: ShortcutModifiers
    /// Only for a single modifier: which physical key (Right Command vs either Command).
    public var side: Side

    public init(keyCode: UInt16? = nil, modifiers: ShortcutModifiers, side: Side = .any) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.side = modifiers.count == 1 && keyCode == nil ? side : .any
    }

    public static let optionCommand = Shortcut(modifiers: [.option, .command])
    public static let rightCommand = Shortcut(modifiers: .command, side: .right)
    public static let rightOption = Shortcut(modifiers: .option, side: .right)
    public static let controlOption = Shortcut(modifiers: [.control, .option])
    public static let function = Shortcut(modifiers: .function)

    public var isModifierOnly: Bool { keyCode == nil }

    /// A bare letter would hijack typing; function keys and anything with a modifier are fine.
    public var isValid: Bool {
        if let keyCode { return !modifiers.isEmpty || Self.standaloneKeys.contains(keyCode) }
        return !modifiers.isEmpty
    }

    static let standaloneKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    // MARK: Words

    /// "Option + Command", "Right Command", "Fn (Globe)", "⌥ Space".
    public var title: String {
        if let keyCode { return symbols(spaced: true) + (modifiers.isEmpty ? "" : " ") + Self.keyName(keyCode) }
        if modifiers == .function { return "Fn (Globe)" }
        var parts: [String] = []
        for (flag, name) in Self.names where modifiers.contains(flag) { parts.append(name) }
        let joined = parts.joined(separator: " + ")
        switch side {
        case .right: return "Right " + joined
        case .left: return "Left " + joined
        case .any: return joined
        }
    }

    /// Short form for prompts: "⌥⌘", "right ⌘", "⌥Space".
    public var symbol: String {
        if let keyCode { return symbols(spaced: false) + Self.keyName(keyCode) }
        if modifiers == .function { return "fn" }
        return (side == .right ? "right " : side == .left ? "left " : "") + symbols(spaced: false)
    }

    /// Same as `symbol` (the old name prompts use).
    public var symbols: String { symbol }

    private func symbols(spaced: Bool) -> String {
        var out = ""
        for (flag, glyph) in Self.glyphs where modifiers.contains(flag) { out += glyph }
        return out
    }

    private static let names: [(ShortcutModifiers, String)] = [
        (.function, "Fn"), (.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command"),
    ]
    private static let glyphs: [(ShortcutModifiers, String)] = [
        (.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E",
        15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-",
        28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'",
        40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 53: "Esc", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20", 123: "←", 124: "→", 125: "↓", 126: "↑", 117: "Fwd Delete", 115: "Home",
        119: "End", 116: "Page Up", 121: "Page Down",
    ]

    public static func keyName(_ code: UInt16) -> String { keyNames[code] ?? "Key \(code)" }

    // MARK: Storage

    /// Compact JSON, or "off" for nil.
    public static func stored(_ shortcut: Shortcut?) -> String {
        guard let shortcut, let data = try? JSONEncoder.sorted.encode(shortcut) else { return "off" }
        return String(decoding: data, as: UTF8.self)
    }

    /// nil is "not a shortcut"; use `isOff` to tell "off" apart from garbage.
    public static func parse(_ text: String) -> Shortcut? {
        guard let value = try? JSONDecoder().decode(Shortcut.self, from: Data(text.utf8)), value.isValid else { return nil }
        return value
    }

    /// The old fixed choices, by their saved names.
    public static func legacy(_ name: String) -> Shortcut? {
        switch name {
        case "controlOption": .controlOption
        case "rightOption": .rightOption
        case "rightCommand": .rightCommand
        case "function": .function
        default: nil
        }
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Loads and migrates the two bindings. "Talk to Zeus" defaults to Control+Option (docs/VOICE-KEY.md);
/// dictation keeps its old default (Right Command). Saved choices of the old fixed list carry over.
public enum ShortcutStore {
    public static let talkKey = "talk.shortcut"
    public static let dictationKey = "dictation.shortcut"
    public static let legacyTalk = "pushToTalk"
    public static let legacyDictation = "dictation.key"
    /// True once the owner picked a talk key in Settings or onboarding. Auto-written defaults never set it.
    public static let talkChosenKey = "talk.shortcut.chosen"
    /// The one-time move of auto-written talk keys to Control+Option has run.
    public static let talkMigrationKey = "talk.shortcut.migratedToControlOption"
    public static let talkDefault = Shortcut.controlOption
    /// Defaults earlier builds wrote for everybody who had not chosen: not choices, so they migrate once.
    static let autoTalkDefaults: Set<Shortcut> = [.optionCommand, .rightCommand]

    /// Earlier builds wrote Option+Command (and before that Right Command) into `talk.shortcut` on first load,
    /// so a stored value alone is not a choice. Those move to Control+Option once; after that, and for any
    /// key the owner recorded, the stored value is kept as it is.
    public static func loadTalk(_ defaults: UserDefaults) -> Shortcut {
        let migrated = defaults.bool(forKey: talkMigrationKey)
        defaults.set(true, forKey: talkMigrationKey)
        if let text = defaults.string(forKey: talkKey), let saved = Shortcut.parse(text) {
            guard !migrated, !defaults.bool(forKey: talkChosenKey), autoTalkDefaults.contains(saved) else { return saved }
            defaults.set(Shortcut.stored(talkDefault), forKey: talkKey)
            return talkDefault
        }
        var result = talkDefault
        if let name = defaults.string(forKey: legacyTalk), let old = Shortcut.legacy(name),
           !autoTalkDefaults.contains(old), old != talkDefault {
            result = old
            defaults.set(true, forKey: talkChosenKey) // Picked from the old fixed list.
        }
        defaults.set(Shortcut.stored(result), forKey: talkKey)
        return result
    }

    /// The owner picked `shortcut` (Settings recorder, Reset, onboarding). Later migrations leave it alone.
    public static func recordTalkChoice(_ shortcut: Shortcut, in defaults: UserDefaults) {
        defaults.set(Shortcut.stored(shortcut), forKey: talkKey)
        defaults.set(true, forKey: talkChosenKey)
        defaults.set(true, forKey: talkMigrationKey)
    }

    /// nil means dictation has no key.
    public static func loadDictation(_ defaults: UserDefaults) -> Shortcut? {
        if let text = defaults.string(forKey: dictationKey) {
            if text == "off" { return nil }
            if let saved = Shortcut.parse(text) { return saved }
        }
        var result: Shortcut? = .rightCommand
        if let name = defaults.string(forKey: legacyDictation) {
            if name == "off" { result = nil } else if let old = Shortcut.legacy(name) { result = old }
        }
        defaults.set(Shortcut.stored(result), forKey: dictationKey)
        return result
    }
}

/// Warnings only: nothing here blocks a choice.
public enum ShortcutConflicts {
    /// Well-known macOS shortcuts a global shortcut would fight with.
    static let system: [(Shortcut, String)] = [
        (Shortcut(keyCode: 49, modifiers: .command), "Spotlight (⌘Space)"),
        (Shortcut(keyCode: 49, modifiers: [.option, .command]), "Finder search (⌥⌘Space)"),
        (Shortcut(keyCode: 49, modifiers: .control), "Input source switch (⌃Space)"),
        (Shortcut(keyCode: 49, modifiers: [.control, .command]), "Emoji picker (⌃⌘Space)"),
        (Shortcut(keyCode: 48, modifiers: .command), "App switcher (⌘Tab)"),
        (Shortcut(keyCode: 12, modifiers: .command), "Quit (⌘Q)"),
        (Shortcut(keyCode: 13, modifiers: .command), "Close window (⌘W)"),
        (Shortcut(keyCode: 4, modifiers: .command), "Hide app (⌘H)"),
        (Shortcut(keyCode: 8, modifiers: .command), "Copy (⌘C)"),
        (Shortcut(keyCode: 9, modifiers: .command), "Paste (⌘V)"),
        (Shortcut(keyCode: 7, modifiers: .command), "Cut (⌘X)"),
        (Shortcut(keyCode: 6, modifiers: .command), "Undo (⌘Z)"),
        (Shortcut(keyCode: 0, modifiers: .command), "Select all (⌘A)"),
        (Shortcut(keyCode: 20, modifiers: [.shift, .command]), "Screenshot (⇧⌘3)"),
        (Shortcut(keyCode: 21, modifiers: [.shift, .command]), "Screenshot (⇧⌘4)"),
        (Shortcut(keyCode: 23, modifiers: [.shift, .command]), "Screenshot options (⇧⌘5)"),
        (Shortcut(keyCode: 53, modifiers: [.option, .command]), "Force Quit (⌥⌘Esc)"),
        (Shortcut(keyCode: 12, modifiers: [.control, .command]), "Lock screen (⌃⌘Q)"),
        (Shortcut(modifiers: .function), "the Globe key (emoji and Apple Dictation)"),
    ]

    /// Why `shortcut` may misbehave, as short sentences. Empty when it looks safe.
    /// Control+Option is VoiceOver's modifier, so it warns only while VoiceOver is on; `voiceOverFallback` is
    /// the key that stands in meanwhile (the talk key has one, see `VoiceKey.effectiveTalkKey`).
    public static func warnings(for shortcut: Shortcut, other: Shortcut?, otherName: String,
                                voiceOverOn: Bool = false, voiceOverFallback: Shortcut? = nil) -> [String] {
        var out: [String] = []
        if let hit = system.first(where: { $0.0 == shortcut }) {
            out.append("This is also \(hit.1). One of them will win; the system usually does.")
        }
        if voiceOverOn, shortcut == .controlOption {
            if let voiceOverFallback, voiceOverFallback != shortcut {
                out.append("VoiceOver is on and uses Control and Option. Hold \(voiceOverFallback.title) to talk until VoiceOver is off.")
            } else {
                out.append("VoiceOver is on and uses Control and Option, so this key pauses until VoiceOver is off.")
            }
        }
        if let other {
            if other == shortcut {
                out.append("Same key as \(otherName). Hold to dictate, double-tap to talk.")
            } else if overlaps(shortcut, other) {
                out.append("Overlaps \(otherName). Use a different key.")
            }
        }
        return out
    }

    /// True when both shortcuts could be held at once (exact match semantics from `ShortcutState`).
    static func overlaps(_ a: Shortcut, _ b: Shortcut) -> Bool {
        guard a.isModifierOnly, b.isModifierOnly else { return false }
        if a == b { return false }
        if a.modifiers == b.modifiers { return sidesOverlap(a.side, b.side) }
        // A strict modifier superset (Option+Command vs Command-only) never activates both at once:
        // the smaller chord needs fewer keys down than the larger one.
        return false
    }

    /// Shipped talk (Control+Option) and dictation (Right Command) must never warn.
    public static func warningsForShippedDefaults(talk: Shortcut, dictation: Shortcut?) -> [String] {
        guard let dictation else { return [] }
        return warnings(for: dictation, other: talk, otherName: "Talk to Zeus")
    }

    private static func sidesOverlap(_ a: Shortcut.Side, _ b: Shortcut.Side) -> Bool {
        switch (a, b) {
        case (.any, _), (_, .any): return true
        case (.left, .right), (.right, .left): return false
        default: return true
        }
    }
}

/// What a keyboard did, as the monitors see it. Fake streams of these drive the tests.
public enum ShortcutEvent: Equatable, Sendable {
    /// A modifier key changed; `modifiers` is the full set now held.
    case flags(keyCode: UInt16, modifiers: ShortcutModifiers)
    case keyDown(keyCode: UInt16, modifiers: ShortcutModifiers)
    case keyUp(keyCode: UInt16)
}

/// Tracks which keys are down from the event stream (no polling) and says whether a shortcut is held.
public struct ShortcutState: Sendable {
    public private(set) var modifiers: ShortcutModifiers = []
    public private(set) var deviceKeys: Set<UInt16> = []
    public private(set) var keysDown: Set<UInt16> = []
    /// A normal key joined while modifiers were down; the chord is not "alone" until all are released.
    public private(set) var spoiled = false

    public init() {}

    public mutating func apply(_ event: ShortcutEvent) {
        switch event {
        case .flags(let code, let mods): flagsChanged(keyCode: code, modifiers: mods)
        case .keyDown(let code, let mods): keyDown(keyCode: code, modifiers: mods)
        case .keyUp(let code): keysDown.remove(code)
        }
    }

    private mutating func flagsChanged(keyCode: UInt16, modifiers mods: ShortcutModifiers) {
        modifiers = mods
        // A repeated flagsChanged for `keyCode` with its flag still present is ambiguous: macOS
        // (and CGEventPost) can redeliver the *same* "still down" notification for a lone key
        // with nothing else pressed (confirmed with `tools/e2e-once.sh`'s two-call-in-a-row
        // dictation check: QA7 P0 item J -- the first turn in a pair worked, the second's
        // key-down went unnoticed, alternating, with no release event between them in the log).
        // But it is also the *only* signal this device-independent `mods` gives for "the left
        // and right key of one modifier are both down, then one specifically lets go": that
        // release still reports the flag present (the other side keeps it) with the same
        // keyCode repeating, which `rightCommandIsNotLeftCommand` depends on. Disambiguate by
        // whether a sibling is also tracked down: only then does a repeat mean "this one let
        // go"; alone, a repeat is just a resend and must not clear the hold.
        if let flag = ShortcutModifiers.modifier(forKeyCode: keyCode), mods.contains(flag) {
            let sibling = ShortcutModifiers.keyCodes.first { $0.0 == flag }.map { $0.left == keyCode ? $0.right : $0.left }
            if deviceKeys.contains(keyCode), let sibling, deviceKeys.contains(sibling) {
                deviceKeys.remove(keyCode)
            } else {
                deviceKeys.insert(keyCode)
            }
        }
        // Keys of a modifier that is no longer down are up, whatever events were missed.
        for (flag, left, right) in ShortcutModifiers.keyCodes where !mods.contains(flag) {
            deviceKeys.remove(left); deviceKeys.remove(right)
        }
        if mods.isEmpty { spoiled = false }
    }

    private mutating func keyDown(keyCode: UInt16, modifiers mods: ShortcutModifiers) {
        keysDown.insert(keyCode)
        modifiers = mods
        // Regression (QA7 P0 item J, real E2E): "spoiled" is meant for a normal key joining a
        // chord *we* are tracking as held (`aKeyPressedDuringTheChordSpoilsIt`) -- it must not
        // fire just because this keyDown's own `mods` happens to carry a flag. Any Command+key
        // shortcut anywhere on the Mac (even one Zeus itself sends, like the auto-insert paste
        // right after a dictation turn) is seen by this same global monitor and used to read
        // `mods` as "Command is held", with no flagsChanged ever following to clear it -- that
        // stuck a bare modifier-only shortcut (Right Command dictation) off until some unrelated
        // future modifier release happened to pass through (confirmed with
        // `tools/e2e-once.sh`'s two-call-in-a-row dictation check: the first turn's own
        // auto-insert paste "spoiled" every dictation key-down after it). `deviceKeys` is only
        // ever populated by real flagsChanged holds, so its emptiness is the right signal for
        // "nothing we're tracking is actually down right now".
        if !mods.isEmpty, !deviceKeys.isEmpty { spoiled = true }
    }

    public mutating func reset() { self = ShortcutState() }

    /// `exact`: nothing else may be down (the normal case). Otherwise extra modifiers are allowed,
    /// which the shared hold-to-dictate / double-tap-to-talk key needs.
    public func isHeld(_ shortcut: Shortcut, exact: Bool = true) -> Bool {
        guard shortcut.isValid else { return false }
        var held = modifiers
        // Arrow and F keys carry the fn flag on their own; it only counts when asked for.
        if shortcut.keyCode != nil, !shortcut.modifiers.contains(.function) { held.remove(.function) }
        let wanted = shortcut.modifiers
        let modsMatch = exact ? held == wanted : held.isSuperset(of: wanted)
        guard modsMatch else { return false }
        if let code = shortcut.keyCode { return keysDown.contains(code) }
        if exact, spoiled || !keysDown.isEmpty { return false }
        guard shortcut.side != .any, let entry = ShortcutModifiers.keyCodes.first(where: { $0.0 == wanted }) else { return true }
        return deviceKeys.contains(shortcut.side == .right ? entry.right : entry.left)
    }
}

/// The recorder's brain: feed it the keyboard while a Record field is armed and it says what was pressed.
public struct ShortcutRecorderState: Sendable {
    public enum Output: Equatable, Sendable {
        case captured(Shortcut)
        case cancelled
    }

    private var state = ShortcutState()
    private var peak: ShortcutModifiers = []
    private var peakKeys: Set<UInt16> = []

    public init() {}

    /// Modifiers held right now, for a live "⌥⌘…" preview.
    public var preview: ShortcutModifiers { state.modifiers }

    public mutating func feed(_ event: ShortcutEvent) -> Output? {
        state.apply(event)
        switch event {
        case .keyDown(let code, let mods):
            if code == 53, mods.isEmpty { return .cancelled }
            let shortcut = Shortcut(keyCode: code, modifiers: mods.subtracting(.function))
            return shortcut.isValid ? .captured(shortcut) : nil
        case .flags:
            let mods = state.modifiers
            if mods.count > peak.count { peak = mods; peakKeys = state.deviceKeys }
            else if mods == peak { peakKeys.formUnion(state.deviceKeys) }
            if mods.isEmpty, !peak.isEmpty {
                defer { peak = []; peakKeys = [] }
                var side = Shortcut.Side.any
                if peak.count == 1, let entry = ShortcutModifiers.keyCodes.first(where: { $0.0 == peak }), entry.left != entry.right {
                    if peakKeys.contains(entry.right) { side = .right } else if peakKeys.contains(entry.left) { side = .left }
                }
                return .captured(Shortcut(modifiers: peak, side: side))
            }
            return nil
        case .keyUp:
            return nil
        }
    }
}
