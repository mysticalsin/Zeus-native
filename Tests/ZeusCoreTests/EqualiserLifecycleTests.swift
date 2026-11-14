import Foundation
import Testing
@testable import ZeusCore

private typealias Life = EqualiserLifecycle
private typealias App = EqualiserPlayingGroup

private let music = App(bundleID: "com.apple.Music", displayName: "Music")
private let spotify = App(bundleID: "com.spotify.client", displayName: "Spotify")
private let podcasts = App(bundleID: "com.apple.podcasts", displayName: "Podcasts")

private let bassBoost = EqualiserParameters(gainsDB: [6, 4, 0, 0, 0, 0, 0, 0, 0, 0], volume: 1, bypass: false)
private let quieter = EqualiserParameters(gainsDB: [Double](repeating: 0, count: 10), volume: 0.5, bypass: false)

private func target(_ app: App, playing: Bool = true, _ parameters: EqualiserParameters = bassBoost) -> Life.Target {
    Life.Target(app: app, parameters: parameters, isPlaying: playing)
}

private func snap(_ targets: [Life.Target] = [], pause: EqualiserPause? = nil) -> Life.Snapshot {
    Life.Snapshot(targets: targets, pause: pause)
}

private func reduce(_ state: Life.State, _ event: Life.Event) -> (state: Life.State, effects: [Life.Effect]) {
    let result = Life.reduce(state, event)
    return (result.0, result.1)
}

/// One state of every kind, for checks that must hold from everywhere.
private let everyState: [Life.State] = [
    .off,
    .waitingForSound,
    .probing(music, attempt: 1, running: []),
    .probing(music, attempt: 2, running: [spotify]),
    .running([]),
    .running([music]),
    .running([music, spotify]),
    .paused(.callRecording),
    .paused(.zeusCaptures),
    .paused(.otherShaper),
    .paused(.asleep),
    .paused(.unsupportedOutput(reason: "no channels")),
    .stopped(.silentWhilePlaying(app: "Music")),
    .stopped(.repeatedFailures(app: "Music")),
    .stopped(.startFailed(status: -50)),
]

// MARK: - Switching on and off

@Suite struct EqualiserSwitchTests {
    @Test func onWithNothingPlayingWaitsForSound() {
        let result = reduce(.off, .switchedOn(personAsked: true, snap()))
        #expect(result.state == .waitingForSound)
        #expect(result.effects.isEmpty)
    }

    @Test func onWithAnAppPlayingProbesItBeforeAnyTap() {
        let result = reduce(.off, .switchedOn(personAsked: true, snap([target(music)])))
        #expect(result.state == .probing(music, attempt: 1, running: []))
        #expect(result.effects == [.probe(music, maxSeconds: Life.probeSeconds)])
        #expect(!result.effects.contains(.buildTap(music)))
    }

    @Test func onWhilePausedForAReasonGoesStraightToThatPause() {
        let result = reduce(.off, .switchedOn(personAsked: true, snap([target(music)], pause: .callRecording)))
        #expect(result.state == .paused(.callRecording))
        #expect(result.effects.first == .destroyAll)
        #expect(!result.effects.contains(.probe(music, maxSeconds: Life.probeSeconds)))
    }

    @Test func switchingOnTwiceChangesNothing() {
        let state = Life.State.running([music])
        let result = reduce(state, .switchedOn(personAsked: true, snap([target(music)])))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func tryAgainAfterAStopStartsOver() {
        let stopped = Life.State.stopped(.repeatedFailures(app: "Music"))
        let result = reduce(stopped, .switchedOn(personAsked: true, snap([target(music)])))
        #expect(result.state == .probing(music, attempt: 1, running: []))
        #expect(result.effects == [.probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func offFromEveryStateGivesOffWithDestroyAllFirst() {
        for state in everyState {
            let result = reduce(state, .switchedOff)
            #expect(result.state == .off, "\(state)")
            #expect(result.effects.first == .destroyAll, "\(state)")
            #expect(result.effects == [.destroyAll, .stopWatchdog], "\(state)")
        }
    }

    @Test func offWhileProbingDestroysTheProbe() {
        let result = reduce(.probing(music, attempt: 1, running: []), .switchedOff)
        #expect(result.state == .off)
        #expect(result.effects.first == .destroyAll)
    }

    @Test func nothingIsDoneInOffForOutsideChanges() {
        let busy = snap([target(music)])
        let events: [Life.Event] = [
            .processesChanged(busy), .settingsChanged(busy), .outputChanged(busy), .formatChanged(busy),
            .deviceGone(busy), .didWake(busy), .callRecordingChanged(busy), .zeusCaptureChanged(busy),
            .willSleep, .claimLost, .heartbeatMissed(music, failures: 1), .zerosWhilePlaying(music),
            .buildFailed(music, status: -1, failures: 1), .idleExpired(music), .helperJoined(music),
            .retargetFailed(music), .probeResult(music, .heard, seconds: 1, busy), .startFailed(status: -1),
        ]
        for event in events {
            let result = reduce(.off, event)
            #expect(result.state == .off, "\(event)")
            #expect(result.effects.isEmpty, "\(event)")
        }
    }
}

// MARK: - Probe

@Suite struct EqualiserProbeFlowTests {
    private let probing = Life.State.probing(music, attempt: 1, running: [])

