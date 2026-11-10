import Foundation
import Testing
@testable import ZeusCore

@Suite("Proactive")
struct ProactiveTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func briefSummarizesTheDay() {
        let now = at("2026-11-02T08:10:00Z")
        let events = [
            BriefEvent(title: "Standup", start: at("2026-11-02T09:30:00Z"), end: at("2026-11-02T09:45:00Z"), hasCall: true),
            BriefEvent(title: "Lunch", start: at("2026-11-02T12:00:00Z"), end: at("2026-11-02T13:00:00Z")),
            BriefEvent(title: "Holiday", start: at("2026-11-02T00:00:00Z"), end: at("2026-11-03T00:00:00Z"), isAllDay: true),
            BriefEvent(title: "Tomorrow", start: at("2026-11-03T09:00:00Z"), end: at("2026-11-03T10:00:00Z")),
            BriefEvent(title: "Already over", start: at("2026-11-02T06:00:00Z"), end: at("2026-11-02T07:00:00Z")),
        ]
        let todos = [
            BriefTodo(id: "1", title: "Send invoice", due: at("2026-11-02T17:00:00Z")),
            BriefTodo(id: "2", title: "Old", due: at("2026-10-30T10:00:00Z")),
            BriefTodo(id: "3", title: "Done", due: at("2026-11-02T10:00:00Z"), done: true),
            BriefTodo(id: "4", title: "Someday", due: nil),
        ]
        let brief = MorningBrief.build(now: now, events: events, todos: todos, name: "Tony Walteur", calendar: utc)
        #expect(brief.greeting == "Good morning, Tony")
        #expect(brief.summary == "2 events, 1 with a call · first at 09:30 · 1 due today · 1 overdue")
        #expect(brief.events.map(\.title) == ["Holiday", "Standup", "Lunch"])
        #expect(brief.dueToday.map(\.title) == ["Send invoice"])
        #expect(brief.overdue == 1)
    }

    @Test func quietDayAndGreetings() {
        let brief = MorningBrief.build(now: at("2026-11-02T15:00:00Z"), events: [], todos: [], name: " ", calendar: utc)
        #expect(brief.greeting == "Good afternoon")
        #expect(brief.summary == "No meetings today")
        #expect(MorningBrief.build(now: at("2026-11-02T19:00:00Z"), events: [], todos: [], name: nil, calendar: utc).greeting == "Good evening")
    }

    @Test func firstUnlockGateShowsOncePerMorning() {
        var gate = FirstUnlockGate()
        #expect(!gate.shouldShow(at: at("2026-11-02T04:30:00Z"), calendar: utc)) // too early
        #expect(gate.shouldShow(at: at("2026-11-02T07:00:00Z"), calendar: utc))
        gate.markShown(at: at("2026-11-02T07:00:00Z"), calendar: utc)
        #expect(gate.lastShownDay == "2026-11-02")
        #expect(!gate.shouldShow(at: at("2026-11-02T09:00:00Z"), calendar: utc)) // already shown
        #expect(gate.shouldShow(at: at("2026-11-03T06:00:00Z"), calendar: utc)) // next day
        #expect(!FirstUnlockGate().shouldShow(at: at("2026-11-02T15:00:00Z"), calendar: utc)) // afternoon
    }

    @Test func quietRules() {
        #expect(ProactiveQuiet.allowsCard(fullScreen: false, focusActive: false))
        #expect(!ProactiveQuiet.allowsCard(fullScreen: true, focusActive: false))
        #expect(!ProactiveQuiet.allowsCard(fullScreen: false, focusActive: true))
    }

    @Test func nudgesArePlannedAhead() {
        let now = at("2026-11-02T08:00:00Z")
        let todos = [
            BriefTodo(id: "a", title: "Call bank", due: at("2026-11-02T11:00:00Z")),
            BriefTodo(id: "b", title: "Pay rent", due: at("2026-11-03T00:00:00Z"), dateOnly: true),
            BriefTodo(id: "c", title: "Past", due: at("2026-11-02T07:00:00Z")),
            BriefTodo(id: "d", title: "Far", due: at("2026-11-09T07:00:00Z")),
            BriefTodo(id: "e", title: "Done", due: at("2026-11-02T12:00:00Z"), done: true),
        ]
        let plan = DueNudge.plan(todos, now: now, calendar: utc)
        #expect(plan.map(\.title) == ["Call bank", "Pay rent"])
        #expect(plan[1].fireDate == at("2026-11-03T09:00:00Z"))
        #expect(plan[0].body == "Due now" && plan[1].body == "Due today")
        #expect(plan[0].id == "zeus.todo.a.\(Int(at("2026-11-02T11:00:00Z").timeIntervalSince1970))")
    }

    @Test func nudgeDiffOnlyTouchesOurOwn() {
        let planned = [DueNudge(id: "zeus.todo.a.1", title: "A", body: "", fireDate: Date()),
                       DueNudge(id: "zeus.todo.b.2", title: "B", body: "", fireDate: Date())]
        let diff = DueNudge.diff(planned: planned, scheduled: ["zeus.todo.a.1", "zeus.todo.old.9", "someone.else"])
        #expect(diff.add.map(\.id) == ["zeus.todo.b.2"])
        #expect(diff.remove == ["zeus.todo.old.9"])
    }
}
