import Foundation
import Testing
@testable import ZeusCore

struct MeetingDrawTests {
    private func cards(_ plan: MeetingDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func joiningDrawsTheTitleThenThePlace() {
        let plan = MeetingDraw.plan(title: "Standup", place: "Zoom")
        #expect(plan.map(cards) == ["Meeting", "Standup", "Zoom"])
        #expect(MeetingAsk.line(title: "Standup", place: "Zoom") == "Joining Standup on Zoom.")
        #expect(MeetingAsk.line(title: "Standup", place: " ") == "Joining Standup.")
        #expect(plan?.boltCaption(at: 0) == "Meeting")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Standup")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Zoom")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(MeetingDraw.plan(title: "  ", place: "Zoom") == nil)
        #expect(MeetingAsk.place(of: URL(string: "https://zoom.us/j/1")!) == "Zoom")
        #expect(MeetingAsk.place(of: URL(string: "https://meet.google.com/abc")!) == "Meet")
        #expect(MeetingAsk.place(of: URL(string: "https://teams.microsoft.com/l/meetup")!) == "Teams")
    }

    @Test func noMeetingDrawsNoneAndAReminderAskIsNotThis() {
        #expect(cards(MeetingDraw.none()) == ["Meeting", "None"])
        #expect(MeetingDraw.none().boltCaption(at: ExplainBeatSchedule.gap) == "None")
        #expect(MeetingAsk.none == "There's no meeting to join.")
        #expect(MeetingAsk.matches("Hey Zeus, join my next meeting"))
        #expect(MeetingAsk.matches("join the meeting"))
        #expect(!MeetingAsk.matches("new reminder: pay rent"))
        #expect(!MeetingAsk.matches("what's my battery"))
        #expect(!MeetingAsk.matches("open zoom"))
    }
}
