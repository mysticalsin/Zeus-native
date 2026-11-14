import Foundation
import Testing
@testable import ZeusCore

private let mlBase = Date(timeIntervalSince1970: 2_000_000)

private func mlSlot(_ id: String, start: TimeInterval, end: TimeInterval? = nil,
                    app: ScribeCallApp? = .teams) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: id, title: "Meeting \(id)", start: mlBase.addingTimeInterval(start),
                       end: end.map { mlBase.addingTimeInterval($0) }, hasCallLink: true, callApp: app)
}

private func mlEvidence(_ at: TimeInterval, slots: [ScribeCalendarSlot] = [], mic: [ScribeCallApp] = [],
                        present: [ScribeCallApp] = []) -> ScribeMeetingEvidence {
    ScribeMeetingEvidence(date: mlBase.addingTimeInterval(at), slots: slots, micApps: mic, presentApps: present)
}

private func mlMeeting(_ evidence: ScribeMeetingEvidence) throws -> ScribeMeeting {
    try #require(evidence.candidate)
}

@Suite("Scribe meeting ledger")
struct ScribeMeetingLedgerTests {
    @Test func dismissAtTwoMinutesStaysQuietAtStartTime() throws {
        let slot = mlSlot("s1", start: 120, end: 1_920)
        var ledger = ScribeMeetingLedger()
        let headsUp = ScribeMeeting(key: "s1", title: "Meeting s1", callApp: .teams, slot: slot)
        ledger.note(headsUp, .declined, date: mlBase)
        ledger.observe(mlEvidence(120, slots: [slot]), now: 120)
        #expect(ledger.mark(of: try mlMeeting(mlEvidence(120, slots: [slot]))) == .declined)
        ledger.observe(mlEvidence(130, slots: [slot], mic: [.teams]), now: 130)
        #expect(ledger.mark(of: try mlMeeting(mlEvidence(130, slots: [slot], mic: [.teams]))) == .declined)
    }

    @Test func aBackToBackMeetingInTheSameAppIsOffered() throws {
        let first = mlSlot("s1", start: 0, end: 1_800)
        let second = mlSlot("s2", start: 1_800, end: 3_600)
        let slots = [first, second]
        var ledger = ScribeMeetingLedger()
        let duringFirst = try mlMeeting(mlEvidence(10, slots: slots, mic: [.teams]))
        #expect(duringFirst.key == "s1")
        ledger.note(duringFirst, .started, date: mlBase.addingTimeInterval(10))
        let late = mlEvidence(1_790, slots: slots, mic: [.teams])
        ledger.observe(late, now: 1_790)
        #expect(try mlMeeting(late).key == "s1")
        #expect(ledger.mark(of: try mlMeeting(late)) == .started)
        let atSecondStart = mlEvidence(1_800, slots: slots, mic: [.teams])
        ledger.observe(atSecondStart, now: 1_800)
        let secondMeeting = try mlMeeting(atSecondStart)
        #expect(secondMeeting.key == "s2")
        #expect(ledger.mark(of: secondMeeting) == nil)
        ledger.note(secondMeeting, .declined, date: mlBase.addingTimeInterval(1_800))
        #expect(ledger.mark(of: secondMeeting) == .declined)
    }

    @Test func aDismissedCallStaysQuietWhenItsCalendarWindowOpens() throws {
        var ledger = ScribeMeetingLedger()
        let call = try mlMeeting(mlEvidence(0, mic: [.teams], present: [.teams]))
        #expect(call.key == "call:Teams")
        ledger.note(call, .declined, date: mlBase)
        let slot = mlSlot("s1", start: 1_100, end: 4_700)
        let opened = mlEvidence(1_000, slots: [slot], mic: [.teams], present: [.teams])
        ledger.observe(opened, now: 1_000)
        let meeting = try mlMeeting(opened)
        #expect(meeting.key == "s1")
        #expect(ledger.mark(of: meeting) == .declined)
        // The machine writes the answer onto the meeting it now belongs to, so it outlives the call app's entry.
        ledger.note(meeting, .declined, date: opened.date)
        let silent = mlEvidence(1_010, slots: [slot], present: [.teams])
        ledger.observe(silent, now: 1_010)
        ledger.observe(mlEvidence(1_050, slots: [slot], present: [.teams]), now: 1_050)
        #expect(ledger.mark(of: meeting) == .declined)
    }

    @Test func aDismissedMeetingStaysQuietWhenItRunsOver() throws {
        let slot = mlSlot("s1", start: 0, end: 600)
        var ledger = ScribeMeetingLedger()
        let inside = try mlMeeting(mlEvidence(10, slots: [slot], mic: [.teams]))
        ledger.note(inside, .declined, date: mlBase.addingTimeInterval(10))
        let over = mlEvidence(700, slots: [slot], mic: [.teams], present: [.teams])
        ledger.observe(over, now: 700)
        let after = try mlMeeting(over)
        #expect(after.key == "call:Teams")
        #expect(ledger.mark(of: after) == .declined)
    }

