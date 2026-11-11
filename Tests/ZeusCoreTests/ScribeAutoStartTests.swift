import Foundation
import Testing
@testable import ZeusCore

private let asBase = Date(timeIntervalSince1970: 1_000_000)

private func asSlot(_ id: String = "s1", title: String = "Design review", start: TimeInterval = 0,
                  end: TimeInterval? = nil, link: Bool = true) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: id, title: title, start: asBase.addingTimeInterval(start),
                       end: end.map { asBase.addingTimeInterval($0) }, hasCallLink: link)
}

private func asEvidence(
    _ now: TimeInterval, mic: [ScribeCallApp] = [], present: [ScribeCallApp] = [], slots: [ScribeCalendarSlot] = [],
    mode: ScribeAutoStartMode = .ask, granted: Bool = false, activity: ScribeActivity = .idle
) -> ScribeAutoStartMachine.Event {
    .evidence(ScribeMeetingEvidence(date: asBase.addingTimeInterval(now), slots: slots, micApps: mic, presentApps: present,
                                    mode: mode, micPermissionGranted: granted, activity: activity), now: now)
}

private let asTeams = ScribeMeeting(key: "call:Teams", title: "Teams call", callApp: .teams)

/// A machine whose Teams call has been seen at 0 and again at 3, so the "Ask me" banner is up.
private func asPrompting(mode: ScribeAutoStartMode = .ask, granted: Bool = false) -> ScribeAutoStartMachine {
    var machine = ScribeAutoStartMachine()
    machine.handle(asEvidence(0, mic: [.teams], mode: mode, granted: granted))
    machine.handle(asEvidence(3, mic: [.teams], mode: mode, granted: granted))
    return machine
}

/// A machine recording a Teams call that began at 10, with the call app seen holding the microphone at 11.
private func asRecordingTeams() -> ScribeAutoStartMachine {
    var machine = asPrompting()
    machine.handle(.accept(now: 10))
    machine.handle(asEvidence(11, mic: [.teams], activity: .recording))
    return machine
}

@Suite("Scribe meeting start")
struct ScribeAutoStartTests {
    // MARK: Setting

