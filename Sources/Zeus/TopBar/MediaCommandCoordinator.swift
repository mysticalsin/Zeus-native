import Foundation
import os
import ZeusCore

private enum MediaCommandLog {
    static let logger = Logger(subsystem: "app.zeus.mac", category: "media-playback")

    static func write(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

/// Runs the home and music transport through `MediaCommandRouter`.
///
/// A scripted player is told with an Apple Event, by bundle id, through the existing out-of-process
/// script runner. A browser tab uses the feed already attached to the hub. `MPRemoteCommandCenter`
/// cannot control another app, so it is not used. The private media-remote gate is off and fails closed,
/// so that path is never taken.
@MainActor
final class MediaCommandCoordinator {
    private let model: TopBarModel
    private let hub: NowPlayingHub
    private let feed: MusicPlayerFeed
    private var router = MediaCommandRouter()
    private var generation = 0

    init(model: TopBarModel, hub: NowPlayingHub, feed: MusicPlayerFeed) {
        self.model = model
        self.hub = hub
        self.feed = feed
    }

    func start() {
        model.homeMediaPress = { [weak self] in self?.press($0) }
        model.mediaRecovery = { [weak self] in self?.recover() }
        model.resyncHomeMedia = { [weak self] in self?.resync($0) }
        resync(model.nowPlaying)
    }

    func stop() {
        generation += 1
        model.homeMediaPress = { _ in }
        model.mediaRecovery = {}
        model.resyncHomeMedia = { _ in }
    }

    private func press(_ command: MediaControlCommand) {
        let effects: [MediaCommandEffect]
        do {
            effects = try router.reduce(.press(command), now: clock())
        } catch let rejection as MediaCommandRejection {
            MediaCommandLog.write("command \(Self.word(command)) rejected \(Self.word(rejection.reason))")
            return
        } catch {
            return
        }
        if effects.isEmpty, case .noSource = router.state {
            MediaCommandLog.write("command \(Self.word(command)) nosource")
            return
        }
        publish()
        perform(effects)
    }

    private func recover() {
        let effects: [MediaCommandEffect]
        do {
            effects = try router.reduce(.recover, now: clock())
        } catch {
            return
        }
        publish()
        perform(effects)
    }

    private func resync(_ playing: NowPlaying?) {
        _ = try? router.reduce(.info(sample(playing)), now: clock())
        publish()
    }

    private func publish() {
        if model.mediaPlayback != router.state { model.mediaPlayback = router.state }
    }

    private func perform(_ effects: [MediaCommandEffect]) {
        var send: (MediaControlCommand, MediaCommandRoute)?
        var after = MediaCommandRouter.resyncDelay
        for effect in effects {
            switch effect {
            case .send(let command, let route):
                send = (command, route)
            case .resync(_, let delay):
                after = delay
            case .openRecovery:
                MediaCommandLog.write("recovery opened")
                model.openPermissions()
            }
        }
        guard let (command, route) = send else { return }
        generation += 1
        let token = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.deliver(command, route: route)
            guard token == self.generation else { return }
            self.apply(.result(result))
            guard result == .accepted else { return }
            try? await Task.sleep(for: .seconds(after))
            guard token == self.generation else { return }
            await self.readBack(route)
        }
    }

    private func apply(_ event: MediaCommandEvent) {
        let pending = Self.pending(router)
        _ = try? router.reduce(event, now: clock())
        if case .result(let delivery) = event, let pending {
            switch delivery {
            case .accepted:
                MediaCommandLog.write("command \(pending.name) accepted\(pending.target)")
            case .permissionDenied:
                MediaCommandLog.write("command \(pending.name) permissionDenied")
            case .unavailable:
                MediaCommandLog.write("command \(pending.name) unavailable")
            case .failed:
                MediaCommandLog.write("command \(pending.name) failed")
            }
        }
        publish()
    }

    private static func pending(_ router: MediaCommandRouter) -> (name: String, target: String)? {
        guard case .commandPending(let command) = router.state else { return nil }
        let target: String
        switch router.route?.endpoint {
        case .scriptedPlayer(let bundleID): target = " bundle=\(bundleID)"
        case .browser: target = " browser"
        case nil: target = ""
        }
        return (word(command), target)
    }

    private static func word(_ command: MediaControlCommand) -> String {
        switch command {
        case .play: "play"
        case .pause: "pause"
        case .next: "next"
        case .previous: "previous"
        case .seek: "seek"
        }
    }

    private static func word(_ reason: MediaCommandRejection.Reason) -> String {
        switch reason {
        case .illegalTransition: "illegalTransition"
        case .duplicate: "duplicate"
        case .unsupported: "unsupported"
        case .inFlight: "inFlight"
        case .blocked: "blocked"
        }
    }

    private func clock() -> Double { Date().timeIntervalSinceReferenceDate }

    // MARK: Delivery

    private func deliver(_ command: MediaControlCommand, route: MediaCommandRoute) async -> MediaCommandDelivery {
        // MediaRemoteCommandGate is off and fails closed. This path does not call it.
        switch route.endpoint {
        case .scriptedPlayer(let bundleID):
            guard let player = NowPlaying.Player(bundleID: bundleID) else { return .unavailable }
            return await feed.deliver(command, to: player)
        case .browser(let tabID, let documentID):
            guard let send = hub.browserCommand,
                  case .browser(let key) = model.nowPlaying?.source,
                  key.tabID == tabID, key.documentID == documentID else { return .unavailable }
            let (kind, seconds) = Self.browserCommand(command)
            send(kind, seconds, key)
            return .accepted
        }
    }

    private func readBack(_ route: MediaCommandRoute) async {
        switch route.endpoint {
        case .scriptedPlayer(let bundleID):
            guard let player = NowPlaying.Player(bundleID: bundleID) else { return }
            guard feed.isPlayerRunning(player) else {
                hub.update(.player(player), nil, announce: false)
                return
            }
            if let playing = await feed.readPlayer(player) {
                hub.update(.player(player), playing, announce: false)
            }
        case .browser:
            break
        }
    }

    private func sample(_ playing: NowPlaying?) -> MediaNowPlayingSample? {
        guard let playing else { return nil }
        let caps = playing.capabilities
        let route: MediaCommandRoute
        switch playing.source {
        case .player(let player):
            route = MediaCommandRoute(endpoint: .scriptedPlayer(bundleID: player.bundleID),
                                       canSkip: caps.contains(.next) && caps.contains(.previous),
                                       canSeek: caps.contains(.seek))
        case .browser(let key):
            route = MediaCommandRoute(endpoint: .browser(tabID: key.tabID, documentID: key.documentID),
                                       canSkip: false,
                                       canSeek: caps.contains(.seek))
        }
        return MediaNowPlayingSample(isPlaying: playing.isPlaying, position: playing.elapsed(),
                                     duration: playing.duration, route: route)
    }

    private static func browserCommand(_ command: MediaControlCommand) -> (MusicCommandKind, Double?) {
        switch command {
        case .play: (.play, nil)
        case .pause: (.pause, nil)
        case .next: (.next, nil)
        case .previous: (.previous, nil)
        case .seek(let seconds): (.seek, seconds)
        }
    }
}
