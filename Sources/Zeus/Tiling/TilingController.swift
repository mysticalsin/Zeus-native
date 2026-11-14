import AppKit
import Observation
import ZeusCore

/// What the key layer gives the controller. The real one is `TilingKeyLayer`; tests use a fake with no tap.
@MainActor
protocol TilingKeyControlling: AnyObject {
    /// A bound chord was pressed.
    var onAction: (TileAction) -> Void { get set }
    /// The tap cannot run and has stopped itself.
    var onUnavailable: () -> Void { get set }
    /// Idempotent: installs, updates or removes the tap to match the three values.
    func apply(enabled: Bool, paused: Bool, keymap: TileKeymap)
}

extension TilingKeyLayer: TilingKeyControlling {}

/// Where the focus ring goes: a window's engine frame and the display it is on.
struct TilingRingTarget: Equatable {
    var display: TileDisplay
    var frame: TileRect
}

/// Work queued for later. It runs on the main actor.
typealias TilingWork = @MainActor @Sendable () -> Void

/// The states `Zeus --snapshots` draws the Tiling page in.
enum TilingSnapshotState: String, CaseIterable {
    case running
    case twoDisplays = "two-displays"
    case off
    case needsAccessibility = "needs-accessibility"
    case paused
}

/// Ties the pure tiling engine, the Accessibility driver and the key layer together.
///
/// Nothing exists while tiling is off: no key tap, no observer, no timer, no panel, no Accessibility read. Turning
/// it on installs the key layer, waits for Accessibility without a prompt, then watches the system for the few
/// events that change which windows are on screen. One generation counter makes work queued before a display,
/// Space or sleep change do nothing when it finally runs. Turning it off, or pausing, never moves a window.
@MainActor
@Observable
final class TilingController {
    /// Everything the controller touches outside itself, so a test can stand in for each part.
    @MainActor
    struct Services {
        var driver: any TilingWindowDriver
        var keys: any TilingKeyControlling
        var readConfig: () -> TileConfig
        var focusBorderOn: () -> Bool
        /// Why the keys for this base cannot be used (another Zeus key or VoiceOver holds them), or nil when they are free.
        var keyClash: (TileModifierBase, TileKeymap) -> String? = { _, _ in nil }
        /// Calls the work each time VoiceOver starts or stops and returns the way to stop watching. VoiceOver writes
        /// no setting, and the key clash depends on it.
        var watchVoiceOver: (@escaping TilingWork) -> () -> Void = { _ in {} }
        /// Runs the closure once Accessibility is on, without ever prompting.
        var whenTrusted: (@escaping () -> Void) -> Void
        var cancelTrustWait: () -> Void
        /// Runs the work after the delay and returns a way to cancel it.
        var schedule: (TimeInterval, @escaping TilingWork) -> () -> Void
        var appCenter: NotificationCenter
        var workspaceCenter: NotificationCenter
        var showRing: (TilingRingTarget?) -> Void
        var showSheet: ([TileKeyRow]?) -> Void
        var writeSetting: (String, String) -> Void
        /// Seconds on a clock that only moves forward. The applier's time budget reads it.
        var now: () -> Double

        static func live() -> Services {
            Services(
                driver: AXTilingWindowDriver(),
                keys: TilingKeyLayer(),
                readConfig: { TileConfig.fromSettings() },
                focusBorderOn: { FeatureSettings.tilingFocusBorder() },
                keyClash: { base, keymap in TilingKeyClash.note(base: base, keymap: keymap) },
                watchVoiceOver: { TilingKeyClash.watchVoiceOver($0) },
                whenTrusted: { work in AccessibilityGate.whenTrusted(key: TilingController.gateKey, work) },
                cancelTrustWait: { AccessibilityGate.cancelWaiting(key: TilingController.gateKey) },
                schedule: { delay, work in
                    let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                    return { item.cancel() }
                },
                appCenter: .default,
                workspaceCenter: NSWorkspace.shared.notificationCenter,
                showRing: { target in
                    if let target { TilingFocusBorder.shared.show(target) } else { TilingFocusBorder.shared.hide() }
                },
                showSheet: { rows in
                    if let rows { TilingKeySheet.shared.show(rows: rows, on: nil) } else { TilingKeySheet.shared.hide() }
                },
                writeSetting: { id, value in SettingsStore.shared.set(id, value) },
                now: { ProcessInfo.processInfo.systemUptime })
        }
    }

