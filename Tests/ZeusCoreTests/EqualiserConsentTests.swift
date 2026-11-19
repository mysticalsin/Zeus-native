import Foundation
import Testing
@testable import ZeusCore

private typealias Life = EqualiserLifecycle
private typealias App = EqualiserPlayingGroup

private let music = App(bundleID: "com.apple.Music", displayName: "Music")
private let spotify = App(bundleID: "com.spotify.client", displayName: "Spotify")
private let bass = EqualiserParameters(gainsDB: [6, 4, 0, 0, 0, 0, 0, 0, 0, 0], volume: 1, bypass: false)

private func playing(_ app: App) -> Life.Target { Life.Target(app: app, parameters: bass, isPlaying: true) }

private func snap(
    _ targets: [Life.Target] = [], permission: AudioCapturePermission = .allowed, personAsked: Bool = true
) -> Life.Snapshot {
    Life.Snapshot(targets: targets, pause: nil, permission: permission, personAsked: personAsked)
}

private func mutedBuilds(_ effects: [Life.Effect]) -> [Life.Effect] {
    effects.filter { if case .buildTap = $0 { return true } else { return false } }
}

@Suite struct EqualiserConsentRuleTests {
    @Test func realSoundIsHeardWhateverElseIsTrue() {
        #expect(EqualiserConsent.verdict(nonZeroFrames: 1, framesSeen: 4_800, appPlaying: true) == .heard)
        #expect(EqualiserConsent.verdict(nonZeroFrames: 1, framesSeen: 4_800, appPlaying: false) == .heard)
    }

    @Test func zerosWhilePlayingAreSilent() {
        #expect(EqualiserConsent.verdict(nonZeroFrames: 0, framesSeen: 240_000, appPlaying: true) == .silent)
    }

    @Test func zerosWithoutPlayingOrWithoutFramesAreInconclusive() {
        #expect(EqualiserConsent.verdict(nonZeroFrames: 0, framesSeen: 240_000, appPlaying: false) == .inconclusive)
        #expect(EqualiserConsent.verdict(nonZeroFrames: 0, framesSeen: 0, appPlaying: true) == .inconclusive)
    }

    @Test func theFirstProbeAfterNotAskedIsThirtySecondsAndTheRestFive() {
        #expect(EqualiserConsent.probeSeconds(permission: .notAsked) == 30)
        #expect(EqualiserConsent.probeSeconds(permission: .allowed) == 5)
        #expect(EqualiserConsent.probeSeconds(permission: .refused) == 5)
    }

    @Test func twoCountedSilentProbesStop() {
        #expect(!EqualiserConsent.stopsAfter(0))
        #expect(!EqualiserConsent.stopsAfter(1))
        #expect(EqualiserConsent.stopsAfter(2))
        #expect(EqualiserConsent.stopsAfter(3))
    }
}

@Suite struct EqualiserConsentFlowTests {
    @Test func noProbeWithoutAPersonsRequest() {
        let result = Life.reduce(.off, .switchedOn(personAsked: false, snap([playing(music)], permission: .notAsked)))
        #expect(result.0 == .waitingForSound)
        #expect(result.1.isEmpty)
        let later = Life.reduce(
            result.0, .processesChanged(snap([playing(music)], permission: .notAsked, personAsked: false)))
        #expect(later.1.isEmpty)
    }

    @Test func aStoredAllowedStillProbesBeforeAnyMutedTap() {
        let result = Life.reduce(.off, .switchedOn(personAsked: true, snap([playing(music)], permission: .allowed)))
        #expect(result.1 == [.probe(music, maxSeconds: 5)])
        #expect(mutedBuilds(result.1).isEmpty)
    }

    @Test func theFirstProbeAfterNotAskedListensThirtySeconds() {
        let result = Life.reduce(.off, .switchedOn(personAsked: true, snap([playing(music)], permission: .notAsked)))
        #expect(result.1 == [.probe(music, maxSeconds: 30)])
    }

