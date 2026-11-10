import AppKit
import Carbon.HIToolbox
import Observation
import Speech
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// State of the floating teleprompter. Shares its script with the notch teleprompter.
@MainActor
@Observable
final class PrompterWindowModel {
    let topBar: TopBarModel
    var roll: PrompterRoll
    var follower: ScriptFollower
    var mode: PrompterFollowMode { didSet { defaults.set(mode.rawValue, forKey: "prompterWindow.mode") } }
    /// A fallback for the run in progress (permission missing, mic busy). Never saved, so your chosen
    /// mode comes back next time.
    var sessionMode: PrompterFollowMode?
    /// What the session actually does: the fallback if one happened, otherwise your saved choice.
    var effectiveMode: PrompterFollowMode { sessionMode ?? mode }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "prompterWindow.font") } }
    var mirrored: Bool { didSet { defaults.set(mirrored, forKey: "prompterWindow.mirror") } }
    var countdown: Bool { didSet { defaults.set(countdown, forKey: "prompterWindow.countdown") } }
    var hiddenFromCapture: Bool { didSet { defaults.set(hiddenFromCapture, forKey: "prompterWindow.private"); onPrivacyChange(hiddenFromCapture) } }
    /// Scroll offset in points (smoothed).
    var offset: Double = 0
    var level: Double = 0
    var notice: String?
    var recordingSince: Date?
    var hovered = false
    /// Layout of each block in content coordinates (top y, height), measured by the view.
    var blockFrames: [Int: CGRect] = [:]
    var contentHeight: Double = 0
    var viewHeight: Double = 300

    // Following a live slideshow: the slide on screen and its notes.
    /// The slide shown, with its notes as the script; nil when not following slides.
    var presenter: PresenterPage?
    /// Why there is nothing to read (no deck, no permission…); fills the window.
    var presenterEmpty: PresenterEmptyState?
    var presenterPlaying = false
    var loadingNotes = false
    /// Opens the prompter on its own when a slideshow starts.
    var followPresentation: Bool {
        didSet { defaults.set(followPresentation, forKey: PrompterHub.followKey); PrompterHub.shared.updateWatcher() }
    }
    /// Voice-follow moves to the next slide at the end of a slide's notes. Off by default while
    /// following a slideshow, so a clicker press and ZEUS never both advance.
    var advanceWhileFollowing: Bool { didSet { defaults.set(advanceWhileFollowing, forKey: "prompter.followAdvances") } }
    var opacity: Double { didSet { defaults.set(opacity, forKey: "prompterWindow.opacity"); onOpacityChange(opacity) } }
    /// `PrompterPlacement.camera` or a display's id.
    var displayID: String { didSet { defaults.set(displayID, forKey: "prompterWindow.display"); onDisplayChange() } }
    var displays: [PrompterDisplay] = []

    var onPrivacyChange: (Bool) -> Void = { _ in }
    var onOpacityChange: (Double) -> Void = { _ in }
    var onDisplayChange: () -> Void = {}
    private let defaults = UserDefaults.standard

    static let opacitySteps: [Double] = [1, 0.85, 0.7, 0.55, 0.4]

    /// Following a slideshow (or trying to): the window sits above it and never takes the keys.
    var isFollowingSlides: Bool { presenter != nil || presenterEmpty != nil || loadingNotes }

    /// What fills the window instead of text: a blocking problem, or a slide without notes.
    var emptyState: PresenterEmptyState? { presenterEmpty ?? (presenter?.script.blocks.isEmpty == true ? presenter?.empty : nil) }

    func dimStep() {
        let steps = Self.opacitySteps
        let index = steps.firstIndex { abs($0 - opacity) < 0.01 } ?? 0
        opacity = steps[(index + 1) % steps.count]
    }

    static let fontRange: ClosedRange<Double> = 18...72
    /// The line you read at, as a fraction of the window's height (just under the camera).
    static let readingLine = 0.28

    init(topBar: TopBarModel) {
        self.topBar = topBar
        roll = PrompterRoll(speed: defaults.object(forKey: "prompterWindow.speed") as? Double ?? 40, voiceFollow: true)
        follower = ScriptFollower(script: PrompterScript(topBar.script))
        mode = defaults.string(forKey: "prompterWindow.mode").flatMap(PrompterFollowMode.init(rawValue:)) ?? .words
        fontSize = defaults.object(forKey: "prompterWindow.font") as? Double ?? 32
        mirrored = defaults.bool(forKey: "prompterWindow.mirror")
        countdown = defaults.object(forKey: "prompterWindow.countdown") as? Bool ?? true
        hiddenFromCapture = defaults.object(forKey: "prompterWindow.private") as? Bool ?? true
        followPresentation = defaults.bool(forKey: PrompterHub.followKey)
        advanceWhileFollowing = defaults.bool(forKey: "prompter.followAdvances")
        opacity = min(max(defaults.object(forKey: "prompterWindow.opacity") as? Double ?? 1, 0.3), 1)
        displayID = defaults.string(forKey: "prompterWindow.display") ?? PrompterPlacement.camera
    }

    /// The current slide's notes while following a slideshow, otherwise your script.
    var script: PrompterScript { presenter?.script ?? PrompterScript(topBar.script) }
    var isRunning: Bool { roll.phase == .rolling || roll.phase == .countdown }

    /// First script word of each block (cues have none).
    var blockWordStarts: [Int: (start: Int, count: Int)] {
        var result: [Int: (Int, Int)] = [:]
        var index = 0
        for block in script.blocks where !block.isCue {
            let count = ScriptFollower.normalize(block.text).count
            result[block.id] = (index, count)
            index += count
        }
        return result
    }

    /// Where the view should be scrolled so the next word to read sits on the reading line.
    func offsetForWord(_ word: Int) -> Double? {
        guard let entry = blockWordStarts.first(where: { word >= $0.value.start && word < $0.value.start + max($0.value.count, 1) })
                ?? blockWordStarts.max(by: { $0.value.start < $1.value.start }),
              let frame = blockFrames[entry.key] else { return nil }
        let fraction = entry.value.count > 0 ? Double(min(word - entry.value.start, entry.value.count)) / Double(entry.value.count) : 0
        return max(0, frame.minY + fraction * frame.height - viewHeight * Self.readingLine + fontSize * 0.6)
    }

    var maxOffset: Double { max(0, contentHeight - viewHeight * Self.readingLine) }

    /// The block the reading line is on, for highlighting.
    var currentBlock: Int? {
        let line = offset + viewHeight * Self.readingLine
        return blockFrames.first { $0.value.minY - 4 <= line && line <= $0.value.maxY + 4 }?.key
    }

    var cueOffsets: [Double] {
        script.cues.compactMap { blockFrames[$0.id].map { max(0, $0.minY - viewHeight * Self.readingLine + fontSize) } }.sorted()
    }
}