    /// Seconds one pass may run before it stops starting writes: the listing's budget and the writes' budget.
    static let passBudget = AXTilingWindowDriver.passBudget + TileApplier.defaultBudget

    static let shared = TilingController(services: .live())
    /// The key of the controller's own no-prompt wait. The key layer waits under its own key.
    static let gateKey = "tiling.controller"

    // MARK: What the section shows

    /// The switch and the settings as the owner has them, for the page.
    private(set) var config = TileConfig()
    private(set) var phase: TilingPhase = .off
    private(set) var picture: [TilingPictureDisplay] = []
    private(set) var keyRows: [TileKeyRow] = []
    private(set) var accessibilityOn = false
    private(set) var isPaused = false
    private(set) var keysUnavailable = false
    /// Why tiling is refused: another Zeus key or VoiceOver already holds the chosen keys. Nil when they are free.
    private(set) var keyClashNote: String?

    // MARK: Inner state

    @ObservationIgnored private let services: Services
    @ObservationIgnored private let isFixture: Bool
    @ObservationIgnored private var layout = TileLayoutState()
    @ObservationIgnored private var generation = TileGeneration()
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @ObservationIgnored private var cancelPending: (() -> Void)?
    @ObservationIgnored private var cancelSheetTimer: (() -> Void)?
    /// Stops the VoiceOver watch. Present from the first start with the switch on until tiling is turned off, so a
    /// clash that holds tiling back can end when VoiceOver does.
    @ObservationIgnored private var cancelVoiceOverWatch: (() -> Void)?
    @ObservationIgnored private var appliedConfig: TileConfig?
    @ObservationIgnored private var keymap = TileKeymap()
    /// The switch is on.
    @ObservationIgnored private var running = false
    /// Accessibility is on and the system observers are installed.
    @ObservationIgnored private var active = false
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var fullScreenFront = false
    /// The layout's focused window is the one with the keyboard now (or was just given it).
    @ObservationIgnored private var focusIsFront = false
    @ObservationIgnored private var followUps = 0
    @ObservationIgnored private var sheetVisible = false
    @ObservationIgnored private var ringTarget: TilingRingTarget?
    /// What the focus ring setting said the last time the ring was worked out.
    @ObservationIgnored private var ringAllowed = true
    @ObservationIgnored private var lastDisplays: [TileDisplay] = []
    @ObservationIgnored private var preTiling: [TileWindowID: TileRect] = [:]

    init(services: Services, fixture: Bool = false) {
        self.services = services
        isFixture = fixture
        keymap = TileKeymap.defaults(base: TileConfig.defaults.base)
        keyRows = TileKeyList.rows(keymap: keymap)
        services.keys.onAction = { [weak self] action in self?.handle(action) }
        services.keys.onUnavailable = { [weak self] in self?.keysGaveUp() }
    }

    // MARK: Test seams

    var isRunning: Bool { running }
    var observerCount: Int { observers.count }
    var generationValue: Int { generation.value }
    var floatingWindows: Set<TileWindowID> { layout.floating }
    func layoutWindows(on displayID: UInt32) -> [TileWindowID] { layout.trees[displayID]?.windows ?? [] }
    /// The frame a window had before tiling first moved it. Kept for a later undo; nothing restores it yet.
    func preTilingFrame(of window: TileWindowID) -> TileRect? { preTiling[window] }

    // MARK: Lifecycle

    /// Turns tiling on, or brings a running one up to date with the settings. Idempotent and cheap when nothing
    /// changed: the owner's settings notify on every preference write, and this runs on each. With the switch
    /// off it stops everything.
    func start() {
        guard !isFixture else { return }
        let wanted = services.readConfig()
        if config != wanted { config = wanted }
        guard wanted.enabled else {
            stop()
            return
        }
        watchVoiceOver()
        let wantedKeymap = TileKeymap.defaults(base: wanted.base)
        if keymap != wantedKeymap {
            keymap = wantedKeymap
            keyRows = TileKeyList.rows(keymap: keymap)
        }
        // Another Zeus key or VoiceOver holds these keys: the tap would consume the chord before that key's monitor
        // could cancel its hold. Nothing is installed until the owner picks another pair. The VoiceOver watch stays,
        // so tiling comes back when the clash ends.
        if let note = services.keyClash(wanted.base, wantedKeymap) {
            shutDown()
            if keyClashNote != note { keyClashNote = note }
            refreshPhase()
            return
        }
        if keyClashNote != nil { keyClashNote = nil }
        if running, appliedConfig == wanted {
            // An equal write still tells the owner about a revoked permission: the tap and the observers must not
            // outlive it, paused or not.
            if active, !services.driver.isTrusted {
                accessibilityLost()
                return
            }
            // The focus ring is not part of the config, so it is checked here.
            if services.focusBorderOn() != ringAllowed { updateRing(displays: lastDisplays) }
            refreshPhase()
            return
        }
        appliedConfig = wanted
        running = true
        setAccessibility(services.driver.isTrusted)
        services.keys.apply(enabled: true, paused: isPaused, keymap: keymap)
        if accessibilityOn {
            activate()
            if !isPaused { queueRelayout(delay: 0) }
        } else if active {
            // Accessibility was revoked while tiling ran: stop reading and writing, and wait for it again.
            accessibilityLost()
        } else {
            waitForAccessibility()
        }
        refreshPhase()
    }

