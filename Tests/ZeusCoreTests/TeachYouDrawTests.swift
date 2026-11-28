import Testing
@testable import ZeusCore

struct TeachYouDrawTests {
    private func cards(_ plan: TeachYouDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theNameAndTheNotesFolder() {
        let usual = TeachYouDraw.plan(name: "None", notes: "None")
        #expect(cards(usual) == ["You", "Name: None", "Notes: None"])
        #expect(TeachYouAsk.line(name: "None", notes: "None") == "No name is saved, and no notes folder is saved.")
        #expect(usual.boltCaption(at: 0) == "You")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Notes: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(TeachYouAsk.line(name: "Set", notes: "None") == "A name is saved, and no notes folder is saved.")
        #expect(TeachYouAsk.line(name: "Set", notes: "Set") == "A name is saved, and a notes folder is saved.")
        #expect(cards(TeachYouDraw.plan(name: "Yes", notes: "None")) == ["You", "Can't"])
        #expect(TeachYouAsk.line(name: "None", notes: "Path") == "I can't read what Zeus knows about you.")
    }

    @Test func theSecondBrainStaysOffThisAsk() {
        #expect(TeachYouAsk.matches("has zeus been taught about you"))
        #expect(TeachYouAsk.matches("Hey Zeus, is your name saved?"))
        #expect(TeachYouAsk.matches("is a notes folder saved"))
        #expect(!TeachYouAsk.matches("how is the second brain set"))
        #expect(!TeachYouAsk.matches("is a vault connected"))
        #expect(!TeachYouAsk.matches("how dim is the prompter"))
        #expect(!TeachYouAsk.matches("how many macs are nearby"))
    }
}
