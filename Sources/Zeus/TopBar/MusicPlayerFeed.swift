import AppKit
import ZeusCore

/// Music and Spotify as sources: reads what each player says (its public change notifications, and an Apple Event
/// read for a player already running at launch), reports to the hub, and carries out the commands the hub sends.
/// Nothing here decides what is shown. Apple Events go through `SpotifyPlayer.osascript`, out of process and bounded,
/// only to a running player Zeus is already allowed to script; nothing here ever prompts.
@MainActor
final class MusicPlayerFeed {
    private let hub: NowPlayingHub
    private let model: TopBarModel
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var musicSyncTasks: [NowPlaying.Player: Task<Void, Never>] = [:]
    /// Bumped by each player notification, so a slower state read started earlier never overwrites it.
    private var musicRevision: [NowPlaying.Player: Int] = [:]
    /// Runs the shuffle and repeat sends and reads one after another, so a press is read back after its own script.
    private var musicModesTask: Task<Void, Never>?
    /// Bumped by each press, reset and new read, so a slower earlier read never overwrites a newer state.
    private var musicModesRevision = 0

    init(hub: NowPlayingHub, model: TopBarModel) {
        self.hub = hub
        self.model = model
    }

    func start() {
        hub.ports.sendToPlayer = { [weak self] player, kind in self?.send(kind, to: player) ?? false }
        hub.ports.seekPlayer = { [weak self] player, seconds in self?.seek(to: seconds, player: player) ?? false }
        hub.ports.readBack = { [weak self] player in self?.syncMusicSoon(player, delays: [1.5, 4]) }
        hub.ports.readModes = { [weak self] player in self?.refreshMusicModes(player) }
        hub.ports.resetModes = { [weak self] in self?.resetMusicModes() }
        observeMusic()
    }

    /// Removes the notification observers, stops pending reads and takes the players' entries off the hub.
    func stop() {
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        for task in musicSyncTasks.values { task.cancel() }
        musicSyncTasks.removeAll()
        // Drops every queued or in-flight read and readback, not only the newest task.
        musicModesRevision += 1
        musicModesTask?.cancel()
        musicModesTask = nil
        hub.remove { $0.scriptedPlayer != nil }
    }

    // MARK: Reading (public player notifications)