    /// Removes everything: the observers, every queued item, the key tap, both overlays, the wait for
    /// Accessibility and the VoiceOver watch. Windows are left where they are.
    func stop() {
        guard !isFixture else { return }
        cancelVoiceOverWatch?()
        cancelVoiceOverWatch = nil
        shutDown()
    }

    /// `stop()` without the VoiceOver watch, for a clash that holds tiling back: the watch must outlive it.
    private func shutDown() {
        if keyClashNote != nil { keyClashNote = nil }
        guard running || active else {
            refreshPhase()
            return
        }
        running = false
        deactivate()
        _ = generation.advance()
        cancelPending?()
        cancelPending = nil
        hideSheet()
        setRing(nil)
        services.cancelTrustWait()
        services.keys.apply(enabled: false, paused: false, keymap: keymap)
        layout = TileLayoutState()
        picture = []
        appliedConfig = nil
        isPaused = false
        keysUnavailable = false
        sleeping = false
        fullScreenFront = false
        focusIsFront = false
        followUps = 0
        refreshPhase()
    }

    /// Watches VoiceOver once. When it starts or stops, the clash is checked again as it is on any settings write.
    private func watchVoiceOver() {
        guard cancelVoiceOverWatch == nil else { return }
        cancelVoiceOverWatch = services.watchVoiceOver { [weak self] in self?.start() }
    }

    /// Reads the settings and the Accessibility state for the page. Reads a permission, never asks for one.
    func refresh() {
        guard !isFixture else { return }
        let current = services.readConfig()
        if config != current { config = current }
        setAccessibility(services.driver.isTrusted)
        refreshPhase()
    }

    // MARK: The page's controls

    /// Writes the same switch Settings has. The app's settings observer starts or stops tiling from it.
    func setEnabled(_ on: Bool) {
        services.writeSetting("tiling.enabled", on ? "true" : "false")
        refresh()
    }

    func setGap(inner: Bool, to value: Double) {
        let clamped = min(max(value.isFinite ? value : TileConfig.defaultGap, TileConfig.gapRange.lowerBound), TileConfig.gapRange.upperBound)
        services.writeSetting(inner ? "tiling.innerGap" : "tiling.outerGap", String(Int(clamped.rounded())))
        refresh()
    }

    func chooseBase(_ base: TileModifierBase) {
        services.writeSetting("tiling.keyBase", base.label)
        refresh()
    }

    /// Stops or resumes arranging. A pause leaves windows where they are; the tap then takes only the resume
    /// chord. It does nothing when the keys are unavailable, because there would be no chord to resume with.
    func togglePause() {
        guard !isFixture, running, !keysUnavailable else { return }
        isPaused.toggle()
        services.keys.apply(enabled: true, paused: isPaused, keymap: keymap)
        if isPaused {
            cancelPending?()
            cancelPending = nil
            hideSheet()
            setRing(nil)
        } else if active {
            queueRelayout(delay: 0)
        }
        refreshPhase()
    }

    // MARK: Keys