    @Test func heardBuildsTheTapAndRecordsAllowed() {
        let result = reduce(probing, .probeResult(music, .heard, seconds: 0.4, snap([target(music)])))
        #expect(result.state == .running([music]))
        #expect(result.effects == [.recordAllowed, .buildTap(music), .startWatchdog])
    }

    @Test func recordAllowedComesOnlyAfterHeard() {
        for verdict in [EqualiserProbeVerdict.silent, .inconclusive] {
            let result = reduce(probing, .probeResult(music, verdict, seconds: 5, snap([target(music)])))
            #expect(!result.effects.contains(.recordAllowed), "\(verdict)")
        }
        for state in everyState {
            let result = reduce(state, .switchedOn(personAsked: true, snap([target(music)])))
            #expect(!result.effects.contains(.recordAllowed), "\(state)")
        }
    }

    @Test func noMutedTapFollowsASilentOrInconclusiveProbe() {
        for verdict in [EqualiserProbeVerdict.silent, .inconclusive] {
            for seconds in [0.5, 5, 30] {
                let result = reduce(probing, .probeResult(music, verdict, seconds: seconds, snap([target(music)])))
                #expect(!result.effects.contains(.buildTap(music)), "\(verdict) \(seconds)")
            }
        }
    }

    @Test func aFirstLongSilentProbeTriesOnceMore() {
        let result = reduce(probing, .probeResult(music, .silent, seconds: 5, snap([target(music)])))
        #expect(result.state == .probing(music, attempt: 2, running: []))
        #expect(result.effects == [.probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func twoLongSilentProbesStopWithTheAppName() {
        let second = Life.State.probing(music, attempt: 2, running: [spotify])
        let result = reduce(second, .probeResult(music, .silent, seconds: 5, snap([target(music), target(spotify)])))
        #expect(result.state == .stopped(.silentWhilePlaying(app: "Music")))
        #expect(result.effects.first == .destroyAll)
    }

    @Test func aShortSilentProbeDoesNotCount() {
        let second = Life.State.probing(music, attempt: 2, running: [])
        let result = reduce(second, .probeResult(music, .silent, seconds: 4.9, snap([target(music)])))
        #expect(result.state == .waitingForSound)
        #expect(result.effects.isEmpty)
    }

    @Test func inconclusiveWaitsForTheNextPlayInsteadOfLooping() {
        let result = reduce(probing, .probeResult(music, .inconclusive, seconds: 30, snap([target(music)])))
        #expect(result.state == .waitingForSound)
        #expect(result.effects.isEmpty)
    }

    @Test func inconclusiveKeepsTheTapsAlreadyRunning() {
        let state = Life.State.probing(music, attempt: 1, running: [spotify])
        let result = reduce(state, .probeResult(music, .inconclusive, seconds: 5, snap([target(music), target(spotify)])))
        #expect(result.state == .running([spotify]))
        #expect(result.effects.isEmpty)
    }

    @Test func aResultForAnotherAppIsStale() {
        let result = reduce(probing, .probeResult(spotify, .heard, seconds: 1, snap([target(spotify)])))
        #expect(result.state == probing)
        #expect(result.effects.isEmpty)
    }

    @Test func aResultOutsideAProbeIsStale() {
        let state = Life.State.running([music])
        let result = reduce(state, .probeResult(music, .heard, seconds: 1, snap([target(music)])))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func heardForAnAppThatStoppedPlayingBuildsNothing() {
        let result = reduce(probing, .probeResult(music, .heard, seconds: 1, snap()))
        #expect(result.state == .waitingForSound)
        #expect(!result.effects.contains(.buildTap(music)))
    }

    @Test func theNextWaitingAppIsProbedOnlyAfterTheFirstFinishes() {
        let start = reduce(.off, .switchedOn(personAsked: true, snap([target(music), target(spotify)])))
        #expect(start.state == .probing(music, attempt: 1, running: []))
        #expect(start.effects == [.probe(music, maxSeconds: Life.probeSeconds)])

        let both = snap([target(music), target(spotify)])
        let more = reduce(start.state, .processesChanged(both))
        #expect(more.effects.isEmpty)

        let done = reduce(start.state, .probeResult(music, .heard, seconds: 0.3, both))
        #expect(done.state == .probing(spotify, attempt: 1, running: [music]))
        #expect(done.effects == [.recordAllowed, .buildTap(music), .startWatchdog, .probe(spotify, maxSeconds: Life.probeSeconds)])
    }

    @Test func aProbeIsCancelledWhenItsAppStopsPlaying() {
        let result = reduce(probing, .processesChanged(snap()))
        #expect(result.state == .waitingForSound)
        #expect(result.effects == [.destroyTap(music)])
    }

    @Test func aProbeIsNotKeptByAnIdleTarget() {
        let result = reduce(probing, .processesChanged(snap([target(music, playing: false)])))
        #expect(result.effects == [.destroyTap(music)])
    }
}

// MARK: - Building and keeping taps

@Suite struct EqualiserTapSetTests {
    @Test func aNeutralAppNeverGetsATap() {
        // Neutral apps are not targets, so no event can build one.
        let result = reduce(.waitingForSound, .processesChanged(snap([])))
        #expect(result.effects.isEmpty)
        #expect(result.state == .waitingForSound)
    }

