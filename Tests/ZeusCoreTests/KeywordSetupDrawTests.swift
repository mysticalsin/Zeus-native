import Testing
@testable import ZeusCore

struct KeywordSetupDrawTests {
    private func cards(_ plan: KeywordSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallListensOffOnTheDefaults() {
        let usual = KeywordSetupDraw.plan(listen: "Off", approve: "Default", deny: "Default", open: "Default")
        #expect(cards(usual) == ["Keywords", "Listen: Off", "Approve: Default", "Deny: Default", "Open: Default"])
        #expect(KeywordSetupAsk.line(listen: "Off", approve: "Default", deny: "Default", open: "Default") == "Approval listening is off. Approve uses the default words, deny uses the default words, and open uses the default words.")
        #expect(usual.boltCaption(at: 0) == "Keywords")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Open: Default")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(KeywordSetupAsk.wordState(KeywordSetupAsk.approveDefault, default: KeywordSetupAsk.approveDefault) == "Default")
        #expect(KeywordSetupAsk.wordState("sure", default: KeywordSetupAsk.approveDefault) == "Custom")
        #expect(KeywordSetupAsk.line(listen: "On", approve: "Custom", deny: "Default", open: "Custom") == "Approval listening is on. Approve uses your own words, deny uses the default words, and open uses your own words.")
        #expect(cards(KeywordSetupDraw.plan(listen: "Maybe", approve: "Default", deny: "Default", open: "Default")) == ["Keywords", "Can't"])
        #expect(KeywordSetupAsk.line(listen: "Off", approve: "ok, yes", deny: "Default", open: "Default") == "I can't read the approval words.")
    }

    @Test func aLiveApprovalStaysOffThisAsk() {
        #expect(KeywordSetupAsk.matches("how are approval words set"))
        #expect(KeywordSetupAsk.matches("Hey Zeus, are approval keywords on?"))
        #expect(KeywordSetupAsk.matches("does zeus listen for approval words"))
        #expect(!KeywordSetupAsk.matches("how many words today"))
        #expect(!KeywordSetupAsk.matches("how's the voice styled"))
        #expect(!KeywordSetupAsk.matches("how's privacy set"))
        #expect(!KeywordSetupAsk.matches("is hey zeus on"))
    }
}
