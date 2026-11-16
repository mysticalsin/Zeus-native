import Foundation

/// Control+Option is the Zeus voice key: one hold is one voice turn (docs/VOICE-KEY.md).
/// Pure routing, so "exactly one turn per hold" is proved by tests rather than by two monitors agreeing.
///
/// The talk turn (`VoiceTurnController`) owns every hold of the talk key: Ultron voice, fast path,
/// screenshots when Screen Recording is granted, and `[POINT]`/`[HIGHLIGHT]` marks on screen. The desktop
/// pointing turn starts its own turns only on a pointing key that is different from the talk key.
public enum VoiceKey {
    /// Who answers one hold.
    public enum Owner: Equatable, Sendable {
        /// The Zeus talk turn. `screenAware` is false without Screen Recording: a plain talk turn.
        case talk(screenAware: Bool)
        /// The desktop pointing turn, on its own separate key.
        case pointing
    }

    /// Talk keys tried, in order, while VoiceOver holds Control+Option.
    public static let voiceOverFallbacks: [Shortcut] = [.optionCommand, .rightOption, .function]

    /// The key the talk monitor listens for right now. VoiceOver uses Control+Option as its own modifier, so
    /// while it runs a Control+Option talk key moves to the first fallback no other Zeus key uses.
    public static func effectiveTalkKey(chosen: Shortcut, dictation: Shortcut?, pointing: Shortcut?,
                                        voiceOverOn: Bool) -> Shortcut {
        guard voiceOverOn, chosen == .controlOption else { return chosen }
        return voiceOverFallbacks.first { $0 != dictation && $0 != pointing } ?? chosen
    }

    /// Whether a hold of the pointing key starts a pointing turn. Not when it is the talk key or the second talk key: the talk turn
    /// owns that hold, so one hold never opens the microphone twice or plays two listening sounds.
    public static func pointingStartsTurns(talk: Shortcut, pointing: Shortcut, pointingEnabled: Bool,
                                           secondTalk: Shortcut? = nil) -> Bool {
        pointingEnabled && pointing != talk && pointing != secondTalk
    }

    /// Who answers one hold of `chord`. nil: nobody in Zeus (VoiceOver has it, or it is no voice key).
    public static func owner(ofHold chord: Shortcut, talk: Shortcut, dictation: Shortcut?, pointing: Shortcut,
                             pointingEnabled: Bool, voiceOverOn: Bool, screenRecording: Bool, secondTalk: Shortcut? = nil) -> Owner? {
        let listened = effectiveTalkKey(chosen: talk, dictation: dictation,
                                        pointing: pointingEnabled ? pointing : nil, voiceOverOn: voiceOverOn)
        if chord == listened, !(voiceOverOn && chord == .controlOption) { return .talk(screenAware: screenRecording) }
        if let secondTalk, chord == secondTalk { return .talk(screenAware: screenRecording) }
        guard chord == pointing, pointingStartsTurns(talk: talk, pointing: pointing, pointingEnabled: pointingEnabled,
                                                     secondTalk: secondTalk),
              !(voiceOverOn && pointing == .controlOption) else { return nil }
        return .pointing
    }

    /// How long the second talk key must be down alone before it acts. Right Option types accents, so a letter inside this time
    /// reads as typing and starts nothing (docs/RIGHT-OPTION-TALK-PLAN.md). 0.25 s is a first value, not measured.
    public static let secondKeyConfirm: TimeInterval = 0.25

    /// The second key's confirm: the typing confirm, or the tiling confirm when that is longer.
    public static func secondTalkConfirm(tiling: TimeInterval) -> TimeInterval { max(secondKeyConfirm, tiling) }

