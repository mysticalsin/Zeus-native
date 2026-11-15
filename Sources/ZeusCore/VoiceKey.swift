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

    /// Whether a hold of the pointing key starts a pointing turn. Not when it is the talk key: the talk turn
    /// owns that hold, so one hold never opens the microphone twice or plays two listening sounds.
    public static func pointingStartsTurns(talk: Shortcut, pointing: Shortcut, pointingEnabled: Bool) -> Bool {
        pointingEnabled && pointing != talk
    }

    /// Who answers one hold of `chord`. nil: nobody in Zeus (VoiceOver has it, or it is no voice key).
    public static func owner(ofHold chord: Shortcut, talk: Shortcut, dictation: Shortcut?, pointing: Shortcut,
                             pointingEnabled: Bool, voiceOverOn: Bool, screenRecording: Bool) -> Owner? {
        let listened = effectiveTalkKey(chosen: talk, dictation: dictation,
                                        pointing: pointingEnabled ? pointing : nil, voiceOverOn: voiceOverOn)
        if chord == listened, !(voiceOverOn && chord == .controlOption) { return .talk(screenAware: screenRecording) }
        guard chord == pointing, pointingStartsTurns(talk: talk, pointing: pointing, pointingEnabled: pointingEnabled),
              !(voiceOverOn && pointing == .controlOption) else { return nil }
        return .pointing
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
