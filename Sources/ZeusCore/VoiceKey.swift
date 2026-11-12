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
}