    @Test func aPlayingTargetAlreadyTappedChangesNothing() {
        let state = Life.State.running([music])
        let result = reduce(state, .processesChanged(snap([target(music)])))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func aTapStaysWhileItsAppIsIdleForTheGracePeriod() {
        let state = Life.State.running([music])
        let result = reduce(state, .processesChanged(snap([target(music, playing: false)])))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
        #expect(Life.idleSeconds == 30)
    }

    @Test func anIdleAppThatWasNeverTappedIsNotProbed() {
        let result = reduce(.waitingForSound, .processesChanged(snap([target(music, playing: false)])))
        #expect(result.effects.isEmpty)
    }

    @Test func aQuitAppLosesItsTapAtOnce() {
        let result = reduce(.running([music, spotify]), .processesChanged(snap([target(spotify)])))
        #expect(result.state == .running([spotify]))
        #expect(result.effects == [.destroyTap(music)])
    }

    @Test func theLastTapGoingStopsTheWatchdog() {
        let result = reduce(.running([music]), .processesChanged(snap()))
        #expect(result.state == .running([]))
        #expect(result.effects == [.destroyTap(music), .stopWatchdog])
    }

    @Test func idleExpiryRemovesThatTap() {
        let result = reduce(.running([music, spotify]), .idleExpired(music))
        #expect(result.state == .running([spotify]))
        #expect(result.effects == [.destroyTap(music)])
    }

    @Test func idleExpiryOfTheLastTapStopsTheWatchdog() {
        let result = reduce(.running([music]), .idleExpired(music))
        #expect(result.state == .running([]))
        #expect(result.effects == [.destroyTap(music), .stopWatchdog])
    }

    @Test func idleExpiryOfAnUnknownAppDoesNothing() {
        let result = reduce(.running([music]), .idleExpired(spotify))
        #expect(result.state == .running([music]))
        #expect(result.effects.isEmpty)
    }

    @Test func aSecondAppStartingPlayingIsProbedWhileTheFirstKeepsItsTap() {
        let result = reduce(.running([music]), .processesChanged(snap([target(music), target(spotify)])))
        #expect(result.state == .probing(spotify, attempt: 1, running: [music]))
        #expect(result.effects == [.probe(spotify, maxSeconds: Life.probeSeconds)])
    }

    @Test func destroysComeBeforeAProbeInTheSameChange() {
        let result = reduce(.running([music]), .processesChanged(snap([target(spotify)])))
        #expect(result.effects == [.destroyTap(music), .stopWatchdog, .probe(spotify, maxSeconds: Life.probeSeconds)])
    }

    @Test func settingsChangedPostsNewValuesToTappedApps() {
        let result = reduce(.running([music, spotify]), .settingsChanged(snap([target(music, quieter), target(spotify)])))
        #expect(result.state == .running([music, spotify]))
        #expect(result.effects == [.post(music, quieter), .post(spotify, bassBoost)])
    }

    @Test func settingsChangedToNeutralRemovesTheTap() {
        let result = reduce(.running([music]), .settingsChanged(snap()))
        #expect(result.state == .running([]))
        #expect(result.effects == [.destroyTap(music), .stopWatchdog])
    }

    @Test func settingsChangedForANewAppProbesIt() {
        let result = reduce(.running([music]), .settingsChanged(snap([target(music), target(spotify)])))
        #expect(result.state == .probing(spotify, attempt: 1, running: [music]))
        #expect(result.effects == [.post(music, bassBoost), .probe(spotify, maxSeconds: Life.probeSeconds)])
    }

    @Test func waitingForSoundProbesWhenAnAppStartsPlaying() {
        let result = reduce(.waitingForSound, .processesChanged(snap([target(podcasts)])))
        #expect(result.state == .probing(podcasts, attempt: 1, running: []))
        #expect(result.effects == [.probe(podcasts, maxSeconds: Life.probeSeconds)])
    }

    @Test func policyTargetsFeedTheReducerSoANeutralAppNeverBuilds() {
        var book = AppSoundBook()
        book.add(AppSoundSettings(bundleID: "com.apple.Music", displayName: "Music", shapes: true))
        let group = EqualiserProcessGroup(
            bundleID: "com.apple.Music", objectIDs: [1], pids: [2], isPlaying: true, devices: ["speakers"])
        let targets = EqualiserPolicy.targets(
            [group], names: [:], book: book, ownBundleID: "app.zeus.Zeus", defaultOutputUID: "speakers")
        let result = reduce(.off, .switchedOn(personAsked: true, snap(targets)))
        #expect(result.state == .waitingForSound)
        #expect(result.effects.isEmpty)
    }
}

// MARK: - Pauses

@Suite struct EqualiserPauseFlowTests {
    private let busy = [target(music)]