    /// The second talk key the talk monitor listens on right now, or nil with the name of the key it gives way to. `chosen` is
    /// the stored key (`ShortcutStore.loadSecondTalk`), `explicit` whether the owner chose it, `heard` the talk key as the
    /// monitor hears it (`effectiveTalkKey`), the others nil when off. A key one of them already uses is theirs: the default
    /// gives way to a key chosen for pointing, an explicit second key keeps it and pointing stands down (`pointingStartsTurns`).
    /// A Carbon shortcut on Option alone (Chat on Option-Space) beats an Option-only key, as Carbon beats the chord: it may
    /// hide the key-down of its Space from the monitors.
    public static func secondTalkKey(chosen: Shortcut?, explicit: Bool, heard: Shortcut, dictation: Shortcut?, pointing: Shortcut?,
                                     polyglot: Shortcut?, voiceOverOn: Bool,
                                     carbonHolders: [(name: String, shortcut: Shortcut?)]) -> (key: Shortcut?, yieldsTo: String?) {
        guard let chosen else { return (nil, nil) }
        func meets(_ other: Shortcut?) -> Bool { other.map { $0 == chosen || ShortcutConflicts.overlaps(chosen, $0) } ?? false }
        if meets(heard) { return (nil, "Talk to Zeus") }
        if meets(dictation) { return (nil, "Dictation") }
        if meets(polyglot) { return (nil, "Polyglot") }
        if !explicit, meets(pointing) { return (nil, "Pointing") }
        if voiceOverOn, chosen == .controlOption { return (nil, "VoiceOver") }
        if chosen.isModifierOnly, chosen.modifiers == .option,
           let holder = carbonHolders.first(where: { $0.shortcut.map { $0.keyCode != nil && $0.modifiers == .option } ?? false }) {
            return (nil, holder.name)
        }
        return (chosen, nil)
    }

    /// Whether the sentence for a second key that gave way is quiet (a plain "Off") rather than a warning. Only the default key
    /// that merely repeats the talk key is: the owner never recorded it, so there is nothing for them to fix. A key they recorded
    /// that clashes, or any other holder (Dictation, Polyglot, Pointing, Chat, VoiceOver), keeps the warning.
    public static func secondTalkNoteIsQuiet(yieldsTo: String?, explicit: Bool) -> Bool {
        yieldsTo == "Talk to Zeus" && !explicit
    }

    /// Why `key` cannot be recorded as the second talk key: it is already the talk, dictation or Polyglot key. Nil when it can.
    public static func secondTalkRefusal(_ key: Shortcut, talk: Shortcut, dictation: Shortcut?, polyglot: Shortcut?) -> String? {
        let named: [(String, Shortcut?)] = [("Talk to Zeus", talk), ("Dictation", dictation), ("Polyglot", polyglot)]
        guard let hit = named.first(where: { name, other in other.map { $0 == key || ShortcutConflicts.overlaps(key, $0) } ?? false }) else {
            return nil
        }
        return "This is already your \(hit.0) key."
    }

    /// Control-Option-Space: Space joins the held talk key without spoiling it (docs/ULTRON-CHORD-PLAN.md).
    public static let talkChord = Shortcut(keyCode: 49, modifiers: [.control, .option])

    public struct ChatClash: Equatable, Sendable {
        public let sentence: String
        public let fix: ChatHotkey
    }

    /// The chord on this keyboard right now. Only the bare Control-Option talk key as heard has one, in hold mode (not shared
    /// with dictation) and with VoiceOver off, since Control-Option-Space is VoiceOver's own activate key. A Carbon shortcut
    /// that holds Control-Option-Space keeps it: the chord yields and `heldBy` names the holder.
    public static func talkChord(heard: Shortcut, shared: Bool, voiceOverOn: Bool,
                                 holders: [(name: String, shortcut: Shortcut?)]) -> (chord: Shortcut?, heldBy: String?) {
        guard heard == .controlOption, !shared, !voiceOverOn else { return (nil, nil) }
        if let holder = holders.first(where: { $0.shortcut == talkChord }) { return (nil, holder.name) }
        return (talkChord, nil)
    }

    /// Chat against the talk chord. Nil when they do not meet. Chat wins either clash, so the fix moves Chat.
    public static func chatClash(talk: Shortcut, heard: Shortcut, chat: ChatHotkey, shared: Bool, voiceOverOn: Bool,
                                 holders: [(name: String, shortcut: Shortcut?)]) -> ChatClash? {
        guard let chatKey = chat.shortcut else { return nil }
        if chatKey == heard {
            // The recorded talk key is the Chat key. Moving Chat to C would meet a talk key that is already on C.
            return ChatClash(sentence: "This is also your Talk to Zeus key. Chat takes it.",
                             fix: heard == ChatHotkey.controlOptionC.shortcut ? .off : .controlOptionC)
        }
        guard chatKey == talkChord, heard == .controlOption, !shared, !voiceOverOn else { return nil }
        return ChatClash(sentence: "Control-Option-Space also talks to Zeus. While Chat uses it, it opens Chat instead.",
                         fix: .controlOptionC)
    }
}