    /// A bound chord. Runs on the main actor after the tap callback has returned.
    func handle(_ action: TileAction) {
        guard !isFixture, running, active, !sleeping else { return }
        if isPaused, action != .togglePause { return }
        if action != .showKeys { hideSheet() }
        // These two read no window and move none, so they need neither Accessibility nor a window in front.
        switch action {
        case .togglePause:
            togglePause()
            return
        case .showKeys:
            presentSheet()
            return
        default:
            break
        }
        let driver = services.driver
        guard driver.isTrusted else {
            accessibilityLost()
            return
        }
        let front = driver.frontmost()
        // A full-screen app has the screen: tiling keys do nothing over it.
        guard !front.isFullScreen else { return }
        syncFocus(front)
        // The keyboard is in an app tiling does not read, so the layout's focused window is not the one the owner is
        // looking at. These act on that window, so they wait until a tiled window has the keyboard.
        if !focusIsFront {
            switch action {
            case .swap, .flipSplit, .nudge, .toggleFloat: return
            default: break
            }
        }
        let displays = driver.displays()
        lastDisplays = displays
        let outcome = TileResolver.resolve(action, in: layout, displays: displays, config: engineConfig)
        layout = outcome.state
        switch outcome.effect {
        case .none:
            break
        case .focus(let window):
            driver.focus(window)
            // The neighbour came from the last listing, which can be minutes old: it may be minimized, on another
            // Space, or an app that did not answer, and then the driver cannot give it the keyboard. The ring follows
            // the keyboard as the system reports it after the call, not the request.
            syncFocus(driver.frontmost())
            publish(displays: displays)
            queueRelayout(delay: 0.15)
        case .relayout:
            cancelPending?()
            cancelPending = nil
            runPass()
        case .togglePause:
            togglePause()
        case .showKeys:
            presentSheet()
        }
    }

    private func keysGaveUp() {
        guard running else { return }
        keysUnavailable = true
        isPaused = true
        cancelPending?()
        cancelPending = nil
        hideSheet()
        setRing(nil)
        refreshPhase()
    }

    // MARK: Watching the system

