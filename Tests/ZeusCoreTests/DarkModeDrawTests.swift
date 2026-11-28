import Testing
@testable import ZeusCore

struct DarkModeDrawTests {
    private func cards(_ plan: DarkModeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func darkModeDrawsDark() {
        let plan = DarkModeDraw.plan(dark: true)
        #expect(cards(plan) == ["Mode", "Dark"])
        #expect(DarkModeAsk.line(dark: true) == "Dark Mode is on.")
        #expect(plan.boltCaption(at: 0) == "Mode")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Dark")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func lightModeStaysOffTheBrightnessAsk() {
        let plan = DarkModeDraw.plan(dark: false)
        #expect(cards(plan) == ["Mode", "Light"])
        #expect(DarkModeAsk.line(dark: false) == "Dark Mode is off.")
        #expect(cards(DarkModeDraw.unread()) == ["Mode", "Can't"])
        #expect(DarkModeAsk.unread == "I can't read Dark Mode.")
        #expect(DarkModeAsk.matches("is dark mode on"))
        #expect(DarkModeAsk.matches("Hey Zeus, is the Mac in dark mode?"))
        #expect(DarkModeAsk.matches("light mode"))
        #expect(!DarkModeAsk.matches("how's the brightness"))
        #expect(!DarkModeAsk.matches("are you recording"))
        #expect(!DarkModeAsk.matches("how many words today"))
        #expect(!DarkModeAsk.matches("is caps lock on"))
    }
}
