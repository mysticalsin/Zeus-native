import Testing
@testable import ZeusCore

/// QA7 round 10: a degraded fallback brain (Claude parked, Gemini signed out, Ollama timed out)
/// leaked invented bracket tags, raw terminal control codes and hallucinated conversation turns
/// straight into speech. `ResponseSanitizer` is the floor every reply is read through, regardless
/// of which brain answered.
@Suite("Response sanitizer")
struct ResponseSanitizerTests {
    @Test func stripsAnInventedScreenTag() {
        #expect(ResponseSanitizer.stripArtifacts("Click the Share button [SCREEN 1 of 1] now.") == "Click the Share button  now.")
    }

    @Test func stripsAnInventedScreenTagLowercase() {
        #expect(ResponseSanitizer.stripArtifacts("[screen 1 of 1]\n\nYou") == "\n\nYou")
    }

    @Test func stripsAnInventedSpotlightTag() {
        #expect(ResponseSanitizer.stripArtifacts("Click the Share button [SPOTLIGHT:640,42] to continue.") == "Click the Share button  to continue.")
    }

    @Test func stripsAnInventedTargetTagEvenRepeated() {
        let input = "[TARGET:~/Library/Logs/Todo.txt] [TARGET:~/Library/Logs/Todo.txt] [POINT:200,50:Edit] Focus on one task."
        let result = ResponseSanitizer.stripArtifacts(input)
        #expect(!result.contains("TARGET"))
        #expect(!result.contains("POINT"))
        #expect(result.trimmingCharacters(in: .whitespaces) == "Focus on one task.")
    }

    @Test func stripsARawTerminalControlSequenceWithTheEscapeByteAlreadyLost() {
        #expect(ResponseSanitizer.stripArtifacts("priorit[7D[K priorities") == "priorit priorities")
    }

    @Test func stripsARealEscPrefixedCSISequence() {
        #expect(ResponseSanitizer.stripArtifacts("word\u{1B}[7D\u{1B}[K done") == "word done")
    }

    @Test func leavesARealAccessibilityRefAlone() {
        // [s4:e7]-style refs (letter first, no leading digits) must never be mistaken for CSI debris.
        #expect(ResponseSanitizer.stripArtifacts("click [s4:e7] to continue") == "click [s4:e7] to continue")
    }

    @Test func leavesOrdinaryTextAlone() {
        let text = "The sky appears blue because of Rayleigh scattering."
        #expect(ResponseSanitizer.stripArtifacts(text) == text)
    }

    @Test func findsAHallucinatedUserTurn() {
        let text = "The capital of Portugal is Lisbon.\n\nUser: what does the Lisbon Card do"
        let cut = ResponseSanitizer.hallucinatedTurnStart(in: text)
        #expect(cut != nil)
        #expect(String(text[..<cut!]) == "The capital of Portugal is Lisbon.")
    }

    @Test func findsAHallucinatedAppHistoryTurnCaseInsensitively() {
        let text = "Focus on eliminating distractions.\n\nUser: Who are you?\nAssistant: I am Zeus, a synthetic mind."
        let cut = ResponseSanitizer.hallucinatedTurnStart(in: text)
        #expect(cut != nil)
        #expect(String(text[..<cut!]) == "Focus on eliminating distractions.")
    }

    @Test func noMarkerMeansNoCut() {
        #expect(ResponseSanitizer.hallucinatedTurnStart(in: "Just a normal answer.") == nil)
    }

    @Test func sanitizeCombinesBothPasses() {
        let text = "[SCREEN 1 of 1] The capital of Australia is Canberra.\n\nUser: and New Zealand?"
        #expect(ResponseSanitizer.sanitize(text) == "The capital of Australia is Canberra.")
    }

    @Test func sanitizeTrimsWhitespace() {
        #expect(ResponseSanitizer.sanitize("  hello  ") == "hello")
    }

    // QA7 round 11: the round-10 fix still missed two shapes of the same leaked tags, plus a
    // bare trailing role word with no colon at all.

    @Test func stripsATagWithASpaceAfterTheBracket() {
        let input = "[ POINT: 10,20:label:screen1] [ HIGHLIGHT: 10,10:10,10:label:screen1] The capital of Australia is Canberra."
        #expect(ResponseSanitizer.sanitize(input) == "The capital of Australia is Canberra.")
    }

    @Test func stripsATagWithADigitRunOntoItsName() {
        #expect(ResponseSanitizer.sanitize("[SCREEN1] I am Zeus.") == "I am Zeus.")
    }

    @Test func stripsATrailingBareRoleWordWithNoColon() {
        #expect(ResponseSanitizer.sanitize("The capital of Australia is Canberra. User") == "The capital of Australia is Canberra.")
    }

    @Test func stripsATrailingBareTonyWordCaseInsensitively() {
        #expect(ResponseSanitizer.sanitize("I've started the timer. tony") == "I've started the timer.")
    }

    @Test func leavesAMidSentenceMentionOfTheWordUserAlone() {
        let text = "I opened the user guide for you."
        #expect(ResponseSanitizer.sanitize(text) == text)
    }

    @Test func leavesAMidSentenceMentionOfTonyAlone() {
        let text = "Tony, I finished the task."
        #expect(ResponseSanitizer.sanitize(text) == text)
    }
}
