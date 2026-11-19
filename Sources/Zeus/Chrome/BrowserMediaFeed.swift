import AppKit
import Observation
import ZeusCore

/// Chrome tab media as a source: asks the Zeus extension what the tabs play, reports each tab to the hub, and carries
/// out the play, pause and seek the hub sends. Nothing here decides when to ask or what to do about a failure: the
/// pure `BrowserPollMachine` does, and this applies its effects. Socket I/O stays inside `ChromeBridge`'s detached
/// task; only Sendable values cross. It never starts the call watcher and never asks Chrome anything unless the
/// setting is on, Chrome runs, the extension is new enough, the screens are awake and "Show music from" is Any player.
private let chromeBundleID = "com.google.Chrome"

@MainActor
final class BrowserMediaFeed {
    static let settingID = "music.browserMedia"
    static let statusID = "music.browserMediaStatus"
    static let reloadStatus = "Press Reload on the Zeus card in Chrome's extensions page"

    private struct Entry {
        var item: BrowserMediaItem
        var playing: NowPlaying
    }

    private let hub: NowPlayingHub
    private let model: TopBarModel
    private var state = BrowserPollState()
    /// One entry per tab document the hub holds. A new fingerprint in the same document replaces its entry.
    private var entries: [BrowserMediaTarget: Entry] = [:]
    /// Bumped whenever the entries are dropped, so a reply that was already in flight is not applied after.
    private var generation = 0
    private var timer: Task<Void, Never>?
    private var output: ChromeOutputActivity?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var musicPageOpen = false
    private var outputRunning = false
    private var lastCommand: BrowserMediaKey?
    private var running = false

    init(hub: NowPlayingHub, model: TopBarModel) {
        self.hub = hub
        self.model = model
    }