    @Test func settingParsesAndDefaultsToAskMe() {
        #expect(ScribeAutoStartMode.defaultMode == .ask)
        #expect(ScribeAutoStartMode.parse(nil) == .ask)
        #expect(ScribeAutoStartMode.parse("not a choice") == .ask)
        #expect(ScribeAutoStartMode.choices == ["Off", "Ask me", "Start automatically"])
        for mode in ScribeAutoStartMode.allCases { #expect(ScribeAutoStartMode.parse(mode.title) == mode) }
    }

    @Test func settingReadsTheStoredChoiceAndFreshDefaultsAreAskMe() throws {
        let name = "ScribeAutoStartTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ScribeAutoStartMode.current(defaults: defaults) == .ask)
        defaults.set("Start automatically", forKey: FeatureSettings.key(ScribeAutoStartMode.settingID))
        #expect(ScribeAutoStartMode.current(defaults: defaults) == .automatic)
        defaults.set("Off", forKey: FeatureSettings.key(ScribeAutoStartMode.settingID))
        #expect(ScribeAutoStartMode.current(defaults: defaults) == .off)
    }

    // MARK: Signals

    @Test func aCallAppHoldingTheMicrophoneIsAMeeting() {
        let meeting = ScribeMeetingEvidence(date: asBase, micApps: [.teams]).candidate
        #expect(meeting == asTeams)
    }

    @Test func anOpenCallAppAloneIsNotAMeeting() {
        #expect(ScribeMeetingEvidence(date: asBase, presentApps: [.teams]).candidate == nil)
    }

    @Test func aCalendarEventWithALinkAndItsAppOpenIsAMeetingWithItsTitle() {
        let event = asSlot(start: -30)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event], presentApps: [.zoom]).candidate
        #expect(meeting?.key == "s1")
        #expect(meeting?.title == "Design review")
        #expect(meeting?.callApp == .zoom)
        #expect(meeting?.promptDecision == .upcoming(event))
    }

    @Test func aCalendarEventAloneOrWithoutALinkOrOutsideTheWindowIsNotEnough() {
        #expect(ScribeMeetingEvidence(date: asBase, slots: [asSlot(start: 0)]).candidate == nil)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [asSlot(start: 0, link: false)], presentApps: [.teams]).candidate == nil)
        let early = asSlot(start: ScribeMeetingStartPolicy.leadWindow + 1)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [early], presentApps: [.teams]).candidate == nil)
        let late = asSlot(start: -(ScribeMeetingStartPolicy.lateWindow + 1))
        #expect(ScribeMeetingEvidence(date: asBase, slots: [late], presentApps: [.teams]).candidate == nil)
        let over = asSlot(start: -60, end: -1)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [over], presentApps: [.teams]).candidate == nil)
    }

    @Test func theMicrophoneAppNamesTheMeetingEvenWithoutACalendarEvent() {
        let event = asSlot(start: -10)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event], micApps: [.meet], presentApps: [.teams]).candidate
        #expect(meeting?.callApp == .meet)
        #expect(meeting?.key == "s1")
    }

    @Test func theClosestCalendarEventWins() {
        let near = asSlot("near", start: 10)
        let far = asSlot("far", start: -100)
        #expect(ScribeMeetingStartPolicy.slot(in: [far, near], at: asBase)?.id == "near")
    }

    // MARK: Debounce and single trigger

    @Test func nothingShowsOnFirstSightingAndTheBannerComesAfterTheDebounce() {
        var machine = ScribeAutoStartMachine()
        let first = machine.handle(asEvidence(0, mic: [.teams]))
        #expect(first.isEmpty)
        #expect(machine.state == .armed(meeting: asTeams, since: 0))
        let second = machine.handle(asEvidence(1, mic: [.teams]))
        #expect(second.isEmpty)
        let third = machine.handle(asEvidence(3, mic: [.teams]))
        #expect(third == [.showAsk(asTeams)])
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23))
    }

    @Test func aSignalThatVanishesBeforeTheDebounceStartsOver() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams]))
        let gone = machine.handle(asEvidence(1))
        #expect(gone.isEmpty)
        #expect(machine.state == .idle)
        machine.handle(asEvidence(2, mic: [.teams]))
        let tooSoon = machine.handle(asEvidence(4, mic: [.teams]))
        #expect(tooSoon.isEmpty)
        let ready = machine.handle(asEvidence(5, mic: [.teams]))
        #expect(ready == [.showAsk(asTeams)])
    }

    @Test func aDifferentMeetingWhileArmedRestartsTheDebounce() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams]))
        let switched = machine.handle(asEvidence(2, mic: [.zoom]))
        #expect(switched.isEmpty)
        #expect(machine.state == .armed(meeting: ScribeMeeting(key: "call:Zoom", title: "Zoom call", callApp: .zoom), since: 2))
    }

    @Test func aTickNeverPromotesAnArmedMeeting() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams]))
        let tick = machine.handle(.tick(now: 100))
        #expect(tick.isEmpty)
        #expect(machine.state == .armed(meeting: asTeams, since: 0))
        #expect(!machine.needsTick)
    }

    @Test func zeroDebounceShowsOnTheFirstSighting() {
        var machine = ScribeAutoStartMachine(timing: ScribeAutoStartTiming(debounce: 0))
        let effects = machine.handle(asEvidence(0, mic: [.teams]))
        #expect(effects == [.showAsk(asTeams)])
    }

    @Test func oneMeetingTriggersOnlyOnceHoweverLongTheSignalLasts() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        var shown = 0
        var now: TimeInterval = 6
        while now < 600 {
            let effects = machine.handle(asEvidence(now, mic: [.teams]))
            if effects.contains(.showAsk(asTeams)) || effects.contains(.showCountdown(asTeams)) { shown += 1 }
            now += 5
        }
        #expect(shown == 0)
    }

    @Test func aFlickerOfTheMicrophoneDoesNotMakeANewMeeting() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        machine.handle(asEvidence(10))
        machine.handle(asEvidence(20, mic: [.teams]))
        machine.handle(asEvidence(35))
        machine.handle(asEvidence(60, mic: [.teams]))
        let later = machine.handle(asEvidence(90, mic: [.teams]))
        #expect(later.isEmpty)
        guard case .cooldown = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
    }

    // MARK: Ask me

    @Test func askMeStartsWhenTheBannerIsAccepted() {
        var machine = asPrompting()
        let effects = machine.handle(.accept(now: 8))
        #expect(effects == [.hideBanner, .startRecording(asTeams)])
        #expect(machine.state == .recording(ScribeAutoStartRecording(meeting: asTeams, since: 8, micReleasedAt: nil, sawMic: false)))
    }

    @Test func notNowHidesTheBannerAndStaysQuiet() {
        var machine = asPrompting()
        let effects = machine.handle(.decline(now: 8))
        #expect(effects == [.hideBanner])
        guard case .cooldown(let cooldown) = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
        #expect(cooldown.key == "call:Teams")
        #expect(cooldown.until == 68)
    }

    @Test func theAskBannerLeavesAfterTwentySecondsAndCountsAsNotNow() {
        var machine = asPrompting()
        let early = machine.handle(.tick(now: 22.9))
        #expect(early.isEmpty)
        #expect(machine.needsTick)
        let timeout = machine.handle(.tick(now: 23))
        #expect(timeout == [.hideBanner])
        guard case .cooldown = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
        #expect(!machine.needsTick)
        let again = machine.handle(asEvidence(30, mic: [.teams]))
        #expect(again.isEmpty)
    }

    @Test func theAskBannerSurvivesTheCallAppReleasingTheMicrophone() {
        var machine = asPrompting()
        let muted = machine.handle(asEvidence(8))
        #expect(muted.isEmpty)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23))
    }

    @Test func offNeverShowsAnythingAndTurningItOffHidesTheBanner() {
        var off = ScribeAutoStartMachine()
        off.handle(asEvidence(0, mic: [.teams], mode: .off))
        let none = off.handle(asEvidence(10, mic: [.teams], mode: .off))
        #expect(none.isEmpty)
        #expect(off.state == .idle)

        var machine = asPrompting()
        let hidden = machine.handle(asEvidence(8, mic: [.teams], mode: .off))
        #expect(hidden == [.hideBanner])
        guard case .cooldown = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
    }

    @Test func offWhileArmedDropsTheMeeting() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams]))
        machine.handle(asEvidence(1, mic: [.teams], mode: .off))
        #expect(machine.state == .idle)
    }

    // MARK: Start automatically

    @Test func automaticCountsDownFiveSecondsThenStarts() {
        var machine = asPrompting(mode: .automatic, granted: true)
        #expect(machine.state == .countingDown(meeting: asTeams, deadline: 8))
        let early = machine.handle(.tick(now: 7))
        #expect(early.isEmpty)
        let start = machine.handle(.tick(now: 8))
        #expect(start == [.hideBanner, .startRecording(asTeams)])
        guard case .recording = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
    }

    @Test func cancelDuringTheCountdownNeverStarts() {
        var machine = asPrompting(mode: .automatic, granted: true)
        let cancel = machine.handle(.decline(now: 5))
        #expect(cancel == [.hideBanner])
        let later = machine.handle(.tick(now: 60))
        #expect(later.isEmpty)
        let evidenceLater = machine.handle(asEvidence(70, mic: [.teams], mode: .automatic, granted: true))
        #expect(evidenceLater.isEmpty)
    }

    @Test func startNowDuringTheCountdownStartsAtOnce() {
        var machine = asPrompting(mode: .automatic, granted: true)
        let effects = machine.handle(.accept(now: 5))
        #expect(effects == [.hideBanner, .startRecording(asTeams)])
    }

    @Test func automaticWithoutMicrophonePermissionAsksInstead() {
        let machine = asPrompting(mode: .automatic, granted: false)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23))
    }

    @Test func automaticNeverStartsWithoutPermissionEvenAfterTheDeadline() {
        var machine = asPrompting(mode: .automatic, granted: false)
        let tick = machine.handle(.tick(now: 23))
        #expect(tick == [.hideBanner])
        #expect(!tick.contains(.startRecording(asTeams)))
    }

    @Test func permissionWithdrawnDuringTheCountdownFallsBackToAsking() {
        var machine = asPrompting(mode: .automatic, granted: true)
        machine.handle(asEvidence(5, mic: [.teams], mode: .automatic, granted: false))
        let tick = machine.handle(.tick(now: 8))
        #expect(tick == [.showAsk(asTeams)])
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 28))
    }

    @Test func startingRecordingByHandWhileTheBannerIsUpHidesIt() {
        var machine = asPrompting()
        let effects = machine.handle(asEvidence(6, mic: [.teams], activity: .starting))
        #expect(effects == [.hideBanner])
        guard case .cooldown = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
    }

    @Test func aRecordingStartedByHandIsNeverPromptedOver() {
        var machine = ScribeAutoStartMachine()
        let first = machine.handle(asEvidence(0, mic: [.teams], activity: .recording))
        #expect(first.isEmpty)
        var later: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 5.0, through: 300.0, by: 5.0) {
            later += machine.handle(asEvidence(now, mic: [.teams], activity: now < 100 ? .recording : .idle))
        }
        #expect(later.isEmpty)
    }

    // MARK: Call ended

    @Test func callEndedSuggestsStoppingAfterThirtySecondsWithoutTheMicrophone() {
        var machine = asRecordingTeams()
        let released = machine.handle(asEvidence(12, activity: .recording))
        #expect(released.isEmpty)
        let almost = machine.handle(asEvidence(41, activity: .recording))
        #expect(almost.isEmpty)
        let ended = machine.handle(asEvidence(42, activity: .recording))
        #expect(ended == [.requestEnd(asTeams)])
        #expect(machine.state == .endingSuggested(meeting: asTeams, since: 42))
    }

    @Test func noEndIsSuggestedBeforeTheCallAppEverHeldTheMicrophone() {
        var machine = asPrompting()
        machine.handle(.accept(now: 10))
        var all: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 11.0, through: 200.0, by: 5.0) { all += machine.handle(asEvidence(now, activity: .recording)) }
        #expect(all.isEmpty)
    }

    @Test func aBriefMicrophoneGapInTheCallDoesNotEndIt() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        machine.handle(asEvidence(20, mic: [.teams], activity: .recording))
        machine.handle(asEvidence(25, activity: .recording))
        let beforeThirty = machine.handle(asEvidence(54, activity: .recording))
        #expect(beforeThirty.isEmpty)
        let thirty = machine.handle(asEvidence(55, activity: .recording))
        #expect(thirty == [.requestEnd(asTeams)])
    }

    @Test func anotherAppHoldingTheMicrophoneDoesNotKeepTheCallAlive() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, mic: [.zoom], activity: .recording))
        let ended = machine.handle(asEvidence(42, mic: [.zoom], activity: .recording))
        #expect(ended == [.requestEnd(asTeams)])
    }

    @Test func nothingIsSuggestedWhileThePersonIsAlreadyStopping() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        let ending = machine.handle(asEvidence(60, activity: .ending))
        #expect(ending.isEmpty)
        let processing = machine.handle(asEvidence(90, activity: .processing))
        #expect(processing.isEmpty)
        guard case .recording = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
    }

    @Test func afterTheEndWindowSavesTheMeetingTheMachineCoolsDown() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        machine.handle(asEvidence(42, activity: .recording))
        let ending = machine.handle(asEvidence(44, activity: .ending))
        #expect(ending.isEmpty)
        let saved = machine.handle(asEvidence(55, activity: .idle))
        #expect(saved == [.hideBanner])
        guard case .cooldown(let cooldown) = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
        #expect(cooldown.key == "call:Teams")
    }

    @Test func keepRecordingReturnsToRecordingAndWaitsForTheCallToReturn() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        machine.handle(asEvidence(42, activity: .recording))
        let waiting = machine.handle(asEvidence(43, activity: .recording))
        #expect(waiting.isEmpty)
        #expect(machine.state == .endingSuggested(meeting: asTeams, since: 42))
        machine.handle(asEvidence(45, activity: .recording))
        #expect(machine.state == .recording(ScribeAutoStartRecording(meeting: asTeams, since: 45, micReleasedAt: nil, sawMic: false)))
        var quiet: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 50.0, through: 400.0, by: 10.0) { quiet += machine.handle(asEvidence(now, activity: .recording)) }
        #expect(quiet.isEmpty)
        machine.handle(asEvidence(410, mic: [.teams], activity: .recording))
        machine.handle(asEvidence(415, activity: .recording))
        let again = machine.handle(asEvidence(445, activity: .recording))
        #expect(again == [.requestEnd(asTeams)])
    }

    @Test func stoppingByHandAfterTheGraceMovesToCooldown() {
        var machine = asPrompting()
        machine.handle(.accept(now: 10))
        let within = machine.handle(asEvidence(15, activity: .idle))
        #expect(within.isEmpty)
        guard case .recording = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
        let after = machine.handle(asEvidence(20, activity: .idle))
        #expect(after == [.hideBanner])
        guard case .cooldown = machine.state else {
            Issue.record("expected cooldown, got \(machine.state)")
            return
        }
    }

    // MARK: Cooldown

    @Test func theSameMeetingStaysQuietUntilItHasBeenGoneAWhile() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        machine.handle(asEvidence(10))
        machine.handle(asEvidence(41))
        let back = machine.handle(asEvidence(70, mic: [.teams]))
        #expect(back.isEmpty)
        #expect(machine.state == .armed(meeting: asTeams, since: 70))
        let shown = machine.handle(asEvidence(73, mic: [.teams]))
        #expect(shown == [.showAsk(asTeams)])
    }

    @Test func aDifferentMeetingWaitsOutTheCooldownThenTriggers() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Zoom call", callApp: .zoom)
        let early = machine.handle(asEvidence(30, mic: [.zoom]))
        #expect(early.isEmpty)
        let afterCooldown = machine.handle(asEvidence(66, mic: [.zoom]))
        #expect(afterCooldown.isEmpty)
        #expect(machine.state == .armed(meeting: zoom, since: 66))
        let shown = machine.handle(asEvidence(69, mic: [.zoom]))
        #expect(shown == [.showAsk(zoom)])
    }

    // MARK: Banner

    @Test func acceptAndDeclineDoNothingOutsideABanner() {
        var machine = ScribeAutoStartMachine()
        let accept = machine.handle(.accept(now: 1))
        let decline = machine.handle(.decline(now: 2))
        #expect(accept.isEmpty)
        #expect(decline.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func bannerWordingIsPlain() {
        #expect(ScribeAutoStartText.askHeadline(asTeams) == "Meeting started: Teams call. Take notes?")
        #expect(ScribeAutoStartText.countdownHeadline(asTeams, seconds: 3) == "Meeting started: Teams call. Taking notes in 3.")
        #expect(ScribeAutoStartText.countdownHeadline(asTeams, seconds: -1).hasSuffix("in 0."))
        for text in [ScribeAutoStartText.askDetail, ScribeAutoStartText.countdownDetail,
                     ScribeAutoStartText.askHeadline(asTeams)] {
            #expect(!text.contains("\u{2014}"))
        }
    }

    @Test func settingNotesAreOnePlainSentenceEachWithoutDashes() {
        for mode in ScribeAutoStartMode.allCases {
            let note = ScribeAutoStartText.settingNote(mode)
            #expect(!note.isEmpty)
            #expect(!note.contains("\u{2014}"))
        }
        #expect(ScribeAutoStartText.settingNote(.automatic).contains("5 seconds"))
        #expect(!ScribeAutoStartText.settingEndNote.contains("\u{2014}"))
    }

    @Test func activityFollowsTheScribePhase() {
        let id = ScribeSessionID()
        #expect(ScribeActivity(.idle) == .idle)
        #expect(ScribeActivity(.starting(id)) == .starting)
        #expect(ScribeActivity(.recording(id, since: 0)) == .recording)
        #expect(ScribeActivity(.ending(id, deadline: 9)) == .ending)
        #expect(ScribeActivity(.processing(id)) == .processing)
        #expect(ScribeActivity(.complete(id)) == .idle)
        #expect(ScribeActivity(.failed(id, reason: "x")) == .idle)
    }
}
