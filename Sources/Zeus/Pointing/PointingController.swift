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
    @MainActor struct Services {
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }
        var displays: () -> [PointingDisplay] = { PointingDisplay.live() }
        /// Preflight only. Pointing never requests Screen Recording.
        var hasScreenPermission: () -> Bool = { CGPreflightScreenCaptureAccess() }
        var frontmostBundleID: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        /// AX element under a Quartz global point. Hops to the main actor: AX calls never run off it.
        var probe: @Sendable (CGPoint) async -> PointingRawTarget? = { point in
            await MainActor.run { PointingTargetProbe.hitTest(atQuartzPoint: point) }
        }
        /// The focused text input's Quartz frame, for the explanation card. Runs off the main actor.
        var focusedInput: @Sendable () async -> CGRect? = {
            await Task.detached(priority: .userInitiated) { PointingTargetProbe.focusedInputFrame() }.value
        }
        var enabled: () -> Bool = { PointingSettings.enabled }
        var sendScreenshot: () -> Bool = { PointingSettings.sendScreenshot }
        var drawWhileHeld: () -> Bool = { PointingSettings.drawWhileHeld }
        var textEntryEnabled: () -> Bool = { PointingSettings.textEntry }
        /// One `[ZEUS] pointing-trace` line per turn. Offsets only; never text or image data.
        var log: (String) -> Void = { line in NSLog("%@", line) }
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
        var spans = PointingTraceSpans()
        var flightLagMilliseconds: Double? {
            guard let firstAudioAt, let flightStartAt else { return nil }
            return (flightStartAt - firstAudioAt) * 1000
        }
    }

    let explanation: ExplanationController
    let hotkey = PointingHotkeyMonitor()
    let textEntry = PointingTextEntry()
    let watcher = PointingTargetWatcher()
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
    private var strokeCount = 0
    private var flightLaunched = false
    private var screenNoticeShown = false
    private var stale: PointingStaleTarget?
    private var watchedQuartzPoint: CGPoint?
    private var staleWork: Task<Void, Never>?
    private var inkTrail = PointingInkTrail()
    private var traceEmitted = true
    private var systemObservers: [NSObjectProtocol] = []

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
        textEntry.onSubmit = { [weak self] text in self?.submitText(text) }
        explanation.onTranscriptFinal = { [weak self] in self?.mark(.transcriptFinal) }
        explanation.onRequestSent = { [weak self] in self?.mark(.requestSent) }
        explanation.onFirstValidBeat = { [weak self] in self?.mark(.firstValidBeat) }
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

    func start() { guard services.enabled() else { return }; hotkey.start(); installSystemObservers() }
    func stop() {
        hotkey.stop()
        removeSystemObservers()
        textEntry.hide()
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
        case .doubleTapControl: openTextEntry()
        case .timedOut:
            onNotice?(.hint("The keys never reported being released, so Zeus sent what it heard."))
            end(event: .holdTimedOut)
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
        textEntry.hide(); stopWatching()
        trace = PointingTrace(); candidatesForTest = []; strokeCount = 0
        metrics.releaseAt = nil; metrics.firstAudioAt = nil; metrics.flightStartAt = nil
        metrics.flightUsedFallback = false; metrics.stopLatency = nil; metrics.lastFailure = nil
        flightLaunched = false
        beginSpans()
        guard let id = inputs.begin() else {
            fail("The microphone is busy. Try again in a moment.")
            return
        }
        attempt = id
        marker.listen()
        if services.drawWhileHeld() { startInk() }
        startSampling()
        prepareTask = Task { [prepare] in await prepare() }
        captureTask = Task { [weak self] in await self?.captureAtPointer(generation: generation) }
    }

    private func end(event: PointingSession.Event = .keyUp) {
        endInkStroke()
        let transition = session.send(event)
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
        finishCancel(.cancelled)
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
        finishCancel(.interrupted)
        _ = session.send(.cleanedUp)
    }

    /// Sleep, wake or a display change. A hold in progress is dropped without a request; a turn in
    /// flight is stopped; marks are hidden because the capture geometry is no longer valid.
    func systemInterrupt(_ event: PointingSession.Event) {
        let transition = session.send(event)
        hotkey.interruptGesture()
        textEntry.hide()
        guard transition.changed else {
            if event == .displaysChanged { stopWatching(); hideMarks() }
            return
        }
        halt(clearScreen: true)
        if transition.effects.contains(.stopOutput) { explanation.stop() }
        if let id = attempt { inputs.cancel(id) }
        attempt = nil
        marker.idle()
        finishCancel(transition.to == .interrupted ? .interrupted : .cancelled)
        _ = session.send(.cleanedUp)
    }

    private func installSystemObservers() {
        guard systemObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        systemObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemInterrupt(.systemSleep) }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemInterrupt(.systemWake) }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemInterrupt(.displaysChanged) }
            },
        ]
    }

    private func removeSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in systemObservers {
            workspace.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        systemObservers = []
    }

    // MARK: Trace spans

    private func mark(_ mark: PointingTraceSpans.Mark) { metrics.spans.mark(mark, at: services.now()) }

    private func beginSpans() {
        metrics.spans = PointingTraceSpans(); traceEmitted = false
        mark(.keyDown)
    }

    private func emitTrace(_ outcome: PointingTraceSpans.Outcome) {
        guard !traceEmitted, !metrics.spans.isEmpty else { return }
        traceEmitted = true
        services.log(metrics.spans.line(outcome: outcome))
    }

    /// A cancelled or interrupted turn is finished once its work is stopped.
    private func finishCancel(_ outcome: PointingTraceSpans.Outcome) {
        mark(.cancelComplete)
        emitTrace(outcome)
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
        emitTrace(.failed)
        _ = session.send(.cleanedUp)
    }

    private func halt(clearScreen: Bool) {
        stopSampling(); stopInk(); cancelTasks(); stopWatching()
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
            mark(.screenshotReady)
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

        // Every probed point with where it came from and when (seconds from the first sample).
        let origin = trace.samples.first?.time ?? 0
        var points: [(point: CGPoint, source: PointingTargetCandidate.Source, time: Double)] = []
        if let first = trace.samples.first { points.append((CGPoint(x: first.x, y: first.y), .axHitTest, 0)) }
        for dwell in trace.dwells.prefix(3) {
            points.append((CGPoint(x: dwell.at.x, y: dwell.at.y), .axDwell, max(0, dwell.at.time - origin)))
        }
        points.append((release, .axHitTest, max(0, (trace.samples.last?.time ?? origin) - origin)))

        let probe = services.probe
        let raws: [PointingRawTarget?] = await withTaskGroup(of: (Int, PointingRawTarget?).self) { group in
            for (index, entry) in points.enumerated() {
                guard let quartz = mapper.convert(entry.point, from: .screen, to: .ax, context: MapContext()) else { continue }
                group.addTask { (index, await probe(quartz)) }
            }
            var out = [PointingRawTarget?](repeating: nil, count: points.count)
            for await (index, raw) in group { out[index] = raw }
            return out
        }

        var candidates: [PointingTargetCandidate] = []
        /// The id of `candidate`, or of the identical one already listed. nil when the list is full.
        func add(_ candidate: PointingTargetCandidate) -> String? {
            if let same = candidates.first(where: { $0.role == candidate.role && $0.label == candidate.label && $0.imageRect == candidate.imageRect }) {
                return same.id
            }
            guard candidates.count < PointingContext.maxCandidates else { return nil }
            candidates.append(candidate)
            return candidate.id
        }
        var evidence: [PointingDeixis.Evidence] = []
        for (index, raw) in raws.enumerated() {
            guard let raw else { continue }
            let rect = capture.flatMap {
                PointingGeometry.imageRect(fromAX: raw.axFrame, mapper: mapper, geometry: $0.geometry, display: $0.currentDisplay)
            }
            let id = add(PointingTargetCandidate(id: "t\(candidates.count)", role: raw.role, subrole: raw.subrole, label: raw.label,
                                                 imageRect: rect, isSecure: raw.isSecure, source: points[index].source))
            if let id, !raw.isSecure { evidence.append(.init(time: points[index].time, candidateID: id)) }
        }
        // Drawn strokes: the best element a stroke circles or underlines, else the region it encloses.
        if let capture {
            let strokes = PointingContext.imageStrokes(trace: trace, geometry: capture.geometry, display: capture.currentDisplay)
            let resolution = PointingStrokeTargeting.resolve(strokes: strokes, candidates: candidates,
                                                             imageSize: capture.geometry.imageSize)
            candidates = resolution.candidates
            for stroke in strokes {
                if let id = resolution.assignments[stroke.id] { evidence.append(.init(time: stroke.time, candidateID: id)) }
            }
        }
        // Apps with no Accessibility tree (canvas, games): a small pointer-centered target still lets
        // the model ring what the user pointed at.
        if let capture, !candidates.contains(where: { $0.source != .pointerOnly && $0.imageRect != nil }),
           let center = capture.geometry.imagePoint(fromGlobal: .init(x: release.x, y: release.y), current: capture.currentDisplay) {
            let size = capture.geometry.imageSize
            let half = 24.0
            let x = max(0, min(size.width - 2 * half, center.x - half)), y = max(0, min(size.height - 2 * half, center.y - half))
            if let id = add(PointingTargetCandidate(id: "t\(candidates.count)", role: "pointer",
                                                    imageRect: .init(x: x, y: y, width: 2 * half, height: 2 * half),
                                                    source: .pointerOnly)) {
                evidence.append(.init(time: points.last?.time ?? 0, candidateID: id))
            }
        }
        candidatesForTest = candidates
        let context = PointingContext.make(trace: trace, candidates: candidates, geometry: capture?.geometry,
                                           display: capture?.currentDisplay, frontmostBundleID: services.frontmostBundleID())
        // The words are not known yet (speech is transcribed after release). `submit()` runs this on them.
        let known = Set(candidates.map(\.id)), seen = evidence
        let resolver: @Sendable (String) -> [PointingContext.Deixis] = { transcript in
            PointingDeixis.resolve(words: PointingDeixis.words(in: transcript), evidence: seen, validIDs: known)
        }
        let inputFrame = await services.focusedInput()
        let inputArea = inputFrame.flatMap { mapper.convert($0, from: .ax, to: .screen, context: MapContext()) }
        return .init(context: context, snapshot: services.sendScreenshot() ? snapshot : nil,
                     displayID: capture?.currentDisplay.displayID ?? displays.first(where: { $0.frame.contains(release) })?.id,
                     inputArea: inputArea, pointer: release, resolveDeixis: resolver)
    }

    // MARK: Pointer samples and ink

    private func startSampling() {
        stopSampling()
        sampler = PointingTimers.repeating(every: 1.0 / 30) { [weak self] in self?.sample() }
    }

    private func stopSampling() { sampler?.invalidate(); sampler = nil }

    /// One pointer reading while the keys are held. Also the injection point for the self-test.
    /// The pointer path itself is the ink: hovering draws, a pause starts a new shape, and nothing
    /// here takes the mouse, so clicks and focus stay with the app underneath.
    func sample(at point: CGPoint? = nil) {
        guard session.state == .listening || session.state == .drawing else { return }
        if metrics.spans.times[.firstMic] == nil, explanation.microphone.state == .listening { mark(.firstMic) }
        let location = point ?? services.mouseLocation()
        let now = services.now()
        let display = services.displays().first { $0.frame.contains(location) }?.id ?? 0
        let step = inkTrail.add(location, at: now)
        if step == .began {
            endTraceStroke()
            trace.beginStroke(id: "s\(strokeCount)"); strokeCount += 1
            _ = session.send(.strokeBegan)
        }
        trace.add(PointerSample(time: now, x: location.x, y: location.y, displayID: display))
        if step != .dropped, inkOwner { MarkModel.shared.strokes = inkTrail.smoothed }
    }

    private func endTraceStroke() {
        guard trace.isDrawing else { return }
        trace.endStroke()
        _ = session.send(.strokeEnded)
    }

    private func endInkStroke() {
        inkTrail.endStroke()
        endTraceStroke()
    }

    private func startInk() {
        guard !MarkOverlay.shared.capturesMouse else { return }
        inkOwner = true
        inkTrail = PointingInkTrail()
        MarkModel.shared.strokes = []
        MarkModel.shared.inkColor = PointingInkColor.current()
        // Click-through on purpose: the overlay never takes mouse events, so the app under the
        // pointer keeps focus and receives every click and drag while the keys are held.
        MarkOverlay.shared.show(capturingMouse: false)
    }

    private func stopInk() {
        guard inkOwner else { return }
        inkOwner = false
        MarkOverlay.shared.hide()
        MarkModel.shared.strokes = []
        MarkModel.shared.inkColor = nil
        inkTrail = PointingInkTrail()
    }

    /// Test seam for the self-test: a synthetic press, drag and release become pointer samples.
    func ink(_ type: NSEvent.EventType, _ point: CGPoint) {
        switch type {
        case .leftMouseDown: endInkStroke(); sample(at: point)
        case .leftMouseDragged: sample(at: point)
        case .leftMouseUp: sample(at: point); endInkStroke()
        default: break
        }
    }

    // MARK: Typed question (double Control)

    /// Opens the typed-question box near the pointer. Only when the owner turned it on and no hold is active.
    private func openTextEntry() {
        guard services.enabled(), services.textEntryEnabled() else { return }
        guard session.state != .listening, session.state != .drawing else { return }
        textEntry.show(near: services.mouseLocation())
    }

    /// A typed question: the same turn as a spoken one, with no microphone and no ink. Also the test seam.
    func submitText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard services.enabled(), !text.isEmpty, text.utf8.count <= 4096 else { return }
        let transition = session.send(.keyDown)
        guard transition.changed else { return }
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
        textEntry.hide(); stopWatching()
        trace = PointingTrace(); candidatesForTest = []; strokeCount = 0
        metrics.releaseAt = nil; metrics.firstAudioAt = nil; metrics.flightStartAt = nil
        metrics.flightUsedFallback = false; metrics.stopLatency = nil; metrics.lastFailure = nil
        flightLaunched = false; attempt = nil
        beginSpans(); mark(.transcriptFinal)
        // Nothing was spoken: go straight from the key-down to processing.
        let processing = session.send(.keyUp)
        guard processing.to == .processing else { return }
        let generation = session.generation
        metrics.releaseAt = services.now()
        marker.think()
        prepareTask = Task { [prepare] in await prepare() }
        captureTask = Task { [weak self] in await self?.captureAtPointer(generation: generation) }
        work = Task { [weak self] in await self?.finishTextTurn(generation: generation, text: text) }
    }

    private func finishTextTurn(generation: Int, text: String) async {
        let order = await prepareTask?.value ?? []
        guard session.isCurrent(generation) else { return }
        guard !order.isEmpty else {
            fail("Add an Anthropic, OpenAI or Any LLM key in Settings to use pointing.")
            return
        }
        await captureTask?.value
        guard session.isCurrent(generation) else { return }
        let turn = await buildTurn()
        guard session.isCurrent(generation) else { return }
        explanation.desktopTurn = turn
        explanation.draft = text
        metrics.turns += 1; metrics.requestsSent += 1
        explanation.submit()
        // `submit()` consumes the turn only when it can run; a leftover means it did not.
        if explanation.desktopTurn != nil {
            explanation.desktopTurn = nil
            fail("Zeus could not start that question. Try again.")
        }
    }

    // MARK: Stale targets

    private func quartzPoint(fromScreen point: CGPoint) -> CGPoint? {
        let mapper = ScreenCoordinateMapper(displays: services.displays().map { DisplayMap(id: Int($0.id), frame: $0.frame, scale: $0.scale) })
        return mapper.convert(point, from: .screen, to: .ax, context: MapContext())
    }

    /// Starts watching the control a mark was placed on. `global` is the ring centre in AppKit points.
    private func startWatching(atGlobal global: CGPoint) {
        guard !watcher.isWatching, let quartz = quartzPoint(fromScreen: global) else { return }
        let frame = watcher.start(atQuartzPoint: quartz) { [weak self] event in self?.targetEvent(event) }
        guard let frame else { return }
        watchedQuartzPoint = quartz
        stale = PointingStaleTarget(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private func stopWatching() {
        staleWork?.cancel(); staleWork = nil
        watcher.stop(); stale = nil; watchedQuartzPoint = nil
    }

    /// Per-beat drift check: a re-read of the target frame, more than 2 pt of drift marks it stale.
    private func beatTick() {
        guard stale?.isFresh == true else { return }
        guard let frame = watcher.currentFrame() else { targetEvent(.destroyed); return }
        targetEvent(.observed(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
    }

    /// An AXObserver notification or a beat read. Also the injection point for tests.
    func targetEvent(_ event: PointingStaleTarget.Event) {
        guard var current = stale else { return }
        let action = current.send(event)
        stale = current
        switch action {
        case .none, .showMark: break
        case .hideAndReResolve:
            hideMarks()
            reResolve()
        case .ask(let message):
            hideMarks()
            onNotice?(.hint(message))
        }
    }

    /// Hides every capture-space mark. The overlay needs the capture identity, so dropping it hides them.
    private func hideMarks() {
        explanation.screenContext.cancel()
        explanation.screenContext.clear()
    }

    /// One more hit test at the original point. A control still there at a new spot is reported, not
    /// re-ringed: the old scene is gone, so the user asks again and gets a fresh mark.
    private func reResolve() {
        guard let quartz = watchedQuartzPoint else { return }
        let probe = services.probe
        staleWork?.cancel()
        staleWork = Task { [weak self] in
            let raw = await probe(quartz)
            guard !Task.isCancelled, let self, var current = self.stale else { return }
            if let raw {
                _ = current.send(.resolved(x: raw.axFrame.minX, y: raw.axFrame.minY, width: raw.axFrame.width, height: raw.axFrame.height))
                self.stale = current
                self.onNotice?(.hint("That moved. Hold the keys and ask again to point at its new spot."))
            } else {
                let action = current.send(.resolveFailed)
                self.stale = current
                if case .ask(let message) = action { self.onNotice?(.hint(message)) }
            }
            self.staleWork = nil
        }
    }

    // MARK: Turn hooks

    private func speechStarted() {
        guard session.state == .processing else { return }
        _ = session.send(.firstPlaybackStart)
        mark(.firstAudio)
        metrics.firstAudioAt = services.now()
        if let release = metrics.releaseAt { recordAudio(services.now() - release) }
    }

    /// The flight starts when a ring is admitted by real playback, which is never before first audio.
    private func revealed(_ scene: ExplanationScene, fallback: Bool) {
        mark(.firstVisual)
        beatTick()
        guard !flightLaunched, let capture = explanation.screenContext.annotationContext else { return }
        let marks = scene.objects.values.filter { $0.space == .capture && $0.captureID == capture.geometry.captureID }
        guard let ring = marks.filter({ $0.geometry.kind == .ring }).min(by: { $0.id < $1.id }),
              let global = capture.geometry.globalPoint(fromImage: .init(x: ring.transform.position.x, y: ring.transform.position.y),
                                                        current: capture.currentDisplay) else { return }
        let text = marks.filter { $0.geometry.kind == .label }.min(by: { $0.id < $1.id })?.text ?? "Here"
        startWatching(atGlobal: CGPoint(x: global.x, y: global.y))
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
        emitTrace(.completed)
    }

    private func emptyInput() {
        guard session.state == .processing || session.state == .listening else { return }
        let reason = explanation.problem
        _ = session.send(.emptyTranscript)
        halt(clearScreen: true)
        attempt = nil
        marker.idle()
        if let reason { onNotice?(.hint(reason)) }
        emitTrace(.empty)
        _ = session.send(.cleanedUp)
    }
}