    func start() {
        guard !running else { return }
        running = true
        hub.browserCommand = { [weak self] kind, seconds, key in self?.send(kind, seconds: seconds, to: key) }
        hub.observeMusicPage { [weak self] visible in
            guard let self else { return }
            self.musicPageOpen = visible
            if visible { self.apply(.tick(self.context())) }
        }
        observeWorkspace()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(.screensSlept) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(.screensWoke) }
        })
        observeSettings()
        if !Self.followsAny { apply(.followChanged(followsAny: false)) }
        if Self.chromeIsRunning { apply(.chromeLaunched) }
        if SettingsStore.shared.bool(Self.settingID) { turnOn() }
    }

    /// Stops asking, drops every tab off the hub and lets go of the listeners.
    func stop() {
        guard running else { return }
        running = false
        timer?.cancel()
        timer = nil
        generation += 1
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        output?.stop()
        output = nil
        outputRunning = false
        hub.browserCommand = nil
        dropAll()
        state = BrowserPollState()
        publishStatus()
    }

    // MARK: Inputs

    private static var chromeIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleID).isEmpty
    }

    private static var followsAny: Bool {
        NowPlayingArbiter.Follow(label: SettingsStore.shared.string(NowPlayingHub.followSettingID)) == .any
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == chromeBundleID else { return }
            MainActor.assumeIsolated { self?.apply(.chromeLaunched) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == chromeBundleID else { return }
            MainActor.assumeIsolated { self?.apply(.chromeQuit) }
        })
    }

    /// Re-reads the two settings whenever any setting changes, then listens again.
    private func observeSettings() {
        withObservationTracking {
            _ = SettingsStore.shared.string(Self.settingID)
            _ = SettingsStore.shared.string(NowPlayingHub.followSettingID)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.running else { return }
                self.settingsChanged()
                self.observeSettings()
            }
        }
    }

    private func settingsChanged() {
        let enabled = SettingsStore.shared.bool(Self.settingID)
        if enabled != state.settingOn {
            if enabled { turnOn() } else { turnOff() }
        }
        let follows = Self.followsAny
        if follows != state.followsAny { apply(.followChanged(followsAny: follows)) }
    }

    private func turnOn() {
        if output == nil {
            output = ChromeOutputActivity { [weak self] running in
                guard let self else { return }
                self.outputRunning = running
                self.apply(.outputActivity(running))
            }
        }
        output?.start()
        apply(.settingOn)
    }

    private func turnOff() {
        output?.stop()
        outputRunning = false
        apply(.settingOff)
    }

    // MARK: Machine

    private func context() -> BrowserPollContext {
        var shown = false
        var shownPlaying = false
        if let item = model.nowPlaying, case .browser = item.source {
            shown = true
            shownPlaying = item.isPlaying
        }
        return BrowserPollContext(followsAny: state.followsAny, outputRunning: outputRunning, browserShown: shown,
                                  browserShownPlaying: shownPlaying,
                                  pausedKnownWithMusicPageOpen: musicPageOpen && entries.values.contains { !$0.playing.isPlaying })
    }

    private func apply(_ event: BrowserPollEvent) {
        let step = BrowserPollMachine.next(state, event)
        state = step.0
        for effect in step.1 { run(effect) }
        publishStatus()
    }

    private func run(_ effect: BrowserPollEffect) {
        switch effect {
        case .pingNow: ping()
        case .pollNow: poll()
        case .schedule(let delay): schedule(after: delay)
        case .cancelTimer:
            timer?.cancel()
            timer = nil
        case .dropEntries:
            generation += 1
            dropAll()
        case .dropTarget:
            if let key = lastCommand { drop(key) }
        case .hint(let hint):
            switch hint {
            case .reloadExtension: break // The Settings status row says it; see `publishStatus`.
            case .commandNotSupported: model.show(.hint("This page can't do that"))
            }
        }
    }

    private func schedule(after delay: TimeInterval) {
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.apply(.tick(self.context()))
        }
    }

    private func ping() {
        let token = generation
        Task { @MainActor [weak self] in
            let outcome = await ChromeBridge.ping()
            guard let self, token == self.generation else { return }
            switch outcome {
            case .ok(let value): self.apply(.version(value?["version"]?.stringValue))
            default: self.apply(Self.failure(outcome))
            }
        }
    }

    private func poll() {
        let token = generation
        let known = entries.keys.sorted { ($0.tabID, $0.documentID) < ($1.tabID, $1.documentID) }
        Task { @MainActor [weak self] in
            let outcome = await ChromeBridge.mediaState(known: known)
            guard let self, token == self.generation else { return }
            // A reply that arrives while the loop is stopped or paused is late and changes nothing.
            guard self.state.canPoll else { return self.apply(.reply(self.context())) }
            guard case .ok(let value) = outcome else { return self.apply(Self.failure(outcome)) }
            // A malformed reply is a failure, like a timeout. A stale one repeats the last reply and is not applied.
            guard let value, let parsed = BrowserMediaState.parse(value) else { return self.apply(.timedOut) }
            if !parsed.stale { self.ingest(parsed) }
            self.apply(.reply(self.context()))
        }
    }

    private static func failure(_ outcome: ChromeBridge.CallOutcome) -> BrowserPollEvent {
        switch outcome {
        case .notConnected: .notConnected
        case .ok, .timedOut, .failed: .timedOut
        }
    }

    // MARK: Entries

    /// Reports what the tabs play to the hub. While a call runs in a browser nothing is shown. A tab whose element
    /// changed gets a new entry; one the reply did not mention (slow, or failed) keeps its last one.
    private func ingest(_ reply: BrowserMediaState) {
        let callPresent = ScribeCallWatcher.shared.browserCallPresent
        if callPresent {
            dropAll()
            return
        }
        for target in reply.gone { remove(target) }
        let now = Date()
        for item in BrowserMediaRules.usable(reply.items, callPresent: callPresent) {
            let sample = BrowserMediaRules.nowPlaying(item, anchor: now)
            var previous: NowPlaying?
            if let existing = entries[item.target] {
                if existing.item.key == item.key { previous = existing.playing } else { hub.update(existing.playing.source, nil) }
            }
            let playing = BrowserMediaRules.merged(previous: previous, sample: sample)
            entries[item.target] = Entry(item: item, playing: playing)
            hub.update(playing.source, playing)
        }
    }

    private func remove(_ target: BrowserMediaTarget) {
        guard let entry = entries.removeValue(forKey: target) else { return }
        hub.update(entry.playing.source, nil)
    }

    private func drop(_ key: BrowserMediaKey) {
        for (target, entry) in entries where entry.item.key == key { remove(target) }
    }

    private func dropAll() {
        entries.removeAll()
        hub.remove { Self.isBrowser($0) }
    }

    private static func isBrowser(_ source: NowPlayingSource) -> Bool {
        switch source {
        case .browser: return true
        case .player: return false
        }
    }

    // MARK: Commands

    /// Sends a play, pause or seek to one tab. The hub has already checked the shown item's capabilities, so next and
    /// previous never arrive; the rules say nothing goes to a tab while a call runs in a browser.
    private func send(_ kind: MusicCommandKind, seconds: Double?, to key: BrowserMediaKey) {
        guard let entry = entries.values.first(where: { $0.item.key == key }),
              let command = BrowserMediaRules.command(for: kind, seconds: seconds, item: entry.item,
                                                      callPresent: ScribeCallWatcher.shared.browserCallPresent) else { return }
        lastCommand = key
        Task { @MainActor [weak self] in
            let outcome = await ChromeBridge.mediaCommand(command)
            guard let self else { return }
            switch outcome {
            case .ok, .timedOut: break // The next poll is the read-back.
            case .notConnected: self.apply(.notConnected)
            case .failed(let error):
                switch BrowserMediaFailure(code: error.code) {
                case .staleTarget: self.apply(.staleTarget)
                case .notSupported, .blockedByPage: self.apply(.notSupported)
                case .other: break
                }
            }
        }
    }

    // MARK: Status

    /// The Settings row that says to reload the extension, present only while Chrome runs with an old one.
    private func publishStatus() {
        let store = SettingsStore.shared
        if state.needsExtensionReload {
            if store.statusOverrides[Self.statusID]?.1 != Self.reloadStatus {
                store.statusOverrides[Self.statusID] = (false, Self.reloadStatus)
            }
        } else if store.statusOverrides[Self.statusID] != nil {
            store.statusOverrides[Self.statusID] = nil
        }
    }
}
