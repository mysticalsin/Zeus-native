import Testing
@testable import ZeusCore

struct ArrivalLightsDrawTests {
    private func cards(_ plan: ArrivalLightsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNotAskedForTheFolders() {
        let usual = ArrivalLightsDraw.plan(air: "Off", downloads: "Not asked", shot: "Off", desktop: "Not asked")
        #expect(cards(usual) == ["Intake", "AirDrop: Off", "Downloads: Not asked", "Shot: Off", "Desktop: Not asked"])
        #expect(ArrivalLightsAsk.line(air: "Off", downloads: "Not asked", shot: "Off", desktop: "Not asked") == "The AirDrop glow is off, Downloads is not asked, the screenshot cue is off, and the Desktop is not asked.")
        #expect(usual.boltCaption(at: 0) == "Intake")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Desktop: Not asked")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(ArrivalLightsAsk.line(air: "On", downloads: "Allowed", shot: "On", desktop: "Not allowed") == "The AirDrop glow is on, Downloads is allowed, the screenshot cue is on, and the Desktop is not allowed.")
        #expect(cards(ArrivalLightsDraw.plan(air: "Off", downloads: "Allowed", shot: "Off", desktop: "Allowed")) == ["Intake", "AirDrop: Off", "Downloads: Allowed", "Shot: Off", "Desktop: Allowed"])
        #expect(cards(ArrivalLightsDraw.plan(air: "Maybe", downloads: "Not asked", shot: "Off", desktop: "Not asked")) == ["Intake", "Can't"])
        #expect(ArrivalLightsAsk.line(air: "On", downloads: "Soon", shot: "Off", desktop: "Not asked") == "I can't read the arrival lights.")
    }

    @Test func theEverydayLightsStayOffThisAsk() {
        #expect(ArrivalLightsAsk.matches("are airdrop lights on"))
        #expect(ArrivalLightsAsk.matches("Hey Zeus, does airdrop glow?"))
        #expect(ArrivalLightsAsk.matches("is the screenshot cue on"))
        #expect(!ArrivalLightsAsk.matches("which everyday lights"))
        #expect(!ArrivalLightsAsk.matches("which music lights"))
        #expect(!ArrivalLightsAsk.matches("is dictation enabled"))
        #expect(!ArrivalLightsAsk.matches("how's the shelf set"))
    }
}