/// The floating teleprompter window: just under the camera, above every app, out of screen
/// shares by default. Space starts and pauses, arrows change speed and jump cues, Esc stops.
///
/// Following a slideshow, it shows the current slide's notes, sits above the full-screen show
/// on the display you picked, never takes the keyboard (arrows and clickers keep driving the
/// slides) and lets clicks through unless the pointer is over it. ⌃⌥P pauses and resumes.
@MainActor
final class PrompterWindowController {
    private let model: PrompterWindowModel
    private var window: PrompterPanel?
    private let speech = SpeechInput()
    private var timer: Timer?
    private var lastTick = Date()
    private var speechRestart: Date?
    private var listening = false
    private let recorder = PrompterRecorder()
    private let notes = PresenterNotesController()
    private var mouseMonitors: [Any] = []
    private var screenObserver: Any?

    // Slideshow following.
    private var sync: SlideSync?
    private var syncTimer: Timer?
    private var syncInterval: TimeInterval = 0
    private var lastReload = Date.distantPast
    /// Opened by "Follow my presentation": it closes again when the show ends.
    private var autoOpened = false

    /// Visibility changed (the pause hotkey is registered only while the window is up).
    var onVisibilityChange: () -> Void = {}
    /// Closed by you while a slideshow plays, so the watcher doesn't open it again right away.
    var onDismissDuringShow: () -> Void = {}

    /// Reads the switches Settings owns again (follow, advance, mirror, countdown, hide from sharing).
    func reloadPreferences() {
        let defaults = UserDefaults.standard
        model.followPresentation = defaults.bool(forKey: PrompterHub.followKey)
        model.advanceWhileFollowing = defaults.bool(forKey: "prompter.followAdvances")
        model.mirrored = defaults.bool(forKey: "prompterWindow.mirror")
        model.countdown = defaults.object(forKey: "prompterWindow.countdown") as? Bool ?? true
        model.hiddenFromCapture = defaults.object(forKey: "prompterWindow.private") as? Bool ?? true
    }

