import Testing
@testable import ZeusCore

struct ChromeLinkDrawTests {
    private func cards(_ plan: ChromeLinkDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theBridgeAndTheExtension() {
        let usual = ChromeLinkDraw.plan(bridge: "Off", loaded: "Not loaded")
        #expect(cards(usual) == ["Chrome", "Bridge: Off", "Extension: Not loaded"])
        #expect(ChromeLinkAsk.line(bridge: "Off", loaded: "Not loaded") == "The Chrome bridge is off, and the extension is not loaded.")
        #expect(usual.boltCaption(at: 0) == "Chrome")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Extension: Not loaded")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ChromeLinkAsk.line(bridge: "Registered", loaded: "Connected") == "The Chrome bridge is registered, and the extension is connected.")
        #expect(ChromeLinkAsk.line(bridge: "Registered", loaded: "Not loaded") == "The Chrome bridge is registered, and the extension is not loaded.")
        #expect(cards(ChromeLinkDraw.plan(bridge: "On", loaded: "Connected")) == ["Chrome", "Can't"])
        #expect(ChromeLinkAsk.line(bridge: "Off", loaded: "Missing") == "I can't read the Chrome connection.")
    }

    @Test func chromeMediaStaysOffThisAsk() {
        #expect(ChromeLinkAsk.matches("is chrome connected"))
        #expect(ChromeLinkAsk.matches("Hey Zeus, how is the Chrome bridge set?"))
        #expect(ChromeLinkAsk.matches("is the chrome extension loaded"))
        #expect(!ChromeLinkAsk.matches("is chrome media on"))
        #expect(!ChromeLinkAsk.matches("which agents are connected"))
        #expect(!ChromeLinkAsk.matches("which clips are showing"))
        #expect(!ChromeLinkAsk.matches("which reminders are showing"))
    }
}
