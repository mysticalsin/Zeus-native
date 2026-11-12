import AppKit
import SwiftUI
import ZeusCore

/// Owns the notch window. It sits over the menu bar at the top centre of the notched screen
/// (or the main screen as a pill on Macs without a notch) and is click-through while closed.
@MainActor
final class NotchController {
    let model = NotchModel()
    /// Set before `start()` to get the full top bar (pages, wings, shelf drop).
    var topBar: TopBarModel?
    /// One borderless window per display that shows the notch (Settings > General).
    private var panels: [(display: DisplayDescriptor, screen: NSScreen, panel: NotchPanel)] = []
    private var window: NSPanel? { panels.first { $0.screen == screen }?.panel ?? panels.first?.panel }
    /// For `zeus debug screenshot --window notch`.
    var debugWindow: NSWindow? { window }
    /// The display the pointer and the open panel work on.
    private(set) var screen: NSScreen?
    private(set) var notchSize: CGSize = .zero
    /// How far the closed bar and the peek card sit below the screen top on the active display
    /// (Settings > Appearance > Top bar position); 0 while the panel is open.
    private var topOffset: CGFloat {
        CGFloat(TopBarPosition.applied(resolved: TopBarPositionModel.shared.offset, panelOpen: model.presentation == .panel))
    }
    private(set) var displays: [DisplayDescriptor] = []
    private var stallTimer: Timer?
    /// Tests and previews replace the clock.
    var now: () -> Date = { Date() }
    /// One sleep to the next alert deadline; nil whenever nothing will expire on its own.
    private var alertWake: Task<Void, Never>?
    /// Alerts waiting out their ten minute snooze, by alert id.
    private var snoozeTasks: [String: Task<Void, Never>] = [:]
    /// What happens when the notification line is clicked.
    var openNotificationLine: (NotchModel.NotificationLine) -> Void = { _ in }

    private var hoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var dragMonitors: [Any] = []
    private var dragChangeCount = 0
    private var hoverTask: Task<Void, Never>?
    /// Injectable for non-capturing app tests. Pinning applies only to the Polyglot page.
    var isPolyglotPinned: () -> Bool = { PolyglotController.shared.isPinned }
    /// The pin rules live in ZeusCore; this only reports the current facts.
    private func pinContext() -> PolyglotPinContext {
        PolyglotPinContext(isPolyglotTabSelected: topBar?.selectedTab == .polyglot, isPinned: isPolyglotPinned(),
                           autoHideEnabled: SettingsStore.shared.bool("notch.autoHide"))
    }