    @Test func aNewCallInTheSameAppAfterAGapIsANewMeeting() throws {
        var ledger = ScribeMeetingLedger()
        let call = try mlMeeting(mlEvidence(0, mic: [.teams]))
        ledger.note(call, .declined, date: mlBase)
        ledger.observe(mlEvidence(10, present: [.teams]), now: 10)
        ledger.observe(mlEvidence(39, present: [.teams]), now: 39)
        #expect(ledger.mark(of: call) == .declined)
        ledger.observe(mlEvidence(41, mic: [.teams], present: [.teams]), now: 41)
        #expect(ledger.mark(of: call) == .declined)
        ledger.observe(mlEvidence(50, present: [.teams]), now: 50)
        ledger.observe(mlEvidence(80, present: [.teams]), now: 80)
        #expect(ledger.mark(of: call) == nil)
    }

    @Test func aCallEntryLeavesAtOnceWhenItsAppIsGone() throws {
        var ledger = ScribeMeetingLedger()
        let call = try mlMeeting(mlEvidence(0, mic: [.zoom]))
        ledger.note(call, .started, date: mlBase)
        ledger.observe(mlEvidence(5, present: [.zoom]), now: 5)
        #expect(ledger.mark(of: call) == .started)
        ledger.observe(mlEvidence(6), now: 6)
        #expect(ledger.mark(of: call) == nil)
    }

    @Test func marksNeverGoDown() throws {
        let slot = mlSlot("s1", start: 0, end: 600)
        var ledger = ScribeMeetingLedger()
        let meeting = ScribeMeeting(key: "s1", title: "Meeting s1", callApp: .teams, slot: slot)
        ledger.note(meeting, .declined, date: mlBase)
        ledger.note(meeting, .headsUp, date: mlBase)
        ledger.note(meeting, .asked, date: mlBase)
        #expect(ledger.mark(of: meeting) == .declined)
        ledger.note(meeting, .started, date: mlBase)
        #expect(ledger.mark(of: meeting) == .started)
        #expect(ScribeMeetingLedger.Mark.headsUp < .asked)
        #expect(ScribeMeetingLedger.Mark.asked < .declined)
        #expect(ScribeMeetingLedger.Mark.declined < .started)
        #expect(!ScribeMeetingLedger.Mark.headsUp.isAnswered)
        #expect(!ScribeMeetingLedger.Mark.asked.isAnswered)
        #expect(ScribeMeetingLedger.Mark.declined.isAnswered)
        #expect(ScribeMeetingLedger.Mark.started.isAnswered)
    }

    @Test func entriesLeaveWhenTheSlotEnds() {
        let ended = mlSlot("s1", start: 0, end: 600)
        let openEnded = mlSlot("s2", start: 0, end: nil)
        var ledger = ScribeMeetingLedger()
        let first = ScribeMeeting(key: "s1", title: "Meeting s1", callApp: .teams, slot: ended)
        let second = ScribeMeeting(key: "s2", title: "Meeting s2", callApp: .teams, slot: openEnded)
        ledger.note(first, .declined, date: mlBase)
        ledger.note(second, .declined, date: mlBase)
        ledger.observe(mlEvidence(ScribeMeetingStartPolicy.lateWindow - 1), now: 299)
        #expect(ledger.mark(of: first) == .declined)
        #expect(ledger.mark(of: second) == .declined)
        ledger.observe(mlEvidence(ScribeMeetingStartPolicy.lateWindow), now: 300)
        #expect(ledger.mark(of: first) == .declined)
        #expect(ledger.mark(of: second) == nil)
        ledger.observe(mlEvidence(599), now: 599)
        #expect(ledger.mark(of: first) == .declined)
        ledger.observe(mlEvidence(600), now: 600)
        #expect(ledger.mark(of: first) == nil)
    }

    @Test func aMeetingNotedAfterItsSlotEndedLeavesNothingBehind() {
        let slot = mlSlot("s1", start: 0, end: 600)
        var ledger = ScribeMeetingLedger()
        let meeting = ScribeMeeting(key: "s1", title: "Meeting s1", callApp: .teams, slot: slot)
        ledger.note(meeting, .started, date: mlBase.addingTimeInterval(700))
        #expect(ledger.mark(of: meeting) == nil)
    }

    @Test func aLiveMeetingAlsoMarksItsCallApp() throws {
        let slot = mlSlot("s1", start: 0, end: 600)
        var ledger = ScribeMeetingLedger()
        let live = ScribeMeeting(key: "s1", title: "Meeting s1", callApp: .teams, slot: slot, isLive: true)
        ledger.note(live, .started, date: mlBase)
        let slotless = ScribeMeeting(key: "call:Teams", title: "Call", callApp: .teams, isLive: true)
        #expect(ledger.mark(of: slotless) == .started)
        let scheduled = ScribeMeeting(key: "s3", title: "Meeting s3", callApp: .teams, slot: mlSlot("s3", start: 0))
        ledger.note(scheduled, .started, date: mlBase)
        #expect(ledger.mark(of: ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)) == nil)
    }

    @Test func aMarkedSlotNeverAdoptsACallMark() throws {
        var ledger = ScribeMeetingLedger()
        let call = ScribeMeeting(key: "call:Teams", title: "Call", callApp: .teams, isLive: true)
        ledger.note(call, .started, date: mlBase)
        let slot = mlSlot("n1", start: 80)
        let next = ScribeMeeting(key: "n1", title: "Meeting n1", callApp: .teams, slot: slot, isLive: true)
        #expect(ledger.mark(of: next) == .started)
        ledger.note(ScribeMeeting(key: "n1", title: "Meeting n1", callApp: .teams, slot: slot), .headsUp, date: mlBase)
        #expect(ledger.mark(of: next) == .headsUp)
    }
}
