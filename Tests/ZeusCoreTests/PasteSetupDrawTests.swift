import Testing
@testable import ZeusCore

struct PasteSetupDrawTests {
    private func cards(_ plan: PasteSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshPastePutsTheClipboardBack() {
        let usual = PasteSetupDraw.plan(restore: "On", apps: "5")
        #expect(cards(usual) == ["Paste", "Clipboard: On", "Apps: 5"])
        #expect(PasteSetupAsk.line(restore: "On", apps: "5") == "Dictation puts the clipboard back, and 5 apps are typed into.")
        #expect(usual.boltCaption(at: 0) == "Paste")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Apps: 5")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PasteSetupAsk.line(restore: "Off", apps: "0") == "Dictation leaves the clipboard, and no apps are typed into.")
        #expect(PasteSetupAsk.line(restore: "On", apps: "1") == "Dictation puts the clipboard back, and 1 app is typed into.")
        #expect(cards(PasteSetupDraw.plan(restore: "Yes", apps: "5")) == ["Paste", "Can't"])
        #expect(PasteSetupAsk.line(restore: "On", apps: "1000") == "I can't read how dictation pastes.")
    }

    @Test func aRecordingAskStaysOffThisAsk() {
        #expect(PasteSetupAsk.matches("how does dictation paste"))
        #expect(PasteSetupAsk.matches("Hey Zeus, does dictation restore the clipboard?"))
        #expect(PasteSetupAsk.matches("how many apps are typed into"))
        #expect(!PasteSetupAsk.matches("how is recording set"))
        #expect(!PasteSetupAsk.matches("how is dictation set"))
        #expect(!PasteSetupAsk.matches("how is recordly export set"))
        #expect(!PasteSetupAsk.matches("which dictation microphone"))
    }
}
