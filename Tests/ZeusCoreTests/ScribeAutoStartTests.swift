import Foundation
import Testing
@testable import ZeusCore

private let asBase = Date(timeIntervalSince1970: 1_000_000)

private func asSlot(_ id: String = "s1", title: String = "Design review", start: TimeInterval = 0,
                  end: TimeInterval? = nil, link: Bool = true, app: ScribeCallApp? = nil) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: id, title: title, start: asBase.addingTimeInterval(start),
                       end: end.map { asBase.addingTimeInterval($0) }, hasCallLink: link, callApp: app)
}

private let asSession = ScribeSessionID()

private func asPhase(_ activity: ScribeActivity) -> ScribePhase {
    switch activity {
    case .idle: return .idle
    case .starting: return .starting(asSession)
    case .recording: return .recording(asSession, since: 0)
    case .ending: return .ending(asSession, deadline: 0)
    case .processing: return .processing(asSession)
    }
}

private func asContext(_ activity: ScribeActivity = .idle, ready: ScribeAutoStartReadiness = .ready) -> ScribeStartContext {
    ScribeStartContext(scribe: asPhase(activity), microphone: .allowed, automatic: ready)
}

private func asEvidence(
    _ now: TimeInterval, mic: [ScribeCallApp] = [], present: [ScribeCallApp] = [], slots: [ScribeCalendarSlot] = [],
    mode: ScribeAutoStartMode = .ask, ready: ScribeAutoStartReadiness? = nil, activity: ScribeActivity = .idle,
    windows: [ScribeCallApp: ScribeCallWindowState] = [:]
) -> ScribeAutoStartMachine.Event {
    // Without an explicit answer, automatic is fully ready and every other choice is simply not chosen.
    let automatic = ready ?? (mode == .automatic ? .ready : .blocked(.notChosen))
    return .evidence(ScribeMeetingEvidence(date: asBase.addingTimeInterval(now), slots: slots, micApps: mic, presentApps: present,
                                           mode: mode, context: asContext(activity, ready: automatic),
                                           callWindows: windows), now: now)
}

private func asTick(_ now: TimeInterval, activity: ScribeActivity = .idle,
                    ready: ScribeAutoStartReadiness = .ready) -> ScribeAutoStartMachine.Event {
    .tick(now: now, context: asContext(activity, ready: ready))
}

private func asTap(_ card: ScribeMeetingCard, _ now: TimeInterval, activity: ScribeActivity = .idle) -> ScribeAutoStartMachine.Event {
    .primary(on: card, now: now, context: asContext(activity))
}

private let asTeams = ScribeMeeting(key: "call:Teams", title: "Call", callApp: .teams, isLive: true)

private func asOffer(_ meeting: ScribeMeeting = asTeams) -> ScribeMeetingCard { .offer(meeting, blocked: nil) }

/// The card Cancel is tapped on during a countdown.
private func asCountdownCard(_ meeting: ScribeMeeting = asTeams) -> ScribeMeetingCard {
    .countdown(meeting, seconds: 5, deadline: 0, total: 5)
}

/// Whether the effects hold a start.
private func asStarts(_ effects: [ScribeAutoStartMachine.Effect]) -> Bool {
    effects.contains { if case .start = $0 { return true } else { return false } }
}

/// A machine whose Teams call has been seen at 0 and again at 3, so the "Ask me" card is up.
private func asPrompting(mode: ScribeAutoStartMode = .ask, ready: ScribeAutoStartReadiness? = nil) -> ScribeAutoStartMachine {
    var machine = ScribeAutoStartMachine()
    machine.handle(asEvidence(0, mic: [.teams], mode: mode, ready: ready))
    machine.handle(asEvidence(3, mic: [.teams], mode: mode, ready: ready))
    return machine
}

/// A machine recording a Teams call, started by a tap at 9, with the call app seen holding the microphone at 11.
private func asRecordingTeams() -> ScribeAutoStartMachine {
    var machine = asPrompting()
    machine.handle(asTap(asOffer(), 9))
    machine.handle(.scribe(.recording(asSession, since: 9), now: 9))
    machine.handle(asEvidence(11, mic: [.teams], activity: .recording))
    return machine
}

/// The heads-up meeting for a slot that has not started: no call has begun, so it is not live.
private func asHeadsUp(_ slot: ScribeCalendarSlot) -> ScribeMeeting {
    ScribeMeeting(key: slot.id, title: slot.title, callApp: slot.callApp, slot: slot)
}

/// The same slot once a call app holds the microphone for it.
private func asLive(_ slot: ScribeCalendarSlot) -> ScribeMeeting {
    ScribeMeeting(key: slot.id, title: slot.title, callApp: slot.callApp, slot: slot, isLive: true)
}