    private func observeMusic() {
        let center = DistributedNotificationCenter.default()
        for player in NowPlaying.Player.allCases {
            observers.append(center.addObserver(forName: .init(player.notificationName), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let parsed = NowPlaying.parse(info, player: player)
                MainActor.assumeIsolated {
                    self?.musicRevision[player, default: 0] += 1
                    self?.hub.update(.player(player), parsed)
                }
            })
        }
        // Apps launching or quitting: catch music already playing, and drop a track whose player is gone.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = app?.bundleIdentifier.flatMap(NowPlaying.Player.init(bundleID:)) else { return }
            MainActor.assumeIsolated { self?.syncMusicSoon(player, delays: [2, 5, 10]) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = app?.bundleIdentifier.flatMap(NowPlaying.Player.init(bundleID:)) else { return }
            MainActor.assumeIsolated {
                self?.musicSyncTasks[player]?.cancel()
                self?.hub.update(.player(player), nil)
            }
        })
        // Music already playing at launch sends no notification. The Automation check is asynchronous,
        // so the first tries may find it unresolved; each try stops once it could read (or nothing runs).
        for player in NowPlaying.Player.allCases { syncMusicSoon(player, delays: [1.5, 4, 9]) }
    }

    /// Reads the player's current state a few times with growing gaps, stopping after the first try that could.
    private func syncMusicSoon(_ player: NowPlaying.Player, delays: [TimeInterval]) {
        musicSyncTasks[player]?.cancel()
        musicSyncTasks[player] = Task { @MainActor [weak self] in
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                if await self.syncMusic(player) { return }
            }
        }
    }

    /// One read of the player's state through Apple Events. True when it is settled (answered, or the
    /// player isn't running); false when Automation isn't confirmed yet. Never prompts: without
    /// consent no AppleScript runs at all.
    private func syncMusic(_ player: NowPlaying.Player) async -> Bool {
        guard isRunning(player) else { return true }
        guard Automation.allowed(player.bundleID) else { return false }
        let revision = musicRevision[player, default: 0]
        let output = await SpotifyPlayer.osascript(NowPlaying.probeScript(player: player))
        // A notification that arrived during the read is newer than this answer.
        guard musicRevision[player, default: 0] == revision else { return true }
        guard !Task.isCancelled, isRunning(player) else { return true }
        if let playing = NowPlaying.parseProbe(output, player: player) {
            hub.update(.player(player), playing, announce: false)
        } else if output != nil {
            // A stopped player (or one with no track) leaves nothing to show; a failed read changes nothing.
            hub.update(.player(player), nil)
        }
        return true
    }

    // MARK: Commands

    private func isRunning(_ player: NowPlaying.Player) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false
    }

    private func canScript(_ player: NowPlaying.Player) -> Bool {
        isRunning(player) && Automation.allowed(player.bundleID)
    }

    /// Only a player that is already running is talked to, so a tap never launches one. Apple Events would prompt
    /// the first time; without consent the notch points to Settings. True when a play, pause, next or previous went out.
    private func send(_ kind: MusicCommandKind, to player: NowPlaying.Player) -> Bool {
        let verb: String? = switch kind {
        case .playPause: "playpause"
        case .play: "play"
        case .pause: "pause"
        case .next: "next track"
        case .previous: "previous track"
        case .toggleShuffle, .cycleRepeat, .seek, .open: nil
        }
        guard isRunning(player) else { return false }
        guard Automation.allowed(player.bundleID) else {
            NSLog("[ZEUS] permissions: Automation off for %@, showing hint", player.bundleID)
            model.show(.hint(PermissionsModel.hint(.automation)))
            return false
        }
        guard let verb else {
            changeMusicMode(kind, player: player)
            return false
        }
        // Off the main thread and bounded: a hung player must never freeze the notch.
        let source = "tell application id \"\(player.bundleID)\" to \(verb)"
        Task.detached(priority: .userInitiated) { _ = await SpotifyPlayer.osascript(source) }
        return true
    }

    /// Scrub: `set player position`, only for a running player Zeus may already script. The bar moves at once
    /// (the hub does that); the player confirms on its next notification.
    private func seek(to seconds: Double, player: NowPlaying.Player) -> Bool {
        guard isRunning(player) else { return false }
        guard Automation.allowed(player.bundleID) else {
            model.show(.hint(PermissionsModel.hint(.automation)))
            return false
        }
        let script = MusicSeek.script(player: player, seconds: seconds)
        Task.detached(priority: .userInitiated) {
            if await SpotifyPlayer.osascript(script) == nil { NSLog("[ZEUS] seek failed") }
        }
        return true
    }

    // MARK: Shuffle and repeat

    /// The press itself is `MusicModePress`: a known mode moves at once and the change is sent; an unknown
    /// mode is read from the player first. This carries out each effect and reports what happened.
    /// Runs after `send` has checked the player is running and allowed.
    private func changeMusicMode(_ kind: MusicCommandKind, player: NowPlaying.Player) {
        let control: MusicModePress.Control
        switch kind {
        case .toggleShuffle: control = .shuffle
        case .cycleRepeat: control = .repeatMode
        case .play, .pause, .playPause, .next, .previous, .seek, .open: return
        }
        var press = MusicModePress(control: control, player: player)
        let start = press.press(current: model.musicModes)
        if let shown = start.optimistic { model.musicModes = shown }
        musicModesRevision += 1
        let revision = musicModesRevision
        let started = press
        enqueueMusicModes { feed in
            await feed.runMusicPress(started, first: start.next, revision: revision)
        }
    }

    private func runMusicPress(_ started: MusicModePress, first: MusicModePress.Effect, revision: Int) async {
        var press = started
        let player = press.player
        var effect = first
        while !Task.isCancelled {
            let event: MusicModePress.Event
            switch effect {
            case .stop:
                return
            case .show(let modes):
                model.musicModes = modes
                return
            case .readPlayer:
                // Read directly: a newer read bumping the shared revision must not leave this press without
                // an answer. If the player says nothing, the press is skipped.
                guard canScript(player) else { event = .unavailable; break }
                let output = await SpotifyPlayer.osascript(MusicModeRules.readScript(player: player))
                event = .playerRead(MusicModeRules.parse(output, player: player))
            case .send(let script):
                // The player may have quit or lost consent while this press waited behind a read.
                guard canScript(player) else { event = .unavailable; break }
                _ = await SpotifyPlayer.osascript(script)
                event = .sent
            case .readBack:
                // A newer press, read or reset already owns the control: skip the read, drop the answer.
                guard musicModesRevision == revision else {
                    event = .readBack(output: nil, current: model.musicModes, isCurrent: false)
                    break
                }
                guard canScript(player) else { event = .unavailable; break }
                let output = await SpotifyPlayer.osascript(MusicModeRules.readScript(player: player))
                let current = musicModesRevision == revision && isRunning(player)
                event = .readBack(output: output, current: model.musicModes, isCurrent: current)
            }
            guard !Task.isCancelled else { return }
            effect = press.handle(event)
        }
    }

    /// Reads the modes for a new player or track. Skipped when the player is not running or not allowed.
    private func refreshMusicModes(_ player: NowPlaying.Player) {
        musicModesRevision += 1
        let revision = musicModesRevision
        enqueueMusicModes { await $0.readMusicModes(player, revision: revision) }
    }

    private func resetMusicModes() {
        musicModesRevision += 1
        model.musicModes = MusicModes()
    }

    private func enqueueMusicModes(_ work: @escaping @MainActor (MusicPlayerFeed) async -> Void) {
        let previous = musicModesTask
        musicModesTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await work(self)
        }
    }

    /// One bounded read through Apple Events; never prompts, and only for a running player Zeus may script.
    /// A failed read changes nothing.
    private func readMusicModes(_ player: NowPlaying.Player, revision: Int) async {
        guard musicModesRevision == revision, canScript(player) else { return }
        let output = await SpotifyPlayer.osascript(MusicModeRules.readScript(player: player))
        guard musicModesRevision == revision, !Task.isCancelled, isRunning(player) else { return }
        model.musicModes = MusicModeRules.resolved(output: output, player: player, current: model.musicModes, afterPress: false)
    }
}
