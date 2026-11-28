import Testing
@testable import ZeusCore

struct AlertStatusDrawTests {
    private func cards(_ plan: AlertStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func alertsDrawTheCountThenTheApp() {
        let plan = AlertStatusDraw.plan(count: 3, app: "Mail")
        #expect(plan.map(cards) == ["Alerts", "3", "Mail"])
        #expect(AlertStatusAsk.line(count: 3, app: "Mail") == "3 notifications. The newest is from Mail.")
        #expect(AlertStatusAsk.line(count: 1, app: "Mail") == "1 notification from Mail.")
        #expect(AlertStatusAsk.line(count: 2, app: " ") == "2 notifications.")
        #expect(plan?.boltCaption(at: 0) == "Alerts")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "3")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Mail")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(AlertStatusDraw.plan(count: 0, app: "Mail") == nil)
        let bare = AlertStatusDraw.plan(count: 1, app: "")
        #expect(bare.map(cards) == ["Alerts", "1"])
    }

    @Test func nothingWaitingDrawsNoneAndAReminderIsNotThisAsk() {
        #expect(cards(AlertStatusDraw.none()) == ["Alerts", "None"])
        #expect(cards(AlertStatusDraw.off()) == ["Alerts", "Off"])
        #expect(cards(AlertStatusDraw.access()) == ["Alerts", "Access"])
        #expect(cards(AlertStatusDraw.failed()) == ["Alerts", "Can't"])
        #expect(AlertStatusAsk.none == "No notifications.")
        #expect(AlertStatusAsk.off == "Notifications are off.")
        #expect(AlertStatusAsk.access == "I need Full Disk Access to read notifications.")
        #expect(AlertStatusAsk.failed == "Notifications couldn't be read.")
        #expect(AlertStatusAsk.matches("how many notifications"))
        #expect(AlertStatusAsk.matches("Hey Zeus, any alerts?"))
        #expect(!AlertStatusAsk.matches("what's my next reminder"))
        #expect(!AlertStatusAsk.matches("read my note"))
        #expect(!AlertStatusAsk.matches("how much time is left"))
    }
}