    @Test func everyPauseFromARunningStateDestroysEverythingFirst() {
        for pause: EqualiserPause in [.callRecording, .zeusCaptures, .otherShaper, .unsupportedOutput(reason: "x")] {
            let events: [Life.Event] = [
                .callRecordingChanged(snap(busy, pause: pause)),
                .zeusCaptureChanged(snap(busy, pause: pause)),
                .processesChanged(snap(busy, pause: pause)),
                .settingsChanged(snap(busy, pause: pause)),
            ]
            for event in events {
                let result = reduce(.running([music]), event)
                #expect(result.state == .paused(pause), "\(event)")
                #expect(result.effects == [.destroyAll, .stopWatchdog], "\(event)")
            }
        }
    }

    @Test func aCallStartDestroysTheTapFirst() {
        let result = reduce(.running([music]), .callRecordingChanged(snap(busy, pause: .callRecording)))
        #expect(result.effects.first == .destroyAll)
        #expect(result.state == .paused(.callRecording))
    }

    @Test func scribeStartingPolyglotAndRecordlyEachPauseWithDestroyAllFirst() {
        let id = ScribeSessionID()
        let cases: [(ScribePhase, Bool, Bool)] = [
            (.starting(id), false, false), (.idle, true, false), (.idle, false, true),
        ]
        for (phase, polyglot, recordly) in cases {
            let captures = EqualiserPolicy.zeusCaptures(
                scribe: phase, polyglotActive: polyglot, recordlySystemAudio: recordly)
            let pause = EqualiserPolicy.pauseReason(
                callRecording: false, zeusCaptures: captures, otherShaper: false, asleep: false, format: .supported)
            let result = reduce(.running([music]), .zeusCaptureChanged(snap(busy, pause: pause)))
            #expect(result.state == .paused(.zeusCaptures), "\(phase)")
            #expect(result.effects.first == .destroyAll, "\(phase)")
        }
    }

    @Test func aPauseWhileProbingOrWaitingDestroysEverythingFirst() {
        for state in [Life.State.waitingForSound, .probing(music, attempt: 1, running: [spotify])] {
            let result = reduce(state, .callRecordingChanged(snap(busy, pause: .callRecording)))
            #expect(result.state == .paused(.callRecording), "\(state)")
            #expect(result.effects.first == .destroyAll, "\(state)")
        }
    }

