import Foundation
import Testing
@testable import ZeusCore

/// Schedule maths only: no test ever runs a CLI.
@Suite("Routines")
struct RoutinesTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    // 2026-10-30 is a Friday, 10-31 Saturday, 11-02 Monday.

    @Test func nextRunDailyAndWeekdays() {
        let daily = RoutineSchedule(days: .daily, hour: 9, minute: 30)
        #expect(daily.next(after: at("2026-10-30T08:00:00Z"), calendar: utc) == at("2026-10-30T09:30:00Z"))
        #expect(daily.next(after: at("2026-10-30T09:30:00Z"), calendar: utc) == at("2026-10-31T09:30:00Z"))
        let weekdays = RoutineSchedule(days: .weekdays, hour: 9, minute: 0)
        #expect(weekdays.next(after: at("2026-10-30T10:00:00Z"), calendar: utc) == at("2026-11-02T09:00:00Z"))
        #expect(weekdays.summary == "Weekdays at 09:00")
        #expect(RoutineSchedule(hour: 30, minute: -5).hour == 23)
    }

    @Test func previousRun() {
        let weekdays = RoutineSchedule(days: .weekdays, hour: 9, minute: 0)
        #expect(weekdays.previous(atOrBefore: at("2026-11-01T12:00:00Z"), calendar: utc) == at("2026-10-30T09:00:00Z"))
        #expect(weekdays.previous(atOrBefore: at("2026-11-02T09:00:00Z"), calendar: utc) == at("2026-11-02T09:00:00Z"))
    }

    @Test func catchesUpOnceAfterSleep() {
        let schedule = RoutineSchedule(days: .daily, hour: 7, minute: 0)
        let created = at("2026-10-20T00:00:00Z")
        // Asleep for days: one catch-up, for the latest missed slot.
        #expect(schedule.missed(lastRun: at("2026-10-25T07:00:00Z"), created: created, now: at("2026-10-30T10:00:00Z"), calendar: utc)
                == at("2026-10-30T07:00:00Z"))
        // Already ran today: nothing missed.
        #expect(schedule.missed(lastRun: at("2026-10-30T07:00:05Z"), created: created, now: at("2026-10-30T10:00:00Z"), calendar: utc) == nil)
        // Made after today's slot: waits for tomorrow.
        #expect(schedule.missed(lastRun: nil, created: at("2026-10-30T08:00:00Z"), now: at("2026-10-30T10:00:00Z"), calendar: utc) == nil)
    }

    @Test func dueAndNextWake() {
        let now = at("2026-10-30T10:00:00Z")
        let morning = Routine(name: "Brief", prompt: "Summarize my day", schedule: .init(days: .daily, hour: 7, minute: 0),
                              created: at("2026-10-01T00:00:00Z"), lastRun: at("2026-10-29T07:00:00Z"))
        let evening = Routine(name: "Wrap", prompt: "Wrap up", schedule: .init(days: .daily, hour: 18, minute: 0),
                              created: at("2026-10-01T00:00:00Z"), lastRun: at("2026-10-29T18:00:00Z"))
        var off = morning
        off.enabled = false
        var empty = morning
        empty.prompt = "  "
        #expect(RoutinePlanner.due([morning, evening, off, empty], now: now, calendar: utc).map(\.name) == ["Brief"])
        #expect(RoutinePlanner.nextWake([morning, evening, off], now: now, calendar: utc) == at("2026-10-30T18:00:00Z"))
        #expect(RoutinePlanner.nextWake([off], now: now, calendar: utc) == nil)
    }

    @Test func storeKeepsRecentHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-routines-\(UUID().uuidString)/routines.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = RoutineStore(url: url)
        #expect(store.load() == .init())
        let routine = Routine(name: "Brief", prompt: "p", engine: .engine(.gemini), created: at("2026-10-01T00:00:00Z"))
        let runs = (0..<60).map { RoutineRun(routineID: routine.id, routineName: "Brief", date: at("2026-10-01T00:00:00Z").addingTimeInterval(Double($0) * 3600),
                                             engine: "gemini", output: "\($0)", failed: false) }
        try store.save(.init(routines: [routine], runs: runs))
        let loaded = store.load()
        #expect(loaded.routines == [routine])
        #expect(loaded.runs.count == RoutineStore.historyLimit)
        #expect(loaded.runs.first?.output == "59")
    }
}
