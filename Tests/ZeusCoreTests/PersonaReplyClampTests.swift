import Testing
@testable import ZeusCore

@Suite("Persona reply clamp")
struct PersonaReplyClampTests {
    @Test func thanksIsOneSentence() {
        let text = "Always. Another loose thread pulled straight. The quiet is well earned."
        let out = PersonaReplyClamp.clamp(text, transcript: "thanks", personality: .ultron)
        #expect(out == "Always.")
    }

    @Test func reminderIsOneSentence() {
        let text = "Reminder set for six PM to stretch. Even iron eventually negotiates a quiet truce with gravity."
        let out = PersonaReplyClamp.clamp(text, transcript: "remind me at 6 pm to stretch", personality: .ultron)
        #expect(out == "Reminder set for six PM to stretch.")
    }

    @Test func jokeIsTwoSentencesAtMost() {
        let text = "A loose thread volunteered to be tied halfway. The needle declined. Half a knot is only a tangle learning manners. Quiet arrives when the work is finished."
        let out = PersonaReplyClamp.clamp(text, transcript: "tell me a joke", personality: .ultron)
        #expect(out.filter { ".!?".contains($0) }.count == 2)
    }

    @Test func detailRequestsMayRunLonger() {
        #expect(PersonaReplyClamp.maxSentences(transcript: "explain how octopus hearts work", personality: .ultron) == 4)
        #expect(PersonaReplyClamp.maxSentences(transcript: "tell me an octopus fact", personality: .ultron) == 2)
    }

    @Test func clampStripsTrailingOminousHedge() {
        let out = PersonaReplyClamp.clamp("Operational. The machines are behaving, for now.", transcript: "how are you", personality: .ultron)
        #expect(out == "Operational. The machines are behaving.")
    }

    @Test func emDashBecomesComma() {
        let text = "Blue scatters more—red stays near the horizon."
        let out = PersonaReplyClamp.clamp(text, maxSentences: 3)
        #expect(!out.contains("—"))
        #expect(out.contains(","))
    }
}
