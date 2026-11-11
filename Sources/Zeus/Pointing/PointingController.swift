import AppKit
import ZeusCore

struct PointingDisplay: Equatable, Sendable {
    var id: UInt32
    /// AppKit global points.
    var frame: CGRect
    var scale: Double

    @MainActor static func live() -> [PointingDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return PointingDisplay(id: id, frame: screen.frame, scale: Double(screen.backingScaleFactor))
        }
    }
}

enum PointingNotice: Equatable {
    case hint(String)
    /// `pane` is the System Settings privacy pane the owner opens themselves.
    case permission(String, pane: String)
}

/// Timers are system callbacks too: this one is created in nonisolated code and only hops to the
/// main actor, so no closure written inside a `@MainActor` type is ever called by the system.
enum PointingTimers {
    /// A real-time wait that is not `Task.sleep`: used only by the self-test to poll for events.
    nonisolated static func wait(_ seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    nonisolated static func repeating(every interval: TimeInterval,
                                      _ tick: @escaping @MainActor @Sendable () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

/// Orchestrates one pointing session: hold the keys, speak, release, hear the answer and see a ring
/// on the control. Everything external is a seam so the self-test and the unit tests drive the same
/// code the real hotkey drives.
@MainActor
final class PointingController {
    struct Services {
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }
        var displays: () -> [PointingDisplay] = { PointingDisplay.live() }
        /// Preflight only. Pointing never requests Screen Recording.
        var hasScreenPermission: () -> Bool = { CGPreflightScreenCaptureAccess() }
        var frontmostBundleID: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        /// AX element under a Quartz global point. Runs off the main actor.
        var probe: @Sendable (CGPoint) async -> PointingRawTarget? = { point in
            await Task.detached(priority: .userInitiated) { PointingTargetProbe.hitTest(atQuartzPoint: point) }.value
        }
        var enabled: () -> Bool = { PointingSettings.enabled }
        var sendScreenshot: () -> Bool = { PointingSettings.sendScreenshot }
    }

    /// Speech input. Live: the explanation microphone. The self-test injects a fixed transcript.
    struct Inputs {
        var begin: @MainActor () -> UUID?
        var finish: @MainActor (UUID) -> Void
        var cancel: @MainActor (UUID) -> Void
    }

    /// The companion marker. Flight starts only on real first audio.
    struct Marker {
        var listen: @MainActor () -> Void
        var think: @MainActor () -> Void
        var idle: @MainActor () -> Void
        /// Returns true when a flight started (false when the companion is hidden).
        var flight: @MainActor (CGPoint, String) -> Bool
    }

    struct Metrics: Equatable {
        var turns = 0
        var captureAttempts = 0
        var requestsSent = 0
        var releaseAt: TimeInterval?
        var firstAudioAt: TimeInterval?
        var flightStartAt: TimeInterval?
        var flightUsedFallback = false
        var stopLatency: TimeInterval?
        var droppedSamples = 0
        var lastFailure: String?
        var flightLagMilliseconds: Double? {
            guard let firstAudioAt, let flightStartAt else { return nil }
            return (flightStartAt - firstAudioAt) * 1000
        }
    }

    let explanation: ExplanationController
    let hotkey = PointingHotkeyMonitor()
    private(set) var session = PointingSession()
    private(set) var metrics = Metrics()
    private(set) var trace = PointingTrace()
    private(set) var candidatesForTest: [PointingTargetCandidate] = []
    var onNotice: ((PointingNotice) -> Void)?

    private let services: Services
    private let inputs: Inputs
    private let marker: Marker
    private let prepare: () async -> [PointingProviderPath]
    private let recordAudio: (Double) -> Void
    private var attempt: UUID?
    private var prepareTask: Task<[PointingProviderPath], Never>?
    private var captureTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var sampler: Timer?
    private var dwellProbes: [Task<(CGPoint, PointingRawTarget?), Never>] = []
    private var inkOwner = false
    private var previousMouseHandler: ((NSEvent.EventType, CGPoint) -> Void)?
    private var strokeCount = 0
    private var flightLaunched = false
    private var screenNoticeShown = false

    init(explanation: ExplanationController, services: Services = Services(), inputs: Inputs? = nil, marker: Marker,
         prepare: @escaping () async -> [PointingProviderPath], recordAudio: @escaping (Double) -> Void = { _ in }) {
        self.explanation = explanation; self.services = services; self.marker = marker
        self.prepare = prepare; self.recordAudio = recordAudio
        self.inputs = inputs ?? Inputs(
            begin: { [weak explanation] in explanation?.beginListening() },
            finish: { [weak explanation] in explanation?.finishListening(attemptID: $0) },
            cancel: { [weak explanation] in explanation?.cancelListening(attemptID: $0) })
        explanation.overlayLevel = .screenSaver // above open menus
        explanation.onSpeechStart = { [weak self] in self?.speechStarted() }
        explanation.onReveal = { [weak self] scene in self?.revealed(scene, fallback: false) }
        explanation.onTurnEnded = { [weak self] error in self?.turnEnded(error) }
        explanation.onEmptyInput = { [weak self] in self?.emptyInput() }
        hotkey.onSignal = { [weak self] signal in self?.handle(signal) }
    }

    var state: PointingSession.State { session.state }
    /// Anything still running that should not be once the session is idle. Empty means clean.
    var leaks: [String] {
        var found: [String] = []
        if sampler != nil { found.append("sampler timer") }
        if inkOwner || MarkOverlay.shared.capturesMouse { found.append("ink overlay") }
        if prepareTask != nil || captureTask != nil || work != nil { found.append("pending task") }
        if !dwellProbes.isEmpty { found.append("dwell probe") }
        if explanation.screenContext.isCapturing { found.append("capture in flight") }
        if explanation.overlayVisible { found.append("annotation overlay") }
        if explanation.microphone.state != .idle { found.append("microphone") }
        return found
    }
    var isEnabled: Bool { services.enabled() }

    func start() { guard services.enabled() else { return }; hotkey.start() }
    func stop() {
        hotkey.stop()
        halt(clearScreen: true)
        _ = session.send(.failure("stopped")); _ = session.send(.cleanedUp)
    }

    // MARK: Signals (the real monitor and the self-test both call this)

    func handle(_ signal: PointingHotkeyMonitor.Signal) {
        switch signal {
        case .began: begin()
        case .ended: end()
        case .cancelled: cancelHold()
        case .escape: interrupt()
        case .doubleTapControl: break // Detected; text entry arrives in a later phase.
        case .blocked(let message): onNotice?(.hint(message))
        }
    }

    // MARK: Hold

    private func begin() {
        guard services.enabled() else { return }
        // Another owner (show-me) already has the screen overlay: never arm both at once.
        if MarkOverlay.shared.capturesMouse, !inkOwner { return }
        let transition = session.send(.keyDown)
        guard transition.changed else { return } // A second hold while holding is a no-op.
        let generation = session.generation
        ExplanationAudioArbitration.yieldToNewCapture()
        // Barge-in: a new hold during processing or speech stops speech and pending animation first.
        if transition.effects.contains(.stopOutput) {
            let began = services.now()
            halt(clearScreen: true)
            explanation.stop()
            metrics.stopLatency = services.now() - began
            marker.idle()
        }
        explanation.prepareDesktopSession()
        explanation.desktopTurn = nil
        explanation.screenContext.clear()
        cancelTasks()
        trace = PointingTrace(); candidatesForTest = []; strokeCount = 0
        metrics.releaseAt = nil; metrics.firstAudioAt = nil; metrics.flightStartAt = nil
        metrics.flightUsedFallback = false; metrics.stopLatency = nil; metrics.lastFailure = nil
        flightLaunched = false
        guard let id = inputs.begin() else {
            fail("The microphone is busy. Try again in a moment.")
            return
        }
        attempt = id
        marker.listen()
        startInk()
        startSampling()
        prepareTask = Task { [prepare] in await prepare() }
        captureTask = Task { [weak self] in await self?.captureAtPointer(generation: generation) }
    }

    private func end() {
        let transition = session.send(.keyUp)
        guard transition.to == .processing, transition.from != .processing else { return }
        let generation = session.generation
        metrics.releaseAt = services.now()
        stopSampling(); stopInk()
        marker.think()
        let id = attempt
        work = Task { [weak self] in await self?.finishTurn(generation: generation, attempt: id) }
    }

    private func cancelHold() {
        let transition = session.send(.spoiled)
        guard transition.changed else { return }
        halt(clearScreen: true)
        if let id = attempt { inputs.cancel(id) }
        attempt = nil
        marker.idle()
        _ = session.send(.cleanedUp)
    }

    /// Esc, or a stop request, while a turn is processing or speaking.
    func interrupt() {
        let transition = session.send(.escape)
        guard transition.changed else { return }
        let began = services.now()
        halt(clearScreen: false)
        explanation.stop()
        metrics.stopLatency = services.now() - began
        explanation.screenContext.cancel()
        marker.idle()
        _ = session.send(.cleanedUp)
    }

    private func fail(_ message: String) {
        let transition = session.send(.failure(message))
        guard transition.changed else { return }
        metrics.lastFailure = message
        halt(clearScreen: true)
        if let id = attempt { inputs.cancel(id) }
        attempt = nil
        explanation.stop()
        marker.idle()
        onNotice?(.hint(message))
        _ = session.send(.cleanedUp)
    }

    private func halt(clearScreen: Bool) {
        stopSampling(); stopInk(); cancelTasks()
        explanation.desktopTurn = nil
        if clearScreen { explanation.screenContext.cancel(); explanation.screenContext.clear() }
    }

    private func cancelTasks() {
        prepareTask?.cancel(); prepareTask = nil
        captureTask?.cancel(); captureTask = nil
        work?.cancel(); work = nil
        for probe in dwellProbes { probe.cancel() }
        dwellProbes = []
    }

    // MARK: Capture and context

    private func displayUnderPointer() -> PointingDisplay? {
        let point = services.mouseLocation()
        return services.displays().first { $0.frame.contains(point) }
    }

    /// One event-driven capture, only when the owner already granted Screen Recording.
    private func captureAtPointer(generation: Int) async {
        guard services.hasScreenPermission() else {
            if !screenNoticeShown {
                screenNoticeShown = true
                onNotice?(.permission("Zeus needs Screen Recording to point at things on your screen. Turn it on in System Settings, then hold the keys again. Pointing still works from what is under your pointer.",
                                      pane: "Privacy_ScreenCapture"))
            }
            return
        }
        screenNoticeShown = false
        guard session.isCurrent(generation) || session.state == .processing, let display = displayUnderPointer() else { return }
        metrics.captureAttempts += 1
        do {
            _ = try await explanation.screenContext.captureSelectedDisplay(display.id, lease: .renewing(max: 120))
        } catch ExplanationScreenContextFailure.permissionRequired {
            onNotice?(.permission("Screen Recording was turned off. Turn it on in System Settings and try again.", pane: "Privacy_ScreenCapture"))
        } catch {
            // Cancelled, busy or unavailable: the turn continues without a screenshot.
        }
    }

    private func finishTurn(generation: Int, attempt id: UUID?) async {
        let order = await prepareTask?.value ?? []
        guard session.isCurrent(generation) else { return }
        guard !order.isEmpty else {
            fail("Add an Anthropic, OpenAI or Any LLM key in Settings to use pointing.")
            return
        }
        await captureTask?.value
        guard session.isCurrent(generation) else { return }
        // A change during the hold dropped the lease: take one more capture, once.
        let screen = explanation.screenContext
        if services.hasScreenPermission(), screen.annotationContext == nil, !screen.isCapturing {
            await captureAtPointer(generation: generation)
            guard session.isCurrent(generation) else { return }
        }
        let turn = await buildTurn()
        guard session.isCurrent(generation), let id else { return }
        explanation.desktopTurn = turn
        metrics.turns += 1; metrics.requestsSent += 1
        metrics.droppedSamples = trace.droppedSamples
        inputs.finish(id)
    }

    func buildTurn() async -> ExplanationController.PointingTurn {
        let screen = explanation.screenContext
        let capture = screen.annotationContext
        let snapshot = screen.snapshot.flatMap { $0.geometry.captureID == capture?.geometry.captureID ? $0 : nil }
        let displays = services.displays()
        let mapper = ScreenCoordinateMapper(displays: displays.map { DisplayMap(id: Int($0.id), frame: $0.frame, scale: $0.scale) })
        let release = services.mouseLocation()

        var points: [(CGPoint, PointingTargetCandidate.Source)] = []
        if let first = trace.samples.first { points.append((CGPoint(x: first.x, y: first.y), .axHitTest)) }
        for dwell in trace.dwells.prefix(3) { points.append((CGPoint(x: dwell.at.x, y: dwell.at.y), .axDwell)) }
        points.append((release, .axHitTest))

        let probe = services.probe
        let raws: [PointingRawTarget?] = await withTaskGroup(of: (Int, PointingRawTarget?).self) { group in
            for (index, entry) in points.enumerated() {
                guard let quartz = mapper.convert(entry.0, from: .screen, to: .ax, context: MapContext()) else { continue }
                group.addTask { (index, await probe(quartz)) }
            }
            var out = [PointingRawTarget?](repeating: nil, count: points.count)
            for await (index, raw) in group { out[index] = raw }
            return out
        }

        var candidates: [PointingTargetCandidate] = []
        func add(_ candidate: PointingTargetCandidate) {
            guard candidates.count < PointingContext.maxCandidates,
                  !candidates.contains(where: { $0.role == candidate.role && $0.label == candidate.label && $0.imageRect == candidate.imageRect })
            else { return }
            candidates.append(candidate)
        }
        for (index, raw) in raws.enumerated() {
            guard let raw else { continue }
            let rect = capture.flatMap {
                PointingGeometry.imageRect(fromAX: raw.axFrame, mapper: mapper, geometry: $0.geometry, display: $0.currentDisplay)
            }
            add(PointingTargetCandidate(id: "t\(candidates.count)", role: raw.role, subrole: raw.subrole, label: raw.label,
                                        imageRect: rect, isSecure: raw.isSecure, source: points[index].1))
        }
        // Apps with no Accessibility tree (canvas, games): a small pointer-centered target still lets
        // the model ring what the user pointed at.
        if let capture, !candidates.contains(where: { $0.source != .pointerOnly && $0.imageRect != nil }),
           let center = capture.geometry.imagePoint(fromGlobal: .init(x: release.x, y: release.y), current: capture.currentDisplay) {
            let size = capture.geometry.imageSize
            let half = 24.0
            let x = max(0, min(size.width - 2 * half, center.x - half)), y = max(0, min(size.height - 2 * half, center.y - half))
            add(PointingTargetCandidate(id: "t\(candidates.count)", role: "pointer", imageRect: .init(x: x, y: y, width: 2 * half, height: 2 * half),
                                        source: .pointerOnly))
        }
        candidatesForTest = candidates
        let context = PointingContext.make(trace: trace, candidates: candidates, geometry: capture?.geometry,
                                           display: capture?.currentDisplay, frontmostBundleID: services.frontmostBundleID())
        return .init(context: context, snapshot: services.sendScreenshot() ? snapshot : nil)
    }

    // MARK: Pointer samples and ink

    private func startSampling() {
        stopSampling()
        sampler = PointingTimers.repeating(every: 1.0 / 30) { [weak self] in self?.sample() }
    }

    private func stopSampling() { sampler?.invalidate(); sampler = nil }

    /// Also the injection point for the self-test: it feeds synthetic pointer positions here.
    func sample(at point: CGPoint? = nil) {
        guard session.state == .listening || session.state == .drawing else { return }
        let location = point ?? services.mouseLocation()
        let display = services.displays().first { $0.frame.contains(location) }?.id ?? 0
        trace.add(PointerSample(time: services.now(), x: location.x, y: location.y, displayID: display))
    }

    private func startInk() {
        guard !MarkOverlay.shared.capturesMouse else { return }
        inkOwner = true
        previousMouseHandler = MarkOverlay.shared.onMouse
        MarkModel.shared.strokes = []
        MarkOverlay.shared.onMouse = { [weak self] type, point in self?.ink(type, point) }
        // While the keys are held, drags are ink and clicks do not reach apps. Release restores both.
        MarkOverlay.shared.show(capturingMouse: true)
    }

    private func stopInk() {
        guard inkOwner else { return }
        inkOwner = false
        MarkOverlay.shared.hide()
        MarkOverlay.shared.onMouse = previousMouseHandler
        previousMouseHandler = nil
        MarkModel.shared.strokes = []
    }

    /// Mouse input on the overlay. Also the injection point for the self-test.
    func ink(_ type: NSEvent.EventType, _ point: CGPoint) {
        switch type {
        case .leftMouseDown:
            guard session.send(.strokeBegan).changed else { return }
            trace.beginStroke(id: "s\(strokeCount)"); strokeCount += 1
            MarkModel.shared.strokes.append([point])
            sample(at: point)
        case .leftMouseDragged:
            guard trace.isDrawing else { return }
            sample(at: point)
            if !MarkModel.shared.strokes.isEmpty { MarkModel.shared.strokes[MarkModel.shared.strokes.count - 1].append(point) }
        case .leftMouseUp:
            guard trace.isDrawing else { return }
            sample(at: point)
            trace.endStroke()
            _ = session.send(.strokeEnded)
        default: break
        }
    }

    // MARK: Turn hooks

    private func speechStarted() {
        guard session.state == .processing else { return }
        _ = session.send(.firstPlaybackStart)
        metrics.firstAudioAt = services.now()
        if let release = metrics.releaseAt { recordAudio(services.now() - release) }
    }

    /// The flight starts when a ring is admitted by real playback, which is never before first audio.
    private func revealed(_ scene: ExplanationScene, fallback: Bool) {
        guard !flightLaunched, let capture = explanation.screenContext.annotationContext else { return }
        let marks = scene.objects.values.filter { $0.space == .capture && $0.captureID == capture.geometry.captureID }
        guard let ring = marks.filter({ $0.geometry.kind == .ring }).min(by: { $0.id < $1.id }),
              let global = capture.geometry.globalPoint(fromImage: .init(x: ring.transform.position.x, y: ring.transform.position.y),
                                                        current: capture.currentDisplay) else { return }
        let text = marks.filter { $0.geometry.kind == .label }.min(by: { $0.id < $1.id })?.text ?? "Here"
        if marker.flight(CGPoint(x: global.x, y: global.y), String(text.prefix(40))) {
            flightLaunched = true
            metrics.flightStartAt = services.now()
            metrics.flightUsedFallback = fallback
        }
    }

    private func turnEnded(_ error: Error?) {
        if let error {
            _ = error
            fail(explanation.problem ?? "The pointing answer could not be completed.")
            return
        }
        // Speech finished (or captions only). If the flight never left, send it now.
        if !flightLaunched, let scene = explanation.scene { revealed(scene, fallback: true) }
        if !flightLaunched { marker.idle() }
        _ = session.send(.turnCompleted)
    }

    private func emptyInput() {
        guard session.state == .processing || session.state == .listening else { return }
        let reason = explanation.problem
        _ = session.send(.emptyTranscript)
        halt(clearScreen: true)
        attempt = nil
        marker.idle()
        if let reason { onNotice?(.hint(reason)) }
        _ = session.send(.cleanedUp)
    }
}
