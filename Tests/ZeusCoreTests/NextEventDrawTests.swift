import Foundation
import Testing
@testable import ZeusCore

struct NextEventDrawTests {
    private func cards(_ plan: NextEventDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theNextEventDrawsTheTitleThenTheTime() {
        let plan = NextEventDraw.plan(title: "Standup", when: "3:00 PM")
        #expect(plan.map(cards) == ["Next", "Standup", "3:00 PM"])
        #expect(NextEventAsk.line(title: "Standup", when: "3:00 PM", allDay: false) == "Next is Standup at 3:00 PM.")
        #expect(NextEventAsk.line(title: "Offsite", when: "All day", allDay: true) == "Next is Offsite, all day.")
        #expect(plan?.boltCaption(at: 0) == "Next")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Standup")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "3:00 PM")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(NextEventDraw.plan(title: " ", when: "3:00 PM") == nil)
        let zone = TimeZone(secondsFromGMT: 0)!
        #expect(NextEventAsk.whenLine(Date(timeIntervalSince1970: 1_700_000_000), allDay: true, timeZone: zone) == "All day")
        #expect(NextEventAsk.whenLine(Date(timeIntervalSince1970: 1_700_000_000), allDay: false, timeZone: zone).contains(":"))
    }

    @Test func nothingElseDrawsNoneAndJoiningIsNotThisAsk() {
        #expect(cards(NextEventDraw.none()) == ["Next", "None"])
        #expect(NextEventAsk.none == "Nothing else today.")
        #expect(NextEventAsk.matches("what's next"))
        #expect(NextEventAsk.matches("Hey Zeus, what's my next event?"))
        #expect(!NextEventAsk.matches("join my next meeting"))
        #expect(!NextEventAsk.matches("what do I have today"))
        #expect(!NextEventAsk.matches("new reminder: pay rent"))
    }
}
