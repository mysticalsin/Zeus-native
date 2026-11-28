import Testing
@testable import ZeusCore

struct UsageMeterDrawTests {
    private func cards(_ plan: UsageMeterDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMeterAndTheAlerts() {
        let usual = UsageMeterDraw.plan(meter: "Busiest", alerts: "On")
        #expect(cards(usual) == ["Usage", "Meter: Busiest", "Alerts: On"])
        #expect(UsageMeterAsk.line(meter: "Busiest", alerts: "On") == "The usage meter uses your busiest window, and limit alerts are on.")
        #expect(usual.boltCaption(at: 0) == "Usage")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Alerts: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(UsageMeterAsk.line(meter: "Custom", alerts: "Off") == "The usage meter uses a limit you set, and limit alerts are off.")
        #expect(UsageMeterAsk.line(meter: "Custom", alerts: "On") == "The usage meter uses a limit you set, and limit alerts are on.")
        #expect(cards(UsageMeterDraw.plan(meter: "Tokens", alerts: "On")) == ["Usage", "Can't"])
        #expect(UsageMeterAsk.line(meter: "Busiest", alerts: "Maybe") == "I can't read the usage meter.")
    }

    @Test func todaysTokensStayOffThisAsk() {
        #expect(UsageMeterAsk.matches("how is the usage meter set"))
        #expect(UsageMeterAsk.matches("Hey Zeus, are usage alerts on?"))
        #expect(UsageMeterAsk.matches("does the usage meter use a limit"))
        #expect(!UsageMeterAsk.matches("what is my usage"))
        #expect(!UsageMeterAsk.matches("how many tokens today"))
        #expect(!UsageMeterAsk.matches("are the lyrics showing"))
        #expect(!UsageMeterAsk.matches("is the chat window open"))
    }
}