    init(topBar: TopBarModel) {
        model = PrompterWindowModel(topBar: topBar)
        model.onPrivacyChange = { [weak self] hidden in
            self?.window?.hiddenFromCapture = hidden
            ZeusWindowSharing.refreshFromAppState(teleprompterSessionHidden: false)
        }
        model.onOpacityChange = { [weak self] value in self?.window?.alphaValue = value }
        model.onDisplayChange = { [weak self] in self?.position(force: true) }
        recorder.onFinish = { [weak self] result in self?.recordingFinished(result) }
    }

    var isVisible: Bool { window?.isVisible == true }
    var isFollowingSlides: Bool { model.isFollowingSlides }

    func toggle() { isVisible ? close() : show() }

    /// `activate`: take the keyboard (the plain prompter). Following slides never does, so the
    /// slideshow keeps its keys.
    func show(activate: Bool = true) {
        if window == nil { build() }
        applyWindowMode()
        position(force: model.isFollowingSlides)
        if activate, !model.isFollowingSlides {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window?.orderFrontRegardless()
        }
        startMouseTracking()
        onVisibilityChange()
    }

    func close() {
        if sync?.playing == true, !autoOpened { onDismissDuringShow() }
        stop()
        endFollowing()
        if recorder.isRecording { recorder.stop() }
        stopMouseTracking()
        window?.orderOut(nil)
        onVisibilityChange()
    }

