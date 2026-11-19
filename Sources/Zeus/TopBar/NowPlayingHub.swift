import AppKit
import Observation
import ZeusCore

extension TopBarModel.MusicCommand {
    /// The command as the pure rules name it.
    var kind: MusicCommandKind {
        switch self {
        case .playPause: .playPause
        case .next: .next
        case .previous: .previous
        case .open: .open
        case .toggleShuffle: .toggleShuffle
        case .cycleRepeat: .cycleRepeat
        }
    }
}

/// The one place that decides what the notch shows and where a music command goes. Feeds report what each source
/// is doing; the pure `NowPlayingArbiter` keeps one entry per source and says which to show; the hub writes
/// `model.nowPlaying` (only when it differs), raises the track cue, asks for the cover and routes the commands,
/// checking every one against the shown item's capabilities first.
///
/// A source that is a scripted player is reached through `ports`, which the player feed fills in. Any other
/// source has its own optional closure; nil does nothing.
@MainActor
final class NowPlayingHub {
    static let followSettingID = "music.follow"

    /// Everything the hub does to the outside world. The defaults do nothing, so a test names only what it watches.
    struct Ports {
        /// The stored "Show music from" label.
        var follow: () -> String? = { nil }
        var now: () -> Date = { Date() }
        /// Sends a command to a scripted player. False when it could not be sent (not running, no Automation).
        var sendToPlayer: (NowPlaying.Player, MusicCommandKind) -> Bool = { _, _ in false }
        var seekPlayer: (NowPlaying.Player, Double) -> Bool = { _, _ in false }
        /// Reads the player again once it has settled after a play or pause.
        var readBack: (NowPlaying.Player) -> Void = { _ in }
        var readModes: (NowPlaying.Player) -> Void = { _ in }
        var resetModes: () -> Void = {}
        var open: (NowPlayingSource) -> Void = { _ in }
        var requestArtwork: (NowPlaying?) -> Void = { _ in }
        var showCue: (NotchCue) -> Void = { _ in }
    }

    var ports: Ports
    /// Sends a command to a browser tab: the command, the target second for a seek, the tab. Nil until a browser
    /// feed exists, and then nothing is sent.
    var browserCommand: ((MusicCommandKind, Double?, BrowserMediaKey) -> Void)?

    private let model: TopBarModel
    private var arbiter = NowPlayingArbiter()
    private var musicPageObservers: [(Bool) -> Void] = []

    init(model: TopBarModel, ports: Ports = Ports()) {
        self.model = model
        self.ports = ports
    }

    /// The ports of the running app: the setting, the clock, Finder, the cover store and the notch's own cues.
    static func livePorts(model: TopBarModel) -> Ports {
        var ports = Ports()
        ports.follow = { SettingsStore.shared.string(followSettingID) }
        ports.open = { open($0) }
        ports.requestArtwork = { ArtworkStore.shared.request(for: $0) }
        ports.showCue = { [weak model] in model?.show($0) }
        return ports
    }

    /// Connects the model's closures to the hub and starts listening for the setting.
    func attach() {
        model.musicCommand = { [weak self] in self?.musicCommand($0) }
        model.seek = { [weak self] in self?.seek(to: $0) }
        model.pauseForDictation = { [weak self] in self?.pauseForDictation() }
        model.resumeAfterDictation = { [weak self] in self?.resumeAfterDictation($0) }
        model.onMusicPageVisible = { [weak self] visible in self?.musicPageObservers.forEach { $0(visible) } }
        model.nowPlayingHub = self
        publishCommandTarget()
        observeFollowSetting()
    }

    // MARK: Reading

    var hasPlayerSession: Bool { arbiter.hasPlayerSession }

    func entry(_ source: NowPlayingSource) -> NowPlayingArbiter.Entry? { arbiter.entry(source) }

    /// The page that holds the music controls opened or closed. A2 and A3 register from their own files.
    func observeMusicPage(_ observer: @escaping (Bool) -> Void) { musicPageObservers.append(observer) }

    private var follow: NowPlayingArbiter.Follow { NowPlayingArbiter.Follow(label: ports.follow()) }

    private var shownItem: NowPlaying? { arbiter.shown(follow: follow)?.playing }

    /// Where a command goes right now: the shown source, else the pinned player, else Music.
    private var commandTarget: NowPlayingSource { arbiter.commandTarget(shown: shownItem?.source, follow: follow) }

    // MARK: Feeds

    /// A feed's latest word on one source; nil when it is gone. `announce` is false for a read the feed made on its own
    /// (a launch sync), which must not raise the track cue.
    func update(_ source: NowPlayingSource, _ playing: NowPlaying?, announce: Bool = true) {
        guard arbiter.update(source, playing, now: ports.now()) else { return }
        publish(updated: playing == nil ? nil : source, announce: announce)
    }

    /// A player quit, a tab closed or a feed went off.
    func remove(where matches: (NowPlayingSource) -> Bool) {
        arbiter.remove(where: matches)
        publish(updated: nil, announce: false)
    }

    /// The "Show music from" setting changed.
    func followChanged() { publish(updated: nil, announce: false) }

