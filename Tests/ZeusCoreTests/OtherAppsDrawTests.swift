import Testing
@testable import ZeusCore

struct OtherAppsDrawTests {
    private func cards(_ plan: OtherAppsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func appsPeekAndDetailsFollowTheTitle() {
        let usual = OtherAppsDraw.plan(apps: "Off", peek: "On", details: "On")
        #expect(cards(usual) == ["Apps", "Apps: Off", "Peek: On", "Details: On"])
        #expect(OtherAppsAsk.line(apps: "Off", peek: "On", details: "On") == "Other apps are off, the peek is on, and details are on.")
        #expect(usual.boltCaption(at: 0) == "Apps")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Details: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(OtherAppsAsk.line(apps: "On", peek: "Off", details: "Off") == "Other apps are on, the peek is off, and details are off.")
        #expect(cards(OtherAppsDraw.plan(apps: "Maybe", peek: "On", details: "On")) == ["Apps", "Can't"])
        #expect(OtherAppsAsk.line(apps: "On", peek: "Loud", details: "On") == "I can't read other-app notices.")
    }

    @Test func theWaitingCountStaysOffThisAsk() {
        #expect(OtherAppsAsk.matches("how's other apps set"))
        #expect(OtherAppsAsk.matches("Hey Zeus, does the peek show details?"))
        #expect(OtherAppsAsk.matches("other app notification settings"))
        #expect(!OtherAppsAsk.matches("notifications"))
        #expect(!OtherAppsAsk.matches("how many alerts"))
        #expect(!OtherAppsAsk.matches("how's agent notices set"))
        #expect(!OtherAppsAsk.matches("which events play a sound"))
    }
}
