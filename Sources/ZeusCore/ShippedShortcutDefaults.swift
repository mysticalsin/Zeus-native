import Foundation

/// The chords Zeus ships before anyone records a key. Two entries with the same modifiers and the same key
/// (or both modifier-only) are a collision: one press cannot do both.
public enum ShippedShortcutDefaults {
    public struct Chord: Equatable, Sendable {
        public var name: String
        public var keyCode: UInt16?
        public var modifiers: ShortcutModifiers

        public init(name: String, keyCode: UInt16?, modifiers: ShortcutModifiers) {
            self.name = name
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    /// Control and Option, held, talks. No ordinary key.
    public static let talk = Chord(name: "Talk to Zeus", keyCode: nil, modifiers: [.control, .option])
    /// Right Option, held, is the second talk key.
    public static let secondTalk = Chord(name: "Hold Right Option", keyCode: nil, modifiers: [.option])
    /// Right Command is Murmur. The side is not part of the collision key; no other default is Command alone.
    public static let murmur = Chord(name: "Murmur", keyCode: nil, modifiers: [.command])
    /// Control-Option-T. Key code 17 is T.
    public static let polyglot = Chord(name: "Live captions", keyCode: 17, modifiers: [.control, .option])
    /// Control-Command-Z. Key code 6 is Z. Not Control-Option-T.
    public static let quickTodo = Chord(name: "Quick to-do", keyCode: 6, modifiers: [.control, .command])
    /// Option-Command-Z.
    public static let agentPicker = Chord(name: "Agent picker", keyCode: 6, modifiers: [.option, .command])
    /// Control-Option-C. Key code 8 is C.
    public static let chat = Chord(name: "Chat", keyCode: 8, modifiers: [.control, .option])

    public static var chords: [Chord] { [talk, secondTalk, murmur, polyglot, quickTodo, agentPicker, chat] }

    /// Names of each pair that share a chord. Empty when the shipped defaults are free of each other.
    public static func collisions() -> [String] {
        var seen: [String: String] = [:]
        var hits: [String] = []
        for chord in chords {
            let key = "\(chord.modifiers.rawValue):\(chord.keyCode.map(String.init) ?? "-")"
            if let other = seen[key] {
                hits.append("\(other) and \(chord.name)")
            } else {
                seen[key] = chord.name
            }
        }
        return hits
    }
}
