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

    @Test func scribeLeadWindowIsNotPlannedTwice() {
        let soon = occasion(.meeting, id: "standup", minutesFromStart: 1)
        let later = occasion(.meeting, id: "review", minutesFromStart: 15)
        let reminder = occasion(.reminder, id: "pay-rent", minutesFromStart: 1)
        let slots = [
            ScribeCalendarSlot(id: "standup", title: "standup", start: soon.start),
            ScribeCalendarSlot(id: "review", title: "review", start: later.start),
        ]
        let watched = MeetingHeadsUpScheduler.scribeWatchedIDs(slots: slots, now: start)
        #expect(watched == ["standup"])
        #expect(ScribeMeetingStartPolicy.leadWindow == 120)
        let plan = MeetingHeadsUpScheduler.plan(
            settings: settings(enabled: true, lead: 15),
            occasions: [soon, later, reminder],
            now: start,
            scribeWatchedIDs: watched
        )
        #expect(plan.cues.map(\.occasionID) == ["review", "pay-rent"])
        #expect(plan.createdEvents.isEmpty)
        #expect(!plan.cues.contains { $0.occasionID == "standup" })
    }

    @Test func thePeekTitleIsTheFirstDueCue() throws {
        let later = occasion(.meeting, id: "later", minutesFromStart: 20)
        let due = occasion(.reminder, id: "pay-rent", minutesFromStart: 0)
        let plan = MeetingHeadsUpScheduler.plan(
            settings: settings(enabled: true, lead: 15),
            occasions: [later, due],
            now: start
        )
        #expect(plan.phase == .showing)
        #expect(plan.cues.first?.occasionID == "later")
        #expect(plan.firstDueTitle == "pay-rent")
        let model = try repoSource("Sources/Zeus/Notch/NotchModel.swift")
        #expect(model.contains("firstDueTitle"))
        #expect(!model.contains("cues.first"))
    }

    /// A cue inside its window is showing. Returning armed here used to pass the older suite.
    @Test func aCueInsideItsWindowIsShowing() {
        let meeting = occasion(.meeting, id: "standup", minutesFromStart: 10)
        let now = meeting.start.addingTimeInterval(-5 * 60)
        let plan = MeetingHeadsUpScheduler.plan(
            settings: settings(enabled: true, lead: 15),
            occasions: [meeting],
            now: now
        )
        #expect(plan.phase == .showing)
        #expect(plan.firstDueTitle == "standup")
        #expect(plan.cues.first?.title != plan.firstDueTitle || plan.cues.count == 1)
    }

    @Test func duplicateOccasionIdsDoNotTrap() throws {
        let source = try schedulerSource()
        #expect(!source.contains("uniqueKeysWithValues"))
        let first = occasion(.meeting, id: "same", minutesFromStart: 30)
        let second = occasion(.reminder, id: "same", minutesFromStart: 5)
        let plan = MeetingHeadsUpScheduler.plan(
            settings: settings(enabled: true, lead: 15),
            occasions: [first, second],
            now: start
        )
        #expect(plan.cues.map(\.occasionID) == ["same"])
        #expect(plan.cues.first?.kind == .meeting)
        #expect(plan.createdEvents.isEmpty)
    }

    @Test func thePlanRefreshesAfterSleepWakeAndAMovedMeeting() throws {
        let notch = try repoSource("Sources/Zeus/Notch/NotchController.swift")
        let watcher = try repoSource("Sources/Zeus/Scribe/ScribeCallWatcher.swift")
        #expect(notch.contains("willSleepNotification"))
        #expect(notch.contains("onSlotsUpdated"))
        #expect(watcher.contains("onSlotsUpdated"))
        if let range = notch.range(of: "didWakeNotification") {
            let window = notch[range.upperBound...].prefix(500)
            #expect(window.contains("refreshMeetingHeadsUp"))
        } else {
            #expect(Bool(false))
        }
    }

    @Test func thePeekCallsPlanAndNotificationsBindsTheCard() throws {
        let notch = try repoSource("Sources/Zeus/Notch/NotchController.swift")
        let page = try repoSource("Sources/Zeus/Settings/GlanceSettingsPages.swift")
        let hub = try repoSource("Sources/Zeus/Settings/GSAgentHubCards.swift")
        let scheduler = try schedulerSource()
        #expect(notch.contains("MeetingHeadsUpScheduler.plan("))
        #expect(page.contains("MeetingHeadsUpCard()"))
        #expect(!hub.contains("MeetingHeadsUpCard()"))
        #expect(!scheduler.contains("EventKit"))
        #expect(!scheduler.contains("saveEvent"))
        #expect(!notch.contains("startScribe"))
    }

    private func repoSource(_ relative: String) throws -> String {
        if let root = ProcessInfo.processInfo.environment["ZEUS_REPO"], !root.isEmpty {
            return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(relative), encoding: .utf8)
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        Issue.record("Missing \(relative)")
        return ""
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