    @Test func aRecordedRefusalShowsTheStoppedLineWithoutProbing() {
        let result = Life.reduce(.off, .switchedOn(personAsked: true, snap([playing(music)], permission: .refused)))
        #expect(result.0 == .stopped(.silentWhilePlaying(app: "Music")))
        #expect(!result.1.contains(.probe(music, maxSeconds: 5)))
        #expect(mutedBuilds(result.1).isEmpty)
        // Nothing but the owner's switch leaves a stop.
        let still = Life.reduce(
            result.0, .processesChanged(snap([playing(music)], permission: .allowed)))
        #expect(still.0 == result.0)
        #expect(still.1.isEmpty)
    }

    @Test func aRefusalWithNothingPlayingWaitsQuietly() {
        let result = Life.reduce(.off, .switchedOn(personAsked: true, snap([], permission: .refused)))
        #expect(result.0 == .waitingForSound)
        #expect(result.1.isEmpty)
    }

    @Test func oneSilentProbeIsInconclusiveAndTwoStopWithNoMutedTap() {
        let probing = Life.State.probing(music, attempt: 1, running: [])
        let first = Life.reduce(probing, .probeResult(music, .silent, seconds: 5, snap([playing(music)])))
        #expect(first.0 == .probing(music, attempt: 2, running: []))
        #expect(mutedBuilds(first.1).isEmpty)
        let second = Life.reduce(first.0, .probeResult(music, .silent, seconds: 5, snap([playing(music)])))
        #expect(second.0 == .stopped(.silentWhilePlaying(app: "Music")))
        #expect(mutedBuilds(second.1).isEmpty)
        #expect(second.1.first == .destroyAll)
    }

    @Test func aShortSilentProbeDoesNotCount() {
        let probing = Life.State.probing(music, attempt: 1, running: [])
        let short = Life.reduce(probing, .probeResult(music, .silent, seconds: 4.9, snap([playing(music)])))
        if case .stopped = short.0 { Issue.record("a short silent probe must not stop") }
        #expect(mutedBuilds(short.1).isEmpty)
    }

    @Test func inconclusiveNeverMutesAnyApp() {
        let probing = Life.State.probing(music, attempt: 1, running: [])
        let result = Life.reduce(
            probing, .probeResult(music, .inconclusive, seconds: 5, snap([playing(music), playing(spotify)])))
        #expect(mutedBuilds(result.1).isEmpty)
        #expect(result.1 == [.probe(spotify, maxSeconds: 5)])
    }

    @Test func allowedIsRecordedOnlyAfterHeardAndNoEffectWritesARefusal() {
        let probing = Life.State.probing(music, attempt: 1, running: [])
        for verdict in [EqualiserProbeVerdict.silent, .inconclusive] {
            let result = Life.reduce(probing, .probeResult(music, verdict, seconds: 5, snap([playing(music)])))
            #expect(!result.1.contains(.recordAllowed), "\(verdict)")
        }
        let heard = Life.reduce(probing, .probeResult(music, .heard, seconds: 1, snap([playing(music)])))
        #expect(heard.1 == [.recordAllowed, .buildTap(music), .startWatchdog])
        // The effect list has no case that records a refusal at all.
        let every: [Life.Effect] = heard.1
        #expect(every.allSatisfy { "\($0)" != "recordRefused" })
    }

    @Test func switchingOffDuringAProbeDestroysTheProbe() {
        let result = Life.reduce(.probing(music, attempt: 1, running: []), .switchedOff)
        #expect(result.0 == .off)
        #expect(result.1.first == .destroyAll)
    }

    @Test func aMutedBuildOnlyFollowsAHeardProbeFromEveryStartingState() {
        let starts: [Life.State] = [.off, .waitingForSound, .stopped(.repeatedFailures(app: "Music"))]
        for start in starts {
            for permission in [AudioCapturePermission.notAsked, .allowed, .refused] {
                let result = Life.reduce(start, .switchedOn(personAsked: true, snap([playing(music)], permission: permission)))
                #expect(mutedBuilds(result.1).isEmpty, "\(start) \(permission)")
            }
        }
    }
}
