import Foundation
import Testing
@testable import ZeusCore

private let asBase = Date(timeIntervalSince1970: 1_000_000)

private func asSlot(_ id: String = "s1", title: String = "Design review", start: TimeInterval = 0,
                  end: TimeInterval? = nil, link: Bool = true, app: ScribeCallApp? = nil) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: id, title: title, start: asBase.addingTimeInterval(start),
                       end: end.map { asBase.addingTimeInterval($0) }, hasCallLink: link, callApp: app)
}

private func asEvidence(
    _ now: TimeInterval, mic: [ScribeCallApp] = [], present: [ScribeCallApp] = [], slots: [ScribeCalendarSlot] = [],
    mode: ScribeAutoStartMode = .ask, granted: Bool = false, activity: ScribeActivity = .idle,
    consent: Bool = false, windows: [ScribeCallApp: ScribeCallWindowState] = [:]
) -> ScribeAutoStartMachine.Event {
    .evidence(ScribeMeetingEvidence(date: asBase.addingTimeInterval(now), slots: slots, micApps: mic, presentApps: present,
                                    mode: mode, micPermissionGranted: granted, activity: activity,
                                    autoConsentGiven: consent, callWindows: windows), now: now)
}

private let asTeams = ScribeMeeting(key: "call:Teams", title: "Call", callApp: .teams, isLive: true)

