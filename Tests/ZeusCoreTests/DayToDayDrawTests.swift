import Testing
@testable import ZeusCore

struct DayToDayDrawTests {
    private func cards(_ plan: DayToDayDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSwitchesThatAreOnFollowDay() {
        let usual = DayToDayDraw.plan(words: ["Login", "Meeting", "Welcome"])
        #expect(cards(usual) == ["Day", "Login", "Meeting", "Welcome"])
        #expect(DayToDayAsk.line(words: ["Login", "Meeting", "Welcome"]) == "Day to day has Login, Meeting, and Welcome on.")
        #expect(usual.boltCaption(at: 0) == "Day")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Welcome")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        let all = DayToDayAsk.order
        #expect(cards(DayToDayDraw.plan(words: all)) == ["Day", "Login", "Awake", "Music", "Meeting"])
        #expect(DayToDayAsk.line(words: all) == "Day to day has 6 on, starting Login, Awake, Music, and Meeting.")
        #expect(cards(DayToDayDraw.plan(words: [])) == ["Day", "None"])
        #expect(DayToDayAsk.line(words: []) == "Day to day is off.")
        #expect(DayToDayAsk.line(words: ["Login"]) == "Day to day has Login on.")
        #expect(cards(DayToDayDraw.plan(words: ["Welcome", "Login"])) == ["Day", "Can't"])
        #expect(DayToDayAsk.line(words: ["Beep"]) == "I can't read day to day.")
    }

    @Test func theDateAndAKeepAwakeSessionStayOffThisAsk() {
        #expect(DayToDayAsk.matches("what's on day to day"))
        #expect(DayToDayAsk.matches("Hey Zeus, how's day to day?"))
        #expect(DayToDayAsk.matches("day to day"))
        #expect(!DayToDayAsk.matches("what is today"))
        #expect(!DayToDayAsk.matches("keep awake"))
        #expect(!DayToDayAsk.matches("which voice cues"))
        #expect(!DayToDayAsk.matches("what's on home"))
    }
}