    @Test func theSamePauseAgainDoesNothing() {
        let state = Life.State.paused(.callRecording)
        let result = reduce(state, .processesChanged(snap(busy, pause: .callRecording)))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func aDifferentPauseReplacesTheOldOneWithoutNewEffects() {
        let result = reduce(.paused(.callRecording), .zeusCaptureChanged(snap(busy, pause: .zeusCaptures)))
        #expect(result.state == .paused(.zeusCaptures))
        #expect(result.effects.isEmpty)
    }

    @Test func whenTheReasonEndsAnAppThatPlaysIsProbedAgain() {
        let result = reduce(.paused(.callRecording), .callRecordingChanged(snap(busy)))
        #expect(result.state == .probing(music, attempt: 1, running: []))
        #expect(result.effects == [.probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func whenTheReasonEndsWithNothingPlayingTheStateIsRunningWithNoTaps() {
        let result = reduce(.paused(.zeusCaptures), .zeusCaptureChanged(snap()))
        #expect(result.state == .running([]))
        #expect(result.effects.isEmpty)
    }

    @Test func aLostClaimPausesWithDestroyAllFirst() {
        let result = reduce(.running([music]), .claimLost)
        #expect(result.state == .paused(.otherShaper))
        #expect(result.effects == [.destroyAll, .stopWatchdog])
    }

    @Test func sleepPausesAndWakeResumes() {
        let slept = reduce(.running([music]), .willSleep)
        #expect(slept.state == .paused(.asleep))
        #expect(slept.effects == [.destroyAll, .stopWatchdog])

        let woke = reduce(slept.state, .didWake(snap(busy)))
        #expect(woke.state == .probing(music, attempt: 1, running: []))
        #expect(woke.effects == [.probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func wakeIntoACallStaysPaused() {
        let woke = reduce(.paused(.asleep), .didWake(snap(busy, pause: .callRecording)))
        #expect(woke.state == .paused(.callRecording))
    }

    @Test func nothingResumesWhileAsleepExceptWake() {
        let result = reduce(.paused(.asleep), .processesChanged(snap(busy)))
        #expect(result.state == .paused(.asleep))
        #expect(result.effects.isEmpty)
        let other = reduce(.paused(.asleep), .callRecordingChanged(snap(busy)))
        #expect(other.state == .paused(.asleep))
    }

    @Test func aLostClaimWhilePausedOnlyChangesTheReason() {
        let result = reduce(.paused(.callRecording), .claimLost)
        #expect(result.state == .paused(.otherShaper))
        #expect(result.effects.isEmpty)
        let asleep = reduce(.paused(.asleep), .claimLost)
        #expect(asleep.state == .paused(.asleep))
        #expect(asleep.effects.isEmpty)
    }

    @Test func sleepWhileOffOrStoppedChangesNothing() {
        for state in [Life.State.off, .stopped(.startFailed(status: -1))] {
            let result = reduce(state, .willSleep)
            #expect(result.state == state)
            #expect(result.effects.isEmpty)
        }
    }

    @Test func sleepFromEveryOtherStateDestroysEverythingFirst() {
        for state in everyState {
            switch state {
            case .off, .stopped: continue
            default: break
            }
            let result = reduce(state, .willSleep)
            #expect(result.state == .paused(.asleep), "\(state)")
            #expect(result.effects.first == .destroyAll, "\(state)")
        }
    }

    @Test func aStoppedStateIgnoresEverythingExceptOffAndOn() {
        let stopped = Life.State.stopped(.repeatedFailures(app: "Music"))
        let events: [Life.Event] = [
            .processesChanged(snap(busy)), .settingsChanged(snap(busy)), .didWake(snap(busy)),
            .callRecordingChanged(snap(busy, pause: .callRecording)), .claimLost,
            .probeResult(music, .heard, seconds: 1, snap(busy)), .idleExpired(music),
        ]
        for event in events {
            let result = reduce(stopped, event)
            #expect(result.state == stopped, "\(event)")
            #expect(result.effects.isEmpty, "\(event)")
        }
    }
}

// MARK: - Output, format and device changes

@Suite struct EqualiserOutputChangeTests {
    private let busy = snap([target(music)])

    @Test func outputFormatAndDeviceChangesDestroyEverythingFirst() {
        let events: [Life.Event] = [.outputChanged(busy), .formatChanged(busy), .deviceGone(busy)]
        for event in events {
            for state in everyState {
                switch state {
                case .off, .stopped: continue
                case .paused(.asleep): continue
                default: break
                }
                let result = reduce(state, event)
                #expect(result.effects.first == .destroyAll, "\(event) from \(state)")
            }
        }
    }

    @Test func aRunningAppIsRebuiltDirectlyOnTheNewOutput() {
        let result = reduce(.running([music, spotify]), .outputChanged(snap([target(music), target(spotify)])))
        #expect(result.state == .running([music, spotify]))
        #expect(result.effects == [.destroyAll, .buildTap(music), .buildTap(spotify), .startWatchdog])
    }

    @Test func anAppThatWentQuietIsNotRebuiltButADeviceGoneStillDestroysFirst() {
        let result = reduce(.running([music]), .deviceGone(snap()))
        #expect(result.state == .running([]))
        #expect(result.effects == [.destroyAll, .stopWatchdog])
    }

    @Test func anUnsupportedNewFormatPausesInsteadOfRebuilding() {
        let bad = snap([target(music)], pause: .unsupportedOutput(reason: "sample rates differ"))
        let result = reduce(.running([music]), .formatChanged(bad))
        #expect(result.state == .paused(.unsupportedOutput(reason: "sample rates differ")))
        #expect(result.effects == [.destroyAll, .stopWatchdog])
        #expect(!result.effects.contains(.buildTap(music)))
    }

    @Test func aSupportedOutputEndsAnUnsupportedPause() {
        let state = Life.State.paused(.unsupportedOutput(reason: "x"))
        let result = reduce(state, .outputChanged(busy))
        #expect(result.state == .probing(music, attempt: 1, running: []))
        #expect(result.effects == [.destroyAll, .probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func aProbingAppIsProbedAgainOnTheNewOutput() {
        let result = reduce(.probing(music, attempt: 1, running: []), .outputChanged(busy))
        #expect(result.state == .probing(music, attempt: 1, running: []))
        #expect(result.effects == [.destroyAll, .probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func aTapThatWasBeingProbedKeepsOtherRunningTapsRebuilt() {
        let state = Life.State.probing(music, attempt: 2, running: [spotify])
        let result = reduce(state, .outputChanged(snap([target(music), target(spotify)])))
        #expect(result.state == .probing(music, attempt: 1, running: [spotify]))
        #expect(result.effects == [.destroyAll, .buildTap(spotify), .startWatchdog, .probe(music, maxSeconds: Life.probeSeconds)])
    }