    private func activate() {
        guard !active else { return }
        active = true
        observe(services.appCenter, NSApplication.didChangeScreenParametersNotification) { $0.systemChanged(delay: 0.5) }
        let workspace = services.workspaceCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.systemChanged(delay: 0.4) }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.willSleep() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.didWake() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.appsChanged(delay: 0.15) }
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { $0.appsChanged(delay: 0.5) }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { $0.appsChanged(delay: 0.4) }
    }

    private func deactivate() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers = []
        active = false
    }

    /// These notifications post on the main thread; a post from anywhere else is moved there.
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (TilingController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { if let self { handler(self) } }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { if let self { handler(self) } } }
            }
        }
        observers.append((center, token))
    }

    /// A display or a Space changed: work queued before now is stale. Rebuild once, after things settle.
    private func systemChanged(delay: TimeInterval) {
        guard running, active, !sleeping else { return }
        _ = generation.advance()
        queueRelayout(delay: delay)
    }

    private func appsChanged(delay: TimeInterval) {
        guard running, active, !sleeping, !isPaused else { return }
        queueRelayout(delay: delay)
    }

    private func willSleep() {
        guard running, active else { return }
        sleeping = true
        _ = generation.advance()
        cancelPending?()
        cancelPending = nil
        hideSheet()
    }

    private func didWake() {
        guard running, active else { return }
        sleeping = false
        _ = generation.advance()
        queueRelayout(delay: 2)
    }

    private func waitForAccessibility() {
        services.whenTrusted { [weak self] in self?.accessibilityArrived() }
    }

    private func accessibilityArrived() {
        guard running, !active, services.driver.isTrusted else { return }
        accessibilityOn = true
        activate()
        if !isPaused { queueRelayout(delay: 0) }
        refreshPhase()
    }

    /// Accessibility went away while tiling was on: stop reading and writing, drop the observers, wait for it.
    private func accessibilityLost() {
        accessibilityOn = false
        deactivate()
        cancelPending?()
        cancelPending = nil
        hideSheet()
        setRing(nil)
        services.keys.apply(enabled: true, paused: isPaused, keymap: keymap)
        waitForAccessibility()
        refreshPhase()
    }

    // MARK: Passes

    /// One pass at a time is queued: a new request replaces the one waiting.
    private func queueRelayout(delay: TimeInterval, followUp: Bool = false) {
        cancelPending?()
        followUps = followUp ? followUps + 1 : 0
        let token = generation.value
        cancelPending = services.schedule(delay) { [weak self] in self?.relayoutNow(token: token) }
    }

    private func relayoutNow(token: Int) {
        guard generation.isCurrent(token) else { return }
        cancelPending = nil
        guard running, active, !sleeping, !isPaused else { return }
        runPass()
    }

    private var engineConfig: TileConfig {
        var engine = config
        engine.paused = isPaused
        engine.floating = layout.floating
        return engine
    }

    private func syncFocus(_ front: TileFrontmost) {
        if let focused = front.focused {
            layout.focused = focused
            focusIsFront = true
            if layout.recency.first != focused { layout.noteFocus(focused) }
        } else {
            focusIsFront = false
        }
    }

    /// Reads the windows, brings each display's tree in line with them, and writes only the frames that differ.
    /// A window that would not move is floated for the session and the layout is worked out again without it;
    /// a window the time budget cut off is not floated, and a later pass takes it.
    private func runPass() {
        let driver = services.driver
        guard driver.isTrusted else {
            accessibilityLost()
            return
        }
        accessibilityOn = true
        let front = driver.frontmost()
        guard !front.isFullScreen else {
            // A full-screen app has the screen: keep the layout as it is and write nothing until it ends.
            fullScreenFront = true
            setRing(nil)
            refreshPhase()
            return
        }
        fullScreenFront = false
        syncFocus(front)

        // One deadline bounds the whole pass on the main thread: the listing (its own budget), every display and every
        // round of the loop below. A write in flight cannot be cut short, so the deadline is only checked before each move.
        let deadline = services.now() + Self.passBudget
        let displays = driver.displays()
        lastDisplays = displays
        var listing = driver.windows(config: engineConfig)
        let unread = driver.unreadPIDs
        var deferred = false

        for _ in 0..<3 {
            let engine = engineConfig
            let eligible = TilePlanner.eligible(listing, config: engine, displays: displays)
            let listed = Set(listing.map(\.id))
            var trees: [UInt32: TileTree] = [:]
            for display in displays {
                let mine = eligible.filter { TileDisplays.display(for: $0.frame, in: displays)?.id == display.id }
                var wanted = Set(mine.map(\.id))
                let old = layout.trees[display.id] ?? TileTree(displayID: display.id)
                // An app that did not answer in time is unknown, not gone: its windows keep their slots. A window
                // missing from an app that did answer is gone.
                wanted.formUnion(TilePlanner.slotsToKeep(old: old.windows, listed: listed, floating: engine.floating, unreadPIDs: unread))
                trees[display.id] = TileOps.reconcile(tree: old, eligible: wanted, order: mine.map(\.id),
                                                      display: display.visibleFrame, config: engine).tree
            }
            layout.trees = trees

            var refused: [TileWindowID] = []
            for display in displays {
                guard let tree = layout.trees[display.id], !tree.isEmpty else { continue }
                let plan = TilePlanner.plan(tree: tree, display: display, config: engine, windows: listing)
                for move in plan.moves where preTiling[move.id] == nil { preTiling[move.id] = move.current }
                let outcome = TileApplier.apply(plan, with: driver, until: deadline, clock: services.now)
                if outcome.state == .accessibilityOff {
                    accessibilityLost()
                    return
                }
                refused += outcome.refused
                deferred = deferred || !outcome.deferred.isEmpty
                for (index, window) in listing.enumerated() where outcome.moved.contains(window.id) {
                    if let landed = outcome.intended[window.id] { listing[index].frame = landed }
                }
            }
            guard !refused.isEmpty else { break }
            layout.floating.formUnion(refused)
        }

        let known = Set(layout.tiledWindows).union(layout.floating).union(listing.map(\.id))
        if let focused = layout.focused, !known.contains(focused) { layout.focused = nil }
        layout.recency = layout.recency.filter { known.contains($0) }
        // Ids are never reused, so the undo memory of a window that is gone is dead weight. The windows of an app
        // that did not answer in time are unknown, not gone, so their memory stays.
        preTiling = preTiling.filter { known.contains($0.key) || unread.contains($0.key.pid) }
        publish(displays: displays)
        if deferred, followUps < 5 { queueRelayout(delay: 0.2, followUp: true) }
    }

    // MARK: Showing the result

    /// The picture for the page and the ring for the focused tiled window.
    private func publish(displays: [TileDisplay]) {
        let engine = engineConfig
        let marked = focusIsFront ? layout.focused : nil
        picture = TilingPicture.make(displays: displays, trees: layout.trees, config: engine, focused: marked)
        refreshPhase()
        updateRing(displays: displays)
    }

    /// Puts the ring around the focused tiled window, or orders it out when it should not show.
    private func updateRing(displays: [TileDisplay]) {
        let engine = engineConfig
        let marked = focusIsFront ? layout.focused : nil
        let allowed = services.focusBorderOn()
        ringAllowed = allowed
        guard running, !isPaused, !fullScreenFront, accessibilityOn, allowed,
              let marked, let place = layout.location(of: marked),
              let display = displays.first(where: { $0.id == place.displayID }),
              let frame = TileFrames.frames(of: place.tree, display: display.visibleFrame, config: engine)[marked],
              !frame.isEmpty else {
            setRing(nil)
            return
        }
        setRing(TilingRingTarget(display: display, frame: frame))
    }

    private func setRing(_ target: TilingRingTarget?) {
        guard target != ringTarget else { return }
        ringTarget = target
        services.showRing(target)
    }

    private func presentSheet() {
        cancelSheetTimer?()
        sheetVisible = true
        services.showSheet(keyRows)
        cancelSheetTimer = services.schedule(6) { [weak self] in self?.hideSheet() }
    }

    private func hideSheet() {
        cancelSheetTimer?()
        cancelSheetTimer = nil
        guard sheetVisible else { return }
        sheetVisible = false
        services.showSheet(nil)
    }

    /// Each of these only assigns a changed value: `@Observable` notifies on every set, and the settings observer
    /// calls `start()` on every preference write in the process, so an equal assignment would redraw the page.
    private func refreshPhase() {
        let next = TilingPhase(enabled: running || keyClashNote != nil, accessibilityOn: accessibilityOn,
                               keysUnavailable: keysUnavailable, paused: isPaused, keyClash: keyClashNote != nil)
        if phase != next { phase = next }
    }

    private func setAccessibility(_ on: Bool) {
        if accessibilityOn != on { accessibilityOn = on }
    }
}

