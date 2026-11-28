import Testing
@testable import ZeusCore

struct GrantSetDrawTests {
    private func cards(_ plan: GrantSetDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func accessCalendarAndRemindersFollowGrant() {
        let usual = GrantSetDraw.plan(access: "Off", calendar: "Off", reminders: "Off")
        #expect(cards(usual) == ["Grant", "Access: Off", "Calendar: Off", "Reminders: Off"])
        #expect(GrantSetAsk.line(access: "Off", calendar: "Off", reminders: "Off") == "Accessibility is off, the calendar is off, and reminders are off.")
        #expect(usual.boltCaption(at: 0) == "Grant")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Reminders: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(GrantSetAsk.line(access: "Allowed", calendar: "Allowed", reminders: "Off") == "Accessibility is allowed, the calendar is allowed, and reminders are off.")
        #expect(cards(GrantSetDraw.plan(access: "Allowed", calendar: "Off", reminders: "Allowed")) == ["Grant", "Access: Allowed", "Calendar: Off", "Reminders: Allowed"])
        #expect(cards(GrantSetDraw.plan(access: "Denied", calendar: "Off", reminders: "Off")) == ["Grant", "Can't"])
        #expect(GrantSetAsk.line(access: "Off", calendar: "Maybe", reminders: "Off") == "I can't read those permissions.")
    }

    @Test func voicePermissionsStayOffThisAsk() {
        #expect(GrantSetAsk.matches("which other permissions"))
        #expect(GrantSetAsk.matches("Hey Zeus, is accessibility on?"))
        #expect(GrantSetAsk.matches("other permission settings"))
        #expect(!GrantSetAsk.matches("which voice permissions"))
        #expect(!GrantSetAsk.matches("is screen recording on"))
        #expect(!GrantSetAsk.matches("is the camera allowed"))
        #expect(!GrantSetAsk.matches("how long is dictation kept"))
    }
}
