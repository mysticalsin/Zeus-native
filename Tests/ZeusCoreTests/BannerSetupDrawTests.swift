import Testing
@testable import ZeusCore

struct BannerSetupDrawTests {
    private func cards(_ plan: BannerSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallShowsNoBanners() {
        let usual = BannerSetupDraw.plan(system: "Off", dismiss: "Off", apps: "None")
        #expect(cards(usual) == ["Banners", "System: Off", "Dismiss: Off", "Apps: None"])
        #expect(BannerSetupAsk.line(system: "Off", dismiss: "Off", apps: "None") == "System notifications are off, banner dismiss is off, and no apps are chosen.")
        #expect(usual.boltCaption(at: 0) == "Banners")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Apps: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(BannerSetupAsk.line(system: "On", dismiss: "On", apps: "Chosen") == "System notifications are on, banner dismiss is on, and apps are chosen.")
        #expect(cards(BannerSetupDraw.plan(system: "Off", dismiss: "Off", apps: "Chosen")) == ["Banners", "System: Off", "Dismiss: Off", "Apps: Chosen"])
        #expect(cards(BannerSetupDraw.plan(system: "Maybe", dismiss: "Off", apps: "None")) == ["Banners", "Can't"])
        #expect(BannerSetupAsk.line(system: "On", dismiss: "Off", apps: "Mail") == "I can't read the system banners.")
    }

    @Test func waitingNotificationsStayOffThisAsk() {
        #expect(BannerSetupAsk.matches("how are system notifications set"))
        #expect(BannerSetupAsk.matches("Hey Zeus, does zeus dismiss banners?"))
        #expect(BannerSetupAsk.matches("system notification settings"))
        #expect(!BannerSetupAsk.matches("how many notifications"))
        #expect(!BannerSetupAsk.matches("how is agent notices set"))
        #expect(!BannerSetupAsk.matches("how is other apps set"))
        #expect(!BannerSetupAsk.matches("how are approval words set"))
    }
}