    func start() {
        NotchControllerBridge.controller = self
        build()
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        // Over our own window the global monitor goes quiet, so the open panel (and a peek)
        // would never see the pointer leave or arrive. A local monitor covers that half.
        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }
        // Dragging files up to the notch opens the Shelf, like dropping onto a tray.
        dragMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dragChangeCount = NSPasteboard(name: .drag).changeCount
                self?.clickedOutside()
            }
        } as Any)
        dragMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        } as Any)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays(force: true) }
        }
        // Lock, unlock, wake and Space changes can leave the windows behind or on the wrong display.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDisplays(force: false) }
            }
        }
        for name in ["com.apple.screenIsUnlocked", "com.apple.screenIsLocked"] {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDisplays(force: false) }
            }
        }
        // Stalled agents: a quiet check every 20 seconds, nothing while no session works.
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStalls() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    /// QA screencapture: `.none` excludes the notch from local capture; briefly use `.readOnly` instead.
    func boostCaptureVisibility(for seconds: TimeInterval) {
        for entry in panels {
            entry.panel.sharingType = .readOnly
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            let visible = ZeusWindowSharing.policy(
                showInScreenSharing: SettingsStore.shared.bool(ZeusScreenSharePolicy.showInSharingKey),
                meetingActive: MeetingState.active,
                teleprompterSessionHidden: false
            )
            self.applyScreenSharePolicy(visibleInShare: visible)
        }
    }

    /// N1: applies the shared screen-share policy to every notch panel.
    func applyScreenSharePolicy(visibleInShare: Bool) {
        hiddenFromCapture = !visibleInShare
        for entry in panels {
            ZeusWindowSharing.apply(to: entry.panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }

    /// Keeps the notch out of screen shares during meetings (via `applyScreenSharePolicy`).
    func setHiddenFromCapture(_ hidden: Bool) {
        applyScreenSharePolicy(visibleInShare: !hidden)
    }
    private var hiddenFromCapture = false

    // MARK: Presentation

    func show(_ presentation: NotchModel.Presentation) {
        let opening = presentation == .panel && model.presentation != .panel
        if opening { model.openedAt = Date() }
        // NotchView animates width and height on their own springs (Glance's height leads on open).
        model.heightPresentation = presentation
        model.presentation = presentation
        if presentation != .panel { model.picker = nil }
        if presentation != .peek { model.recap = nil }
        setIgnoresMouse(presentation == .closed)
        // The capsule shows only on the closed notch: while a peek or the panel covers it, alert timers pause.
        model.alerts.setSuspended(presentation != .closed, now: now())
        alertsChanged()
        if opening { NotchHaptics.open() }
        onPresentationChange(presentation)
    }

    /// Told every time the notch changes shape (the buddy hides over the open panel).
    var onPresentationChange: (NotchModel.Presentation) -> Void = { _ in }

    func startSession(id: String, agent: String, project: String, task: String) {
        let session = NotchModel.Session(id: id, agent: agent, project: project, task: task, status: .working, startedAt: Date())
        if let index = model.sessions.firstIndex(where: { $0.id == id }) {
            model.sessions[index] = session
        } else {
            model.sessions.append(session)
        }
        model.peekSessionID = id
        if model.presentation == .closed { show(.peek) }
    }

    /// Creates or updates a session from a hook event without changing what is shown.
    func upsertSession(id: String, agent: String, project: String, task: String, status: NotchModel.Status,
                       restartClock: Bool = false) {
        let moment = now()
        if let index = model.sessions.firstIndex(where: { $0.id == id }) {
            model.sessions[index].task = task
            // Any event from a failed or stalled session means it is moving again.
            model.sessions[index].status = status
            model.sessions[index].lastEventAt = moment
            if status != .failed, status != .stalled { model.sessions[index].reason = nil }
            if restartClock { model.sessions[index].startedAt = moment }
        } else {
            model.sessions.append(.init(id: id, agent: agent, project: project, task: task, status: status, startedAt: moment, lastEventAt: moment))
        }
        if model.failure?.sessionID == id, status != .failed { model.failure = nil }
        model.peekSessionID = id
        model.picker?.resize(model.sessions.count)
    }

    /// Any hook event counts as a sign of life, even one that changes nothing visible.
    func touch(sessionID: String) {
        guard let index = model.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        model.sessions[index].lastEventAt = now()
        if model.sessions[index].status == .stalled {
            model.sessions[index].status = .working
            model.sessions[index].reason = nil
        }
    }

    /// The agent's turn ended in an error: red halo, a card with the reason, and a macOS notification
    /// when Settings > Notifications > Errors is on.
    func failSession(id: String, agent: String, project: String, reason: String) {
        upsertSession(id: id, agent: agent, project: project, task: reason, status: .failed)
        if let index = model.sessions.firstIndex(where: { $0.id == id }) { model.sessions[index].reason = reason }
        guard SettingsStore.shared.bool("notify.errors") else { return }
        model.failure = NotchModel.Failure(sessionID: id, agent: agent, project: project, reason: reason)
        model.completion = nil
        if model.presentation == .closed { show(.peek) }
        Task { await SystemNotificationService.shared.deliverAgentAlert(.failed(agent: agent, project: project, reason: reason, session: id)) }
    }

    /// Clears the red card and returns the session to idle.
    func dismissFailure() {
        guard let failure = model.failure else { return }
        model.failure = nil
        if let index = model.sessions.firstIndex(where: { $0.id == failure.sessionID }), model.sessions[index].status == .failed {
            model.sessions[index].status = .idle
            model.sessions[index].reason = nil
        }
        if model.presentation == .peek, model.approval == nil, model.completion == nil { show(.closed) }
    }

    /// Marks silent working sessions as stalled (amber) and cues once per stall.
    func checkStalls() {
        let minutes = AgentStall.minutes(fromLabel: SettingsStore.shared.string("notify.stallMinutes"))
        let newly = model.checkStalls(now: now(), threshold: TimeInterval(minutes * 60))
        guard !newly.isEmpty, SettingsStore.shared.bool("notify.errors") else { return }
        for session in newly {
            Task { await SystemNotificationService.shared.deliverAgentAlert(.stalled(agent: session.agent, project: session.project, minutes: minutes, session: session.id)) }
        }
        if model.presentation == .closed, model.approval == nil, let first = newly.first {
            model.peekSessionID = first.id
            show(.peek)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.model.presentation == .peek, self.model.approval == nil, self.model.completion == nil, self.model.failure == nil else { return }
                self.show(.closed)
            }
        }
    }

    func removeSession(id: String) {
        model.sessions.removeAll { $0.id == id }
        model.picker?.resize(model.sessions.count)
        if model.failure?.sessionID == id { model.failure = nil }
        if model.peekSessionID == id { model.peekSessionID = model.sessions.last?.id }
        // With the top bar the panel is useful without agents, so don't snap it shut under the pointer.
        if model.sessions.isEmpty, model.approval == nil, !(topBar != nil && model.presentation == .panel) { show(.closed) }
    }

    func update(sessionID: String, status: NotchModel.Status, task: String? = nil) {
        guard let index = model.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        model.sessions[index].status = status
        model.sessions[index].lastEventAt = now()
        if status != .failed, status != .stalled { model.sessions[index].reason = nil }
        if let task { model.sessions[index].task = task }
        model.peekSessionID = sessionID
    }

    /// Shows an approval card and waits for Approve / Deny (click or voice). One card at a time:
    /// a second request waits for the first. On timeout it returns `onTimeout`.
    func requestApproval(agent: String, project: String, tool: String, command: String, risk: HookEvent.Risk,
                         timeout: Duration = .seconds(120),
                         onTimeout: HookDecision.Verdict = .deny,
                         detail: ApprovalDetail? = nil,
                         trust: (session: String, onTrust: @MainActor () -> Void)? = nil) async -> HookDecision.Verdict {
        // A cancelled caller (`zeus cancel`, Esc) must not spin here: sleep throws at once when cancelled.
        while model.approval != nil, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if Task.isCancelled { return .deny }
        return await withCheckedContinuation { continuation in
            let id = UUID().uuidString
            var finished = false
            let finish: @MainActor (HookDecision.Verdict) -> Void = { [weak self] verdict in
                guard !finished else { return }
                finished = true
                if self?.model.approval?.id == id { self?.model.approval = nil }
                continuation.resume(returning: verdict)
            }
            let seconds = Double(timeout.components.seconds)
            let note = switch onTimeout {
            case .ask: "then your terminal asks"
            case .allow: "then it's approved"
            case .deny: "then it's denied"
            }
            var trustChat: (@MainActor () -> Void)?
            if let onTrust = trust?.onTrust {
                trustChat = { onTrust(); finish(.allow) }
            }
            model.approval = NotchModel.Approval(
                id: id, agent: agent, project: project, tool: tool, command: command, risk: risk,
                deadline: Date().addingTimeInterval(seconds), timeoutNote: note, detail: detail,
                sessionID: trust?.session,
                trustChat: trustChat,
                resolve: finish
            )
            model.completion = nil
            model.recap = nil
            // VoiceOver users hear the request even though the notch never takes focus.
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: detail.map { "\(agent) \($0.announcement)" } ?? "\(agent) needs approval: \(command)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
            if model.presentation == .closed { show(.peek) }
            setIgnoresMouse(false)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish(onTimeout)
            }
        }
    }

    /// Hover the notch to open the panel; move away to close it. With the top bar the panel
    /// always has something to show, so it opens after a short dwell (no accidental flashes).
    private func mouseMoved() {
        followPointer()
        guard let screen, topBar != nil || !model.sessions.isEmpty || model.approval != nil else { return }
        switch model.presentation {
        case .closed, .peek:
            if PointerZone.shared.overNotchPanel { PointerZone.shared.overNotchPanel = false }
            // The slim notification line takes the mouse only while the pointer is on it.
            if model.notificationLine != nil, model.presentation == .closed {
                let over = notificationLineRect(screen).contains(NSEvent.mouseLocation)
                setIgnoresMouse(!over)
                if !over, model.alerts.isHovered { setAlertHovered(false) }
                if over { return }
            }
            guard inHotZone(screen) else { hoverTask?.cancel(); hoverTask = nil; return }
            guard topBar != nil else { show(.panel); return }
            guard hoverTask == nil else { return }
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Self.openDelayMilliseconds))
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if self.inHotZone(screen), self.model.presentation != .panel { self.show(.panel) }
            }
        case .panel:
            // The teleprompter stays up while you read, wherever the pointer goes; so does the picker.
            if topBar?.prompterActive == true || model.picker != nil { return }
            // A menu from the ... button is open: keep the panel up until it closes.
            if topBar?.menuOpen == true { return }
            let mouse = NSEvent.mouseLocation
            let top = screen.frame.maxY
            let barHeight = max(notchSize.height, 30)
            let size: CGSize
            if topBar != nil {
                size = NotchView.topBarPanelSize(barHeight: barHeight, hasApproval: model.approval != nil,
                                                 extra: model.approval?.extraHeight ?? 0, home: topBar?.selectedTab == .home,
                                                 homeStrip: topBar?.homeExtraHeight ?? 0)
            } else {
                let rows = CGFloat(max(model.sessions.count, 1))
                size = CGSize(width: 560, height: barHeight + 34 + rows * 62 + (model.approval != nil ? 110 : 0))
            }
            // Glance-like slack: a little room past the sides and bottom before it closes.
            let outside = abs(mouse.x - screen.frame.midX) > size.width / 2 + 36 || mouse.y < top - size.height - 48
            let over = topBar != nil
                ? GlanceTopBar.openShapeContains(mouse, screen: screen.frame, size: size)
                : abs(mouse.x - screen.frame.midX) <= size.width / 2 && mouse.y >= top - size.height
            if PointerZone.shared.overNotchPanel != over { PointerZone.shared.overNotchPanel = over }
            // The window spans the screen: it takes the mouse only over the notch's shape, so clicks
            // beside or below it reach the app underneath.
            setIgnoresMouse(!over)
            guard outside else { closeTask?.cancel(); closeTask = nil; return }
            switch PolyglotPinPolicy.decide(.pointerExited, pinContext()) {
            case .keepOpen:
                closeTask?.cancel(); closeTask = nil
                return
            case .close, .scheduleClose:
                guard closeTask == nil else { return }
            }
            let delay = Self.closeDelayMilliseconds
            guard delay > 0 else { dismissAutomatically(); return }
            closeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, !Task.isCancelled else { return }
                self.closeTask = nil
                if self.model.presentation == .panel { self.dismissAutomatically() }
            }
        }
    }

    private var closeTask: Task<Void, Never>?

    /// Re-evaluate a pending close immediately when the pin is changed, including unpinning.
    func polyglotPinChanged() {
        closeTask?.cancel()
        closeTask = nil
        mouseMoved()
    }

    /// Automatic dismissal respects a pin; explicit `show(.closed)` still always works.
    func dismissAutomatically() {
        guard PolyglotPinPolicy.decide(.clickedOutside, pinContext()) == .close else { return }
        show(model.approval != nil ? .peek : .closed)
    }

    /// The Dismiss button: closes even a pinned bar (it always showed `.closed`, approval or not).
    func dismissExplicitly() {
        guard PolyglotPinPolicy.decide(.explicitDismiss, pinContext()) == .close else { return }
        show(.closed)
    }

    /// With auto-hide off the panel stays open until a click elsewhere (global monitors only see other apps).
    private func clickedOutside() {
        guard model.presentation == .panel, !SettingsStore.shared.bool("notch.autoHide"), topBar?.prompterActive != true, model.picker == nil else { return }
        dismissAutomatically()
    }

    /// Settings > Appearance > Notch behavior.
    static var openDelayMilliseconds: Int {
        switch SettingsStore.shared.string("notch.openDelay") { case "Fast": 100; case "Relaxed": 600; default: 250 }
    }
    static var closeDelayMilliseconds: Int {
        switch SettingsStore.shared.string("notch.closeDelay") { case "0.5 s": 500; case "1 s": 1000; case "2 s": 2000; default: 0 }
    }

    /// Glance's trigger (TOPBAR-SPEC §6): the closed island plus the 27.5 pt ears either side, as
    /// tall as the bar. With wings showing, the island is the notch and both wings.
    private func inHotZone(_ screen: NSScreen) -> Bool {
        var island = max(notchSize.width, 160)
        if let topBar, ClosedWings.kind(of: topBar) != .none {
            island += 2 * (ClosedWings.wingWidth + 8) + ClosedWings.extraWidth(for: topBar)
        }
        return GlanceTopBar.inHoverZone(NSEvent.mouseLocation, screen: screen.frame,
                                        notch: CGSize(width: island, height: max(notchSize.height, 30) + topOffset))
    }

    private func mouseDragged() {
        guard let topBar, let screen else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != dragChangeCount,
              board.types?.contains(.fileURL) == true else { return }
        if !topBar.isDraggingFiles {
            topBar.isDraggingFiles = true
            dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
                MainActor.assumeIsolated { self?.dragEnded() }
            }
        }
        let mouse = NSEvent.mouseLocation
        let near = abs(mouse.x - screen.frame.midX) < 330 && mouse.y > screen.frame.maxY - 110
        if near, !(model.presentation == .panel && topBar.selectedTab == .shelf) {
            topBar.selectedTab = .shelf
            show(.panel)
        }
    }

    private var dragEndMonitor: Any?

    private func dragEnded() {
        topBar?.isDraggingFiles = false
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
        dragEndMonitor = nil
    }

    /// Where the Approve button sits on screen while an approval peek is open (global AppKit coordinates).
    var approveButtonPoint: CGPoint? {
        guard let screen else { return nil }
        // Mirrors NotchView's approval peek: a diff card is 520 wide, the plain one 440. The button row
        // sits 10 pt under the bar, after the 22 pt header row and 8 pt of spacing (its centre is about 55 pt
        // below the bar); a diff detail above the buttons pushes them down by its height plus 8 pt, and a
        // multi-line change preview by its own height.
        let detailHeight = model.approval?.detail?.height ?? 0
        let wide = detailHeight > 0
        let peekWidth = max(notchSize.width + 16 + 240, wide ? 520 : 440)
        let rowOffset: CGFloat = 55 + (wide ? detailHeight + 8 : 0) + (model.approval?.previewHeight ?? 0)
        return CGPoint(x: screen.frame.midX + peekWidth / 2 - 60, y: screen.frame.maxY - topOffset - max(notchSize.height, 30) - rowOffset)
    }

    // MARK: Window

    func allowKeyboard(_ check: @escaping @MainActor () -> Bool) {
        NotchPanel.acceptsKeyboard = { [weak self] in check() || self?.model.picker != nil }
        NotchPanel.pickerKey = { [weak self] code in self?.pickerKey(code) ?? false }
    }

    private func setIgnoresMouse(_ ignore: Bool) {
        for entry in panels {
            // Only the window on the active display ever takes the mouse.
            let want = ignore || entry.screen != screen
            if entry.panel.ignoresMouseEvents != want { entry.panel.ignoresMouseEvents = want }
        }
    }

    // MARK: Displays

    static func describe(_ screen: NSScreen) -> DisplayDescriptor {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
        return DisplayDescriptor(id: number, frame: screen.frame, hasNotch: screen.safeAreaInsets.top > 0,
                                 isBuiltIn: number != 0 && CGDisplayIsBuiltin(CGDirectDisplayID(number)) != 0)
    }

    private var displayMode: NotchDisplayMode { NotchDisplayMode(label: SettingsStore.shared.string("notch.displays")) }

    private func targetDisplays() -> [DisplayDescriptor] {
        DisplaySelection.targets(mode: displayMode, screens: NSScreen.screens.map(Self.describe), pointer: NSEvent.mouseLocation)
    }

    /// Settings changed the display choice, a display came or went, or the Mac woke or unlocked.
    /// Rebuilds only when the target displays changed; otherwise raises the windows again.
    func refreshDisplays(force: Bool) {
        let next = targetDisplays()
        if force || panels.isEmpty || DisplaySelection.needsRebuild(current: displays, next: next) {
            build()
        } else {
            for entry in panels { entry.panel.orderFrontRegardless() }
        }
    }

    /// "Display with the pointer": while the notch is closed and quiet it moves to the pointer's display.
    private func followPointer() {
        if panels.count > 1 {
            // All displays: the pointer's display is the active one until the panel is open.
            if model.presentation != .panel, let under = panels.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) }) {
                activate(under.screen)
            }
            return
        }
        guard displayMode == .pointer, model.presentation == .closed, model.approval == nil, model.notificationLine == nil else { return }
        let next = targetDisplays()
        if let id = next.first?.id, displays.first?.id != id { build() }
    }

    private func build() {
        for entry in panels { entry.panel.orderOut(nil) }
        panels = []
        let targets = targetDisplays()
        displays = targets
        let byID = Dictionary(NSScreen.screens.map { (Self.describe($0).id, $0) }, uniquingKeysWith: { first, _ in first })
        for display in targets {
            guard let target = byID[display.id] else { continue }
            let size = Self.notchSize(of: target)
            // Glance's window: as wide as the screen (room for the halo arms and the edge wave), 470 tall,
            // at the status-bar layer; transparent areas pass clicks through.
            let frame = GlanceTopBar.windowFrame(screen: target.frame)
            let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            // After isFloatingPanel, which resets the level to floating (3).
            panel.level = NSWindow.Level(rawValue: GlanceTopBar.windowLayer)
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = true
            ZeusWindowSharing.apply(to: panel, visibleInShare: !hiddenFromCapture, surface: .zeusStandard)
            let hosting = NotchHostingView(rootView: NotchView(model: model, topBar: topBar, notch: size,
                                                                slimPill: DisplaySelection.showsPill(display)))
            // The panel's frame is set here, never from the content: without this the hosting view
            // re-measures the whole notch tree on every animation frame (≈30% of the main thread in QA).
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            panels.append((display, target, panel))
        }
        let primary = panels.first
        screen = primary?.screen ?? NSScreen.main ?? NSScreen.screens.first
        notchSize = screen.map(Self.notchSize(of:)) ?? .zero
        setIgnoresMouse(model.presentation == .closed)
    }

    /// With several displays the one under the pointer is the one that opens.
    private func activate(_ target: NSScreen) {
        guard screen != target else { return }
        screen = target
        notchSize = Self.notchSize(of: target)
    }

    // MARK: Notification line

    /// A mirrored notification from another app becomes a glass alert under the notch (see `AlertStack`).
    func showNotificationLine(_ line: NotchModel.NotificationLine) {
        postAlert(AlertItem(id: "\(line.id)", appID: line.app, appName: NotificationsController.shared.appName(line.app),
                            title: line.title, body: line.detail, priority: .normal, postedAt: now()))
    }

    /// `whileOpen` queues the alert even when the notch is open (a snoozed alert coming back must not be lost); it then
    /// shows, with its full time, when the notch closes.
    func postAlert(_ item: AlertItem, whileOpen: Bool = false) {
        guard whileOpen || model.presentation == .closed else { return }
        let result = model.alerts.post(item, now: now())
        if case .added = result {
            // Each alert is announced once, politely; a coalesced duplicate does not repeat it.
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: item.spokenText,
                .priority: NSAccessibilityPriorityLevel.low.rawValue,
            ])
        }
        alertsChanged()
    }

    func dismissNotificationLine() {
        model.alerts.clear()
        alertsChanged()
    }

    func dismissAlert(_ id: String) {
        model.alerts.dismiss(id: id, now: now())
        alertsChanged()
    }

    func openAlert(_ id: String) {
        guard let item = model.alerts.items.first(where: { $0.id == id }) else { return }
        openNotificationLine(.init(id: Int64(item.id) ?? 0, app: item.appID, title: item.title, detail: item.body))
        dismissAlert(id)
    }

    /// Opens the source app on a reply to the alert (a draft the owner sends). Without a reply URL, or when the
    /// app is not installed, it falls back to Open; the button is only shown when a URL exists.
    func replyAlert(_ id: String) {
        guard let item = model.alerts.items.first(where: { $0.id == id }) else { return }
        guard let url = AlertReply.url(for: item), AlertReplyLauncher.open(url, bundleID: item.appID) else {
            return openAlert(id)
        }
        dismissAlert(id)
    }

    /// Hides the alert and brings it back in ten minutes.
    func snoozeAlert(_ id: String) {
        guard let item = model.alerts.items.first(where: { $0.id == id }) else { return }
        dismissAlert(id)
        // One snooze per alert: snoozing it again replaces the pending return instead of doubling it.
        snoozeTasks[id]?.cancel()
        snoozeTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled, let self else { return }
            self.snoozeTasks[id] = nil
            var again = item
            again.postedAt = self.now()
            self.postAlert(again, whileOpen: true)
        }
    }

    func clickNotificationLine() {
        guard let front = model.alerts.visible.first else { return }
        openAlert(front.id)
    }

    func setAlertHovered(_ hovered: Bool) {
        model.alerts.setHovered(hovered, now: now())
        alertsChanged()
    }

    /// Re-arms the single wake-up for the next deadline. With nothing to expire there is no task at all.
    private func alertsChanged() {
        alertWake?.cancel()
        alertWake = nil
        if model.alerts.isEmpty {
            if model.presentation == .closed { setIgnoresMouse(true) }
            return
        }
        guard let deadline = model.alerts.nextDeadline() else { return }
        alertWake = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(self.now()))))
            guard !Task.isCancelled else { return }
            self.model.alerts.expire(now: self.now())
            self.alertsChanged()
        }
    }

    /// Where the line sits, in screen coordinates: centred under the notch.
    private func notificationLineRect(_ screen: NSScreen) -> CGRect {
        let top = screen.frame.maxY - topOffset - max(notchSize.height, 30) - 6
        // Room for the fanned stack and the hover actions, so the pointer stays on the capsule while it grows.
        let height = AlertCapsule.actionHeight + 24
        return CGRect(x: screen.frame.midX - AlertCapsule.width / 2, y: top - height, width: AlertCapsule.width, height: height)
    }

    // MARK: Keyboard agent picker

    /// The open-notch shortcut: the agent list with a highlighted row. Pressed again, it closes.
    func togglePicker() {
        if model.picker != nil { return closePicker() }
        model.completion = nil
        let index = model.sessions.firstIndex { $0.id == model.peekSessionID } ?? 0
        model.picker = AgentPicker(count: model.sessions.count, index: index)
        topBar?.selectedTab = .agents
        show(.panel)
        window?.makeKey()
    }

    func closePicker() {
        model.picker = nil
        show(model.approval != nil ? .peek : .closed)
        // Give the keyboard back: the panel must not stay key once it no longer takes keys.
        if let panel = window { panel.orderOut(nil); panel.orderFrontRegardless() }
    }

    /// Up, down, Return and Escape while the picker is open. Returns true when the key was used.
    func pickerKey(_ code: UInt16) -> Bool {
        guard var picker = model.picker, let action = AgentPicker.action(forKeyCode: code) else { return false }
        let result = picker.apply(action)
        model.picker = picker
        switch result {
        case .open?:
            if let session = model.pickedSession { AgentTerminals.shared.jump(to: session.id) }
            closePicker()
        case .close?:
            closePicker()
        default:
            break
        }
        return true
    }

    static func notchSize(of screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return .zero }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }
}

/// The notch panel never becomes key (so it never takes the keyboard from your app); its first
/// click must still press the tab or button under it, not just wake the window.
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// AppKit normally keeps windows below the menu bar; the notch window has to sit on top of it.
private final class NotchPanel: NSPanel {
    /// Typing only while a page that takes text (the to-do input) is open, so clicking the notch
    /// never steals the keyboard from the app you were in.
    @MainActor static var acceptsKeyboard: () -> Bool = { false }
    /// Arrow, Return and Escape keys for the agent picker; true when it used the key.
    @MainActor static var pickerKey: (UInt16) -> Bool = { _ in false }
    override var canBecomeKey: Bool { NotchPanel.acceptsKeyboard() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, NotchPanel.pickerKey(event.keyCode) { return }
        super.sendEvent(event)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
