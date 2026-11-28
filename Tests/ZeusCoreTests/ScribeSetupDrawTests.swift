import Testing
@testable import ZeusCore

struct ScribeSetupDrawTests {
    private func cards(_ plan: ScribeSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func startAndHoldFollowMeet() {
        let usual = ScribeSetupDraw.plan(start: "Ask me", hold: "Clear")
        #expect(cards(usual) == ["Meet", "Start: Ask me", "Hold: Clear"])
        #expect(ScribeSetupAsk.line(start: "Ask me", hold: "Clear") == "When a meeting starts, Zeus asks you, and nothing is holding an automatic start.")
        #expect(usual.boltCaption(at: 0) == "Meet")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Hold: Clear")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ScribeSetupAsk.line(start: "Off", hold: "Clear") == "When a meeting starts, Zeus stays off, and nothing is holding an automatic start.")
        #expect(ScribeSetupAsk.line(start: "Start automatically", hold: "Not yet") == "When a meeting starts, Zeus starts on its own, but the microphone is not allowed yet.")
        #expect(ScribeSetupAsk.line(start: "Start automatically", hold: "Denied") == "When a meeting starts, Zeus starts on its own, but the microphone is off for Zeus.")
        #expect(ScribeSetupAsk.line(start: "Start automatically", hold: "Once") == "When a meeting starts, Zeus starts on its own, but automatic start needs one recording first.")
        #expect(cards(ScribeSetupDraw.plan(start: "Start automatically", hold: "Once")) == ["Meet", "Start: Start automatically", "Hold: Once"])
        #expect(cards(ScribeSetupDraw.plan(start: "Always", hold: "Clear")) == ["Meet", "Can't"])
        #expect(ScribeSetupAsk.line(start: "Ask me", hold: "Stuck") == "I can't read when a meeting starts.")
    }

    @Test func aLiveRecordingStaysOffThisAsk() {
        #expect(ScribeSetupAsk.matches("how's scribe set"))
        #expect(ScribeSetupAsk.matches("Hey Zeus, when a meeting starts?"))
        #expect(ScribeSetupAsk.matches("scribe settings"))
        #expect(!ScribeSetupAsk.matches("is scribe recording"))
        #expect(!ScribeSetupAsk.matches("how's research set"))
        #expect(!ScribeSetupAsk.matches("how's face presence set"))
        #expect(!ScribeSetupAsk.matches("start scribe"))
    }
}
