import Testing
@testable import ZeusCore

struct ScriptSetupDrawTests {
    private func cards(_ plan: ScriptSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func fourAppsFollowScript() {
        let usual = ScriptSetupDraw.plan(music: "Off", spotify: "Off", keynote: "Off", powerpoint: "Off")
        #expect(cards(usual) == ["Script", "Music: Off", "Spotify: Off", "Keynote: Off", "PowerPoint: Off"])
        #expect(ScriptSetupAsk.line(music: "Off", spotify: "Off", keynote: "Off", powerpoint: "Off") == "Music is off, Spotify is off, Keynote is off, and PowerPoint is off.")
        #expect(usual.boltCaption(at: 0) == "Script")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "PowerPoint: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(ScriptSetupAsk.line(music: "Allowed", spotify: "Checking", keynote: "Off", powerpoint: "Off") == "Music is allowed, Spotify is still being checked, Keynote is off, and PowerPoint is off.")
        #expect(cards(ScriptSetupDraw.plan(music: "Allowed", spotify: "Allowed", keynote: "Allowed", powerpoint: "Allowed")) == ["Script", "Music: Allowed", "Spotify: Allowed", "Keynote: Allowed", "PowerPoint: Allowed"])
        #expect(cards(ScriptSetupDraw.plan(music: "Denied", spotify: "Off", keynote: "Off", powerpoint: "Off")) == ["Script", "Can't"])
        #expect(ScriptSetupAsk.line(music: "Off", spotify: "Off", keynote: "Yes", powerpoint: "Off") == "I can't read which apps Zeus can script.")
    }

    @Test func proactiveNoticesStayOffThisAsk() {
        #expect(ScriptSetupAsk.matches("how's automation set"))
        #expect(ScriptSetupAsk.matches("Hey Zeus, can zeus control music?"))
        #expect(ScriptSetupAsk.matches("automation settings"))
        #expect(!ScriptSetupAsk.matches("how's proactive set"))
        #expect(!ScriptSetupAsk.matches("how's the explanation set"))
        #expect(!ScriptSetupAsk.matches("which other permissions"))
        #expect(!ScriptSetupAsk.matches("how's location set"))
    }
}