// MARK: Snapshot fixtures

extension TilingController {
    /// A controller that only shows a state. It reads no setting and no window, starts nothing, and ignores every
    /// call, so the page renders the same everywhere and `Zeus --snapshots` touches no Accessibility function.
    static func snapshotFixture(_ state: TilingSnapshotState, driver: (any TilingWindowDriver)? = nil) -> TilingController {
        let quiet = Services(
            driver: driver ?? AXTilingWindowDriver(isTrusted: { false }), keys: FixtureKeys(),
            readConfig: { TileConfig() }, focusBorderOn: { false }, whenTrusted: { _ in }, cancelTrustWait: {},
            schedule: { _, _ in {} }, appCenter: NotificationCenter(), workspaceCenter: NotificationCenter(),
            showRing: { _ in }, showSheet: { _ in }, writeSetting: { _, _ in }, now: { 0 })
        let controller = TilingController(services: quiet, fixture: true)
        controller.seed(state)
        return controller
    }

    @MainActor private final class FixtureKeys: TilingKeyControlling {
        var onAction: (TileAction) -> Void = { _ in }
        var onUnavailable: () -> Void = {}
        func apply(enabled: Bool, paused: Bool, keymap: TileKeymap) {}
    }

    private func seed(_ state: TilingSnapshotState) {
        let main = Self.fixtureDisplay(id: 1, appKit: TileRect(x: 0, y: 0, width: 1512, height: 982), menuBar: 38)
        let side = Self.fixtureDisplay(id: 2, appKit: TileRect(x: 1512, y: -458, width: 2560, height: 1440), menuBar: 24)
        let windows = (1...3).map { TileWindowID(pid: 100, index: $0) }
        let others = (1...2).map { TileWindowID(pid: 200, index: $0) }
        let enabled = state != .off
        config = TileConfig(enabled: enabled)
        accessibilityOn = state != .needsAccessibility
        isPaused = state == .paused
        running = enabled
        let displays = state == .twoDisplays ? [main, side] : [main]
        if enabled, state != .needsAccessibility {
            var trees: [UInt32: TileTree] = [:]
            trees[main.id] = TileOps.reconcile(tree: TileTree(displayID: main.id), eligible: Set(windows), order: windows,
                                               display: main.visibleFrame, config: config).tree
            if state == .twoDisplays {
                trees[side.id] = TileOps.reconcile(tree: TileTree(displayID: side.id), eligible: Set(others), order: others,
                                                   display: side.visibleFrame, config: config).tree
            }
            picture = TilingPicture.make(displays: displays, trees: trees, config: config, focused: windows[0])
        }
        phase = TilingPhase(enabled: running, accessibilityOn: accessibilityOn, keysUnavailable: false, paused: isPaused)
    }

    private static func fixtureDisplay(id: UInt32, appKit: TileRect, menuBar: Double) -> TileDisplay {
        TileDisplay(id: id, appKitFrame: appKit,
                    appKitVisibleFrame: TileRect(x: appKit.x, y: appKit.y, width: appKit.width, height: appKit.height - menuBar),
                    engineFrame: TileDisplay.engineFrame(appKitFrame: appKit, mainScreenHeight: 982))
    }
}