    @Test func aWakeDuringSleepIsTheOnlyWayOut() {
        let result = reduce(.paused(.asleep), .outputChanged(busy))
        #expect(result.state == .paused(.asleep))
    }
}

// MARK: - Failures and back-off

@Suite struct EqualiserBackoffTests {
    @Test func theDelaysAreHalfOneTwoAndFourSecondsThenStop() {
        #expect(RebuildBackoff.delay(afterFailures: 1) == 0.5)
        #expect(RebuildBackoff.delay(afterFailures: 2) == 1)
        #expect(RebuildBackoff.delay(afterFailures: 3) == 2)
        #expect(RebuildBackoff.delay(afterFailures: 4) == 4)
        #expect(RebuildBackoff.delay(afterFailures: 5) == nil)
        #expect(RebuildBackoff.delay(afterFailures: 9) == nil)
    }

    @Test func failuresCountInsideASixtySecondWindow() {
        var backoff = RebuildBackoff()
        #expect(backoff.recordFailure(bundleID: "a", at: 0) == 1)
        #expect(backoff.recordFailure(bundleID: "a", at: 10) == 2)
        #expect(backoff.recordFailure(bundleID: "a", at: 20) == 3)
        #expect(backoff.recordFailure(bundleID: "a", at: 30) == 4)
        #expect(backoff.recordFailure(bundleID: "a", at: 40) == 5)
    }

    @Test func oldFailuresFallOutOfTheWindow() {
        var backoff = RebuildBackoff()
        for time in [0.0, 10, 20, 30] { _ = backoff.recordFailure(bundleID: "a", at: time) }
        #expect(backoff.recordFailure(bundleID: "a", at: 59.9) == 5)
        var later = RebuildBackoff()
        for time in [0.0, 10, 20, 30] { _ = later.recordFailure(bundleID: "a", at: time) }
        #expect(later.recordFailure(bundleID: "a", at: 60) == 4)
        #expect(later.recordFailure(bundleID: "a", at: 100) == 3)
    }

    @Test func eachAppHasItsOwnCount() {
        var backoff = RebuildBackoff()
        for time in [0.0, 1, 2, 3] { _ = backoff.recordFailure(bundleID: "a", at: time) }
        #expect(backoff.recordFailure(bundleID: "b", at: 4) == 1)
    }

    @Test func clearingForgetsOneApp() {
        var backoff = RebuildBackoff()
        for time in [0.0, 1, 2] { _ = backoff.recordFailure(bundleID: "a", at: time) }
        _ = backoff.recordFailure(bundleID: "b", at: 3)
        backoff.clear(bundleID: "a")
        #expect(backoff.recordFailure(bundleID: "a", at: 4) == 1)
        #expect(backoff.recordFailure(bundleID: "b", at: 5) == 2)
    }

    @Test func aBuildFailureDestroysThatTapAndSchedulesTheFirstRetry() {
        let result = reduce(.running([music, spotify]), .buildFailed(music, status: -50, failures: 1))
        #expect(result.state == .running([music, spotify]))
        #expect(result.effects == [.destroyTap(music), .scheduleRebuild(music, after: 0.5)])
    }

    @Test func laterFailuresBackOffLonger() {
        let delays: [Int: TimeInterval] = [2: 1, 3: 2, 4: 4]
        for (failures, delay) in delays {
            let result = reduce(.running([music]), .buildFailed(music, status: -50, failures: failures))
            #expect(result.effects == [.destroyTap(music), .scheduleRebuild(music, after: delay)])
        }
    }

    @Test func theFifthFailureInsideTheWindowStopsWithTheAppName() {
        let result = reduce(.running([music, spotify]), .buildFailed(music, status: -50, failures: 5))
        #expect(result.state == .stopped(.repeatedFailures(app: "Music")))
        #expect(result.effects == [.destroyAll, .stopWatchdog])
    }

    @Test func aMissedHeartbeatBacksOffTheSameWay() {
        let first = reduce(.running([music]), .heartbeatMissed(music, failures: 1))
        #expect(first.effects == [.destroyTap(music), .scheduleRebuild(music, after: 0.5)])
        let fifth = reduce(.running([music]), .heartbeatMissed(music, failures: 5))
        #expect(fifth.state == .stopped(.repeatedFailures(app: "Music")))
        #expect(fifth.effects.first == .destroyAll)
    }

