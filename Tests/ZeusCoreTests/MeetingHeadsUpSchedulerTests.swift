import Foundation
import Testing
@testable import ZeusCore

@Suite struct MeetingHeadsUpSchedulerTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func settings(enabled: Bool, lead: Int, reminders: Bool = true, focus: Bool = true) -> MeetingHeadsUpSettings {
        MeetingHeadsUpSettings(enabled: enabled, calendarLeadMinutes: lead, reminders: reminders, focus: focus)
    }

    private func occasion(_ kind: InAppOccasion.Kind, id: String, minutesFromStart: Int = 0) -> InAppOccasion {
        InAppOccasion(id: id, title: id, start: start.addingTimeInterval(Double(minutesFromStart) * 60), kind: kind)
    }

    @Test func staysOffUntilTheUserTurnsItOn() {
        let meeting = occasion(.meeting, id: "standup", minutesFromStart: 30)
        let now = start
        let atZero = MeetingHeadsUpScheduler.plan(settings: settings(enabled: false, lead: 0), occasions: [meeting], now: now)
        let atFifteen = MeetingHeadsUpScheduler.plan(settings: settings(enabled: false, lead: 15), occasions: [meeting], now: now)
        #expect(atZero == atFifteen)
        #expect(atZero.phase == .off)
        #expect(atZero.cues.isEmpty)
        #expect(atZero.createdEvents.isEmpty)
        #expect(MeetingHeadsUpScheduler.createsCalendarEvents == false)
    }

    @Test func leadChangesTheHeadsUpOnceEnabled() {
        let meeting = occasion(.meeting, id: "standup", minutesFromStart: 30)
        let now = start
        let off = MeetingHeadsUpScheduler.plan(settings: settings(enabled: true, lead: 0), occasions: [meeting], now: now)
        let soon = MeetingHeadsUpScheduler.plan(settings: settings(enabled: true, lead: 15), occasions: [meeting], now: now)
        #expect(off.cues.isEmpty)
        #expect(soon.cues.count == 1)
        #expect(soon.cues[0].fireAt == meeting.start.addingTimeInterval(-15 * 60))
        #expect(soon.cues[0].occasionID == "standup")
        #expect(soon.createdEvents.isEmpty)
        #expect(soon.phase == .armed)
    }

    @Test func remindersAndFocusFollowTheirOwnSwitches() {
        let items = [
            occasion(.meeting, id: "standup", minutesFromStart: 20),
            occasion(.reminder, id: "pay-rent", minutesFromStart: 10),
            occasion(.focusEnd, id: "deep-work", minutesFromStart: 5),
        ]
        let now = start
        let all = MeetingHeadsUpScheduler.plan(settings: settings(enabled: true, lead: 5), occasions: items, now: now)
        let meetingsOnly = MeetingHeadsUpScheduler.plan(
            settings: settings(enabled: true, lead: 5, reminders: false, focus: false),
            occasions: items,
            now: now
        )
        #expect(all.cues.map(\.kind) == [.meeting, .reminder, .focusEnd])
        #expect(meetingsOnly.cues.map(\.kind) == [.meeting])
        #expect(all.createdEvents.isEmpty)
    }

    @Test func freshDefaultsAreOffAndReadTheExistingKeys() {
        let name = "zeus.meeting-heads-up.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let loaded = MeetingHeadsUpSettings.load(defaults)
        #expect(loaded.enabled == false)
        #expect(loaded.calendarLeadMinutes == 5)
        #expect(loaded.reminders == true)
        #expect(loaded.focus == true)
        defaults.set(15, forKey: MeetingHeadsUpSettings.leadKey)
        defaults.set(false, forKey: MeetingHeadsUpSettings.remindersKey)
        defaults.set(true, forKey: MeetingHeadsUpSettings.enabledKey)
        let turnedOn = MeetingHeadsUpSettings.load(defaults)
        #expect(turnedOn.enabled == true)
        #expect(turnedOn.calendarLeadMinutes == 15)
        #expect(turnedOn.reminders == false)
        let meeting = occasion(.meeting, id: "review", minutesFromStart: 40)
        let plan = MeetingHeadsUpScheduler.plan(settings: turnedOn, occasions: [meeting], now: start)
        #expect(plan.cues.first?.fireAt == meeting.start.addingTimeInterval(-15 * 60))
        #expect(plan.createdEvents.isEmpty)
    }

    @Test func schedulerSourceDoesNotCreateCalendarEvents() throws {
        let source = try schedulerSource()
        #expect(!source.contains("EventKit"))
        #expect(!source.contains("EKEvent"))
        #expect(!source.contains("saveEvent"))
        #expect(source.contains("createsCalendarEvents"))
    }

    private func schedulerSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("../../Sources/ZeusCore/Notifications/MeetingHeadsUpScheduler.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
