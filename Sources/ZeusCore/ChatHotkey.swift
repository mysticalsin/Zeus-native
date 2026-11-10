import Foundation

/// The keyboard shortcut that opens the chat window from anywhere. A short list of safe
/// combinations: none of them is a dictation or push-to-talk key, and none is taken by macOS.
public enum ChatHotkey: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case controlOptionSpace
    case optionSpace
    case optionShiftSpace
    case commandShiftSpace
    case controlOptionC

    public static let standard = ChatHotkey.controlOptionSpace

    public var id: String { rawValue }

    /// Carbon virtual key code (kVK_Space = 49, kVK_ANSI_C = 8).
    public var keyCode: UInt32? {
        switch self {
        case .off: nil
        case .controlOptionC: 8
        default: 49
        }
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        // Carbon modifier bits (cmdKey, shiftKey, optionKey, controlKey).
        public static let command = Modifiers(rawValue: 1 << 8)
        public static let shift = Modifiers(rawValue: 1 << 9)
        public static let option = Modifiers(rawValue: 1 << 11)
        public static let control = Modifiers(rawValue: 1 << 12)
    }

    public var modifiers: Modifiers {
        switch self {
        case .off: []
        case .controlOptionSpace, .controlOptionC: [.control, .option]
        case .optionSpace: [.option]
        case .optionShiftSpace: [.option, .shift]
        case .commandShiftSpace: [.command, .shift]
        }
    }

    /// "⌃⌥Space", in the order macOS menus use (⌃ ⌥ ⇧ ⌘).
    public var symbols: String {
        guard let keyCode else { return "Off" }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (keyCode == 49 ? "Space" : "C")
    }

    /// Spoken form for VoiceOver.
    public var spoken: String {
        guard keyCode != nil else { return "Off" }
        var words: [String] = []
        if modifiers.contains(.control) { words.append("Control") }
        if modifiers.contains(.option) { words.append("Option") }
        if modifiers.contains(.shift) { words.append("Shift") }
        if modifiers.contains(.command) { words.append("Command") }
        return (words + [keyCode == 49 ? "Space" : "C"]).joined(separator: " ")
    }

    public static func stored(_ raw: String?) -> ChatHotkey {
        raw.flatMap(ChatHotkey.init(rawValue:)) ?? standard
    }
}