    @Test func aFailureForAnUnknownAppIsIgnored() {
        let state = Life.State.running([music])
        let result = reduce(state, .buildFailed(spotify, status: -1, failures: 1))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func aFailureForAnAppStillBeingProbedIsIgnored() {
        let state = Life.State.probing(music, attempt: 1, running: [])
        let result = reduce(state, .buildFailed(music, status: -1, failures: 1))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func aFailureWhileProbingAnotherAppKeepsTheProbe() {
        let state = Life.State.probing(spotify, attempt: 1, running: [music])
        let result = reduce(state, .buildFailed(music, status: -50, failures: 1))
        #expect(result.state == state)
        #expect(result.effects == [.destroyTap(music), .scheduleRebuild(music, after: 0.5)])
    }

    @Test func aStartFailureStopsWithTheStatusAndDestroysFirst() {
        for state in everyState {
            switch state {
            case .off, .stopped: continue
            default: break
            }
            let result = reduce(state, .startFailed(status: -10_877))
            #expect(result.state == .stopped(.startFailed(status: -10_877)), "\(state)")
            #expect(result.effects == [.destroyAll, .stopWatchdog], "\(state)")
        }
    }
}

// MARK: - Helpers joining

@Suite struct EqualiserHelperTests {
    @Test func aHelperJoiningRetargetsTheLiveTap() {
        let result = reduce(.running([music]), .helperJoined(music))
        #expect(result.state == .running([music]))
        #expect(result.effects == [.retarget(music)])
    }

    @Test func aHelperJoiningAnUntappedAppDoesNothing() {
        let result = reduce(.running([music]), .helperJoined(spotify))
        #expect(result.effects.isEmpty)
    }

    @Test func aFailedRetargetRebuildsThatTap() {
        let result = reduce(.running([music, spotify]), .retargetFailed(music))
        #expect(result.state == .running([music, spotify]))
        #expect(result.effects == [.destroyTap(music), .buildTap(music)])
    }

    @Test func aFailedRetargetForAnUntappedAppDoesNothing() {
        let result = reduce(.running([music]), .retargetFailed(spotify))
        #expect(result.effects.isEmpty)
    }
}

// MARK: - Watchdog and zeros

@Suite struct EqualiserWatchdogTests {
    @Test func noCallbackForTwoSecondsWhilePlayingIsMissed() {
        #expect(EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 10, elapsed: 2, appPlaying: true))
        #expect(EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 10, elapsed: 3.5, appPlaying: true))
    }

    @Test func justUnderTwoSecondsIsNotMissed() {
        #expect(!EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 10, elapsed: 1.99, appPlaying: true))
        #expect(!EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 10, elapsed: 1, appPlaying: true))
    }

    @Test func aMovingCounterIsNeverMissed() {
        #expect(!EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 11, elapsed: 30, appPlaying: true))
    }

    @Test func aResetCounterIsNotMissed() {
        #expect(!EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 0, elapsed: 30, appPlaying: true))
    }

    @Test func silenceIsFineWhileTheAppIsNotPlaying() {
        #expect(!EqualiserWatchdog.missed(lastBeatCount: 10, currentCount: 10, elapsed: 60, appPlaying: false))
    }
}

@Suite struct EqualiserZeroWatchTests {
    @Test func twoSecondsOfZerosUnderAMutedTapWhilePlayingIsAStall() {
        #expect(ZeroWatch.verdict(zeroFrames: 96_000, sampleRate: 48_000, playing: true, muted: true) == .stalled)
        #expect(ZeroWatch.verdict(zeroFrames: 88_200, sampleRate: 44_100, playing: true, muted: true) == .stalled)
    }

    @Test func justUnderTwoSecondsIsFine() {
        #expect(ZeroWatch.verdict(zeroFrames: 95_999, sampleRate: 48_000, playing: true, muted: true) == .fine)
    }

    @Test func zerosWhileNotPlayingAreFine() {
        #expect(ZeroWatch.verdict(zeroFrames: 960_000, sampleRate: 48_000, playing: false, muted: true) == .fine)
    }

    @Test func zerosUnderAListenOnlyProbeAreNotAStall() {
        #expect(ZeroWatch.verdict(zeroFrames: 960_000, sampleRate: 48_000, playing: true, muted: false) == .fine)
    }

    @Test func aBadRateIsNeverAStall() {
        #expect(ZeroWatch.verdict(zeroFrames: 960_000, sampleRate: 0, playing: true, muted: true) == .fine)
        #expect(ZeroWatch.verdict(zeroFrames: 960_000, sampleRate: -1, playing: true, muted: true) == .fine)
    }

    @Test func zerosUnderAMutedTapDestroyTheTapBeforeAnythingElseThenProbe() {
        let result = reduce(.running([music, spotify]), .zerosWhilePlaying(music))
        #expect(result.effects.first == .destroyTap(music))
        #expect(result.effects == [.destroyTap(music), .probe(music, maxSeconds: Life.probeSeconds)])
        #expect(result.state == .probing(music, attempt: 1, running: [spotify]))
    }

    @Test func zerosOnTheOnlyTapAlsoStopTheWatchdogAfterTheDestroy() {
        let result = reduce(.running([music]), .zerosWhilePlaying(music))
        #expect(result.effects == [.destroyTap(music), .stopWatchdog, .probe(music, maxSeconds: Life.probeSeconds)])
        #expect(result.state == .probing(music, attempt: 1, running: []))
    }

    @Test func zerosForAnUntappedAppDoNothing() {
        let state = Life.State.running([music])
        let result = reduce(state, .zerosWhilePlaying(spotify))
        #expect(result.state == state)
        #expect(result.effects.isEmpty)
    }

    @Test func afterAStallTheAppIsMutedAgainOnlyAfterHeard() {
        let stalled = reduce(.running([music]), .zerosWhilePlaying(music))
        let silent = reduce(stalled.state, .probeResult(music, .silent, seconds: 5, snap([target(music)])))
        #expect(!silent.effects.contains(.buildTap(music)))
        let heard = reduce(stalled.state, .probeResult(music, .heard, seconds: 0.3, snap([target(music)])))
        #expect(heard.effects == [.recordAllowed, .buildTap(music), .startWatchdog])
        #expect(heard.state == .running([music]))
    }
}

// MARK: - Status text

@Suite struct EqualiserStatusTextTests {
    @Test func theLinesMatchTheDesignCopy() {
        #expect(EqualiserStatusText.line(for: .off) == "Off. No app is tapped.")
        #expect(EqualiserStatusText.line(for: .waitingForSound) == "On. Play something in an app to finish setting up.")
        #expect(EqualiserStatusText.line(for: .running([])) == "On. Nothing to shape right now.")
        #expect(EqualiserStatusText.line(for: .running([music])) == "Shaping 1 app.")
        #expect(EqualiserStatusText.line(for: .running([music, spotify])) == "Shaping 2 apps.")
        #expect(
            EqualiserStatusText.line(for: .paused(.callRecording))
                == "Paused while a call app uses the microphone.")
        #expect(
            EqualiserStatusText.line(for: .paused(.zeusCaptures))
                == "Paused while Zeus records or captions this Mac's sound.")
        #expect(
            EqualiserStatusText.line(for: .paused(.otherShaper))
                == "Paused: another copy of Zeus is shaping sound.")
        #expect(
            EqualiserStatusText.line(for: .paused(.unsupportedOutput(reason: "anything")))
                == "Paused: this output is not supported.")
        #expect(
            EqualiserStatusText.line(for: .stopped(.silentWhilePlaying(app: "Music")))
                == "Zeus hears nothing from Music while it plays. If System Audio Recording is off for Zeus, turn it on. If you just turned it on, quit and reopen Zeus. Then press Try again.")
        #expect(
            EqualiserStatusText.line(for: .stopped(.repeatedFailures(app: "Spotify")))
                == "Stopped shaping Spotify after repeated errors. It plays normally.")
    }

