import Foundation
import Testing
@testable import ZeusCore

private let moBase = Date(timeIntervalSince1970: 2_000_000)
private let moPrevious = ScribeSessionID()
private let moFresh = ScribeSessionID()
private let moTeams = ScribeMeeting(key: "call:Teams", title: "Call", callApp: .teams, isLive: true)

private func moContext(_ scribe: ScribePhase = .idle, microphone: ScribeMicrophoneAccess = .allowed,
                       ready: ScribeAutoStartReadiness = .ready) -> ScribeStartContext {
    ScribeStartContext(scribe: scribe, microphone: microphone, automatic: ready)
}

/// One reading of a Teams call (or whatever `mic` says) with the given choice. Without an explicit answer,
/// automatic is fully ready and every other choice is simply not chosen.
private func moEvidence(
    _ now: TimeInterval, mic: [ScribeCallApp] = [.teams], present: [ScribeCallApp] = [],
    slots: [ScribeCalendarSlot] = [], mode: ScribeAutoStartMode = .ask, ready: ScribeAutoStartReadiness? = nil,
    scribe: ScribePhase = .idle, microphone: ScribeMicrophoneAccess = .allowed
) -> ScribeAutoStartMachine.Event {
    let automatic = ready ?? (mode == .automatic ? .ready : .blocked(.notChosen))
    let context = ScribeStartContext(scribe: scribe, microphone: microphone, automatic: automatic)
    return .evidence(ScribeMeetingEvidence(date: moBase.addingTimeInterval(now), slots: slots, micApps: mic,
                                           presentApps: present, mode: mode, context: context), now: now)
}

private func moTick(_ now: TimeInterval, scribe: ScribePhase = .idle, microphone: ScribeMicrophoneAccess = .allowed,
                    ready: ScribeAutoStartReadiness = .ready) -> ScribeAutoStartMachine.Event {
    .tick(now: now, context: moContext(scribe, microphone: microphone, ready: ready))
}

private func moOffer(_ meeting: ScribeMeeting = moTeams) -> ScribeMeetingCard { .offer(meeting, blocked: nil) }

private func moTap(_ card: ScribeMeetingCard, _ now: TimeInterval, scribe: ScribePhase = .idle,
                   microphone: ScribeMicrophoneAccess = .allowed) -> ScribeAutoStartMachine.Event {
    .primary(on: card, now: now, context: moContext(scribe, microphone: microphone))
}

private func moCountdownCard(_ meeting: ScribeMeeting = moTeams) -> ScribeMeetingCard {
    .countdown(meeting, seconds: 5, deadline: 8, total: 5)
}

/// Teams seen at 0 and 3: the "Ask me" offer is up until 23, or the countdown until 8.
private func moPrompting(_ mode: ScribeAutoStartMode = .ask, ready: ScribeAutoStartReadiness? = nil)
    -> ScribeAutoStartMachine {
    var machine = ScribeAutoStartMachine()
    machine.handle(moEvidence(0, mode: mode, ready: ready))
    machine.handle(moEvidence(3, mode: mode, ready: ready))
    return machine
}

/// A tap at 4 asked Scribe to start while Scribe sat on a failed earlier session.
private func moTapStarted() -> ScribeAutoStartMachine {
    var machine = moPrompting()
    machine.handle(moTap(moOffer(), 4, scribe: .failed(moPrevious, reason: "old")))
    return machine
}

/// The countdown ended at 8 on its own while Scribe sat on a failed earlier session.
private func moAutomaticStarted() -> ScribeAutoStartMachine {
    var machine = moPrompting(.automatic)
    machine.handle(moTick(8, scribe: .failed(moPrevious, reason: "old")))
    return machine
}

private func moRecording(_ machine: ScribeAutoStartMachine) -> ScribeAutoStartRecording? {
    if case .recording(let recording) = machine.state { return recording }
    return nil
}

private func moAttempt(_ machine: ScribeAutoStartMachine) -> ScribeStartAttempt? {
    switch machine.state {
    case .starting(let attempt): return attempt
    case .failed(let attempt, _, _): return attempt
    default: return nil
    }
}

private func moNext() -> (slot: ScribeCalendarSlot, meeting: ScribeMeeting) {
    let slot = ScribeCalendarSlot(id: "n1", title: "Standup", start: moBase.addingTimeInterval(80), hasCallLink: true)
    return (slot, ScribeMeeting(key: "n1", title: "Standup", callApp: .teams, slot: slot))
}

/// Recording Teams, with the next meeting offered at 20 (its card stays until 40).
private func moRecordingWithNext() -> ScribeAutoStartMachine {
    var machine = moTapStarted()
    machine.handle(.scribe(.starting(moFresh), now: 4))
    machine.handle(.scribe(.recording(moFresh, since: 5), now: 5))
    machine.handle(moTick(7))
    machine.handle(moEvidence(20, slots: [moNext().slot], scribe: .recording(moFresh, since: 5)))
    return machine
}

@Suite("Scribe meeting start outcome")
struct ScribeMeetingStartOutcomeTests {
    // MARK: A tap