    private func build() {
        let panel = PrompterPanel(contentRect: CGRect(x: 0, y: 0, width: 640, height: 300),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.title = "Teleprompter"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.acceptsMouseMovedEvents = true
        panel.minSize = CGSize(width: 360, height: 180)
        panel.hiddenFromCapture = model.hiddenFromCapture
        applySharing(to: panel)
        panel.onKey = { [weak self] key in self?.handle(key) ?? false }
        panel.onClose = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: PrompterWindowView(model: model, actions: PrompterActions(
            toggle: { [weak self] in self?.togglePlay() },
            restart: { [weak self] in self?.restart() },
            stop: { [weak self] in self?.stop() },
            importScript: { [weak self] in self?.importScript() },
            loadNotes: { [weak self] in self?.followSlides() },
            editScript: { [weak self] in self?.model.topBar.editScript() },
            record: { [weak self] in self?.toggleRecording() },
            close: { [weak self] in self?.close() },
            jumpCue: { [weak self] forward in self?.jumpCue(forward: forward) },
            stopFollowing: { [weak self] in self?.stopFollowingSlides() },
            openPermissions: { [weak self] in self?.model.topBar.openPermissions() }
        )))
        panel.setFrameAutosaveName("ZeusPrompterWindow")
        window = panel
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.displays = Self.displays()
                if self.isVisible { self.position(force: self.model.isFollowingSlides) }
            }
        }
    }

    /// Above everything on every Space, full-screen slideshows included, and out of Mission
    /// Control. Following slides it sits above the show and can't become key.
    private func applyWindowMode() {
        guard let window else { return }
        let following = model.isFollowingSlides
        window.level = following ? .screenSaver : .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.allowsKey = !following
        window.alphaValue = model.opacity
        window.hiddenFromCapture = model.hiddenFromCapture
        applySharing(to: window)
    }

    private func applySharing(to panel: PrompterPanel) {
        let show = SettingsStore.shared.bool(ZeusScreenSharePolicy.showInSharingKey)
        let visible = ZeusScreenSharePolicy.zeusSurfacesVisible(
            showInScreenSharing: show,
            meetingActive: MeetingState.active,
            teleprompterSessionHidden: false
        )
        ZeusWindowSharing.apply(to: panel, visibleInShare: visible, surface: .prompterOwnHide(panel.hiddenFromCapture))
    }

    /// Centred just under the camera (or on the display you picked). Left alone if you moved
    /// it before, unless `force` and it isn't on the chosen display.
    private func position(force: Bool = false) {
        guard let window else { return }
        let displays = Self.displays()
        model.displays = displays
        guard let display = PrompterPlacement.display(preferred: model.displayID, among: displays) else { return }
        let saved = UserDefaults.standard.string(forKey: "NSWindow Frame ZeusPrompterWindow") != nil
        let fresh = window.screen == nil || !saved
        guard fresh || (force && PrompterPlacement.needsMove(window: window.frame, to: display)) else { return }
        window.setFrameOrigin(PrompterPlacement.origin(for: window.frame.size, on: display))
    }

    static func displays() -> [PrompterDisplay] {
        NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            let id = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
                .flatMap { CFUUIDCreateString(nil, $0) as String? } ?? screen.localizedName
            let builtIn = number.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            return PrompterDisplay(id: id, name: screen.localizedName, frame: screen.frame,
                                   topInset: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness),
                                   hasCamera: screen.safeAreaInsets.top > 0 || builtIn)
        }
    }

    // MARK: Click-through

    /// Mouse events pass through to the slideshow unless the pointer is over the prompter.
    private func startMouseTracking() {
        guard mouseMonitors.isEmpty else { return updateClickThrough() }
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateClickThrough() }
            return event
        }) { mouseMonitors.append(local) }
        updateClickThrough()
    }

    private func stopMouseTracking() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    private func updateClickThrough() {
        guard let window, window.isVisible else { return }
        let over = window.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
        if !over, model.hovered { model.hovered = false }
    }

    // MARK: Following a slideshow

    /// Shows the open Keynote or PowerPoint deck's notes for the slide on screen and follows
    /// the slideshow. `auto`: opened by "Follow my presentation".
    func followSlides(auto: Bool = false) {
        if !isVisible { autoOpened = auto } else if !auto { autoOpened = false }
        model.loadingNotes = true
        model.presenterEmpty = nil
        model.notice = "Reading speaker notes…"
        notes.onProblem = { [weak self] message in self?.model.notice = message }
        if isVisible { applyWindowMode(); position(force: true) } else { show(activate: false) }
        Task { await loadDeck() }
    }

    private func loadDeck() async {
        do {
            let deck = try await notes.load()
            model.loadingNotes = false
            model.notice = nil
            begin(deck)
        } catch {
            model.loadingNotes = false
            model.notice = nil
            stopSync()
            sync = nil
            model.presenter = nil
            model.presenterEmpty = PresenterEmptyState.from(error)
            applyWindowMode()
        }
    }

    private func begin(_ deck: PresenterDeck) {
        stop()
        sync = SlideSync(deck: deck)
        model.presenterPlaying = false
        model.presenterEmpty = deck.hasNotes ? nil : .noNotesInDeck(name: deck.name)
        showSlide(sync?.slide ?? 1)
        applyWindowMode()
        position(force: true)
        startSync(interval: PresenterPolling.followInterval(playing: false))
        pollSlideshow()
    }

    /// Jumps to a slide's notes and restarts the scroll for it.
    private func showSlide(_ slide: Int) {
        guard let deck = sync?.deck else { return }
        let page = PresenterPage(deck: deck, slide: slide)
        model.presenter = page
        model.follower = page.begin(roll: &model.roll)
        model.offset = 0
        notes.shown(slide: slide)
        if model.roll.phase == .rolling || model.roll.phase == .countdown {
            startListening()
            startTimer()
        }
    }

    func stopFollowingSlides() {
        stop()
        endFollowing()
    }

    private func endFollowing() {
        stopSync()
        sync = nil
        notes.clear()
        model.presenter = nil
        model.presenterEmpty = nil
        model.loadingNotes = false
        model.presenterPlaying = false
        autoOpened = false
        applyWindowMode()
    }

    private func startSync(interval: TimeInterval) {
        syncTimer?.invalidate()
        syncInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSlideshow() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func stopSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        syncInterval = 0
    }

    private func pollSlideshow() {
        Task {
            do {
                guard case .status(let status) = try await notes.poll(), sync != nil else { return }
                apply(status)
            } catch {
                guard sync != nil else { return }
                // The app quit, or Automation was turned off mid-show.
                lost(PresenterEmptyState.from(error))
            }
        }
    }

    private func apply(_ status: SlideshowStatus?) {
        guard var sync else { return }
        let changes = sync.update(status)
        self.sync = sync
        for change in changes {
            switch change {
            case .jump(let slide):
                showSlide(slide)
            case .started:
                model.presenterPlaying = true
                model.notice = nil
                if model.roll.phase == .idle || model.roll.phase == .finished { start(countdown: false) }
            case .ended:
                model.presenterPlaying = false
                if autoOpened { return close() }
                if model.isRunning { togglePlay() }
                model.notice = "The slideshow ended."
            case .reload:
                reload()
            case .closed:
                lost(.noPresentation(app: sync.deck.app.title))
                return
            }
        }
        let interval = PresenterPolling.followInterval(playing: sync.playing)
        if interval != syncInterval, syncTimer != nil { startSync(interval: interval) }
    }

    /// Nothing to follow any more: close if the show opened it, otherwise say why.
    private func lost(_ state: PresenterEmptyState) {
        if autoOpened { return close() }
        stop()
        stopSync()
        sync = nil
        notes.clear()
        model.presenter = nil
        model.presenterPlaying = false
        model.presenterEmpty = state
    }

    /// Another deck, or slides added or removed: read the notes again (at most every 3 s).
    private func reload() {
        guard Date().timeIntervalSince(lastReload) > 3 else { return }
        lastReload = Date()
        Task {
            guard let deck = try? await notes.load(), var sync = self.sync else { return }
            if deck.isSameDocument(sync.deck.name) {
                sync.replace(deck: deck)
                self.sync = sync
                model.presenterEmpty = deck.hasNotes ? nil : .noNotesInDeck(name: deck.name)
                showSlide(sync.slide)
            } else {
                let wasPlaying = sync.playing
                begin(deck)
                if wasPlaying { apply(SlideshowStatus(document: deck.name, playing: true, slide: deck.current, slideCount: deck.slideCount)) }
            }
        }
    }

    // MARK: Playback

    func togglePlay() {
        switch model.roll.phase {
        case .idle, .finished: start()
        case .rolling, .countdown: model.roll.pause(); stopListening(); stopTimer()
        case .paused: model.roll.resume(); startListening(); startTimer()
        }
    }

    private func start(countdown: Bool? = nil) {
        model.follower = ScriptFollower(script: model.script)
        model.offset = 0
        if !model.isFollowingSlides { model.notice = nil }
        // A new run tries your saved mode again.
        model.sessionMode = nil
        model.roll.voiceFollow = model.mode == .voice
        model.roll.start(countdown: countdown ?? model.countdown)
        startListening()
        startTimer()
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        stopTimer()
        stopListening()
        model.roll.stop()
        model.offset = 0
        model.level = 0
        model.follower.reset()
    }

    private func jumpCue(forward: Bool) {
        let cues = model.cueOffsets
        let current = model.offset
        let target = forward ? cues.first { $0 > current + 4 } : cues.last { $0 < current - 4 }
        guard let target = target ?? (forward ? nil : 0) else { return }
        model.offset = target
        model.roll.jump(to: target)
        // Words mode picks up from the first word at the new spot.
        if let word = wordAtOffset(target) { model.follower.reset(to: word) }
    }

    private func wordAtOffset(_ offset: Double) -> Int? {
        let line = offset + model.viewHeight * PrompterWindowModel.readingLine
        let starts = model.blockWordStarts
        let block = model.blockFrames.filter { starts[$0.key] != nil && $0.value.maxY >= line }.min { $0.value.minY < $1.value.minY }
        return block.flatMap { starts[$0.key]?.start }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// No timer at all while paused or stopped, so an idle prompter costs nothing.
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.2)
        lastTick = now
        switch model.effectiveMode {
        case .words:
            // The countdown still runs through the roll; then the words drive the offset.
            if model.roll.phase == .countdown {
                model.roll.tick(dt, at: now, hovered: false, maxOffset: model.maxOffset)
            } else if let target = model.offsetForWord(model.follower.position), !model.hovered {
                model.offset += (min(target, model.maxOffset) - model.offset) * min(1, dt * 5)
            }
        case .voice, .steady:
            model.roll.tick(dt, at: now, hovered: model.hovered, maxOffset: model.maxOffset)
            model.offset = model.roll.offset
        }
        // Following slides, the end of one slide's notes isn't the end: the next slide restarts
        // the roll, so the mic and timer keep going.
        let finished = model.roll.phase == .finished || (model.effectiveMode == .words && model.follower.isFinished && model.roll.phase == .rolling)
        if finished, !model.isFollowingSlides {
            stopListening()
            stopTimer()
        }
        // On-device recognition is restarted now and then so long reads never hit a limit.
        if model.effectiveMode == .words, let restart = speechRestart, now > restart { restartSpeech() }
    }

    // MARK: Listening

    private func startListening() {
        guard model.effectiveMode != .steady, !listening else { return }
        speech.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.level = level
                    self.model.roll.hear(level: level)
                }
            }
        }
        speech.onPartial = { [weak self] text in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.model.follower.hear(text) else { return }
                    self.heardWord()
                }
            }
        }
        speech.recordsSamples = false
        speech.deviceUID = DictationSettings.shared.microphoneUID
        speech.contextualStrings = Array(Set(model.follower.words.filter { $0.count > 6 })).prefix(80).map { $0 }
        let canRecognize = SFSpeechRecognizer.authorizationStatus() == .authorized
        if model.effectiveMode == .words, !canRecognize {
            model.notice = "Allow Speech Recognition to follow your words. Scrolling while you speak instead."
            model.sessionMode = .voice
            model.roll.voiceFollow = true
        }
        speech.recognizes = model.effectiveMode == .words
        do {
            try speech.start()
            listening = true
            speechRestart = model.effectiveMode == .words ? Date().addingTimeInterval(50) : nil
        } catch {
            model.notice = "The microphone is unavailable, so the script scrolls at a steady pace."
            model.sessionMode = .steady
            model.roll.voiceFollow = false
        }
    }

    /// The follower moved: maps the slide's word to the whole deck for the voice slide advance.
    private func heardWord() {
        guard let sync, let page = model.presenter else {
            notes.heard(wordIndex: model.follower.position)
            return
        }
        let start = sync.deck.firstWord(ofSlide: page.slide) ?? 0
        notes.heard(wordIndex: start + model.follower.position, enabled: model.advanceWhileFollowing && model.effectiveMode == .words)
    }

    private func restartSpeech() {
        speech.cancel()
        // The follower keeps its place; the new transcript starts empty.
        try? speech.start()
        speechRestart = Date().addingTimeInterval(50)
    }

    private func stopListening() {
        speech.cancel()
        listening = false
        speechRestart = nil
        model.level = 0
    }

    // MARK: Keys, import, recording

    private func handle(_ key: PrompterKey) -> Bool {
        switch key {
        case .toggle: togglePlay()
        case .stop: if model.roll.phase == .idle { close() } else { stop() }
        case .faster: model.roll.adjustSpeed(by: 4); persistSpeed()
        case .slower: model.roll.adjustSpeed(by: -4); persistSpeed()
        case .previousCue: jumpCue(forward: false)
        case .nextCue: jumpCue(forward: true)
        case .larger: model.fontSize = min(model.fontSize + 2, PrompterWindowModel.fontRange.upperBound)
        case .smaller: model.fontSize = max(model.fontSize - 2, PrompterWindowModel.fontRange.lowerBound)
        case .mirror: model.mirrored.toggle()
        case .restart: restart()
        }
        return true
    }

    private func persistSpeed() { UserDefaults.standard.set(model.roll.speed, forKey: "prompterWindow.speed") }

    func importScript() {
        stopFollowingSlides()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText, .rtf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a script (text, Markdown or RTF)"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text: String?
        if url.pathExtension.lowercased() == "rtf" {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        } else {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.notice = "That file has no text to read."
            return
        }
        stop()
        model.topBar.script = PrompterImport.script(from: text, isMarkdown: PrompterImport.isMarkdown(pathExtension: url.pathExtension))
        model.follower = ScriptFollower(script: model.script)
        model.notice = "Imported \(url.lastPathComponent)."
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        Task {
            do {
                try await recorder.start()
                model.recordingSince = Date()
                model.notice = nil
                if model.roll.phase == .idle { start() }
            } catch {
                model.notice = error.localizedDescription
            }
        }
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        model.recordingSince = nil
        switch result {
        case .success(let url):
            model.notice = "Saved \(url.lastPathComponent) in Movies."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failure(let error):
            model.notice = "Recording failed: \(error.localizedDescription)"
        }
    }
}

