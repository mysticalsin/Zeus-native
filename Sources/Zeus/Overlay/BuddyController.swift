import AppKit
import QuartzCore
import SwiftUI
import ZeusCore

/// Drives the spark: follows the cursor, flies to targets on a bezier arc, strikes, shows a
/// typed label, then flies home. One click-through window per screen; one display link.
@MainActor
final class BuddyController: NSObject {
    let model = BuddyModel()

    private var windows: [NSWindow] = []
    private var captionHide: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var mouseMonitors: [Any] = []

    /// When Zeus shows beside the pointer: "Only when I call him" by default (see `BuddyVisibility`).
    private var visibility = BuddyVisibility(policy: BuddyShow.stored(UserDefaults.standard.string(forKey: BuddyShow.defaultsKey)))
    private var hiddenForPanel = false
    private var recheck: Task<Void, Never>?
    private var callExpiry: Task<Void, Never>?
    private var shownAlpha: CGFloat = -1

    var showPolicy: BuddyShow {
        get { visibility.policy }
        set {
            guard newValue != visibility.policy else { return }
            visibility.policy = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: BuddyShow.defaultsKey)
            applyVisibility()
        }
    }

    private struct ActiveFlight {
        var curve: CompanionFlight
        var start: CFTimeInterval
        var returning: Bool
        var mouseAtStart: CGPoint
    }

    private struct Pointing {
        var target: CGPoint
        var label: CompanionPointingLabel
        var holdUntil: CFTimeInterval?
        var returnAt: CFTimeInterval?
    }

    private var flight: ActiveFlight?
    private var pointing: Pointing?
    private var strikeStart: CFTimeInterval?
    private var follow = CompanionSpring()
    private var ring = RingSession()
    private var landingTangent: CGPoint = .zero
    private var lastDisplays: [DisplayMap] = []

    func start() {
        BuddyControllerBridge.shared = self
        model.onModeChange = { [weak self] mode in self?.modeChanged(mode) }
        model.onCaptionChange = { [weak self] shown in
            guard let self else { return }
            if shown { self.visibility.begin(.caption) } else { self.visibility.end(.caption, at: Date()) }
            self.applyVisibility()
        }
        rebuildWindows()
        lastDisplays = presentMapper().displays
        let rest = followTarget()
        follow = CompanionSpring(position: rest, velocity: .zero)
        model.position = rest
        model.glow = CompanionFlight.glowRest
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        let link = (NSScreen.main ?? NSScreen.screens[0]).displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        // The frame loop sleeps once the spark has settled and wakes on the next mouse move,
        // so an idle Mac costs nothing (it used to redraw the overlay at display rate forever).
        let wake: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.wake() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged], handler: wake) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged], handler: { event in
            wake(event); return event
        }) {
            mouseMonitors.append(local)
        }
        let dismiss: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.clearRing() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: dismiss) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { event in
            dismiss(event); return event
        }) {
            mouseMonitors.append(local)
        }
        DispatchQueue.main.async { self.model.hasAppeared = true }
        applyVisibility(animated: false)
    }

    // MARK: Visibility

    /// Something called Zeus (the talk shortcut, "Hey Zeus"): he appears now, before the turn starts.
    /// If no turn follows, he leaves again after a few seconds.
    func call() {
        wake()
        visibility.begin(.call)
        applyVisibility()
        callExpiry?.cancel()
        callExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            self.visibility.end(.call, at: Date())
            self.applyVisibility()
        }
    }

    private func modeChanged(_ mode: BuddyModel.Mode) {
        let now = Date()
        switch mode {
        case .following:
            visibility.end(.turn, at: now)
            visibility.end(.pointing, at: now)
        case .listening, .thinking:
            visibility.begin(.turn)
            callExpiry?.cancel()
            visibility.end(.call, at: now)
        case .flying, .pointing, .returning:
            visibility.begin(.pointing)
        }
        applyVisibility()
    }

    private func applyVisibility(animated: Bool = true) {
        let now = Date()
        let target: CGFloat = (hiddenForPanel || !visibility.isVisible(at: now)) ? 0 : 1
        if target != shownAlpha {
            shownAlpha = target
            for window in windows where window.alphaValue != target {
                if animated, !Motion.reduced {
                    NSAnimationContext.runAnimationGroup({ $0.duration = target == 1 ? 0.2 : 0.35; window.animator().alphaValue = target }, completionHandler: nil)
                } else {
                    window.alphaValue = target
                }
            }
        }
        recheck?.cancel()
        if let next = visibility.nextChange(after: now) {
            recheck = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.05))
                guard !Task.isCancelled else { return }
                self?.applyVisibility()
            }
        }
    }

    // MARK: Commands

    private func wake() {
        guard let link = displayLink, link.isPaused else { return }
        lastTimestamp = 0
        link.isPaused = false
    }

    func listen() { wake(); resetPointing(); model.mode = .listening; AvatarStatus.shared.set(\.turn, .listening) }
    func think() { wake(); resetPointing(); model.mode = .thinking; AvatarStatus.shared.set(\.turn, .thinking) }
    func idle() { wake(); resetPointing(); model.mode = .following; AvatarStatus.shared.set(\.turn, .idle) }

    /// Shows `text` as a caption by the spark until `hideCaption` (or the next caption).
    func showCaption(_ text: String) {
        captionHide?.cancel()
        guard Preferences.shared.showCaptions else { return }
        model.caption = text
        model.captionVisible = true
    }

    /// Hides the caption after a reading delay that grows with its length.
    /// Glance never draws a companion over its open panel: fade the spark while the pointer
    /// is inside the notch panel, bring it back when the panel closes.
    func setHiddenForPanel(_ hidden: Bool) {
        hiddenForPanel = hidden
        applyVisibility()
    }

    func hideCaption() {
        captionHide?.cancel()
        let delay = min(max(Double(model.caption.count) * 0.06, 3), 10)
        captionHide = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.model.captionVisible = false
        }
    }

    private var pointingClickMonitor: Any?

    /// Fly to `point` (global AppKit coordinates) and ring it. An accessibility frame under the
    /// point wins over the raw coordinate. Decorative: this does not move the system pointer.
    func point(to point: CGPoint, label: String) {
        guard CompanionSpring.tracksPointer(showPolicy) else { return }
        wake()
        resetPointing()
        startPointingClickMonitor()
        AvatarStatus.shared.set(\.turn, .pointing)
        let mapper = presentMapper()
        if let display = mapper.display(containing: point),
           let snapshot = AXSnapshotter.shared.latest,
           let frame = ElementSnap.best(axFrames: snapshot.elements.map(\.frame), around: point, displayID: display.id, mapper: mapper),
           let plan = ShowMeWhere.plan(from: model.position, axFrame: frame, displayID: display.id, mapper: mapper, label: label, reducedMotion: Motion.reduced),
           let screenRect = mapper.convert(plan.ring.frame, from: .overlay, to: .screen, context: MapContext(displayID: display.id)) {
            launch(plan.flight, label: label, ring: screenRect)
            return
        }
        let target = clampedToScreen(point)
        let curve = CompanionFlight.plan(from: model.position, to: target, reducedMotion: Motion.reduced)
        launch(curve, label: label, ring: CGRect(x: target.x - 22, y: target.y - 22, width: 44, height: 44))
    }

    private func launch(_ curve: CompanionFlight, label: String, ring rect: CGRect) {
        flight = ActiveFlight(curve: curve, start: CACurrentMediaTime(), returning: false, mouseAtStart: NSEvent.mouseLocation)
        pointing = Pointing(target: curve.to,
                            label: CompanionPointingLabel(text: label, beganAt: 0, reduceMotion: Motion.reduced))
        model.ringFrame = rect
        self.ring.show(TargetRing(displayID: 0, center: CGPoint(x: rect.midX, y: rect.midY), frame: rect, label: label))
        model.mode = .flying
    }

    /// The next click or key removes the ring and sends the companion home.
    private func clearRing() {
        guard ring.clearOnUserInput() else { return }
        model.ringFrame = nil
        pointing = nil
        guard model.mode == .flying || model.mode == .pointing else { return }
        let now = CACurrentMediaTime()
        if model.mode == .flying, let current = flight {
            let curve = current.curve.retarget(to: followTarget(), at: now - current.start)
            flight = ActiveFlight(curve: curve, start: now, returning: true, mouseAtStart: NSEvent.mouseLocation)
            model.mode = .returning
            return
        }
        startReturn(now: now)
    }

    // MARK: Frame loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(now - lastTimestamp, 0.05)
        lastTimestamp = now

        switch model.mode {
        case .following, .listening, .thinking:
            guard CompanionSpring.tracksPointer(showPolicy) else {
                link.isPaused = true
                return
            }
            let k = 1 - exp(-dt * 28)
            let target = followTarget()
            follow = follow.stepped(toward: target, dt: dt, reducedMotion: Motion.reduced)
            let moving = hypot(target.x - model.position.x, target.y - model.position.y) > 0.25
            if moving || follow.position != model.position { model.position = follow.position }
            if abs(-15 - model.rotation) > 0.05 { model.rotation += (-15 - model.rotation) * k } else if model.rotation != -15 { model.rotation = -15 }
            if abs(1 - model.scale) > 0.001 { model.scale += (1 - model.scale) * k } else if model.scale != 1 { model.scale = 1 }
            if abs(model.glow - CompanionFlight.glowRest) > 0.05 { model.glow += (CompanionFlight.glowRest - model.glow) * k }
            if model.mode == .following, !moving, model.rotation == -15, model.scale == 1, strikeStart == nil {
                link.isPaused = true
            }

        case .flying, .returning:
            advanceFlight(now: now)

        case .pointing:
            advancePointing(now: now)
        }

        if let start = strikeStart {
            let progress = (now - start) / 0.35
            model.strikeProgress = min(progress, 1)
            if progress >= 1 { strikeStart = nil }
        }
    }

    private func advanceFlight(now: CFTimeInterval) {
        guard var current = flight else {
            model.mode = .following
            AvatarStatus.shared.set(\.turn, .idle)
            return
        }
        if current.returning {
            // Home moves with the mouse; a real mouse move cancels the trip back.
            current.curve.to = followTarget()
            let mouse = NSEvent.mouseLocation
            if hypot(mouse.x - current.mouseAtStart.x, mouse.y - current.mouseAtStart.y) > 100 {
                flight = nil
                follow.position = model.position
                follow.velocity = .zero
                model.mode = .following
                AvatarStatus.shared.set(\.turn, .idle)
                return
            }
            flight = current
        }

        let elapsed = now - current.start
        let sample = current.curve.sample(at: elapsed)
        model.position = sample.position
        let tangent = current.curve.tangent(at: elapsed)
        if hypot(tangent.x, tangent.y) > 0.01 { model.rotation = sample.rotation }
        model.scale = sample.scale
        model.glow = sample.glow

        guard sample.progress >= 1 else { return }
        landingTangent = current.curve.tangent(at: current.curve.duration)
        flight = nil
        follow.position = model.position
        follow.velocity = .zero
        if current.returning {
            model.mode = .following
            AvatarStatus.shared.set(\.turn, .idle)
        } else {
            arrive(now: now)
        }
    }

    private func arrive(now: CFTimeInterval) {
        model.mode = .pointing
        model.scale = 1
        model.strikeCenter = model.position
        if !Motion.reduced {
            model.strikeProgress = 0
            strikeStart = now
        }
        if var state = pointing {
            state.label = CompanionPointingLabel(text: state.label.text, beganAt: now, reduceMotion: Motion.reduced)
            model.bubbleText = state.label.visibleText
            if state.label.isComplete { state.holdUntil = now + 3 }
            pointing = state
        }
        model.bubbleVisible = true
    }

    private func advancePointing(now: CFTimeInterval) {
        guard var state = pointing else {
            model.mode = .following
            AvatarStatus.shared.set(\.turn, .idle)
            return
        }
        model.position = state.target

        if !state.label.isComplete {
            state.label.advance(at: now, reduceMotion: Motion.reduced, characterDelay: Double.random(in: 0.03...0.06))
            model.bubbleText = state.label.visibleText
        }
        if state.label.isComplete, state.holdUntil == nil {
            state.holdUntil = now + 3
        } else if let hold = state.holdUntil, now >= hold, state.returnAt == nil {
            model.bubbleVisible = false
            state.returnAt = now + 0.5
        } else if let returnAt = state.returnAt, now >= returnAt {
            pointing = nil
            startReturn(now: now)
            return
        }
        pointing = state
    }

    private func startReturn(now: CFTimeInterval) {
        let home = followTarget()
        let curve = CompanionFlight.plan(from: model.position, to: home, departureTangent: landingTangent, reducedMotion: Motion.reduced)
        flight = ActiveFlight(curve: curve, start: now, returning: true, mouseAtStart: NSEvent.mouseLocation)
        model.mode = .returning
    }

    private func resetPointing() {
        stopPointingClickMonitor()
        flight = nil
        pointing = nil
        model.bubbleVisible = false
        model.ringFrame = nil
        ring.clearOnUserInput()
    }

    private func startPointingClickMonitor() {
        stopPointingClickMonitor()
        pointingClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.mode == .pointing else { return }
                self.idle()
            }
        }
    }

    private func stopPointingClickMonitor() {
        if let pointingClickMonitor { NSEvent.removeMonitor(pointingClickMonitor) }
        pointingClickMonitor = nil
    }

    // MARK: Geometry

    private func followTarget() -> CGPoint {
        CompanionSpring.rest(near: NSEvent.mouseLocation)
    }

    private func clampedToScreen(_ point: CGPoint) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame.insetBy(dx: 20, dy: 20)
        return CGPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }

    private func presentMapper() -> ScreenCoordinateMapper {
        let displays: [DisplayMap] = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return DisplayMap(id: Int(id), frame: screen.frame, scale: Double(screen.backingScaleFactor))
        }
        let mainID = NSScreen.main?.displayID.map { Int($0) }
        return ScreenCoordinateMapper(displays: displays, mainDisplayID: mainID)
    }

    // MARK: Windows

    @objc private func screensChanged() {
        let next = presentMapper().displays
        if flight != nil || pointing != nil {
            let geometry = CompanionPointingGeometry(flight: flight?.curve, target: pointing?.target,
                position: model.position, ringFrame: model.ringFrame, strikeCenter: model.strikeCenter)
            if let moved = geometry.rebased(from: lastDisplays, to: next) {
                if let curve = moved.flight { flight?.curve = curve }
                if let target = moved.target { pointing?.target = target }
                model.position = moved.position
                model.ringFrame = moved.ringFrame
                model.strikeCenter = moved.strikeCenter
                follow.position = moved.position
            } else {
                resetPointing()
                strikeStart = nil
                model.strikeProgress = 1
                follow = CompanionSpring(position: followTarget(), velocity: .zero)
                model.position = follow.position
                model.mode = .following
                AvatarStatus.shared.set(\.turn, .idle)
            }
            wake()
        }
        lastDisplays = next
        rebuildWindows()
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        let visible = lastVisibleInShare
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: BuddyOverlayView(model: model, screenFrame: screen.frame))
            window.setFrame(screen.frame, display: false)
            window.alphaValue = shownAlpha == 0 ? 0 : 1
            ZeusWindowSharing.apply(to: window, visibleInShare: visible, surface: .zeusStandard)
            window.orderFrontRegardless()
            return window
        }
    }

    private var lastVisibleInShare = false

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        for window in windows {
            ZeusWindowSharing.apply(to: window, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }
}