    @Test func aTapAsksForOneStartAndShowsStartingAtOnce() {
        var machine = moPrompting()
        let effects = machine.handle(moTap(moOffer(), 5))
        #expect(effects == [.start(moTeams)])
        #expect(machine.state == .starting(ScribeStartAttempt(meeting: moTeams, since: 5, origin: .tap,
                                                              previousSession: nil, session: nil)))
        #expect(machine.card(now: 5) == .starting(moTeams, cancellable: false))
    }

    @Test func aDoubleTapStartsScribeOnlyOnce() {
        var machine = moPrompting()
        let first = machine.handle(moTap(moOffer(), 5))
        let second = machine.handle(moTap(moOffer(), 5.2, scribe: .starting(moFresh)))
        #expect(first == [.start(moTeams)])
        #expect(second.isEmpty)
        #expect(moAttempt(machine)?.origin == .tap)
    }

    @Test func aTapWhileTheAutomaticStartIsRunningConfirmsInsteadOfStartingTwice() {
        var machine = moPrompting()
        let effects = machine.handle(moTap(moOffer(), 5, scribe: .starting(moFresh)))
        #expect(effects.isEmpty)
        #expect(machine.state == .starting(ScribeStartAttempt(meeting: moTeams, since: 5, origin: .tap,
                                                              previousSession: nil, session: moFresh)))
        machine.handle(.scribe(.recording(moFresh, since: 6), now: 6))
        #expect(machine.card(now: 6) == .recording(moTeams))

        var running = moPrompting()
        let adopted = running.handle(moTap(moOffer(), 5, scribe: .recording(moFresh, since: 4)))
        #expect(adopted.isEmpty)
        #expect(running.card(now: 5) == .recording(moTeams))
        #expect(moRecording(running)?.session == moFresh)
        #expect(moRecording(running)?.origin == .tap)
    }

    @Test func aTapThatAdoptsARunningSessionCannotBeCancelledIntoDiscardingIt() {
        var machine = moPrompting()
        machine.handle(moTap(moOffer(), 5, scribe: .recording(moFresh, since: 4)))
        let cancel = machine.handle(.cancel(on: .starting(moTeams, cancellable: true), now: 5.5))
        #expect(cancel.isEmpty)
        #expect(moRecording(machine) != nil)
    }

    @Test func aTapAfterTheOfferEndedStillStartsThatMeeting() {
        var idle = ScribeAutoStartMachine()
        let effects = idle.handle(moTap(moOffer(), 2))
        #expect(effects == [.start(moTeams)])
        #expect(moAttempt(idle)?.origin == .tap)

        var armed = ScribeAutoStartMachine()
        armed.handle(moEvidence(0))
        guard case .armed = armed.state else {
            Issue.record("expected armed, got \(armed.state)")
            return
        }
        #expect(armed.handle(moTap(moOffer(), 1)) == [.start(moTeams)])

        var other = moPrompting()
        let zoom = ScribeMeeting(key: "call:Zoom", title: "Call", callApp: .zoom, isLive: true)
        #expect(other.handle(moTap(moOffer(zoom), 5)) == [.start(zoom)])
        #expect(moAttempt(other)?.meeting == zoom)
    }

    @Test func aLateTapIsIgnoredWhileAnythingElseIsUnderWay() {
        var counting = moPrompting(.automatic)
        #expect(counting.handle(moTap(moOffer(), 5)).isEmpty)
        #expect(counting.state == .countingDown(meeting: moTeams, deadline: 8))

        var held = moPrompting()
        held.handle(moTap(moOffer(), 5, scribe: .processing(moPrevious)))
        #expect(held.handle(moTap(moOffer(), 6, scribe: .processing(moPrevious))).isEmpty)
        #expect(held.state == .held(meeting: moTeams, startOwed: true))

        var starting = moTapStarted()
        #expect(starting.handle(moTap(moOffer(), 5)).isEmpty)

        var recording = moRecordingWithNext()
        #expect(recording.handle(moTap(moOffer(), 25, scribe: .recording(moFresh, since: 5))).isEmpty)

        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        #expect(failed.handle(moTap(moOffer(), 6)).isEmpty)
    }

    @Test func aCaptureFailureIsShownWithItsReason() {
        var machine = moTapStarted()
        machine.handle(.scribe(.starting(moFresh), now: 4.1))
        machine.handle(.scribe(.failed(moFresh, reason: "Screen Recording is off."), now: 5))
        #expect(machine.card(now: 5) == .failed(moTeams, .captureFailed("Screen Recording is off.")))
        #expect(ScribeMeetingCardText.status(machine.card(now: 5), now: moBase) == "Screen Recording is off.")
        #expect(ScribeMeetingCardText.primary(machine.card(now: 5)) == "Try again")
    }

    @Test func anAutomaticStartThatFailsShowsItsReason() {
        var machine = moAutomaticStarted()
        machine.handle(.scribe(.starting(moFresh), now: 8))
        machine.handle(.scribe(.failed(moFresh, reason: "Screen Recording is off."), now: 9))
        #expect(machine.card(now: 9) == .failed(moTeams, .captureFailed("Screen Recording is off.")))
        #expect(machine.nextWake(now: 9) == 69)
    }

    @Test func theMicrophoneBeingOffIsSaidAndAllowOpensSettings() {
        var machine = moPrompting()
        let tap = machine.handle(moTap(moOffer(), 5, microphone: .denied))
        #expect(tap.isEmpty)
        #expect(machine.card(now: 5) == .failed(moTeams, .microphoneOff))
        #expect(ScribeMeetingCardText.primary(machine.card(now: 5)) == "Allow")
        let allow = machine.handle(.primary(on: .failed(moTeams, .microphoneOff), now: 6,
                                            context: moContext(microphone: .denied)))
        #expect(allow == [.openMicrophoneSettings])
        // Allowed in System Settings meanwhile: the same button now starts.
        let retry = machine.handle(.primary(on: .failed(moTeams, .microphoneOff), now: 30, context: moContext()))
        #expect(retry == [.start(moTeams)])
    }

    @Test func automaticWithTheMicrophoneDeniedShowsAllow() {
        var machine = moPrompting(.automatic, ready: .blocked(.microphoneDenied))
        #expect(machine.card(now: 3) == .offer(moTeams, blocked: .microphoneDenied))
        #expect(ScribeMeetingCardText.status(machine.card(now: 3), now: moBase) == "Microphone is off for Zeus")
        // The card asks; Record never counts down. With the microphone denied it says why and offers Allow.
        let tap = machine.handle(moTap(.offer(moTeams, blocked: .microphoneDenied), 5, microphone: .denied))
        #expect(tap.isEmpty)
        #expect(ScribeMeetingCardText.primary(machine.card(now: 5)) == "Allow")
    }

    @Test func theMicrophoneNotYetAskedShowsTheReasonWithRecord() {
        var machine = moPrompting(.automatic, ready: .blocked(.microphoneNotAsked))
        #expect(machine.card(now: 3) == .offer(moTeams, blocked: .microphoneNotAsked))
        #expect(ScribeMeetingCardText.primary(machine.card(now: 3)) == "Record")
        let tap = machine.handle(moTap(.offer(moTeams, blocked: .microphoneNotAsked), 5, microphone: .notAsked))
        #expect(tap == [.start(moTeams)])
    }

    @Test func aStaleFailureFromThePreviousMeetingIsNotThisTapsFailure() {
        var machine = moTapStarted()
        machine.handle(.scribe(.failed(moPrevious, reason: "old"), now: 4.1))
        #expect(machine.card(now: 4.1) == .starting(moTeams, cancellable: false))
        machine.handle(.scribe(.starting(moFresh), now: 4.2))
        machine.handle(.scribe(.recording(moFresh, since: 5), now: 5))
        #expect(machine.card(now: 5) == .recording(moTeams))
        #expect(moRecording(machine)?.session == moFresh)
    }

    @Test func aStartRefusedWhileSavingSaysSoAtOnce() {
        var machine = ScribeAutoStartMachine()
        // Scribe looked free when the tap was read, and was still saving when the start effect ran.
        let effects = machine.handle(moTap(moOffer(), 1, scribe: .complete(moPrevious)))
        #expect(effects == [.start(moTeams)])
        machine.handle(.scribe(.processing(moPrevious), now: 1))
        #expect(machine.card(now: 1) == .failed(moTeams, .stillSaving))
        let again = machine.handle(.primary(on: .failed(moTeams, .stillSaving), now: 20,
                                            context: moContext(.complete(moPrevious))))
        #expect(again == [.start(moTeams)])
    }

    @Test func recordingAppearsOnlyForTheRecordingPhase() {
        var machine = moAutomaticStarted()
        let phases: [ScribePhase] = [.idle, .failed(moPrevious, reason: "old"), .starting(moFresh)]
        for phase in phases {
            machine.handle(.scribe(phase, now: 8.5))
            #expect(machine.card(now: 8.5) == .starting(moTeams, cancellable: true), "\(phase)")
        }
        machine.handle(.scribe(.recording(moFresh, since: 9), now: 9))
        #expect(machine.card(now: 9) == .recording(moTeams))
    }

    @Test func aSessionThatEndsBeforeItWasSeenRecordingHidesTheCard() {
        for phase in [ScribePhase.ending(moFresh, deadline: 20), .processing(moFresh), .complete(moFresh)] {
            var machine = moTapStarted()
            machine.handle(.scribe(phase, now: 5))
            #expect(machine.card(now: 5) == .hidden, "\(phase)")
            #expect(machine.ledger.mark(of: moTeams) == .started, "\(phase)")
        }
    }

    @Test func theConfirmationLeavesOnItsOwn() {
        var machine = moTapStarted()
        machine.handle(.scribe(.recording(moFresh, since: 5), now: 5))
        #expect(machine.card(now: 6.4) == .recording(moTeams))
        let stays = machine.handle(moTick(6.4))
        #expect(stays.isEmpty)
        #expect(machine.card(now: 6.4) == .recording(moTeams))
        machine.handle(moTick(6.5))
        #expect(machine.card(now: 6.5) == .hidden)
        #expect(machine.ledger.mark(of: moTeams) == .started)
        guard case .recording = machine.state else {
            Issue.record("the call stays watched while recording, got \(machine.state)")
            return
        }
    }

    // MARK: The countdown ends

    @Test func aCountdownThatEndsGoesToStartingNeverStraightToRecording() {
        var machine = moPrompting(.automatic)
        #expect(machine.state == .countingDown(meeting: moTeams, deadline: 8))
        let early = machine.handle(moTick(7.9))
        #expect(early.isEmpty)
        let effects = machine.handle(moTick(8))
        #expect(effects == [.start(moTeams)])
        #expect(machine.card(now: 8) == .starting(moTeams, cancellable: true))
        #expect(moAttempt(machine)?.origin == .automatic)
        // A second tick never starts a second time.
        #expect(machine.handle(moTick(8.2)).isEmpty)
    }

    @Test func aCountdownThatEndsWithReadinessLostAsksInstead() {
        var machine = moPrompting(.automatic)
        let effects = machine.handle(moTick(8, ready: .blocked(.microphoneDenied)))
        #expect(effects.isEmpty)
        #expect(machine.card(now: 8) == .offer(moTeams, blocked: .microphoneDenied))
    }

    // MARK: Cancel

    @Test func cancelDuringTheCountdownEndsItAndNeverStarts() {
        var machine = moPrompting(.automatic)
        let effects = machine.handle(.cancel(on: moCountdownCard(), now: 5))
        #expect(effects.isEmpty)
        #expect(machine.card(now: 5) == .hidden)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
        #expect(machine.handle(moTick(8)).isEmpty)
        #expect(machine.handle(moEvidence(70, mode: .automatic)).isEmpty)
    }

    @Test func cancelAtTheSameInstantAsExpiryNeverRecords() {
        var machine = moPrompting(.automatic)
        let cancel = machine.handle(.cancel(on: moCountdownCard(), now: 8))
        #expect(cancel.isEmpty)
        let tick = machine.handle(moTick(8))
        #expect(tick.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func cancelAfterExpiryAbandonsTheAutomaticStart() {
        var machine = moAutomaticStarted()
        machine.handle(.scribe(.starting(moFresh), now: 8))
        let cancel = machine.handle(.cancel(on: moCountdownCard(), now: 8.1))
        #expect(cancel == [.abandonStart(moFresh)])
        #expect(machine.card(now: 8.1) == .hidden)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
        #expect(machine.state == .idle)
    }

    @Test func cancelDuringTheConfirmationDiscardsTheAutomaticStart() {
        var machine = moAutomaticStarted()
        machine.handle(.scribe(.starting(moFresh), now: 8))
        machine.handle(.scribe(.recording(moFresh, since: 9), now: 9))
        #expect(machine.card(now: 9.5) == .recording(moTeams))
        let cancel = machine.handle(.cancel(on: .starting(moTeams, cancellable: true), now: 9.5))
        #expect(cancel == [.abandonStart(moFresh)])
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
    }

    @Test func cancelAfterTheConfirmationDoesNothing() {
        var machine = moAutomaticStarted()
        machine.handle(.scribe(.recording(moFresh, since: 9), now: 9))
        let cancel = machine.handle(.cancel(on: .starting(moTeams, cancellable: true), now: 10.5))
        #expect(cancel.isEmpty)
        #expect(moRecording(machine) != nil)
    }

    @Test func cancelOnAnAutomaticStartWithNoSessionSeenYetEndsWithNothingToDiscard() {
        var machine = moAutomaticStarted()
        let cancel = machine.handle(.cancel(on: .starting(moTeams, cancellable: true), now: 8.1))
        #expect(cancel.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
    }

    @Test func aCancelNeverStartsAnything() {
        var machines: [(String, ScribeAutoStartMachine)] = []
        machines.append(("idle", ScribeAutoStartMachine()))
        machines.append(("prompting", moPrompting()))
        machines.append(("countdown", moPrompting(.automatic)))
        var held = moPrompting()
        held.handle(moTap(moOffer(), 5, scribe: .processing(moPrevious)))
        machines.append(("held, owed", held))
        var heldAutomatic = ScribeAutoStartMachine()
        heldAutomatic.handle(moEvidence(0, mode: .automatic, scribe: .processing(moPrevious)))
        machines.append(("held", heldAutomatic))
        machines.append(("starting by tap", moTapStarted()))
        machines.append(("starting automatic", moAutomaticStarted()))
        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        machines.append(("failed", failed))
        machines.append(("recording", moRecordingWithNext()))
        let cards: [ScribeMeetingCard] = [moCountdownCard(), .waiting(moTeams), .starting(moTeams, cancellable: true),
                                          .recording(moTeams), moOffer(), .hidden]
        for (name, machine) in machines {
            for card in cards {
                var copy = machine
                let effects = copy.handle(.cancel(on: card, now: 9))
                let starts = effects.filter { if case .start = $0 { return true } else { return false } }
                #expect(starts.isEmpty, "\(name) \(card)")
            }
        }
    }

    @Test func aRecordTapStartHasNoCancel() {
        var machine = moTapStarted()
        machine.handle(.scribe(.starting(moFresh), now: 4.1))
        let cancel = machine.handle(.cancel(on: .starting(moTeams, cancellable: true), now: 4.2))
        #expect(cancel.isEmpty)
        #expect(machine.card(now: 4.2) == .starting(moTeams, cancellable: false))
    }

    @Test func aStrayCloseNeverCancelsAStartInFlight() {
        var machine = moTapStarted()
        let close = machine.handle(.dismiss(on: .starting(moTeams, cancellable: false), now: 4.5))
        #expect(close.isEmpty)
        #expect(machine.card(now: 4.5) == .starting(moTeams, cancellable: false))
        var automatic = moAutomaticStarted()
        #expect(automatic.handle(.dismiss(on: .recording(moTeams), now: 8.5)).isEmpty)
        #expect(automatic.card(now: 8.5) == .starting(moTeams, cancellable: true))
    }

    // MARK: Slow starts and failures

    @Test func noSignOfAStartBecomesAVisibleFailureThenALateStartStillConfirms() {
        var machine = moTapStarted()
        machine.handle(moTick(8.9))
        #expect(machine.card(now: 8.9) == .starting(moTeams, cancellable: false))
        machine.handle(moTick(9))
        #expect(machine.card(now: 9) == .failed(moTeams, .noResponse))
        machine.handle(.scribe(.recording(moFresh, since: 11), now: 11))
        #expect(machine.card(now: 11) == .recording(moTeams))
    }

    @Test func aSlowStartAfterNoResponseBecomesRecording() {
        var machine = moAutomaticStarted()
        machine.handle(moTick(13))
        #expect(machine.card(now: 13) == .failed(moTeams, .noResponse))
        machine.handle(.scribe(.starting(moFresh), now: 14))
        #expect(machine.card(now: 14) == .failed(moTeams, .noResponse))
        machine.handle(.scribe(.recording(moFresh, since: 15), now: 15))
        #expect(machine.card(now: 15) == .recording(moTeams))
        #expect(moRecording(machine)?.origin == .automatic)
        // The previous session is never the late answer.
        var stale = moAutomaticStarted()
        stale.handle(moTick(13))
        stale.handle(.scribe(.recording(moPrevious, since: 1), now: 14))
        #expect(stale.card(now: 14) == .failed(moTeams, .noResponse))
    }

    @Test func aStartWaitingOnAPermissionAnswerGetsTheLongerTimeout() {
        var machine = moTapStarted()
        machine.handle(.scribe(.starting(moFresh), now: 4.1))
        machine.handle(moTick(30))
        #expect(machine.card(now: 30) == .starting(moTeams, cancellable: false))
        machine.handle(moTick(49))
        #expect(machine.card(now: 49) == .failed(moTeams, .noResponse))
    }

    @Test func theOfferStaysUpUnderThePointerUntilThePointerLeaves() {
        var machine = moPrompting()
        machine.handle(.pointer(inside: true, now: 15))
        machine.handle(moTick(40))
        #expect(machine.card(now: 40) == .offer(moTeams, blocked: .notChosen))
        machine.handle(.pointer(inside: false, now: 100))
        #expect(machine.handle(moTick(102)).isEmpty)
        #expect(machine.card(now: 102) == .offer(moTeams, blocked: .notChosen))
        machine.handle(moTick(104))
        #expect(machine.card(now: 104) == .hidden)

        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        failed.handle(.pointer(inside: true, now: 6))
        failed.handle(moTick(500))
        #expect(failed.card(now: 500) == .failed(moTeams, .microphoneOff))
        failed.handle(.pointer(inside: false, now: 500))
        failed.handle(moTick(503))
        #expect(failed.card(now: 503) == .failed(moTeams, .microphoneOff))
        failed.handle(moTick(504))
        #expect(failed.card(now: 504) == .hidden)
    }

    @Test func afterAFailureLeavesTheMeetingIsHandled() {
        var machine = moPrompting()
        machine.handle(moTap(moOffer(), 5, microphone: .denied))
        machine.handle(moTick(64.9))
        #expect(machine.card(now: 64.9) == .failed(moTeams, .microphoneOff))
        machine.handle(moTick(65))
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
        var later: [ScribeAutoStartMachine.Effect] = []
        for now in stride(from: 70.0, through: 400.0, by: 5.0) {
            later += machine.handle(moEvidence(now, mode: .automatic))
            later += machine.handle(moTick(now + 1))
        }
        #expect(later.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func theDismissGlyphOnAFailureEndsItAndMarksTheMeeting() {
        var machine = moPrompting()
        machine.handle(moTap(moOffer(), 5, microphone: .denied))
        let effects = machine.handle(.dismiss(on: .failed(moTeams, .microphoneOff), now: 6))
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
    }

    @Test func tryAgainStartsAFreshAttemptFromAFailure() {
        var machine = moTapStarted()
        machine.handle(moTick(9))
        let effects = machine.handle(.primary(on: .failed(moTeams, .noResponse), now: 10,
                                              context: moContext(.failed(moPrevious, reason: "old"))))
        #expect(effects == [.start(moTeams)])
        #expect(moAttempt(machine)?.since == 10)
    }

    @Test func startingAndFailedReactOnlyToTheirOwnEvents() {
        let others: [ScribeAutoStartMachine.Event] = [
            moEvidence(5, mode: .off), moEvidence(5, mic: []), moEvidence(5, mode: .ask, ready: .blocked(.noOptIn)),
            moEvidence(5, mic: [.zoom]),
        ]
        var starting = moTapStarted()
        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        for event in others {
            let before = starting.state
            #expect(starting.handle(event).isEmpty)
            #expect(starting.state == before)
            let failedBefore = failed.state
            #expect(failed.handle(event).isEmpty)
            #expect(failed.state == failedBefore)
        }
    }

    @Test func modeOffDuringStartingKeepsTheCard() {
        var machine = moAutomaticStarted()
        machine.handle(.scribe(.starting(moFresh), now: 8))
        machine.handle(moEvidence(9, mode: .off, scribe: .starting(moFresh)))
        #expect(machine.card(now: 9) == .starting(moTeams, cancellable: true))
        machine.handle(.scribe(.recording(moFresh, since: 9), now: 9.2))
        machine.handle(moEvidence(9.5, mode: .off, scribe: .recording(moFresh, since: 9)))
        #expect(machine.card(now: 9.5) == .recording(moTeams))
    }

    // MARK: Held while Scribe is saving

    @Test func aMeetingHeldWhileSavingIsShownAndStartsWhenFree() {
        var machine = ScribeAutoStartMachine()
        let processing = ScribePhase.processing(moPrevious)
        machine.handle(moEvidence(0, mode: .automatic, scribe: processing))
        #expect(machine.state == .held(meeting: moTeams, startOwed: false))
        #expect(machine.card(now: 0) == .waiting(moTeams))
        #expect(machine.ledger.mark(of: moTeams) == nil)
        machine.handle(moEvidence(5, mode: .automatic, scribe: processing))
        machine.handle(moTick(6, scribe: processing))
        #expect(machine.card(now: 6) == .waiting(moTeams))
        // Free now: automatic counts down for a live, ready call.
        let free = machine.handle(moEvidence(10, mode: .automatic, scribe: .complete(moPrevious)))
        #expect(free.isEmpty)
        #expect(machine.card(now: 10) == .countdown(moTeams, seconds: 5, deadline: 15, total: 5))
    }

    @Test func aHeldMeetingAsksWhenNotReadyAndDropsWhenGone() {
        var ask = ScribeAutoStartMachine()
        ask.handle(moEvidence(0, mode: .ask, scribe: .ending(moPrevious, deadline: 9)))
        #expect(ask.card(now: 0) == .waiting(moTeams))
        ask.handle(moTick(4, scribe: .idle, ready: .blocked(.notChosen)))
        #expect(ask.card(now: 4) == .offer(moTeams, blocked: .notChosen))

        var blocked = ScribeAutoStartMachine()
        blocked.handle(moEvidence(0, mode: .automatic, ready: .blocked(.firstRecordingOwed), scribe: .processing(moPrevious)))
        blocked.handle(moEvidence(5, mode: .automatic, ready: .blocked(.firstRecordingOwed)))
        #expect(blocked.card(now: 5) == .offer(moTeams, blocked: .firstRecordingOwed))

        var gone = ScribeAutoStartMachine()
        gone.handle(moEvidence(0, mode: .ask, scribe: .processing(moPrevious)))
        gone.handle(moEvidence(10, mic: [], mode: .ask))
        #expect(gone.state == .idle)
        #expect(gone.ledger.mark(of: moTeams) == nil)
    }

    @Test func cancelOnTheWaitingCardAnswersTheMeeting() {
        var machine = ScribeAutoStartMachine()
        machine.handle(moEvidence(0, mode: .automatic, scribe: .processing(moPrevious)))
        let effects = machine.handle(.cancel(on: .waiting(moTeams), now: 2))
        #expect(effects.isEmpty)
        #expect(machine.state == .idle)
        #expect(machine.ledger.mark(of: moTeams) == .declined)
        #expect(machine.handle(moEvidence(10, mode: .automatic)).isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func aRecordTapWhileSavingStartsOnceWhenFree() {
        var machine = moPrompting()
        let tap = machine.handle(moTap(moOffer(), 5, scribe: .processing(moPrevious)))
        #expect(tap.isEmpty)
        #expect(machine.state == .held(meeting: moTeams, startOwed: true))
        #expect(machine.card(now: 5) == .waiting(moTeams))
        #expect(machine.handle(moTick(6, scribe: .processing(moPrevious))).isEmpty)
        #expect(machine.handle(moEvidence(7, mode: .off, scribe: .processing(moPrevious))).isEmpty)
        let free = machine.handle(moTick(8, scribe: .complete(moPrevious)))
        #expect(free == [.start(moTeams)])
        #expect(moAttempt(machine)?.origin == .tap)
        #expect(moAttempt(machine)?.previousSession == moPrevious)
        #expect(machine.handle(moTick(8.1, scribe: .complete(moPrevious))).isEmpty)
    }

    @Test func aTapOwedWhileSavingJoinsARecordingThatBeganMeanwhile() {
        var machine = moPrompting()
        machine.handle(moTap(moOffer(), 5, scribe: .processing(moPrevious)))
        let effects = machine.handle(moTick(8, scribe: .recording(moFresh, since: 7)))
        #expect(effects.isEmpty)
        #expect(moRecording(machine)?.session == moFresh)
    }

    @Test func aCandidateSeenWhileSavingIsHeldAndOnlyARecordingMarksItStarted() {
        var saving = ScribeAutoStartMachine()
        saving.handle(moEvidence(0, scribe: .ending(moPrevious, deadline: 9)))
        #expect(saving.state == .held(meeting: moTeams, startOwed: false))
        #expect(saving.ledger.mark(of: moTeams) == nil)

        var armed = ScribeAutoStartMachine()
        armed.handle(moEvidence(0))
        armed.handle(moEvidence(1, scribe: .processing(moPrevious)))
        #expect(armed.state == .held(meeting: moTeams, startOwed: false))

        for phase in [ScribePhase.starting(moFresh), .recording(moFresh, since: 0)] {
            var idle = ScribeAutoStartMachine()
            idle.handle(moEvidence(0, scribe: phase))
            #expect(idle.state == .idle)
            #expect(idle.ledger.mark(of: moTeams) == .started)
        }
    }

    @Test func switchStartsTheNextMeetingOnceWithoutAskingAgain() {
        var machine = moRecordingWithNext()
        let next = moNext().meeting
        #expect(machine.card(now: 21) == .next(next))
        let tap = machine.handle(.primary(on: .next(next), now: 22, context: moContext(.recording(moFresh, since: 5))))
        #expect(tap == [.endNow])
        #expect(machine.state == .held(meeting: next, startOwed: true))
        #expect(machine.card(now: 22) == .waiting(next))
        #expect(machine.ledger.mark(of: moTeams) == .started)
        // The last meeting is ending, then saving: nothing starts, nothing is asked.
        #expect(machine.handle(moEvidence(24, slots: [moNext().slot], scribe: .ending(moFresh, deadline: 30))).isEmpty)
        #expect(machine.handle(moTick(30, scribe: .processing(moFresh))).isEmpty)
        let saved = machine.handle(moTick(40, scribe: .complete(moFresh)))
        #expect(saved == [.start(next)])
        #expect(moAttempt(machine)?.origin == .tap)
        #expect(machine.handle(moTick(40.5, scribe: .complete(moFresh))).isEmpty)
        #expect(machine.handle(moEvidence(41, slots: [moNext().slot], scribe: .complete(moFresh))).isEmpty)
    }

    @Test func dismissOnTheNextMeetingCardKeepsRecordingAndQuietsIt() {
        var machine = moRecordingWithNext()
        let next = moNext().meeting
        let effects = machine.handle(.dismiss(on: .next(next), now: 25))
        #expect(effects.isEmpty)
        #expect(machine.card(now: 25) == .hidden)
        #expect(moRecording(machine) != nil)
        #expect(machine.ledger.mark(of: next) == .declined)
    }

    // MARK: Card and wake rows

    @Test func theCardIsOneSwitchOverTheState() {
        #expect(ScribeAutoStartMachine().card(now: 0) == .hidden)

        var armed = ScribeAutoStartMachine()
        armed.handle(moEvidence(0))
        #expect(armed.card(now: 1) == .hidden)

        #expect(moPrompting().card(now: 3) == .offer(moTeams, blocked: .notChosen))
        #expect(moPrompting(.automatic, ready: .blocked(.noOptIn)).card(now: 3) == .offer(moTeams, blocked: .noOptIn))
        let counting = moPrompting(.automatic)
        #expect(counting.card(now: 3) == .countdown(moTeams, seconds: 5, deadline: 8, total: 5))
        #expect(counting.card(now: 4.5) == .countdown(moTeams, seconds: 4, deadline: 8, total: 5))
        #expect(counting.card(now: 7.2) == .countdown(moTeams, seconds: 1, deadline: 8, total: 5))

        var held = ScribeAutoStartMachine()
        held.handle(moEvidence(0, scribe: .processing(moPrevious)))
        #expect(held.card(now: 0) == .waiting(moTeams))

        #expect(moTapStarted().card(now: 4) == .starting(moTeams, cancellable: false))
        #expect(moAutomaticStarted().card(now: 8) == .starting(moTeams, cancellable: true))

        var recording = moTapStarted()
        recording.handle(.scribe(.recording(moFresh, since: 5), now: 5))
        #expect(recording.card(now: 5) == .recording(moTeams))
        #expect(recording.card(now: 7) == .hidden)

        let withNext = moRecordingWithNext()
        #expect(withNext.card(now: 21) == .next(moNext().meeting))

        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        #expect(failed.card(now: 5) == .failed(moTeams, .microphoneOff))
    }

    @Test func nothingIsScheduledWhenIdle() {
        let machine = ScribeAutoStartMachine()
        #expect(machine.nextWake(now: 0) == nil)
        var done = moPrompting()
        done.handle(.dismiss(on: moOffer(), now: 5))
        #expect(done.state == .idle)
        #expect(done.nextWake(now: 5) == nil)
    }

    @Test func eachStateWakesAtItsOwnNextChange() {
        var armed = ScribeAutoStartMachine()
        armed.handle(moEvidence(0))
        #expect(armed.nextWake(now: 1) == nil)

        // The offer: its deadline.
        var prompting = moPrompting()
        #expect(prompting.nextWake(now: 3) == 23)
        prompting.handle(.pointer(inside: true, now: 4))
        #expect(prompting.nextWake(now: 4) == nil)

        // The countdown: the next whole second, and the deadline for the last one.
        let counting = moPrompting(.automatic)
        #expect(counting.nextWake(now: 3) == 4)
        #expect(counting.nextWake(now: 4.5) == 5)
        #expect(counting.nextWake(now: 7.25) == 8)

        // Waiting for Scribe: only a Scribe event changes it.
        var held = ScribeAutoStartMachine()
        held.handle(moEvidence(0, scribe: .processing(moPrevious)))
        #expect(held.nextWake(now: 0) == nil)

        // Starting: no session yet, then a session that is still starting.
        var starting = moTapStarted()
        #expect(starting.nextWake(now: 4) == 9)
        starting.handle(.scribe(.starting(moFresh), now: 4.1))
        #expect(starting.nextWake(now: 4.1) == 49)

        // The confirmation, then nothing.
        var recording = moTapStarted()
        recording.handle(.scribe(.recording(moFresh, since: 5), now: 5))
        #expect(recording.nextWake(now: 5) == 6.5)
        recording.handle(moTick(6.5))
        #expect(recording.nextWake(now: 6.5) == nil)

        // A failure: its lifetime, unless the pointer is over it.
        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        #expect(failed.nextWake(now: 5) == 65)
        failed.handle(.pointer(inside: true, now: 6))
        #expect(failed.nextWake(now: 6) == nil)
    }

    @Test func aRecordingWakesForTheNextMeetingCardAndTheMinuteItReads() {
        var machine = moTapStarted()
        machine.handle(.scribe(.recording(moFresh, since: 5), now: 5))
        machine.handle(moTick(7))
        let slot = ScribeCalendarSlot(id: "n2", title: "Standup", start: moBase.addingTimeInterval(30), hasCallLink: true)
        machine.handle(moEvidence(20, slots: [slot], scribe: .recording(moFresh, since: 5)))
        #expect(machine.card(now: 20) == .next(ScribeMeeting(key: "n2", title: "Standup", callApp: .teams, slot: slot)))
        // 10 s to the start: "in 1 min" turns to "now" at the start, before the 40 s deadline.
        #expect(machine.nextWake(now: 20) == 30)
        // A far meeting: the minute it reads changes at its whole minutes, and the deadline comes first.
        var far = moRecordingWithNext()
        #expect(far.nextWake(now: 20) == 40)
        far.handle(moTick(40))
        #expect(far.nextWake(now: 40) == nil)
    }

    @Test func theCallLooksOverWakesEachSecond() {
        var machine = moTapStarted()
        machine.handle(.scribe(.recording(moFresh, since: 5), now: 5))
        machine.handle(moTick(7))
        machine.handle(moEvidence(8, scribe: .recording(moFresh, since: 5)))
        machine.handle(moEvidence(9, mic: [], scribe: .recording(moFresh, since: 5)))
        #expect(machine.needsFreshEvidence)
        #expect(machine.nextWake(now: 9) == 10)
    }

    // MARK: Words

    @Test func theStateAndThePhaseHavePlainLogNames() {
        #expect(ScribeAutoStartMachine().state.logName == "idle")
        #expect(moPrompting().state.logName == "offer call:Teams")
        #expect(moPrompting(.automatic).state.logName == "countdown call:Teams")
        #expect(moTapStarted().state.logName == "starting call:Teams")
        var failed = moPrompting()
        failed.handle(moTap(moOffer(), 5, microphone: .denied))
        #expect(failed.state.logName == "failed call:Teams: microphone off")
        var held = ScribeAutoStartMachine()
        held.handle(moEvidence(0, scribe: .processing(moPrevious)))
        #expect(held.state.logName == "waiting call:Teams")
        #expect(ScribePhase.idle.logName == "idle")
        #expect(ScribePhase.failed(moFresh, reason: "x").logName == "failed(x)")
        #expect(ScribePhase.processing(moFresh).logName == "processing")
        #expect(ScribeStartFailure.captureFailed("x").logReason == "capture failed: x")
        #expect(ScribeStartFailure.stillSaving.logReason == "previous meeting still saving")
        #expect(ScribeStartFailure.noResponse.logReason == "no response")
    }

    @Test func startFailureWordsUsePlainPunctuation() {
        let failures: [ScribeStartFailure] = [.microphoneOff, .stillSaving, .captureFailed("x"), .noResponse]
        for failure in failures {
            let words = ScribeMeetingCardText.reason(failure)
            #expect(!words.isEmpty)
            #expect(!words.contains("\u{2014}"))
            #expect(!words.contains("\u{2013}"))
        }
    }
}