/// Keyboard handling and close behaviour for the prompter window.
final class PrompterPanel: NSPanel {
    var onKey: (PrompterKey) -> Bool = { _ in false }
    var onClose: () -> Void = {}
    /// False while following a slideshow: the show keeps the keyboard (arrows, clickers).
    var allowsKey = true
    /// Kept out of screen shares and recordings whatever the app-wide setting says.
    var hiddenFromCapture = true

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if plain, let key = PrompterKey.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers), onKey(key) { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onKey(.stop)
    }

    override func performClose(_ sender: Any?) { onClose() }
}

/// Opens the floating teleprompter from the menu, a deep link or the notch, and watches for a
/// slideshow to start when "Follow my presentation" is on.
@MainActor
final class PrompterHub {
    static let shared = PrompterHub()
    static let followKey = "prompter.followPresentation"
    var topBar: TopBarModel?
    private var controller: PrompterWindowController?
    /// The pause hotkey changed (the window opened or closed).
    var onHotkeysChange: () -> Void = {}

    private var watchTimer: Timer?
    private var lastWatchPoll = Date.distantPast
    private var watchPolling = false
    /// You closed the prompter during a show: don't reopen it until that show ends.
    private var dismissedDuringShow = false

    func toggle() {
        guard let controller = makeController() else { return }
        controller.toggle()
    }

