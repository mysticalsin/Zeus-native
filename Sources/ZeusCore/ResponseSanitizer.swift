import Foundation

/// Defends the text-to-speech pipeline against a degraded brain's own mistakes. `ZeusTagParser`
/// only recognises `[POINT:...]`, `[HIGHLIGHT:...]` and `[ACTION:...]`, and only when they lead or
/// trail a reply (see its own doc comment); everything else a model writes reaches `.text` as
/// plain words to be spoken. QA7 round 10 (the fallback chain exhausted: Claude parked, Gemini
/// signed out, Ollama timed out, down to a weak local/CLI model) showed three concrete ways that
/// goes wrong, none of them something `ZeusTagParser` is meant to catch:
///   - invented or misplaced bracket tags ("[SCREEN 1 of 1]", "[SPOTLIGHT:640,42]",
///     "[TARGET:~/Library/Logs/Todo.txt]", or a real `[POINT:...]`/`[ACTION:...]` landing mid
///     sentence instead of leading) -- never actionable there, so never worth reading aloud;
///   - a raw terminal control sequence leaking through ("priorit[7D[K priorities": cursor-left-7,
///     erase-to-end-of-line, with the ESC byte already lost upstream);
///   - the model hallucinating the next turn of the conversation, because `ZeusPrompt.userText`
///     feeds history back as literal "Tony: ..." / "ZEUS: ..." lines and a weak model completes
///     that pattern instead of just answering ("The capital of Portugal is Lisbon.\n\nUser: what
///     does the Lisbon Card do").
/// None of this is a substitute for a working brain; it is the floor every reply is read through
/// regardless of which one answered.
public enum ResponseSanitizer: Sendable {
    /// Role labels a hallucinating model sometimes continues onto a fresh line, in either the
    /// app's own history format (Tony/ZEUS) or a generic chat-completion one (User/Assistant).
    private static let turnMarkerPattern = #"(?:^|\n)\s*(?:user|tony|assistant|zeus)\s*:"#

    /// QA7 round 11 found a second, looser shape of the same hallucination: a bare role word with
    /// no colon and no leading newline at all, trailing straight off the real answer on the same
    /// line ("The capital of Australia is Canberra. User"). Anchored to the very end of the string
    /// only, so a reply that legitimately mentions "the user" or "Tony" mid-sentence is untouched.
    private static let trailingBareRoleMarkerPattern = #"\s+(?:user|tony|assistant|zeus)\s*:?\s*$"#

    /// The index where a hallucinated continuation starts (the newline, or start of string, right
    /// before the role label), so the caller can keep everything before it and stop listening for
    /// more. `text` is searched in full every time so a marker split across two streamed chunks is
    /// still found once both have been appended to the accumulator the caller passes in.
    public static func hallucinatedTurnStart(in text: String) -> String.Index? {
        text.range(of: turnMarkerPattern, options: [.regularExpression, .caseInsensitive])?.lowerBound
    }

    /// Strips bracket tags and terminal-control debris a model should never have put mid-reply.
    /// Order matters: known tag names (real or invented) are removed whole before the looser
    /// leftover-control-code pass runs, so that pass never has to guess where a tag name ends.
    public static func stripArtifacts(_ text: String) -> String {
        var result = text

        // A real ESC-prefixed CSI sequence (ESC '[' params... final-byte), e.g. cursor movement
        // or erase codes a terminal-backed fallback model echoed verbatim. `\u{1B}` is written
        // as an actual escape character here, not inside the raw string literal below: `#"..."#`
        // never processes backslash escapes, so `\u{1B}` there would match the eight literal
        // characters "\u{1B}", not the ESC byte.
        let esc = "\u{1B}"
        result = result.replacingOccurrences(
            of: esc + #"\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)

        // ZEUS's three real tags only get parsed into an action when they lead or trail a reply;
        // mid-sentence they (or a model's own invented look-alikes: SCREEN, SPOTLIGHT, TARGET,
        // HOTSPOT) are never acted on, so there is nothing to do but stop them being spoken.
        // QA7 round 11 found two shapes this missed: "[ POINT: ...]" with a space after the
        // bracket (so the name wasn't the very next character), and "[SCREEN1]" with a digit
        // run straight onto the name (so `\b` never fired between two word characters). `\s*`
        // covers the first; dropping the `\b` requirement (the alternation itself is specific
        // enough that no real word collides with it) covers the second.
        result = result.replacingOccurrences(
            of: #"\[\s*(?:screen|spotlight|target|hotspot|point|highlight|action)[^\]]*\]"#,
            with: "", options: [.regularExpression, .caseInsensitive])

        // The same family of control codes with the ESC byte already lost somewhere upstream:
        // "[", optional digits, one letter, not immediately followed by a word character or ":"
        // -- so a real accessibility ref like "[s4:e7]" (letter first, no leading digits) or a
        // genuine bracketed abbreviation is never touched, only bare digit+letter CSI debris.
        result = result.replacingOccurrences(
            of: #"\[\d*[A-Za-z](?![\w:])"#, with: "", options: .regularExpression)

        return result
    }

    /// The full defensive pass for a complete (non-streaming) reply: strip artifacts, then cut
    /// off at the first hallucinated turn, if any.
    public static func sanitize(_ text: String) -> String {
        var stripped = stripArtifacts(text)
        if let cut = hallucinatedTurnStart(in: stripped) {
            stripped = String(stripped[..<cut])
        }
        stripped = stripped.replacingOccurrences(
            of: trailingBareRoleMarkerPattern, with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