private func asIsCountingDown(_ state: ScribeAutoStartState) -> Bool {
    if case .countingDown = state { return true }
    return false
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
        let name = "app.zeus.tests.ScribeAutoStart.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removeObject(forKey: FeatureSettings.key(ScribeAutoStartMode.settingID)) }
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
        #expect(third.isEmpty)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23, blocked: .notChosen))
        #expect(machine.card(now: 3) == .offer(asTeams, blocked: .notChosen))
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
        #expect(ready.isEmpty)
        #expect(machine.card(now: 5) == .offer(asTeams, blocked: .notChosen))
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
        let tick = machine.handle(asTick(100))
        #expect(tick.isEmpty)
        #expect(machine.state == .armed(meeting: asTeams, since: 0))
        #expect(machine.nextWake(now: 100) == nil)
    }

    @Test func zeroDebounceShowsOnTheFirstSighting() {
        var machine = ScribeAutoStartMachine(timing: ScribeAutoStartTiming(debounce: 0))
        let effects = machine.handle(asEvidence(0, mic: [.teams]))
        #expect(effects.isEmpty)
        #expect(machine.card(now: 0) == .offer(asTeams, blocked: .notChosen))
    }

    @Test func oneMeetingTriggersOnlyOnceHoweverLongTheSignalLasts() {
        var machine = asPrompting()
        machine.handle(.dismiss(on: asOffer(), now: 5))
        var shown = 0
        var now: TimeInterval = 6
        while now < 600 {
            machine.handle(asEvidence(now, mic: [.teams]))
            if machine.card(now: now) != .hidden { shown += 1 }
            now += 5
        }
        #expect(shown == 0)
    }

    @Test func aFlickerOfTheMicrophoneDoesNotMakeANewMeeting() {
        var machine = asPrompting()
        machine.handle(.dismiss(on: asOffer(), now: 5))
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
        #expect(machine.state == .prompting(meeting: meet, deadline: 23, blocked: .notChosen))
        machine.handle(.dismiss(on: asOffer(meet), now: 5))
        // Another tab is in front: the Meet title is read from neither list.
        machine.handle(asEvidence(10))
        machine.handle(asEvidence(20))
        var shown = 0
        var now: TimeInterval = 23
        while now < 120 {
            machine.handle(asEvidence(now, mic: [.meet], present: [.meet]))
            if machine.card(now: now) != .hidden { shown += 1 }
            now += 3
        }
        #expect(shown == 0)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: meet) == .declined)
    }

    @Test func anUnansweredCallStaysQuietWhenItsCalendarWindowOpensAndTheMicrophoneIsMuted() {
        var machine = asPrompting()
        machine.handle(asTick(23))
        #expect(machine.state == .idle)
        let slot = asSlot("s1", start: 150, end: 1_800, app: .teams)
        let opened = machine.handle(asEvidence(40, mic: [.teams], present: [.teams], slots: [slot]))
        #expect(opened.isEmpty)
        // Muted for longer than the call entry lives: the slot still remembers the question.
        machine.handle(asEvidence(45, present: [.teams], slots: [slot]))
        machine.handle(asEvidence(75, present: [.teams], slots: [slot]))
        var shown = 0
        for now in stride(from: 80.0, through: 120.0, by: 3.0) {
            machine.handle(asEvidence(now, mic: [.teams], present: [.teams], slots: [slot]))
            if machine.card(now: now) != .hidden { shown += 1 }
        }
        #expect(shown == 0)
        #expect(machine.state == .idle)
    }

    // MARK: Ask me

    @Test func askMeStartsWhenTheBannerIsAccepted() {
        var machine = asPrompting()
        let effects = machine.handle(asTap(asOffer(), 8))
        #expect(effects == [.start(asTeams)])
        #expect(machine.state == .starting(ScribeStartAttempt(meeting: asTeams, since: 8, origin: .tap,
                                                              previousSession: nil, session: nil)))
    }

    @Test func notNowHidesTheBannerAndStaysQuiet() {
        var machine = asPrompting()
        let effects = machine.handle(.dismiss(on: asOffer(), now: 8))
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .declined)
    }

    @Test func theAskBannerLeavesAfterTwentySecondsAndCountsAsNotNow() {
        var machine = asPrompting()
        let early = machine.handle(asTick(22.9))
        #expect(early.isEmpty)
        #expect(machine.nextWake(now: 22.9) == 23)
        let timeout = machine.handle(asTick(23))
        #expect(timeout.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .asked)
        #expect(machine.nextWake(now: 23) == nil)
        let again = machine.handle(asEvidence(30, mic: [.teams]))
        #expect(again.isEmpty)
    }

    @Test func theAskBannerSurvivesTheCallAppReleasingTheMicrophone() {
        var machine = asPrompting()
        let muted = machine.handle(asEvidence(8))
        #expect(muted.isEmpty)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23, blocked: .notChosen))
    }

    @Test func offNeverShowsAnythingAndTurningItOffHidesTheBanner() {
        var off = ScribeAutoStartMachine()
        off.handle(asEvidence(0, mic: [.teams], mode: .off))
        let none = off.handle(asEvidence(10, mic: [.teams], mode: .off))
        #expect(none.isEmpty)
        #expect(off.state == .idle)

        var machine = asPrompting()
        let hidden = machine.handle(asEvidence(8, mic: [.teams], mode: .off))
        #expect(hidden.isEmpty)
        #expect(machine.card(now: 8) == .hidden)
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
        var machine = asPrompting(mode: .automatic)
        #expect(machine.state == .countingDown(meeting: asTeams, deadline: 8))
        let early = machine.handle(asTick(7))
        #expect(early.isEmpty)
        let start = machine.handle(asTick(8))
        #expect(start == [.start(asTeams)])
        guard case .starting = machine.state else {
            Issue.record("expected starting, got \(machine.state)")
            return
        }
    }

    @Test func cancelDuringTheCountdownNeverStarts() {
        var machine = asPrompting(mode: .automatic)
        let cancel = machine.handle(.cancel(on: asCountdownCard(), now: 5))
        #expect(cancel.isEmpty)
        let later = machine.handle(asTick(60))
        #expect(later.isEmpty)
        let evidenceLater = machine.handle(asEvidence(70, mic: [.teams], mode: .automatic))
        #expect(evidenceLater.isEmpty)
    }

    @Test func aTapDuringTheCountdownIsIgnored() {
        var machine = asPrompting(mode: .automatic)
        let effects = machine.handle(asTap(asOffer(), 5))
        #expect(effects.isEmpty)
        #expect(machine.state == .countingDown(meeting: asTeams, deadline: 8))
    }

    @Test func automaticWithoutMicrophonePermissionAsksInstead() {
        let machine = asPrompting(mode: .automatic, ready: .blocked(.microphoneNotAsked))
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23, blocked: .microphoneNotAsked))
    }

    @Test func automaticNeverStartsWithoutPermissionEvenAfterTheDeadline() {
        var machine = asPrompting(mode: .automatic, ready: .blocked(.microphoneNotAsked))
        let tick = machine.handle(asTick(23))
        #expect(tick.isEmpty)
        #expect(!asStarts(tick))
    }

    @Test func permissionWithdrawnDuringTheCountdownFallsBackToAskingAtOnce() {
        var machine = asPrompting(mode: .automatic)
        let effects = machine.handle(asEvidence(5, mic: [.teams], mode: .automatic, ready: .blocked(.microphoneNotAsked)))
        #expect(effects.isEmpty)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 25, blocked: .microphoneNotAsked))
        #expect(machine.handle(asTick(8)).isEmpty)
    }

    @Test func startingRecordingByHandWhileTheBannerIsUpHidesIt() {
        var machine = asPrompting()
        let effects = machine.handle(asEvidence(6, mic: [.teams], activity: .starting))
        #expect(effects.isEmpty)
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
        #expect(ended == [.suggestEnd(asTeams)])
        guard case .recording(let recording) = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
        #expect(recording.endSuggested)
        #expect(recording.meeting == asTeams)
    }

    @Test func noEndIsSuggestedBeforeTheCallAppEverHeldTheMicrophone() {
        var machine = asPrompting()
        machine.handle(asTap(asOffer(), 10))
        machine.handle(.scribe(.recording(asSession, since: 10), now: 10))
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
        #expect(thirty == [.suggestEnd(asTeams)])
    }

    @Test func anotherAppHoldingTheMicrophoneDoesNotKeepTheCallAlive() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, mic: [.zoom], activity: .recording))
        let ended = machine.handle(asEvidence(20, mic: [.zoom], activity: .recording))
        #expect(ended == [.suggestEnd(asTeams)])
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
        #expect(saved.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .started)
    }

    @Test func keepRecordingReturnsToRecordingAndWaitsForTheCallToReturn() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        let suggested = machine.handle(asEvidence(20, activity: .recording))
        #expect(suggested == [.suggestEnd(asTeams)])
        // Keep recording leaves the phase alone, so the machine hears nothing: it stays quiet while the signal lasts.
        var quiet: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 21.0, through: 400.0, by: 10.0) { quiet += machine.handle(asEvidence(now, activity: .recording)) }
        #expect(quiet.isEmpty)
        let back = machine.handle(asEvidence(410, mic: [.teams], activity: .recording))
        #expect(back == [.withdrawEnd])
        machine.handle(asEvidence(415, activity: .recording))
        let again = machine.handle(asEvidence(423, activity: .recording))
        #expect(again == [.suggestEnd(asTeams)])
    }

    @Test func stoppingByHandReturnsToIdle() {
        var machine = asPrompting()
        machine.handle(asTap(asOffer(), 10))
        machine.handle(.scribe(.recording(asSession, since: 10), now: 10))
        let after = machine.handle(asEvidence(15, activity: .idle))
        #expect(after.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .started)
    }

    // MARK: Ledger

    @Test func theSameCallStaysQuietUntilItHasBeenGoneAWhile() {
        var machine = asPrompting()
        machine.handle(.dismiss(on: asOffer(), now: 5))
        machine.handle(asEvidence(10, present: [.teams]))
        machine.handle(asEvidence(41, present: [.teams]))
        let back = machine.handle(asEvidence(70, mic: [.teams], present: [.teams]))
        #expect(back.isEmpty)
        #expect(machine.state == .armed(meeting: asTeams, since: 70))
        let shown = machine.handle(asEvidence(73, mic: [.teams], present: [.teams]))
        #expect(shown.isEmpty)
        #expect(machine.card(now: 73) == .offer(asTeams, blocked: .notChosen))
    }

    @Test func aDifferentMeetingArmsWithoutWaiting() {
        var machine = asPrompting()
        machine.handle(.dismiss(on: asOffer(), now: 5))
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)
        let early = machine.handle(asEvidence(6, mic: [.zoom]))
        #expect(early.isEmpty)
        #expect(machine.state == .armed(meeting: zoom, since: 6))
        let shown = machine.handle(asEvidence(9, mic: [.zoom]))
        #expect(shown.isEmpty)
        #expect(machine.card(now: 9) == .offer(zoom, blocked: .notChosen))
    }

    @Test func anAnsweredMeetingIsNeverArmedAgain() {
        var machine = asPrompting()
        machine.handle(.dismiss(on: asOffer(), now: 5))
        let effects = machine.handle(asEvidence(6, mic: [.teams]))
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func automaticNeverCountsDownWithoutALiveCall() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        for now in stride(from: 0.0, through: 3.0, by: 1.0) {
            machine.handle(asEvidence(now, present: [.teams], slots: [event], mode: .automatic))
        }
        #expect(machine.state == .prompting(meeting: ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event),
                                            deadline: 23, blocked: nil))
        let tick = machine.handle(asTick(8))
        #expect(tick.isEmpty)
        let late = machine.handle(asTick(23))
        #expect(late.isEmpty)
        #expect(!asStarts(late))
    }

    @Test func aCalendarMeetingIsOfferedAtItsStartWithNoCallAppOpen() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0)
        machine.handle(asEvidence(0, slots: [event]))
        let shown = machine.handle(asEvidence(3, slots: [event]))
        #expect(shown.isEmpty)
        #expect(machine.card(now: 3) == .offer(ScribeMeeting(key: "s1", title: "Design review", callApp: nil, slot: event),
                                               blocked: .notChosen))
        var early = ScribeAutoStartMachine()
        let notYet = asSlot(start: 30)
        early.handle(asEvidence(0, present: [.teams], slots: [notYet]))
        #expect(early.handle(asEvidence(3, present: [.teams], slots: [notYet])).isEmpty)
        // Before the start there is only the heads-up: it is never the start-time offer or a countdown.
        #expect(early.state == .upcoming(meeting: ScribeMeeting(key: "s1", title: "Design review", callApp: nil, slot: notYet),
                                         deadline: 20))
    }

    @Test func anUnansweredCardDoesNotBlockTheAutomaticCountdown() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, slots: [event], mode: .automatic))
        machine.handle(asEvidence(3, slots: [event], mode: .automatic))
        machine.handle(asTick(23))
        #expect(machine.state == .idle)
        let live = ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event, isLive: true)
        machine.handle(asEvidence(30, mic: [.teams], slots: [event], mode: .automatic))
        #expect(machine.state == .armed(meeting: live, since: 30))
        let counting = machine.handle(asEvidence(33, mic: [.teams], slots: [event], mode: .automatic))
        #expect(counting.isEmpty)
        #expect(machine.state == .countingDown(meeting: live, deadline: 38))
    }

    @Test func anUnansweredCardInAskMeIsNotAskedAgainWhenTheCallBegins() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, slots: [event]))
        machine.handle(asEvidence(3, slots: [event]))
        machine.handle(asTick(23))
        let live = machine.handle(asEvidence(30, mic: [.teams], slots: [event]))
        #expect(live.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func aDeclinedMeetingStaysQuietWhenItsSlotEndsAndTheCallContinues() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, mic: [.teams], slots: [event]))
        machine.handle(asEvidence(3, mic: [.teams], slots: [event]))
        machine.handle(.dismiss(on: asOffer(ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event,
                                                         isLive: true)), now: 4))
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
        machine.handle(asTap(asOffer(ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event)), 4))
        machine.handle(.scribe(.recording(asSession, since: 4), now: 4))
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
        #expect(ended == [.suggestEnd(after.meeting)])
    }

    // MARK: Readiness for an automatic start

    @Test func everyBlockAsksAndNeverCountsDown() {
        for block in ScribeAutoStartBlock.allCases {
            var machine = ScribeAutoStartMachine()
            machine.handle(asEvidence(0, mic: [.teams], mode: .automatic, ready: .blocked(block)))
            let shown = machine.handle(asEvidence(3, mic: [.teams], mode: .automatic, ready: .blocked(block)))
            #expect(shown.isEmpty, "\(block)")
            #expect(machine.state == .prompting(meeting: asTeams, deadline: 23, blocked: block), "\(block)")
            let timeout = machine.handle(asTick(23))
            #expect(timeout.isEmpty, "\(block)")
            #expect(!asStarts(timeout), "\(block)")
        }
    }

    @Test func aBlockedMachineStartsOnlyOnATap() {
        var machine = asPrompting(mode: .automatic, ready: .blocked(.firstRecordingOwed))
        let tap = machine.handle(asTap(.offer(asTeams, blocked: .firstRecordingOwed), 6))
        #expect(tap == [.start(asTeams)])
    }

    @Test func readyCountsDownOnTheFirstLiveMeeting() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams], mode: .automatic, ready: .ready))
        let shown = machine.handle(asEvidence(3, mic: [.teams], mode: .automatic, ready: .ready))
        #expect(shown.isEmpty)
        #expect(machine.state == .countingDown(meeting: asTeams, deadline: 8))
    }

    @Test func readyWithoutALiveCallStillAsks() {
        var machine = ScribeAutoStartMachine()
        let event = asSlot(start: 0, app: .teams)
        machine.handle(asEvidence(0, present: [.teams], slots: [event], mode: .automatic, ready: .ready))
        let shown = machine.handle(asEvidence(3, present: [.teams], slots: [event], mode: .automatic, ready: .ready))
        let meeting = ScribeMeeting(key: "s1", title: "Design review", callApp: .teams, slot: event)
        #expect(shown.isEmpty)
        #expect(machine.card(now: 3) == .offer(meeting, blocked: nil))
    }

    @Test func readyIsNotEnoughWhenTheChoiceIsNotAutomatic() {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.teams], mode: .ask, ready: .ready))
        let shown = machine.handle(asEvidence(3, mic: [.teams], mode: .ask, ready: .ready))
        #expect(shown.isEmpty)
        #expect(machine.card(now: 3) == .offer(asTeams, blocked: nil))
    }

    @Test func leavingAutomaticDuringTheCountdownAsksInstead() {
        var toAsk = asPrompting(mode: .automatic)
        #expect(toAsk.state == .countingDown(meeting: asTeams, deadline: 8))
        let asked = toAsk.handle(asEvidence(6, mic: [.teams], mode: .ask))
        #expect(asked.isEmpty)
        #expect(toAsk.state == .prompting(meeting: asTeams, deadline: 26, blocked: .notChosen))
        let later = toAsk.handle(asTick(8))
        #expect(later.isEmpty)

        var toOff = asPrompting(mode: .automatic)
        let hidden = toOff.handle(asEvidence(6, mic: [.teams], mode: .off))
        #expect(hidden.isEmpty)
        #expect(toOff.state == .idle)
        #expect(toOff.handle(asTick(8)).isEmpty)
    }

    @Test func readinessLostAtTheEndOfTheCountdownAsksInsteadOfStarting() {
        var machine = asPrompting(mode: .automatic)
        let effects = machine.handle(asEvidence(8, mic: [.teams], mode: .automatic, ready: .blocked(.microphoneDenied)))
        #expect(effects.isEmpty)
        #expect(machine.card(now: 8) == .offer(asTeams, blocked: .microphoneDenied))
        var stillReady = asPrompting(mode: .automatic)
        let start = stillReady.handle(asEvidence(8, mic: [.teams], mode: .automatic, ready: .ready))
        #expect(start == [.start(asTeams)])
    }

    @Test func aCallThatEndsDuringTheCountdownAsksInsteadOfStarting() {
        var machine = asPrompting(mode: .automatic)
        let effects = machine.handle(asEvidence(6, present: [.teams], mode: .automatic))
        #expect(effects.isEmpty)
        #expect(machine.card(now: 6) == .offer(asTeams, blocked: nil))
        #expect(machine.handle(asTick(8)).isEmpty)
    }

    @Test func acceptingNeverAddsAnythingForTheOptIn() {
        var machine = asPrompting(mode: .automatic, ready: .blocked(.noOptIn))
        #expect(machine.handle(asTap(.offer(asTeams, blocked: .noOptIn), 6)) == [.start(asTeams)])
    }

    // MARK: Auto-stop: Zoom breakouts, call window

    private func recordingZoom() -> ScribeAutoStartMachine {
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, mic: [.zoom]))
        machine.handle(asEvidence(3, mic: [.zoom]))
        machine.handle(asTap(asOffer(ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)), 10))
        machine.handle(.scribe(.recording(asSession, since: 10), now: 10))
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
        #expect(machine.nextWake(now: 11) == nil)
        machine.handle(asEvidence(12, activity: .recording))
        #expect(machine.nextWake(now: 12) == 13)
        machine.handle(asEvidence(14, mic: [.teams], activity: .recording))
        #expect(machine.nextWake(now: 14) == nil)
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
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)
        #expect(ended == [.suggestEnd(zoom)])
    }

    @Test func microphoneReleaseSuggestsAnEndAndNeverRequestsOne() {
        var machine = asRecordingTeams()
        var all: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 12.0, through: 3_600.0, by: 1.0) {
            all += machine.handle(asEvidence(now, activity: .recording))
        }
        #expect(all == [.suggestEnd(asTeams)])
        #expect(!all.contains(.endNow))
    }

    @Test func aClosedCallWindowSuggestsAnEndAndNeverRequestsOne() {
        var machine = recordingZoom()
        machine.handle(asEvidence(12, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        var all: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 13.0, through: 600.0, by: 1.0) {
            all += machine.handle(asEvidence(now, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        }
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)
        #expect(all == [.suggestEnd(zoom)])
    }

    @Test func theMicrophoneComingBackWithdrawsTheSuggestion() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        let suggested = machine.handle(asEvidence(20, activity: .recording))
        #expect(suggested == [.suggestEnd(asTeams)])
        #expect(machine.needsFreshEvidence)
        let back = machine.handle(asEvidence(22, mic: [.teams], activity: .recording))
        #expect(back == [.withdrawEnd])
        guard case .recording(let recording) = machine.state else {
            Issue.record("expected recording, got \(machine.state)")
            return
        }
        #expect(!recording.endSuggested)
        #expect(!machine.needsFreshEvidence)
        let quiet = machine.handle(asEvidence(23, mic: [.teams], activity: .recording))
        #expect(quiet.isEmpty)
    }

    @Test func aSuggestionStaysWhileTheWindowIsStillGoneEvenIfTheMicrophoneIsHeld() {
        var machine = recordingZoom()
        machine.handle(asEvidence(12, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        machine.handle(asEvidence(13, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        let suggested = machine.handle(asEvidence(21, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        #expect(suggested.count == 1)
        let held = machine.handle(asEvidence(22, mic: [.zoom], activity: .recording, windows: [.zoom: .gone]))
        #expect(held.isEmpty)
        let back = machine.handle(asEvidence(23, mic: [.zoom], activity: .recording, windows: [.zoom: .present]))
        #expect(back == [.withdrawEnd])
    }

    @Test func aSuggestionIsMadeOnceWhileTheSignalLasts() {
        var machine = asRecordingTeams()
        machine.handle(asEvidence(12, activity: .recording))
        let first = machine.handle(asEvidence(20, activity: .recording))
        let second = machine.handle(asEvidence(21, activity: .recording))
        let third = machine.handle(asEvidence(90, activity: .recording))
        #expect(first == [.suggestEnd(asTeams)])
        #expect(second.isEmpty)
        #expect(third.isEmpty)
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
        #expect(offered.isEmpty)
        #expect(machine.card(now: 20) == .next(nextMeeting))
        #expect(machine.nextWake(now: 20) == 40)
        let again = machine.handle(asEvidence(25, mic: [.teams], slots: [next], activity: .recording))
        #expect(again.isEmpty)
        let keep = machine.handle(.dismiss(on: .next(nextMeeting), now: 26))
        #expect(keep.isEmpty)
        #expect(machine.card(now: 26) == .hidden)
        let afterKeep = machine.handle(asEvidence(30, mic: [.teams], slots: [next], activity: .recording))
        #expect(afterKeep.isEmpty)
    }

    @Test func theNextMeetingCardLeavesOnItsOwnAfterTwentySeconds() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        let early = machine.handle(asTick(39))
        #expect(early.isEmpty)
        let gone = machine.handle(asTick(40))
        #expect(gone.isEmpty)
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

    @Test func switchEndsTheRecordingAtOnceAndNeverSuggestsAnEnd() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        let nextMeeting = ScribeMeeting(key: "n1", title: "Standup", callApp: .teams, slot: next)
        let switchNow = machine.handle(.primary(on: .next(nextMeeting), now: 22, context: asContext(.recording)))
        #expect(switchNow == [.endNow])
        #expect(!switchNow.contains(.suggestEnd(asTeams)))
        #expect(machine.state == .held(meeting: nextMeeting, startOwed: true))
    }

    @Test func theCallEndingTakesTheNextMeetingCardDown() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(12, slots: [], activity: .recording))
        machine.handle(asEvidence(14, slots: [next], activity: .recording))
        let ended = machine.handle(asEvidence(20, slots: [next], activity: .recording))
        #expect(ended == [.suggestEnd(asTeams)])
        #expect(machine.card(now: 20) == .hidden)
    }

    @Test func theNextMeetingCardNeedsARecording() {
        let standup = ScribeMeeting(key: "n1", title: "Standup", callApp: .teams)
        var machine = ScribeAutoStartMachine()
        let switchNow = machine.handle(.primary(on: .next(standup), now: 1, context: asContext()))
        let keep = machine.handle(.dismiss(on: .next(standup), now: 2))
        #expect(switchNow.isEmpty)
        #expect(keep.isEmpty)
        var recording = asRecordingTeams()
        let noCard = recording.handle(.primary(on: .next(standup), now: 30, context: asContext(.recording)))
        #expect(noCard.isEmpty)
    }

    @Test func aDeclinedNextMeetingStaysQuietWhenTheRecordingEnds() {
        var machine = asRecordingTeams()
        let next = asSlot("n1", title: "Standup", start: 80)
        machine.handle(asEvidence(20, mic: [.teams], slots: [next], activity: .recording))
        machine.handle(.dismiss(on: .next(ScribeMeeting(key: "n1", title: "Standup", callApp: .teams, slot: next)), now: 26))
        machine.handle(asEvidence(40, mic: [.teams], slots: [next], activity: .idle))
        var effects: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 45.0, through: 200.0, by: 5.0) {
            effects += machine.handle(asEvidence(now, mic: [.teams], slots: [next], activity: .idle))
        }
        #expect(effects.isEmpty)
    }

    // MARK: Banner

    @Test func cancelAndDismissDoNothingOutsideACard() {
        var machine = ScribeAutoStartMachine()
        let cancel = machine.handle(.cancel(on: asCountdownCard(), now: 1))
        let dismiss = machine.handle(.dismiss(on: .failed(asTeams, .noResponse), now: 2))
        #expect(cancel.isEmpty)
        #expect(dismiss.isEmpty)
        #expect(machine.state == .idle)
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
        let held = machine.handle(asTick(40))
        #expect(held.isEmpty)
        #expect(machine.state == .prompting(meeting: asTeams, deadline: 23, blocked: .notChosen))
        let start = machine.handle(asTap(asOffer(), 41))
        #expect(start == [.start(asTeams)])
    }

    @Test func leavingTheBannerGivesAShortGraceThenItTimesOut() {
        var machine = asPrompting()
        machine.handle(.pointer(inside: true, now: 15))
        machine.handle(.pointer(inside: false, now: 30))
        let grace = machine.handle(asTick(33))
        #expect(grace.isEmpty)
        let gone = machine.handle(asTick(34))
        #expect(gone.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func aTapThatArrivesJustAfterTheTimeoutStillStarts() {
        var machine = asPrompting()
        machine.handle(asTick(23))
        #expect(machine.state == .idle)
        let start = machine.handle(asTap(asOffer(), 23.1))
        #expect(start == [.start(asTeams)])
        guard case .starting = machine.state else {
            Issue.record("expected starting, got \(machine.state)")
            return
        }
    }

    @Test func aTapNeverStartsASecondRecording() {
        var machine = asRecordingTeams()
        let effects = machine.handle(asTap(asOffer(), 12, activity: .recording))
        #expect(effects.isEmpty)
    }

    @Test func aNotNowTapThatArrivesJustAfterTheTimeoutIsStillAnAnswer() {
        var machine = asPrompting()
        machine.handle(asTick(23))
        #expect(machine.ledger.mark(of: asTeams) == .asked)
        let effects = machine.handle(.dismiss(on: asOffer(), now: 23.1))
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: asTeams) == .declined)
        let later = machine.handle(asEvidence(30, mic: [.teams], mode: .automatic))
        #expect(later.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func aLateNotNowTapForAnotherMeetingLeavesTheArmedOneArmed() {
        var machine = asPrompting()
        machine.handle(asTick(23))
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)
        machine.handle(asEvidence(24, mic: [.zoom]))
        #expect(machine.state == .armed(meeting: zoom, since: 24))
        let effects = machine.handle(.dismiss(on: asOffer(), now: 24.1))
        #expect(effects.isEmpty)
        #expect(machine.state == .armed(meeting: zoom, since: 24))
        #expect(machine.ledger.mark(of: asTeams) == .declined)
        #expect(machine.ledger.mark(of: zoom) == nil)
    }

    @Test func aLateNotNowNeverAnswersAMeetingWhileScribeRecordsIt() {
        var machine = asRecordingTeams()
        let effects = machine.handle(.dismiss(on: asOffer(), now: 12))
        #expect(effects.isEmpty)
        #expect(machine.ledger.mark(of: asTeams) == .started)
    }

    @Test func aFreshBannerIsNotHeldByAPointerFromTheLastOne() {
        var machine = asPrompting()
        machine.handle(.pointer(inside: true, now: 4))
        machine.handle(.dismiss(on: asOffer(), now: 5))
        machine.handle(asEvidence(70, mic: [.zoom]))
        machine.handle(asEvidence(73, mic: [.zoom]))
        #expect(!machine.pointerInside)
        let gone = machine.handle(asTick(93))
        #expect(gone.isEmpty)
        #expect(machine.card(now: 93) == .hidden)
    }

    // MARK: The heads-up

    @Test func headsUpWindowEdges() {
        func upcoming(_ start: TimeInterval, end: TimeInterval? = nil) -> ScribeMeeting? {
            ScribeMeetingEvidence(date: asBase, slots: [asSlot(start: start, end: end)]).upcoming
        }
        #expect(upcoming(121) == nil)
        #expect(upcoming(120) == asHeadsUp(asSlot(start: 120)))
        #expect(upcoming(1) == asHeadsUp(asSlot(start: 1)))
        // At the start it is no longer upcoming: the meeting has started.
        #expect(upcoming(0) == nil)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [asSlot(start: 0)]).candidate?.key == "s1")
        #expect(upcoming(60, end: -1) == nil)
        #expect(ScribeMeetingStartPolicy.leadWindow == 120)

        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [asSlot(start: 121)]))
        #expect(machine.state == .idle)
        machine.handle(asEvidence(1, slots: [asSlot(start: 121)]))
        #expect(machine.state == .upcoming(meeting: asHeadsUp(asSlot(start: 121)), deadline: 21))
        var edge = ScribeAutoStartMachine()
        edge.handle(asEvidence(0, slots: [asSlot(start: 120)]))
        #expect(edge.state == .upcoming(meeting: asHeadsUp(asSlot(start: 120)), deadline: 20))
        var last = ScribeAutoStartMachine()
        last.handle(asEvidence(0, slots: [asSlot(start: 1)]))
        #expect(last.state == .upcoming(meeting: asHeadsUp(asSlot(start: 1)), deadline: 20))
        var started = ScribeAutoStartMachine()
        started.handle(asEvidence(0, slots: [asSlot(start: 0)]))
        #expect(started.state == .armed(meeting: asHeadsUp(asSlot(start: 0)), since: 0))
    }

    @Test func theClosestSlotWinsTheHeadsUp() {
        let near = asSlot("b", start: 30)
        let far = asSlot("a", start: 90)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [far, near]).upcoming == asHeadsUp(near))
        let twinA = asSlot("a", start: 60)
        let twinB = asSlot("b", start: 60)
        #expect(ScribeMeetingEvidence(date: asBase, slots: [twinB, twinA]).upcoming == asHeadsUp(twinA))
        // A meeting that was already answered does not hide the next one.
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [near, far]))
        machine.handle(.dismiss(on: .offer(asHeadsUp(near), blocked: nil), now: 2))
        machine.handle(asEvidence(3, slots: [near, far]))
        #expect(machine.state == .upcoming(meeting: asHeadsUp(far), deadline: 23))
    }

    @Test func theHeadsUpIsOneCardWithTheTitleTheMinutesAndRecord() {
        var machine = ScribeAutoStartMachine()
        let slot = asSlot(start: 120)
        let effects = machine.handle(asEvidence(0, slots: [slot]))
        #expect(effects.isEmpty)
        let card = machine.card(now: 0)
        #expect(card == .offer(asHeadsUp(slot), blocked: nil))
        #expect(ScribeMeetingCardText.title(asHeadsUp(slot)) == "Design review")
        #expect(ScribeMeetingCardText.status(card, now: asBase) == "in 2 min")
        #expect(ScribeMeetingCardText.status(card, now: asBase.addingTimeInterval(61)) == "in 1 min")
        #expect(ScribeMeetingCardText.primary(card) == "Record")
        #expect(ScribeMeetingCardText.canDismiss(card))
        #expect(machine.ledger.mark(of: asHeadsUp(slot)) == .headsUp)
    }

    @Test func theHeadsUpIsShownInBothModesAndNotInOff() {
        let slot = asSlot(start: 100)
        for mode in [ScribeAutoStartMode.ask, .automatic] {
            var machine = ScribeAutoStartMachine()
            machine.handle(asEvidence(0, slots: [slot], mode: mode))
            #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 20))
            #expect(machine.card(now: 0) == .offer(asHeadsUp(slot), blocked: nil))
        }
        // What blocks an automatic start is not the heads-up's business: it only says when the meeting starts.
        var blocked = ScribeAutoStartMachine()
        blocked.handle(asEvidence(0, slots: [slot], mode: .automatic, ready: .blocked(.microphoneDenied)))
        #expect(blocked.card(now: 0) == .offer(asHeadsUp(slot), blocked: nil))
        var off = ScribeAutoStartMachine()
        let effects = off.handle(asEvidence(0, slots: [slot], mode: .off))
        #expect(effects.isEmpty)
        #expect(off.state == .idle)
        #expect(off.card(now: 0) == .hidden)
        #expect(off.ledger.mark(of: asHeadsUp(slot)) == nil)
        var turnedOff = ScribeAutoStartMachine()
        turnedOff.handle(asEvidence(0, slots: [slot]))
        turnedOff.handle(asEvidence(5, slots: [slot], mode: .off))
        #expect(turnedOff.state == .idle)
        #expect(turnedOff.card(now: 5) == .hidden)
    }

    @Test func theHeadsUpIsShownOncePerMeeting() {
        let slot = asSlot(start: 100, end: 2_000)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        #expect(machine.nextWake(now: 0) == 20)
        let early = machine.handle(asTick(19.9))
        #expect(early.isEmpty)
        #expect(machine.card(now: 19.9) == .offer(asHeadsUp(slot), blocked: nil))
        // Leaving on its own is not an answer: the meeting is marked as announced, nothing more.
        let leave = machine.handle(asTick(20))
        #expect(leave.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.card(now: 20) == .hidden)
        #expect(machine.ledger.mark(of: asHeadsUp(slot)) == .headsUp)
        #expect(machine.ledger.mark(of: asHeadsUp(slot))?.isAnswered == false)
        #expect(machine.nextWake(now: 20) == nil)
        // The same slot read again, an empty or failed read, then the slot back: still one announcement.
        var shown = 0
        for (now, slots) in [(25.0, [slot]), (30.0, []), (35.0, [slot]), (40.0, []), (45.0, []), (50.0, [slot])] {
            machine.handle(asEvidence(now, slots: slots))
            if machine.card(now: now) != .hidden { shown += 1 }
        }
        #expect(shown == 0)
        #expect(machine.state == .idle)
    }

    @Test func aHeadsUpThatIsStillUpSurvivesAnEmptyCalendarRead() {
        let slot = asSlot(start: 100)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asEvidence(5, slots: []))
        #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 20))
        #expect(machine.card(now: 5) == .offer(asHeadsUp(slot), blocked: nil))
    }

    @Test func dismissAtTwoMinutesStaysQuietAtStartTime() {
        for mode in [ScribeAutoStartMode.ask, .automatic] {
            let slot = asSlot(start: 120, end: 1_920, app: .teams)
            var machine = ScribeAutoStartMachine()
            machine.handle(asEvidence(0, slots: [slot], mode: mode))
            let effects = machine.handle(.dismiss(on: .offer(asHeadsUp(slot), blocked: nil), now: 5))
            #expect(effects.isEmpty)
            #expect(machine.state == .idle)
            #expect(machine.ledger.mark(of: asHeadsUp(slot)) == .declined)
            var shown = 0
            for now in stride(from: 100.0, through: 400.0, by: 3.0) {
                // The start time passes, then the call opens in Teams and the microphone is held.
                let held: [ScribeCallApp] = now >= 130 ? [.teams] : []
                machine.handle(asEvidence(now, mic: held, present: [.teams], slots: [slot], mode: mode))
                if machine.card(now: now) != .hidden { shown += 1 }
            }
            #expect(shown == 0)
            #expect(machine.state == .idle)
        }
    }

    @Test func resetLeavesTheMachineAtRestAndKeepsWhatWasAnswered() {
        let slot = asSlot(start: 120, end: 1_920, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(.dismiss(on: .offer(asHeadsUp(slot), blocked: nil), now: 5))
        machine.handle(.pointer(inside: true, now: 6))
        machine.reset()
        #expect(machine.state == .idle)
        #expect(!machine.pointerInside)
        #expect(machine.ledger.mark(of: asHeadsUp(slot)) == .declined)
        machine.handle(asEvidence(60, slots: [slot]))
        #expect(machine.card(now: 60) == .hidden)
    }

    @Test func aTimeoutThenALiveCallAsksInAskMe() {
        let slot = asSlot(start: 60, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asTick(20))
        #expect(machine.state == .idle)
        machine.handle(asEvidence(60, mic: [.teams], slots: [slot]))
        #expect(machine.state == .armed(meeting: asLive(slot), since: 60))
        #expect(machine.card(now: 60) == .hidden)
        machine.handle(asEvidence(63, mic: [.teams], slots: [slot]))
        #expect(machine.state == .prompting(meeting: asLive(slot), deadline: 83, blocked: .notChosen))
    }

    @Test func aTimeoutThenALiveCallCountsDownInAutomatic() {
        let slot = asSlot(start: 60, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot], mode: .automatic))
        machine.handle(asTick(20))
        machine.handle(asEvidence(60, mic: [.teams], slots: [slot], mode: .automatic))
        #expect(!asIsCountingDown(machine.state))
        machine.handle(asEvidence(63, mic: [.teams], slots: [slot], mode: .automatic))
        #expect(machine.state == .countingDown(meeting: asLive(slot), deadline: 68))
        let start = machine.handle(asTick(68))
        #expect(start == [.start(asLive(slot))])
    }

    @Test func aCallBeginningDuringTheHeadsUpKeepsTheCardThroughTheCheckThenAsksReadingNow() {
        let slot = asSlot(start: 12, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asEvidence(12, mic: [.teams], slots: [slot]))
        #expect(machine.state == .armed(meeting: asLive(slot), since: 12, offerUntil: 20))
        // The card does not blink out while the 3 s check runs.
        #expect(machine.card(now: 13) == .offer(asLive(slot), blocked: nil))
        let held = machine.handle(asEvidence(14, mic: [.teams], slots: [slot]))
        #expect(held.isEmpty)
        #expect(machine.card(now: 14) == .offer(asLive(slot), blocked: nil))
        machine.handle(asEvidence(15, mic: [.teams], slots: [slot]))
        #expect(machine.state == .prompting(meeting: asLive(slot), deadline: 35, blocked: .notChosen))
        let card = machine.card(now: 15)
        #expect(card == .offer(asLive(slot), blocked: .notChosen))
        #expect(ScribeMeetingCardText.status(card, now: asBase.addingTimeInterval(15)) == "now")
    }

    @Test func aCallBeginningDuringTheHeadsUpCountsDownInAutomaticAfterTheCheck() {
        let slot = asSlot(start: 12, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot], mode: .automatic))
        machine.handle(asEvidence(12, mic: [.teams], slots: [slot], mode: .automatic))
        #expect(machine.card(now: 13) == .offer(asLive(slot), blocked: nil))
        #expect(!asIsCountingDown(machine.state))
        machine.handle(asEvidence(15, mic: [.teams], slots: [slot], mode: .automatic))
        #expect(machine.state == .countingDown(meeting: asLive(slot), deadline: 20))
    }

    @Test func theHeadsUpStillLeavesOnItsDeadlineWhileTheCheckRuns() {
        let slot = asSlot(start: 100, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asEvidence(18, mic: [.teams], slots: [slot]))
        #expect(machine.nextWake(now: 18) == 20)
        machine.handle(asTick(20))
        #expect(machine.state == .armed(meeting: asLive(slot), since: 18))
        #expect(machine.card(now: 20) == .hidden)
        machine.handle(asEvidence(21, mic: [.teams], slots: [slot]))
        #expect(machine.state == .prompting(meeting: asLive(slot), deadline: 41, blocked: .notChosen))
    }

    @Test func aMicBlipDuringTheHeadsUpDoesNotCountDown() {
        let slot = asSlot(start: 100, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot], mode: .automatic))
        var effects: [ScribeAutoStartMachine.Effect] = []
        var counted = false
        func read(_ now: TimeInterval, mic: [ScribeCallApp]) {
            effects += machine.handle(asEvidence(now, mic: mic, slots: [slot], mode: .automatic))
            counted = counted || asIsCountingDown(machine.state)
        }
        read(10, mic: [.teams])
        #expect(machine.state == .armed(meeting: asLive(slot), since: 10, offerUntil: 20))
        // The microphone lets go within the 3 s check: the heads-up is back as it was, with its deadline.
        read(11, mic: [])
        #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 20))
        #expect(machine.card(now: 11) == .offer(asHeadsUp(slot), blocked: nil))
        read(14, mic: [.teams])
        read(15, mic: [])
        #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 20))
        machine.handle(asTick(20))
        #expect(machine.state == .idle)
        read(30, mic: [])
        #expect(!counted)
        #expect(effects.isEmpty)
    }

    @Test func aCallThatLastsPastTheCheckAfterABlipCountsDownOnce() {
        let slot = asSlot(start: 100, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot], mode: .automatic))
        machine.handle(asEvidence(10, mic: [.teams], slots: [slot], mode: .automatic))
        machine.handle(asEvidence(11, slots: [slot], mode: .automatic))
        machine.handle(asEvidence(14, mic: [.teams], slots: [slot], mode: .automatic))
        #expect(machine.state == .armed(meeting: asLive(slot), since: 14, offerUntil: 20))
        machine.handle(asEvidence(17, mic: [.teams], slots: [slot], mode: .automatic))
        #expect(machine.state == .countingDown(meeting: asLive(slot), deadline: 22))
    }

    @Test func recordOnTheHeadsUpStartsWithTheTitleAndGuestsAndNoCallBinding() throws {
        let slot = ScribeCalendarSlot(id: "s1", title: "Design review", start: asBase.addingTimeInterval(100),
                                      attendeeNames: ["Ana Costa", "Bo Lin"], hasCallLink: true, callApp: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        let effects = machine.handle(asTap(.offer(asHeadsUp(slot), blocked: nil), 5))
        #expect(effects == [.start(asHeadsUp(slot))])
        let meeting = try #require(effects.compactMap { effect -> ScribeMeeting? in
            if case .start(let meeting) = effect { return meeting } else { return nil }
        }.first)
        let identity = ScribeCallProcessIdentity(pid: 4_242, bundleID: "example.calls", launchedAt: 1)
        let context = meeting.context(callIdentity: identity)
        #expect(context.title == "Design review")
        #expect(context.attendeeNames == ["Ana Costa", "Bo Lin"])
        #expect(context.callIdentity == nil)
        #expect(machine.state == .starting(ScribeStartAttempt(meeting: asHeadsUp(slot), since: 5, origin: .tap,
                                                              previousSession: nil, session: nil)))
    }

    @Test func aTapOnTheHeadsUpWhileTheCallCheckRunsStartsTheLiveMeeting() {
        let slot = asSlot(start: 12, end: 2_000, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asEvidence(12, mic: [.teams], slots: [slot]))
        let effects = machine.handle(asTap(.offer(asHeadsUp(slot), blocked: nil), 13))
        #expect(effects == [.start(asLive(slot))])
    }

    @Test func aTapOnTheHeadsUpThatLeftInTheSameInstantStillStarts() {
        let slot = asSlot(start: 100, app: .teams)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asTick(20))
        #expect(machine.state == .idle)
        let effects = machine.handle(asTap(.offer(asHeadsUp(slot), blocked: nil), 20.1))
        #expect(effects == [.start(asHeadsUp(slot))])
    }

    @Test func nothingIsShownWhileScribeIsSaving() {
        let slot = asSlot(start: 100)
        for activity in [ScribeActivity.ending, .processing] {
            var machine = ScribeAutoStartMachine()
            machine.handle(asEvidence(0, slots: [slot], activity: activity))
            #expect(machine.state == .idle)
            #expect(machine.card(now: 0) == .hidden)
            // Nothing was announced, so the heads-up still comes once Scribe is free.
            #expect(machine.ledger.mark(of: asHeadsUp(slot)) == nil)
            machine.handle(asEvidence(10, slots: [slot]))
            #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 30))
        }
    }

    @Test func aRecordingStartedByHandTakesTheHeadsUpDown() {
        let slot = asSlot(start: 100)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(asEvidence(5, slots: [slot], activity: .recording))
        #expect(machine.state == .idle)
        #expect(machine.card(now: 5) == .hidden)
        #expect(machine.ledger.mark(of: asHeadsUp(slot)) == .started)
        var busy = ScribeAutoStartMachine()
        busy.handle(asEvidence(0, slots: [slot], activity: .recording))
        #expect(busy.state == .idle)
        #expect(busy.ledger.mark(of: asHeadsUp(slot)) == nil)
    }

    @Test func theHeadsUpDoesNotTimeOutUnderThePointer() {
        let slot = asSlot(start: 100)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(.pointer(inside: true, now: 10))
        let held = machine.handle(asTick(40))
        #expect(held.isEmpty)
        #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 20))
        machine.handle(.pointer(inside: false, now: 50))
        #expect(machine.state == .upcoming(meeting: asHeadsUp(slot), deadline: 54))
        machine.handle(asTick(53))
        #expect(machine.card(now: 53) == .offer(asHeadsUp(slot), blocked: nil))
        machine.handle(asTick(54))
        #expect(machine.state == .idle)
    }

    @Test func theHeadsUpWakesAtTheMinuteTheTimeChanges() {
        let slot = asSlot(start: 100)
        var machine = ScribeAutoStartMachine()
        machine.handle(asEvidence(0, slots: [slot]))
        machine.handle(.pointer(inside: true, now: 1))
        #expect(machine.nextWake(now: 1) == 40)
    }
}