    @Test func probingNamesTheAppBeingChecked() {
        #expect(
            EqualiserStatusText.line(for: .probing(music, attempt: 1, running: []))
                == "On. Checking sound from Music.")
    }

    @Test func aProbeNextToRunningTapsStillSaysChecking() {
        #expect(
            EqualiserStatusText.line(for: .probing(spotify, attempt: 1, running: [music]))
                == "On. Checking sound from Spotify.")
    }

    @Test func aStartFailureNamesTheStatus() {
        let line = EqualiserStatusText.line(for: .stopped(.startFailed(status: -10_877)))
        #expect(line == "Could not start shaping sound (error -10877). Apps play normally.")
    }

    @Test func pauseAndSleepLines() {
        #expect(EqualiserStatusText.line(for: .paused(.asleep)) == "Paused while this Mac sleeps.")
    }

    @Test func everyLineIsFreeOfEmAndEnDashes() {
        for state in everyState {
            let line = EqualiserStatusText.line(for: state)
            #expect(!line.isEmpty, "\(state)")
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(state)")
        }
    }

    @Test func everyStateHasASymbolThatIsAName() {
        for state in everyState {
            let symbol = EqualiserStatusText.symbol(for: state)
            #expect(!symbol.isEmpty, "\(state)")
            #expect(symbol.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." }, "\(state)")
        }
    }

    @Test func eachKindOfStateHasItsOwnWordsAndNeverRepeatsAnotherKinds() {
        let lines = [
            EqualiserStatusText.line(for: .off),
            EqualiserStatusText.line(for: .waitingForSound),
            EqualiserStatusText.line(for: .running([])),
            EqualiserStatusText.line(for: .paused(.asleep)),
            EqualiserStatusText.line(for: .stopped(.startFailed(status: 1))),
        ]
        #expect(Set(lines).count == lines.count)
    }
}
