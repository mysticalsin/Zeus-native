import Testing
@testable import ZeusCore

struct ExplainHearDrawTests {
    private func cards(_ plan: ExplainHearDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshExplanationUsesTheSystemDefaults() {
        let usual = ExplainHearDraw.plan(voice: "System default", mic: "System default", caption: "Off", whisper: "Off")
        #expect(cards(usual) == ["Narrate", "Voice: System default", "Mic: System default", "Caption: Off", "Whisper: Off"])
        #expect(ExplainHearAsk.line(voice: "System default", mic: "System default", caption: "Off", whisper: "Off") == "Narration uses the system default voice, the explanation microphone is the system default, caption mode is off, and Whisper stays off.")
        #expect(usual.boltCaption(at: 0) == "Narrate")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Whisper: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(ExplainHearAsk.line(voice: "Chosen", mic: "Chosen", caption: "On", whisper: "On") == "Narration uses a voice you chose, the explanation microphone is one you chose, caption mode is on, and Whisper is on.")
        #expect(ExplainHearAsk.line(voice: "Unavailable", mic: "Unavailable", caption: "Off", whisper: "Off") == "The narration voice you chose is unavailable, the explanation microphone you chose is unavailable, caption mode is off, and Whisper stays off.")
        #expect(cards(ExplainHearDraw.plan(voice: "Alex", mic: "System default", caption: "Off", whisper: "Off")) == ["Narrate", "Can't"])
        #expect(ExplainHearAsk.line(voice: "Named", mic: "System default", caption: "Off", whisper: "Off") == "I can't read how explanation hears.")
    }

    @Test func theShortcutStaysOffThisAsk() {
        #expect(ExplainHearAsk.matches("how is narration set"))
        #expect(ExplainHearAsk.matches("Hey Zeus, which narration voice?"))
        #expect(ExplainHearAsk.matches("is whisper used for explanation"))
        #expect(!ExplainHearAsk.matches("how is the explanation set"))
        #expect(!ExplainHearAsk.matches("which explanation shortcut"))
        #expect(!ExplainHearAsk.matches("which dictation microphone"))
        #expect(!ExplainHearAsk.matches("how is the vocabulary set"))
        #expect(!ExplainHearAsk.matches("how is captions set"))
    }
}
