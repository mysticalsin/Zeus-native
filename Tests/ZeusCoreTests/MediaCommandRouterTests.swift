import Foundation
import Testing
@testable import ZeusCore

/// Records the effects a transport press produced. The home play control used to call a closure
/// that sent nothing; these tests require the press to hand a command to this sink.
private struct MediaCommandSink: Equatable {
    var commands: [MediaControlCommand] = []
    var routes: [MediaCommandRoute] = []
    var resyncAfter: [Double] = []
    var recoveries = 0

    mutating func take(_ effects: [MediaCommandEffect]) {
        for effect in effects {
            switch effect {
            case .send(let command, let route):
                commands.append(command)
                routes.append(route)
            case .resync(_, let after):
                resyncAfter.append(after)
            case .openRecovery:
                recoveries += 1
            }
        }
    }
}

@Suite struct MediaCommandRouterTests {
    private let player = MediaCommandRoute(endpoint: .scriptedPlayer(bundleID: "com.apple.Music"), canSkip: true, canSeek: true)

    private func sample(playing: Bool, route: MediaCommandRoute? = nil, duration: Double = 200) -> MediaNowPlayingSample {
        MediaNowPlayingSample(isPlaying: playing, position: 10, duration: duration, route: route ?? player)
    }

    private func pausedRouter(route: MediaCommandRoute? = nil, duration: Double = 200) throws -> MediaCommandRouter {
        var router = MediaCommandRouter()
        _ = try router.reduce(.info(sample(playing: false, route: route, duration: duration)), now: 0)
        return router
    }

    private func playingRouter(route: MediaCommandRoute? = nil, duration: Double = 200) throws -> MediaCommandRouter {
        var router = MediaCommandRouter()
        _ = try router.reduce(.info(sample(playing: true, route: route, duration: duration)), now: 0)
        return router
    }

    // MARK: The press reaches a sink