/// A machine whose Teams call has been seen at 0 and again at 3, so the "Ask me" banner is up.
private func asPrompting(mode: ScribeAutoStartMode = .ask, granted: Bool = false, consent: Bool = true) -> ScribeAutoStartMachine {
    var machine = ScribeAutoStartMachine()
    machine.handle(asEvidence(0, mic: [.teams], mode: mode, granted: granted, consent: consent))
    machine.handle(asEvidence(3, mic: [.teams], mode: mode, granted: granted, consent: consent))
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

    @Test func aStartedCalendarMeetingIsAScheduledMeetingWithItsTitle() {
        let event = asSlot(start: -30, app: .zoom)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event]).candidate
        #expect(meeting == ScribeMeeting(key: "s1", title: "Design review", callApp: .zoom, slot: event, isLive: false))
        #expect(meeting?.promptDecision == .upcoming(event))
        let noApp = ScribeMeetingEvidence(date: asBase, slots: [asSlot(start: -30)], presentApps: [.teams]).candidate
        #expect(noApp?.callApp == nil)
        #expect(noApp?.isLive == false)
    }

    @Test func aCalendarEventOutsideItsWindowIsNotEnough() {
        let early = asSlot(start: ScribeMeetingStartPolicy.leadWindow + 1)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [early], presentApps: [.teams]).candidate == nil)
        let late = asSlot(start: -(ScribeMeetingStartPolicy.lateWindow + 1))
        #expect(ScribeMeetingEvidence(date: asBase, slots: [late], presentApps: [.teams]).candidate == nil)
        let over = asSlot(start: -60, end: -1)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [over], presentApps: [.teams]).candidate == nil)
    }

    @Test func aLinkMeetingIsNotStartedBeforeItsStartTime() {
        let event = asSlot(start: 119, app: .teams)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [event], presentApps: [.teams]).candidate == nil)
        let atStart = ScribeMeetingEvidence(date: asBase.addingTimeInterval(119), slots: [event], presentApps: [.teams]).candidate
        #expect(atStart?.key == "s1")
        #expect(atStart?.isLive == false)
        let justBefore = ScribeMeetingEvidence(date: asBase.addingTimeInterval(118.5), slots: [event], presentApps: [.teams]).candidate
        #expect(justBefore == nil)
    }

    @Test func aLiveCallBeforeTheStartCarriesTheMeetingTitle() {
        let event = asSlot(start: 100, app: .teams)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event], micApps: [.teams]).candidate
        #expect(meeting == ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event, isLive: true))
        let tooEarly = asSlot(start: ScribeMeetingStartPolicy.leadWindow + 1, app: .teams)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [tooEarly], micApps: [.teams]).candidate?.key == "call:Teams")
    }

    @Test func aLiveCallNeedsALinkToBelongToAMeeting() {
        let event = asSlot(start: -30, link: false)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event], micApps: [.teams]).candidate
        #expect(meeting == asTeams)
    }

    @Test func aCalendarMeetingKeepsRunningPastTheLateWindowWhileTheCallLives() {
        let event = asSlot(start: -1_000, end: 600, app: .zoom)
        let live = ScribeMeetingEvidence(date: asBase, slots: [event], micApps: [.zoom]).candidate
        #expect(live?.key == "s1")
        #expect(ScribeMeetingEvidence(date: asBase, slots: [event], presentApps: [.zoom]).candidate == nil)
    }

    @Test func twoLinkMeetingsInWindowThePairedAppTitlesTheCall() {
        let zoom = asSlot("z", title: "Zoom review", start: -20, app: .zoom)
        let teams = asSlot("t", title: "Teams review", start: -10, app: .teams)
        let slots = [zoom, teams]
        let onZoom = ScribeMeetingEvidence(date: asBase, slots: slots, micApps: [.zoom]).candidate
        #expect(onZoom?.key == "z")
        #expect(onZoom?.callApp == .zoom)
        let onTeams = ScribeMeetingEvidence(date: asBase, slots: slots, micApps: [.teams]).candidate
        #expect(onTeams?.key == "t")
        let onMeet = ScribeMeetingEvidence(date: asBase, slots: slots, micApps: [.meet]).candidate
        #expect(onMeet == ScribeMeeting(key: "call:Google Meet", title: "Call", callApp: .meet, isLive: true))
    }

    @Test func aSlotWithAnUnknownLinkPairsWithTheFirstAppHoldingTheMicrophone() {
        let event = asSlot("w", start: -10, app: .other("calls.example"))
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event], micApps: [.zoom, .teams]).candidate
        #expect(meeting?.key == "w")
        #expect(meeting?.callApp == .zoom)
        let none = asSlot("n", start: -10)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [none], micApps: [.teams]).candidate?.key == "n")
    }

    @Test func aCallNearTheNextMeetingKeepsItsOwnName() {
        let next = asSlot("next", title: "Planning", start: 90, app: .zoom)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [next], micApps: [.teams]).candidate
        #expect(meeting == asTeams)
    }

    @Test func aStartedMeetingWinsOverOneStillToCome() {
        let started = asSlot("started", start: -30, app: .teams)
        let coming = asSlot("coming", start: 20, app: .teams)
        let slots = [coming, started]
        let live = ScribeMeetingStartPolicy.liveSlot(in: slots, micApps: [.teams], at: asBase)
        #expect(live?.id == "started")
        let alone = ScribeMeetingStartPolicy.liveSlot(in: [coming], micApps: [.teams], at: asBase)
        #expect(alone?.id == "coming")
        #expect(ScribeMeetingStartPolicy.liveSlot(in: slots, micApps: [], at: asBase) == nil)
    }

    @Test func theLatestStartedMeetingWins() {
        let older = asSlot("older", start: -200)
        let newer = asSlot("newer", start: -10)
        #expect(ScribeMeetingStartPolicy.startedSlot(in: [older, newer], at: asBase)?.id == "newer")
        #expect(ScribeMeetingStartPolicy.startedSlot(in: [asSlot("later", start: 1)], at: asBase) == nil)
        #expect(ScribeMeetingStartPolicy.startedSlot(in: [asSlot("edge", start: -ScribeMeetingStartPolicy.lateWindow)], at: asBase)?.id == "edge")
    }

    @Test func theMicrophoneAppNamesTheMeetingEvenWithoutACalendarEvent() {
        let event = asSlot(start: -10)
        let meeting = ScribeMeetingEvidence(date: asBase, slots: [event], micApps: [.meet], presentApps: [.teams]).candidate
        #expect(meeting?.callApp == .meet)
        #expect(meeting?.key == "s1")
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
        #expect(machine.state == .armed(meeting: ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true), since: 2))
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
        machine.handle(asEvidence(10, present: [.teams]))
        machine.handle(asEvidence(20, mic: [.teams], present: [.teams]))
        machine.handle(asEvidence(35, present: [.teams]))
        machine.handle(asEvidence(60, mic: [.teams], present: [.teams]))
        let later = machine.handle(asEvidence(90, mic: [.teams], present: [.teams]))
        #expect(later.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .declined)
    }

    @Test func aDeclinedBrowserCallStaysQuietWhenItsWindowTitleIsLostForAWhile() throws {
        let meet = try #require(ScribeMeetingEvidence(date: asBase, micApps: [.meet]).candidate)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.meet], present: [.meet]))
        machine.handle(asEvidence(3, mic: [.meet], present: [.meet]))
        #expect(machine.state == .prompting(meeting: meet, deadline: 23))
        machine.handle(.decline(now: 5))
        // Another tab is in front: the Meet title is read from neither list.
        machine.handle(asEvidence(10))
        machine.handle(asEvidence(20))
        var shown = 0
        var now: TimeInterval = 23
        while now < 120 {
            let effects = machine.handle(asEvidence(now, mic: [.meet], present: [.meet]))
            if effects.contains(.showAsk(meet)) { shown += 1 }
            now += 3
        }
        #expect(shown == 0)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: meet) == .declined)
    }

    @Test func anUnansweredCallStaysQuietWhenItsCalendarWindowOpensAndTheMicrophoneIsMuted() {
        var machine = asPrompting()
        machine.handle(.tick(now: 23))
        #expect(machine.state == .idle)
        let slot = asSlot("s1", start: 40, end: 1_800, app: .teams)
        let opened = machine.handle(asEvidence(30, mic: [.teams], present: [.teams], slots: [slot]))
        #expect(opened.isEmpty)
        // Muted for longer than the call entry lives: the slot still remembers the question.
        machine.handle(asEvidence(40, present: [.teams], slots: [slot]))
        machine.handle(asEvidence(75, present: [.teams], slots: [slot]))
        var shown = 0
        for now in stride(from: 80.0, through: 120.0, by: 3.0) {
            let effects = machine.handle(asEvidence(now, mic: [.teams], present: [.teams], slots: [slot]))
            if effects.contains(where: { if case .showAsk = $0 { return true } else { return false } }) { shown += 1 }
        }
        #expect(shown == 0)
        #expect(machine.state == .idle)
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
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .declined)
    }

    @Test func theAskBannerLeavesAfterTwentySecondsAndCountsAsNotNow() {
        var machine = asPrompting()
        let early = machine.handle(.tick(now: 22.9))
        #expect(early.isEmpty)
        #expect(machine.needsTick)
        let timeout = machine.handle(.tick(now: 23))
        #expect(timeout == [.hideBanner])
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .asked)
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
        #expect(machine.state == .idle)
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
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .started)
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

    @Test func callEndedSuggestsStoppingAfterEightSecondsWithoutTheMicrophone() {
        var machine = asRecordingTeams()
        let released = machine.handle(asEvidence(12, activity: .recording))
        #expect(released.isEmpty)
        let almost = machine.handle(asEvidence(19, activity: .recording))
        #expect(almost.isEmpty)
        let ended = machine.handle(asEvidence(20, activity: .recording))
        #expect(ended == [.requestEnd(asTeams)])
        #expect(machine.state == .endingSuggested(meeting: asTeams, since: 20))
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
        machine.handle(asEvidence(15, mic: [.teams], activity: .recording))
        machine.handle(asEvidence(25, activity: .recording))
        let beforeThirty = machine.handle(asEvidence(32, activity: .recording))
        #expect(beforeThirty.isEmpty)
        let thirty = machine.handle(asEvidence(33, activity: .recording))
        #expect(thirty == [.requestEnd(asTeams)])
    }

    @Test func anotherAppHoldingTheMicrophoneDoesNotKeepTheCallAlive() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, mic: [.zoom], activity: .recording))
        let ended = machine.handle(asEvidence(20, mic: [.zoom], activity: .recording))
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

    @Test func afterTheEndWindowSavesTheMeetingTheLedgerKeepsItStarted() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        machine.handle(asEvidence(20, activity: .recording))
        let ending = machine.handle(asEvidence(22, activity: .ending))
        #expect(ending.isEmpty)
        let saved = machine.handle(asEvidence(40, activity: .idle))
        #expect(saved == [.hideBanner])
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .started)
    }

    @Test func keepRecordingReturnsToRecordingAndWaitsForTheCallToReturn() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        machine.handle(asEvidence(20, activity: .recording))
        let waiting = machine.handle(asEvidence(21, activity: .recording))
        #expect(waiting.isEmpty)
        #expect(machine.state == .endingSuggested(meeting: asTeams, since: 20))
        machine.handle(asEvidence(23, activity: .recording))
        #expect(machine.state == .recording(ScribeAutoStartRecording(meeting: asTeams, since: 23, micReleasedAt: nil, sawMic: false)))
        var quiet: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 30.0, through: 400.0, by: 10.0) { quiet += machine.handle(asEvidence(now, activity: .recording)) }
        #expect(quiet.isEmpty)
        machine.handle(asEvidence(410, mic: [.teams], activity: .recording))
        machine.handle(asEvidence(415, activity: .recording))
        let again = machine.handle(asEvidence(423, activity: .recording))
        #expect(again == [.requestEnd(asTeams)])
    }

    @Test func stoppingByHandAfterTheGraceReturnsToIdle() {
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
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .started)
    }

    // MARK: Ledger

    @Test func theSameCallStaysQuietUntilItHasBeenGoneAWhile() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        machine.handle(asEvidence(10, present: [.teams]))
        machine.handle(asEvidence(41, present: [.teams]))
        let back = machine.handle(asEvidence(70, mic: [.teams], present: [.teams]))
        #expect(back.isEmpty)
        #expect(machine.state == .armed(meeting: asTeams, since: 70))
        let shown = machine.handle(asEvidence(73, mic: [.teams], present: [.teams]))
        #expect(shown == [.showAsk(asTeams)])
    }

    @Test func aDifferentMeetingArmsWithoutWaiting() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)
        let early = machine.handle(asEvidence(6, mic: [.zoom]))
        #expect(early.isEmpty)
        #expect(machine.state == .armed(meeting: zoom, since: 6))
        let shown = machine.handle(asEvidence(9, mic: [.zoom]))
        #expect(shown == [.showAsk(zoom)])
    }

    @Test func anAnsweredMeetingIsNeverArmedAgain() {
        var machine = asPrompting()
        machine.handle(.decline(now: 5))
        let effects = machine.handle(asEvidence(6, mic: [.teams]))
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func automaticNeverCountsDownWithoutALiveCall() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        for now in stride(from: 0.0, through: 3.0, by: 1.0) {
            machine.handle(asEvidence(now, slots: [event], mode: .automatic, granted: true, consent: true))
        }
        #expect(machine.state == .prompting(meeting: ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event),
                                            deadline: 23))
        let tick = machine.handle(.tick(now: 8))
        #expect(tick.isEmpty)
        let late = machine.handle(.tick(now: 23))
        #expect(late == [.hideBanner])
        #expect(!late.contains { if case .startRecording = $0 { return true } else { return false } })
    }

    @Test func aCalendarMeetingIsOfferedAtItsStartWithNoCallAppOpen() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0)
        machine.handle(asEvidence(0, slots: [event]))
        let shown = machine.handle(asEvidence(3, slots: [event]))
        #expect(shown == [.showAsk(ScribeMeeting(key: "s1", title: "Design review", callApp: nil, slot: event))])
        var early = ScribeAutoStartMachine()
        let notYet = asSlot(start: 30)
        early.handle(asEvidence(0, present: [.teams], slots: [notYet]))
        #expect(early.handle(asEvidence(3, present: [.teams], slots: [notYet])).isEmpty)
        #expect(early.state == .idle)
    }

    @Test func anUnansweredCardDoesNotBlockTheAutomaticCountdown() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, slots: [event], mode: .automatic, granted: true, consent: true))
        machine.handle(asEvidence(3, slots: [event], mode: .automatic, granted: true, consent: true))
        machine.handle(.tick(now: 23))
        #expect(machine.state == .idle)
        let live = ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event, isLive: true)
        machine.handle(asEvidence(30, mic: [.teams], slots: [event], mode: .automatic, granted: true, consent: true))
        #expect(machine.state == .armed(meeting: live, since: 30))
        let counting = machine.handle(asEvidence(33, mic: [.teams], slots: [event], mode: .automatic, granted: true, consent: true))
        #expect(counting == [.showCountdown(live)])
        #expect(machine.state == .countingDown(meeting: live, deadline: 38))
    }

    @Test func anUnansweredCardInAskMeIsNotAskedAgainWhenTheCallBegins() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, slots: [event]))
        machine.handle(asEvidence(3, slots: [event]))
        machine.handle(.tick(now: 23))
        let live = machine.handle(asEvidence(30, mic: [.teams], slots: [event]))
        #expect(live.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func aDeclinedMeetingStaysQuietWhenItsSlotEndsAndTheCallContinues() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, mic: [.teams], slots: [event]))
        machine.handle(asEvidence(3, mic: [.teams], slots: [event]))
        machine.handle(.decline(now: 4))
        var effects: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 5.0, through: 600.0, by: 5.0) {
            effects += machine.handle(asEvidence(now, mic: [.teams], slots: [event]))
        }
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func aRecordingStartedWithoutALiveAppAdoptsTheAppWhenTheMeetingGoesLive() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, slots: [event]))
        machine.handle(asEvidence(3, slots: [event]))
        machine.handle(.accept(now: 4))
        guard case .recording(let before) = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
        #expect(before.meeting.isLive == false)
        machine.handle(asEvidence(10, mic: [.teams], slots: [event], activity: .recording))
        guard case .recording(let after) = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
        #expect(after.meeting == ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event, isLive: true))
        #expect(after.sawMic)
        machine.handle(asEvidence(11, slots: [event], activity: .recording))
        let ended = machine.handle(asEvidence(19, slots: [event], activity: .recording))
        #expect(ended == [.requestEnd(after.meeting)])
    }

    // MARK: First-use consent

    @Test func firstAutomaticStartAsksOnceAndRecordsTheConsent() {
        var machine = asPrompting(mode: .automatic, granted: true, consent: false)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23))
        let accept = machine.handle(.accept(now: 6))
        #expect(accept == [.hideBanner, .recordConsent, .startRecording(asTeams)])
    }

    @Test func theConsentCardShowsInsteadOfTheCountdown() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams], mode: .automatic, granted: true, consent: false))
        let shown = machine.handle(asEvidence(3, mic: [.teams], mode: .automatic, granted: true, consent: false))
        #expect(shown == [.showConsentAsk(asTeams)])
    }

    @Test func neverAutoRecordsBeforeConsentExistsEvenAfterTheDeadline() {
        var machine = asPrompting(mode: .automatic, granted: true, consent: false)
        let timeout = machine.handle(.tick(now: 23))
        #expect(timeout == [.hideBanner])
        #expect(!timeout.contains(.startRecording(asTeams)))
    }

    @Test func consentWithdrawnDuringTheCountdownAsksAgain() {
        var machine = asPrompting(mode: .automatic, granted: true, consent: true)
        machine.handle(asEvidence(5, mic: [.teams], mode: .automatic, granted: true, consent: false))
        let tick = machine.handle(.tick(now: 8))
        #expect(tick == [.showConsentAsk(asTeams)])
    }

    @Test func startingFromAskMeOrWithoutPermissionNeverRecordsTheConsent() {
        var ask = asPrompting(mode: .ask, granted: true, consent: false)
        let fromAsk = ask.handle(.accept(now: 6))
        #expect(fromAsk == [.hideBanner, .startRecording(asTeams)])
        var noPermission = asPrompting(mode: .automatic, granted: false, consent: false)
        let fromAuto = noPermission.handle(.accept(now: 6))
        #expect(fromAuto == [.hideBanner, .startRecording(asTeams)])
    }

    @Test func withConsentTheCountdownStartsWithoutRecordingItAgain() {
        var machine = asPrompting(mode: .automatic, granted: true, consent: true)
        let start = machine.handle(.tick(now: 8))
        #expect(start == [.hideBanner, .startRecording(asTeams)])
    }

    @Test func consentIsStoredAsATimestamp() throws {
        let name = "ScribeAutoStartConsent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!ScribeAutoStartConsent.isGiven(defaults: defaults))
        #expect(ScribeAutoStartConsent.consentDate(defaults: defaults) == nil)
        ScribeAutoStartConsent.record(at: Date(timeIntervalSince1970: 5_000), defaults: defaults)
        #expect(ScribeAutoStartConsent.isGiven(defaults: defaults))
        #expect(ScribeAutoStartConsent.consentDate(defaults: defaults) == Date(timeIntervalSince1970: 5_000))
    }

    // MARK: Auto-stop: Zoom breakouts, call window

    private func recordingZoom() -> ScribeAutoStartMachine {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.zoom]))
        machine.handle(asEvidence(3, mic: [.zoom]))
        machine.handle(.accept(now: 10))
        machine.handle(asEvidence(11, mic: [.zoom], activity: .recording))
        return machine
    }

    @Test func aZoomBreakoutHopDoesNotStopTheRecording() {
        var machine = recordingZoom()
        let release = machine.handle(asEvidence(12, activity: .recording))
        #expect(release.isEmpty)
        #expect(machine.needsFreshEvidence)
        let back = machine.handle(asEvidence(15, mic: [.zoom], activity: .recording))
        #expect(back.isEmpty)
        #expect(!machine.needsFreshEvidence)
        var later: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 16.0, through: 120.0, by: 1.0) {
            later += machine.handle(asEvidence(now, mic: [.zoom], activity: .recording))
        }
        #expect(later.isEmpty)
    }

    @Test func theEndTimerRunsOnlyWhileTheMicrophoneIsReleased() {
        var machine = asRecordingTeams()
        #expect(!machine.needsTick)
        machine.handle(asEvidence(12, activity: .recording))
        #expect(machine.needsTick)
        machine.handle(asEvidence(14, mic: [.teams], activity: .recording))
        #expect(!machine.needsTick)
    }

    @Test func aClosedCallWindowEndsTheCallEvenWhileTheMicrophoneIsStillHeld() {
        var machine = recordingZoom()
        machine.handle(asEvidence(12, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        let gone = machine.handle(asEvidence(13, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        #expect(gone.isEmpty)
        #expect(machine.needsFreshEvidence)
        let before = machine.handle(asEvidence(20, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        #expect(before.isEmpty)
        let ended = machine.handle(asEvidence(21, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        guard case .some(.requestEnd) = ended.first else {
            Issue.record("expected requestEnd, got \(ended)")
            return
        }
    }

    @Test func aWindowThatReturnsOrIsUnknownOrWasNeverSeenDoesNotEndTheCall() {
        var returns = recordingZoom()
        returns.handle(asEvidence(12, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        returns.handle(asEvidence(13, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        returns.handle(asEvidence(16, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        let afterReturn = returns.handle(asEvidence(40, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        #expect(afterReturn.isEmpty)

        var unknown = recordingZoom()
        unknown.handle(asEvidence(12, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        var effects: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 13.0, through: 100.0, by: 1.0) {
            effects += unknown.handle(asEvidence(now, mic: [.zoom], activity: .recording, windows: [:]))
        }
        #expect(effects.isEmpty)

        var neverSeen = recordingZoom()
        var never: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 12.0, through: 100.0, by: 1.0) {
            never += neverSeen.handle(asEvidence(now, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        }
        #expect(never.isEmpty)
    }

    @Test func callWindowTitlesAreJudgedOnlyWhenTheyCanBeTrusted() {
        #expect(ScribeCallWindow.state(app: .zoom, titles: ["Zoom Meeting"], complete: true) == .present)
        #expect(ScribeCallWindow.state(app: .zoom, titles: ["Zoom Workplace"], complete: true) == .gone)
        #expect(ScribeCallWindow.state(app: .zoom, titles: [], complete: true) == .gone)
        #expect(ScribeCallWindow.state(app: .zoom, titles: ["Zoom Workplace"], complete: false) == .unknown)
        #expect(ScribeCallWindow.state(app: .teams, titles: ["Chat | Microsoft Teams"], complete: true) == .unknown)
        #expect(ScribeCallWindow.state(app: .meet, titles: ["Meet \u{2013} abc-defg-hij"], complete: true) == .present)
        #expect(ScribeCallWindow.state(app: .other("Slack"), titles: ["Huddle with Ana"], complete: true) == .present)
        #expect(ScribeCallWindow.state(app: .other("Slack"), titles: ["general - Slack"], complete: true) == .gone)
        #expect(ScribeCallWindow.state(app: .other("FaceTime"), titles: [], complete: true) == .unknown)
    }

    // MARK: Next meeting

    @Test func aMeetingAboutToStartWhileRecordingIsOfferedOnce() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        let nextMeeting = ScribeMeeting(key: "n1", title: "Standup", callApp: .teams, slot: next)
        let offered = machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        #expect(offered == [.showNextMeeting(nextMeeting)])
        #expect(machine.bannerDeadline == 40)
        #expect(machine.needsTick)
        let again = machine.handle(asEvidence(25, mic: [.teams], slots: [next], activity: .recording))
        #expect(again.isEmpty)
        let keep = machine.handle(.decline(now: 26))
        #expect(keep == [.hideBanner])
        #expect(machine.bannerDeadline == nil)
        let afterKeep = machine.handle(asEvidence(30, mic: [.teams], slots: [next], activity: .recording))
        #expect(afterKeep.isEmpty)
    }

    @Test func theNextMeetingCardLeavesOnItsOwnAfterTwentySeconds() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        let early = machine.handle(.tick(now: 39))
        #expect(early.isEmpty)
        let gone = machine.handle(.tick(now: 40))
        #expect(gone == [.hideBanner])
        guard case .recording(let recording) = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
        #expect(recording.nextMeeting == nil)
    }

    @Test func notEveryCalendarEventIsOffered() {
        var machine = asRecordingTeams()
        let own = asSlot("call:Teams", start: 80)
        let noLink = asSlot("n2", start: 80, link: false)
        let tooFar = asSlot("n3", start: 20 + ScribeMeetingStartPolicy.nextLeadWindow + 60)
        let over = asSlot("n4", start: -100, end: 25)
        let effects = machine.handle(asEvidence(20, mic: [.teams], slots: [own, noLink, tooFar, over], activity: .recording))
        #expect(effects.isEmpty)
    }

    @Test func switchingEndsThisRecordingAndLetsTheNextMeetingStartAtOnce() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        let switchNow = machine.handle(.accept(now: 22))
        #expect(switchNow == [.hideBanner, .requestEnd(asTeams)])
        #expect(machine.state == .endingSuggested(meeting: asTeams, since: 22))
        let saved = machine.handle(asEvidence(40, mic: [.teams], slots: [next], activity: .idle))
        #expect(saved == [.hideBanner])
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .started)
        let nextMeeting = ScribeMeeting(key: "n1", title: "Standup", callApp: .teams, slot: next, isLive: true)
        #expect(machine.ledger.mark(of: nextMeeting) == .headsUp)
        let seen = machine.handle(asEvidence(41, mic: [.teams], slots: [next], activity: .idle))
        #expect(seen.isEmpty)
        let shown = machine.handle(asEvidence(44, mic: [.teams], slots: [next], activity: .idle))
        #expect(shown == [.showAsk(nextMeeting)])
    }

    @Test func theCallEndingTakesTheNextMeetingCardDown() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(12, slots: [], activity: .recording))
        machine.handle(asEvidence(14, slots: [next], activity: .recording))
        let ended = machine.handle(asEvidence(20, slots: [next], activity: .recording))
        #expect(ended == [.hideBanner, .requestEnd(asTeams)])
    }

    @Test func theNextMeetingCardNeedsARecording() {
        var machine = ScribeAutoStartMachine()
        let accept = machine.handle(.accept(now: 1))
        let decline = machine.handle(.decline(now: 2))
        #expect(accept.isEmpty)
        #expect(decline.isEmpty)
        var recording = asRecordingTeams()
        let noCard = recording.handle(.accept(now: 30))
        #expect(noCard.isEmpty)
    }

    @Test func aDeclinedNextMeetingStaysQuietWhenTheRecordingEnds() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        machine.handle(.decline(now: 26))
        machine.handle(asEvidence(40, mic: [.teams], slots: [next], activity: .idle))
        var effects: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 45.0, through: 200.0, by: 5.0) {
            effects += machine.handle(asEvidence(now, mic: [.teams], slots: [next], activity: .idle))
        }
        #expect(effects.isEmpty)
    }

    @Test func newBannerWordingIsPlain() {
        let next = ScribeMeeting(key: "n1", title: "Standup", callApp: .teams)
        #expect(ScribeAutoStartText.nextMeetingHeadline(next) == "Next meeting: Standup is starting. Switch notes to it?")
        for text in [ScribeAutoStartText.nextMeetingDetail, ScribeAutoStartText.consentDetail,
                     ScribeAutoStartText.nextMeetingHeadline(next)] {
            #expect(!text.contains("\u{2014}"))
        }
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
        #expect(ScribeAutoStartText.askHeadline(asTeams) == "Meeting started: Call. Take notes?")
        #expect(ScribeAutoStartText.countdownHeadline(asTeams, seconds: 3) == "Meeting started: Call. Taking notes in 3.")
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

    // MARK: A tap is never lost

    @Test func askMeNeverTimesOutUnderThePointer() {
        var machine = asPrompting()
        machine.handle(.pointer(inside: true, now: 15))
        let held = machine.handle(.tick(now: 40))
        #expect(held.isEmpty)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23))
        let start = machine.handle(.accept(now: 41))
        #expect(start == [.hideBanner, .startRecording(asTeams)])
    }

    @Test func leavingTheBannerGivesAShortGraceThenItTimesOut() {
        var machine = asPrompting()
        machine.handle(.pointer(inside: true, now: 15))
        machine.handle(.pointer(inside: false, now: 30))
        let grace = machine.handle(.tick(now: 33))
        #expect(grace.isEmpty)
        let gone = machine.handle(.tick(now: 34))
        #expect(gone == [.hideBanner])
    }

    @Test func aTapThatArrivesJustAfterTheTimeoutStillStarts() {
        var machine = asPrompting()
        machine.handle(.tick(now: 23))
        let late = machine.handle(.accept(now: 23.1))
        #expect(late.isEmpty)
        let start = machine.handle(.startNow(asTeams, now: 23.1))
        #expect(start == [.hideBanner, .startRecording(asTeams)])
        let isRecording: Bool
        if case .recording = machine.state { isRecording = true } else { isRecording = false }
        #expect(isRecording)
    }

    @Test func startNowWhilePromptingIsTheSameAsAccept() {
        var machine = asPrompting()
        let start = machine.handle(.startNow(asTeams, now: 5))
        #expect(start == [.hideBanner, .startRecording(asTeams)])
    }

    @Test func startNowNeverStartsASecondRecording() {
        var machine = asRecordingTeams()
        let effects = machine.handle(.startNow(asTeams, now: 12))
        #expect(effects.isEmpty)
    }

    @Test func aFreshBannerIsNotHeldByAPointerFromTheLastOne() {
        var machine = asPrompting()
        machine.handle(.pointer(inside: true, now: 4))
        machine.handle(.decline(now: 5))
        machine.handle(asEvidence(70, mic: [.zoom]))
        machine.handle(asEvidence(73, mic: [.zoom]))
        #expect(!machine.pointerInside)
        let gone = machine.handle(.tick(now: 93))
        #expect(gone == [.hideBanner])
    }
}