    /// Shows what the arbiter says, once. The shuffle and repeat modes belong to the shown source: they reset when it
    /// changes and are read only for the shown source and only when it is a scripted player, whether the source
    /// changed because it reported, the setting moved or another source left.
    private func publish(updated: NowPlayingSource?, announce: Bool) {
        let previous = model.nowPlaying
        let shown = arbiter.shown(follow: follow)?.playing
        if model.nowPlaying != shown { model.nowPlaying = shown }
        let changed = shown?.source != previous?.source
        if changed { ports.resetModes() }
        if let shown {
            if changed || updated == shown.source, let player = shown.source.scriptedPlayer,
               MusicModeRules.shouldRead(previous: previous, current: shown, modes: model.musicModes) {
                ports.readModes(player)
            }
            if updated == shown.source, announce, shown.isPlaying, previous?.title != shown.title {
                ports.showCue(.trackChanged(title: shown.title, artist: shown.artist, source: shown.source,
                                            sourceChanged: NowPlayingDisplay.sourceChanged(from: previous?.source, to: shown.source)))
            }
        }
        publishCommandTarget()
        ports.requestArtwork(model.nowPlaying)
    }

    private func publishCommandTarget() {
        let target = commandTarget
        if model.commandTarget != target { model.commandTarget = target }
    }

    // MARK: Commands

    func musicCommand(_ command: TopBarModel.MusicCommand) {
        let item = shownItem
        let target = commandTarget
        if command == .open {
            ports.open(target)
            return
        }
        guard (item?.capabilities ?? target.baseCapabilities).allows(command.kind) else { return }
        dispatch(resolved(command.kind, for: target, item: item), to: target, item: item)
    }

    /// Scrub: the bar moves at once; the source confirms on its next sample.
    func seek(to seconds: Double) {
        guard let item = shownItem, item.capabilities.allows(.seek) else { return }
        dispatch(.seek, seconds: MusicSeek.clampedTarget(seconds, duration: item.duration), to: item.source, item: item)
    }

    /// Pauses the shown source if it plays, for dictation. Returns that source so the resume reaches the same one.
    func pauseForDictation() -> NowPlayingSource? {
        guard let item = shownItem, item.isPlaying, item.capabilities.allows(.pause),
              dispatch(.pause, to: item.source, item: item) else { return nil }
        return item.source
    }

    /// Plays the source dictation paused, only if it still has an entry and is paused. Never any other source.
    func resumeAfterDictation(_ source: NowPlayingSource) {
        guard let item = arbiter.entry(source)?.playing, !item.isPlaying, item.capabilities.allows(.play) else { return }
        dispatch(.play, to: source, item: item)
    }

    /// A player has a toggle and keeps it. A source with only play and pause is told which one, from what it shows.
    private func resolved(_ kind: MusicCommandKind, for target: NowPlayingSource, item: NowPlaying?) -> MusicCommandKind {
        guard kind == .playPause else { return kind }
        switch target {
        case .player: return kind
        case .browser: return item?.isPlaying == true ? .pause : .play
        }
    }

    /// Sends one command to one source, then updates its entry at once as the display is a guess until the source
    /// answers. Returns whether it was sent.
    @discardableResult
    private func dispatch(_ kind: MusicCommandKind, seconds: Double? = nil, to target: NowPlayingSource, item: NowPlaying?) -> Bool {
        let sent: Bool
        switch target {
        case .player(let player):
            switch kind {
            case .seek: sent = ports.seekPlayer(player, seconds ?? 0)
            default: sent = ports.sendToPlayer(player, kind)
            }
        case .browser(let key):
            guard let browserCommand else { return false }
            browserCommand(kind, seconds, key)
            sent = true
        }
        guard sent, var guess = item else { return sent }
        let now = ports.now()
        switch kind {
        case .playPause: guess = flipped(guess, isPlaying: !guess.isPlaying, at: now)
        case .play: guess = flipped(guess, isPlaying: true, at: now)
        case .pause: guess = flipped(guess, isPlaying: false, at: now)
        case .seek:
            guess.position = seconds ?? guess.position
            guess.positionAt = now
        case .next, .previous, .open, .toggleShuffle, .cycleRepeat: return sent
        }
        update(target, guess, announce: false)
        if let player = target.scriptedPlayer, kind != .seek {
            // The display hold follows this guess: read the player once it has settled.
            ports.readBack(player)
        }
        return sent
    }

    /// The item with play or pause applied, the bar kept where it had got to.
    private func flipped(_ item: NowPlaying, isPlaying: Bool, at now: Date) -> NowPlaying {
        var result = item
        result.position = item.elapsed(at: now)
        result.positionAt = now
        result.isPlaying = isPlaying
        return result
    }

    // MARK: Setting

    /// Re-reads the setting whenever any setting changes, then listens again. Cheap: a change that is not this one
    /// finds the same shown source and writes nothing.
    private func observeFollowSetting() {
        withObservationTracking {
            _ = ports.follow()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followChanged()
                self?.observeFollowSetting()
            }
        }
    }

    // MARK: Open

    /// Opens the source's app. A scripted player is launched if it is not running and brought forward if it is, by
    /// `openApplication` as the Open button always did: a panel that does not activate may not use `activate()`.
    /// Any other source is only brought forward when it already runs, never started.
    private static func open(_ source: NowPlayingSource) {
        let id = source.appBundleID
        if source.scriptedPlayer != nil {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
        }
    }
}