    @Test func playOnAPausedPlayerReachesTheSink() throws {
        var router = try pausedRouter()
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.press(.play), now: 1))
        #expect(sink.commands == [.play])
        #expect(sink.routes == [player])
        #expect(sink.resyncAfter == [MediaCommandRouter.resyncDelay])
        #expect(MediaCommandRouter.resyncDelay < 0.15)
        #expect(router.state == .commandPending(.play))
        _ = try router.reduce(.result(.accepted), now: 1.05)
        #expect(router.state == .playing)
    }

    @Test func pauseOnAPlayingPlayerReachesTheSink() throws {
        var router = try playingRouter()
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.press(.pause), now: 1))
        #expect(sink.commands == [.pause])
        #expect(router.state == .commandPending(.pause))
        _ = try router.reduce(.result(.accepted), now: 1.05)
        #expect(router.state == .paused)
    }

    @Test func nextAndPreviousReachTheSink() throws {
        var next = try playingRouter()
        var sink = MediaCommandSink()
        sink.take(try next.reduce(.press(.next), now: 1))
        #expect(sink.commands == [.next])
        _ = try next.reduce(.result(.accepted), now: 1.4)
        #expect(next.state == .playing)

        var previous = try pausedRouter()
        sink = MediaCommandSink()
        sink.take(try previous.reduce(.press(.previous), now: 2))
        #expect(sink.commands == [.previous])
        _ = try previous.reduce(.result(.accepted), now: 2.4)
        #expect(previous.state == .paused)
    }

    @Test func seekReachesTheSinkWhenTheTrackHasALength() throws {
        var router = try playingRouter()
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.press(.seek(500)), now: 1))
        #expect(sink.commands == [.seek(199.5)])
        _ = try router.reduce(.result(.accepted), now: 1.4)
        #expect(router.state == .playing)
        #expect(router.position == 199.5)
    }

    // MARK: Empty, denied, debounce, resync

    @Test func noSourcePressSendsNothingAndKeepsTheGuidance() throws {
        var router = MediaCommandRouter()
        _ = try router.reduce(.info(nil), now: 0)
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.press(.play), now: 1))
        sink.take(try router.reduce(.press(.next), now: 2))
        #expect(sink.commands.isEmpty)
        #expect(router.state == .noSource)
        #expect(MediaControlPresentation.guidance(for: .noSource) == "Nothing is playing. Start playback, then these controls follow it.")
    }

    @Test func permissionDeniedShowsAnErrorAndRecoveryOpensSettings() throws {
        var router = try pausedRouter()
        _ = try router.reduce(.press(.play), now: 1)
        _ = try router.reduce(.result(.permissionDenied), now: 1.05)
        #expect(router.state == .failed(.permissionDenied))
        #expect(MediaControlPresentation.showsRecovery(router.state))
        #expect(MediaControlPresentation.guidance(for: router.state) == "Playback controls need permission.")
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.recover, now: 2))
        #expect(sink.recoveries == 1)
        #expect(sink.commands.isEmpty)
        #expect(router.state == .paused)
        #expect(throws: MediaCommandRejection(.illegalTransition)) {
            try router.reduce(.recover, now: 3)
        }
    }

    @Test func aPressWhilePermissionIsDeniedSendsNothing() throws {
        var router = try pausedRouter()
        _ = try router.reduce(.press(.play), now: 1)
        _ = try router.reduce(.result(.permissionDenied), now: 1.2)
        let before = router
        #expect(throws: MediaCommandRejection(.blocked)) {
            try router.reduce(.press(.play), now: 5)
        }
        #expect(router == before)
    }

    @Test func aRapidSecondPressSendsNothing() throws {
        var router = try pausedRouter()
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.press(.play), now: 10))
        let pending = router
        #expect(throws: MediaCommandRejection(.inFlight)) {
            try router.reduce(.press(.pause), now: 10.05)
        }
        #expect(router == pending)
        #expect(sink.commands == [.play])
        _ = try router.reduce(.result(.accepted), now: 10.1)
        #expect(throws: MediaCommandRejection(.duplicate)) {
            try router.reduce(.press(.pause), now: 10.2)
        }
        #expect(router.state == .playing)
        #expect(sink.commands == [.play])
    }

    @Test func aRealSampleReplacesAPendingCommand() throws {
        var held = try pausedRouter()
        _ = try held.reduce(.press(.play), now: 5)
        _ = try held.reduce(.info(sample(playing: false)), now: 5.05)
        #expect(held.state == .commandPending(.play))
        _ = try held.reduce(.info(sample(playing: true, duration: 180)), now: 5.08)
        #expect(held.state == .playing)
        #expect(held.duration == 180)

        var late = try pausedRouter()
        _ = try late.reduce(.press(.play), now: 5)
        _ = try late.reduce(.info(sample(playing: false)), now: 5.2)
        #expect(late.state == .paused)
    }

    @Test func aFailedCommandCanBeRetried() throws {
        var router = try playingRouter()
        _ = try router.reduce(.press(.pause), now: 1)
        _ = try router.reduce(.result(.failed), now: 1.05)
        #expect(router.state == .failed(.unavailable))
        #expect(MediaControlPresentation.guidance(for: router.state) == "The player did not answer. Try again.")
        var sink = MediaCommandSink()
        sink.take(try router.reduce(.press(.pause), now: 2))
        #expect(sink.commands == [.pause])
    }

    // MARK: Illegal transitions

    @Test func illegalTransitionsAreRejected() throws {
        var fresh = MediaCommandRouter()
        try expectUnchanged(&fresh) { router in _ = try router.reduce(.press(.play), now: 1) }

        var playing = try playingRouter()
        try expectUnchanged(&playing) { router in _ = try router.reduce(.press(.play), now: 1) }

        var paused = try pausedRouter()
        try expectUnchanged(&paused) { router in _ = try router.reduce(.press(.pause), now: 1) }

        let quiet = MediaCommandRoute(endpoint: .browser(tabID: 4, documentID: "doc"), canSkip: false, canSeek: false)
        var browser = try playingRouter(route: quiet, duration: 0)
        try expectUnchanged(&browser) { router in _ = try router.reduce(.press(.next), now: 1) }
        try expectUnchanged(&browser) { router in _ = try router.reduce(.press(.previous), now: 1) }
        try expectUnchanged(&browser) { router in _ = try router.reduce(.press(.seek(3)), now: 1) }

        var settled = try pausedRouter()
        _ = try settled.reduce(.press(.play), now: 1)
        _ = try settled.reduce(.result(.accepted), now: 1.4)
        try expectUnchanged(&settled) { router in _ = try router.reduce(.result(.accepted), now: 2) }
        try expectUnchanged(&settled) { router in _ = try router.reduce(.recover, now: 3) }
    }

    // MARK: Motion, VoiceOver, the private route

    @Test func reduceMotionKeepsTheTransportStill() {
        #expect(MediaControlPresentation.pressScale(reduceMotion: true) == 1)
        #expect(MediaControlPresentation.animatesPress(reduceMotion: true) == false)
        #expect(MediaControlPresentation.pressScale(reduceMotion: false) == MotionTokens.pressScale)
        #expect(MediaControlPresentation.animatesPress(reduceMotion: false))
    }

    @Test func voiceOverLabelsNameTheControlAndTheState() {
        let playing = MediaControlPresentation.accessibility(for: .playing, fallbackPlaying: true)
        #expect(playing.pauseLabel == "Pause")
        #expect(playing.pauseHint == "Pauses the current track.")
        #expect(playing.previousLabel == "Previous track")
        #expect(playing.nextLabel == "Next track")
        #expect(playing.seekLabel == "Playback position")
        #expect(playing.value == "Playing")

        let paused = MediaControlPresentation.accessibility(for: .paused, fallbackPlaying: false)
        #expect(paused.playLabel == "Play")
        #expect(paused.playHint == "Plays the current track.")
        #expect(paused.previousHint == "Plays the previous track.")
        #expect(paused.nextHint == "Plays the next track.")
        #expect(paused.seekHint == "Moves the playhead.")
        #expect(paused.value == "Paused")

        let empty = MediaControlPresentation.accessibility(for: .noSource, fallbackPlaying: false)
        #expect(empty.value == "Nothing playing")
        #expect(MediaControlPresentation.activation(.noSource, fallbackPlaying: false) == .press(.play))

        let denied = MediaControlPresentation.accessibility(for: .failed(.permissionDenied), fallbackPlaying: false)
        #expect(denied.recoveryLabel == "Allow playback control")
        #expect(denied.recoveryHint == "Opens Settings to allow playback control.")
        #expect(denied.value == "Needs permission")
        #expect(MediaControlPresentation.activation(.failed(.permissionDenied), fallbackPlaying: true) == .recover)
        #expect(MediaControlPresentation.showsPause(.failed(.permissionDenied), fallbackPlaying: true) == false)
    }

    @Test func thePrivateRouteStaysOff() {
        #expect(MediaRemoteCommandGate.enabled == false)
        let commands: [MediaControlCommand] = [.play, .pause, .next, .previous, .seek(1)]
        for command in commands {
            #expect(MediaRemoteCommandGate.attempt(command) == .unavailable)
        }
    }

    private func expectUnchanged(_ router: inout MediaCommandRouter, _ body: (inout MediaCommandRouter) throws -> Void) throws {
        let before = router
        var rejected = false
        do {
            try body(&router)
        } catch is MediaCommandRejection {
            rejected = true
        }
        #expect(rejected)
        #expect(router == before)
    }
}