    /// Settings › Features › Teleprompter changed a switch: an open prompter takes it at once, and
    /// the "Follow my presentation" watcher starts or stops.
    func settingsChanged() {
        controller?.reloadPreferences()
        updateWatcher()
    }

    /// The prompter on the open slideshow's notes (the notch's Slides button).
    func followSlides() {
        guard let controller = makeController() else { return }
        dismissedDuringShow = false
        controller.followSlides()
    }

    private func makeController() -> PrompterWindowController? {
        guard let topBar else { return nil }
        if controller == nil {
            let controller = PrompterWindowController(topBar: topBar)
            controller.onVisibilityChange = { [weak self] in self?.onHotkeysChange() }
            controller.onDismissDuringShow = { [weak self] in self?.dismissedDuringShow = true }
            self.controller = controller
        }
        // One prompter at a time: the notch one stops when the window opens.
        if topBar.prompterActive { topBar.stopPrompter() }
        return controller
    }

    /// ⌃⌥P pauses and resumes the prompter from any app, without taking focus from the
    /// slideshow. Registered only while the window is up.
    func hotkeys() -> [(UInt32, UInt32, () -> Void)] {
        guard controller?.isVisible == true else { return [] }
        return [(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), { [weak self] in self?.controller?.togglePlay() })]
    }

    static var followPresentation: Bool { UserDefaults.standard.bool(forKey: followKey) }

    // MARK: Follow my presentation

    /// Starts or stops the watcher to match the setting.
    func updateWatcher() {
        if Self.followPresentation {
            guard watchTimer == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.watch() }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            watchTimer = timer
        } else {
            watchTimer?.invalidate()
            watchTimer = nil
        }
    }

    /// Each second: a running-apps check and a window-list read. The app is asked about its
    /// slideshow only when it is frontmost or has a full-screen window, and never without
    /// Automation permission (this never prompts).
    private func watch() {
        guard controller?.isFollowingSlides != true, !watchPolling,
              let running = PresenterNotesController.runningApp(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: running.bundleID).first else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == running.bundleID
        let fullScreen = PresenterPolling.hasFullScreenWindow(Self.windows(of: app.processIdentifier), screens: NSScreen.screens.map(\.frame))
        guard let interval = PresenterPolling.watchInterval(appRunning: true, frontmost: frontmost, fullScreenWindow: fullScreen),
              Date().timeIntervalSince(lastWatchPoll) >= interval,
              Automation.gate(running.bundleID) == .granted else { return }
        lastWatchPoll = Date()
        watchPolling = true
        let provider = PresenterNotesController.provider(for: running.app)
        Task {
            let status = try? await Task.detached(priority: .utility) { try provider.status() }.value
            watchPolling = false
            let playing = status?.playing == true
            if !playing { dismissedDuringShow = false; return }
            guard !dismissedDuringShow, controller?.isFollowingSlides != true, let controller = makeController() else { return }
            controller.followSlides(auto: true)
        }
    }

    /// On-screen window bounds of one app (no Screen Recording needed for bounds).
    private static func windows(of pid: pid_t) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
}
