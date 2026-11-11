import AppKit
import Foundation
import Observation
import ZeusCore

@MainActor
@Observable
final class RecordlyController {
    static let shared = RecordlyController()

    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case stopping
        case editor
        case failed(String)
    }

    /// The project side of `phase`. Capture phases are never stored here; the session owns them.
    private enum ProjectPhase: Equatable {
        case idle
        case editor
        case failed(String)
    }

    /// Mirror of `session.phase`, updated only from the session's change callback so views observe it.
    private var capturePhase: RecordlyRecordingSession.Phase = .idle
    private var projectPhase: ProjectPhase = .idle
    private var feedbackBeganAt = Date()
    private(set) var completedNotice: RecordingFeedback.Completion?
    @ObservationIgnored private var completionExpiry: Task<Void, Never>?

    var phase: Phase {
        get {
            switch capturePhase {
            case .starting: return .starting
            case .recording: return .recording
            case .stopping: return .stopping
            case .failed(let reason): return .failed(reason)
            case .idle:
                switch projectPhase {
                case .idle: return .idle
                case .editor: return .editor
                case .failed(let reason): return .failed(reason)
                }
            }
        }
        set {
            feedbackBeganAt = Date()
            if newValue == .idle { clearCompletionNotice() }
            switch newValue {
            case .idle:
                projectPhase = .idle
                session.clearFailure()
            case .editor:
                projectPhase = .editor
            case .failed(let reason):
                projectPhase = .failed(reason)
            case .starting, .recording, .stopping:
                assertionFailure("Capture phases belong to RecordlyRecordingSession.")
            }
        }
    }

    /// Visible feedback for an action that could not run (for example a click on a stale source row).
    private(set) var actionNotice: String?
    /// Shown in the editor when a recording ended early but was kept.
    private(set) var recoveryNotice: String?
    /// True while "New" is asking what to do with the saved recording.
    private(set) var isConfirmingNew = false

    private var source: RecordlyCaptureSource?
    var sourceKind: RecordlyCaptureSource.Kind = .display
    var audio = RecordlyAudioOptions()
    var exportSettings = RecordlyExportSettings(formats: [.mp4, .gif])
    var frameStyle = RecordlyFrameStyle.default
    var project: RecordlyProject?
    var startedAt: Date?
    var elapsed: TimeInterval = 0
    var lastMediaURL: URL?
    private var sourcePicker = RecordlySourcePicker()
    private let catalogProvider: any RecordlySourceCatalogProvider
    @ObservationIgnored private let displayLister: any RecordlyDisplayListing
    @ObservationIgnored private let defaults: UserDefaults
    static let rememberedDisplayKey = "recordly.lastDisplayUUID"

    /// Connected displays, main first. Always current, independent of the picker's catalog state.
    private(set) var displays: [RecordlySourceSelection.CatalogSnapshot.Display] = []
    /// Why the selection moved on its own (for example the chosen monitor was unplugged).
    private(set) var displayNotice: String?
    /// Preflight only, refreshed on page open, source load and app activation. Never prompts.
    private(set) var screenRecordingGranted = false
    /// A still of the selected display. Only taken when Screen Recording is already granted, on open and on selection.
    private(set) var thumbnail: CGImage?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailDisplayID: UInt32?

    private(set) var countdown = RecordlyCountdown()
    /// When the current countdown began, for the ring. Nil while no countdown runs.
    private(set) var countdownBeganAt: Date?
    var isCountingDown: Bool { countdown.isCounting }
    var countdownRemaining: Int? { countdown.remaining }
    @ObservationIgnored private var countdownTimer: Timer?
    @ObservationIgnored private weak var countdownTopBar: TopBarModel?
    @ObservationIgnored private var screenObservers: [NSObjectProtocol] = []
    var pickerState: RecordlySourcePicker.State { sourcePicker.state }
    var selectionIntent: RecordlySourceSelection.SelectionIntent? { sourcePicker.selectionIntent }
    var selectionNotice: String? { sourcePicker.selectionNotice }
    var failureReason: String? { if case .failed(let reason) = phase { reason } else { nil } }
    var canStart: Bool { sourcePicker.canStart && phase == .idle }
    /// Record is live only with a valid source and Screen Recording already granted. The page explains the rest.
    var canRecord: Bool { canStart && screenRecordingGranted && !isCountingDown }
    var isStarting: Bool { phase == .starting }
    var isStopping: Bool { phase == .stopping }
    var canChooseSource: Bool { phase == .idle && !isCountingDown }
    var isLoadingSources: Bool { if case .loading = sourcePicker.state { true } else { false } }
    /// The running page stays up while a recording that was running is stopping, so Stop shows as disabled.
    var showsRunning: Bool { isRecording || (isStopping && startedAt != nil) }

    static let loadTimeoutSeconds = 15
    static let startTimeoutSeconds = 15
    static let loadTimeoutMessage = "Loading sources took longer than 15 seconds. Check Screen Recording permission, then choose Refresh."
    static let startTimeoutMessage = "Starting the recording took longer than 15 seconds, so it was cancelled. Check Screen Recording permission and try again; if Zeus says another recording is still starting, relaunch Zeus."

    enum ExportState: Equatable {
        case idle
        case exporting(Double)
        case exported([URL])
        case failed(String)
    }

    private(set) var exportState: ExportState = .idle
    private var exportHasPartialFailure = false
    /// Limits applied, features skipped, and per-format failures from the last export, shown beside the result.
    private(set) var exportNotes: [String] = []
    var isExporting: Bool { if case .exporting = exportState { true } else { false } }
    @ObservationIgnored private let exporter = RecordlyExporter()
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    /// Bumped whenever an export starts or is abandoned, so a late completion never touches newer state.
    @ObservationIgnored private var exportGeneration = 0

    private let engine: RecordlyCaptureEngine
    /// Latest system-audio peak for the live meter, 0...1. Read on the meter's own frame clock, never observed.
    func systemAudioPeak() -> Float { engine.currentLevel() }
    private let session: RecordlyRecordingSession
    private var tickTimer: Timer?
    /// What one attempt needs when its recording finishes, kept by attempt until that result is handled, so a finish
    /// that arrives after the watchdog (or after a newer attempt began) still gets its own source and display bounds.
    private struct AttemptMeta {
        let source: RecordlyCaptureSource
        let audio: RecordlyAudioOptions
        let cursorSpace: (displayID: UInt32, space: RecordlyExportPlan.CursorSpace.Pending)?
    }

    private struct QueuedRecovery {
        let attemptID: UInt64
        let output: RecordlyRecordingOutput
        let message: String
    }

    @ObservationIgnored private var attemptMeta: [UInt64: AttemptMeta] = [:]
    @ObservationIgnored private var currentAttemptID: UInt64?
    /// Recovered recordings that arrived while something else owned the page. Opened one at a time when it is free.
    @ObservationIgnored private var queuedRecoveries: [QueuedRecovery] = []
    /// Where the current project's cursor samples sit on screen. Nil for window sources, restored projects, and any
    /// recording whose display moved; export then applies no zoom.
    @ObservationIgnored private var cursorSpace: RecordlyExportPlan.CursorSpace.Pending?

    private static func captureCursorSpace(for resolved: RecordlySourceSelection.ResolvedSource) -> (displayID: UInt32, space: RecordlyExportPlan.CursorSpace.Pending)? {
        guard resolved.kind == .display, let id = resolved.displayID,
              let space = RecordlyExportPlan.CursorSpace.Pending(
                  displayBounds: CGDisplayBounds(id),
                  primaryHeight: Double(CGDisplayBounds(CGMainDisplayID()).height)
              )
        else { return nil }
        return (id, space)
    }

    init(catalogProvider: any RecordlySourceCatalogProvider = RecordlyScreenCaptureCatalogProvider(),
         displayLister: any RecordlyDisplayListing = RecordlySystemDisplays(),
         defaults: UserDefaults = .standard) {
        self.catalogProvider = catalogProvider
        self.displayLister = displayLister
        self.defaults = defaults
        let engine = RecordlyCaptureEngine()
        self.engine = engine
        self.session = RecordlyRecordingSession(port: engine)
        session.onPhaseChange = { [weak self] phase in self?.applyCapturePhase(phase) }
        session.onRecovered = { [weak self] attempt, output, message in
            self?.recover(attempt, output, message: message)
        }
    }

    /// A recording ended early or finished late but was kept. It is queued with its attempt and opened with the reason
    /// shown as soon as nothing else is capturing or open; otherwise it waits for New, Dismiss, or a cancelled start.
    private func recover(_ attempt: RecordlyRecordingAttempt, _ output: RecordlyRecordingOutput, message: String) {
        queuedRecoveries.append(QueuedRecovery(attemptID: attempt.id, output: output, message: message))
        offerQueuedRecovery()
    }

    private func offerQueuedRecovery() {
        guard capturePhase == .idle, project == nil, !queuedRecoveries.isEmpty else { return }
        let next = queuedRecoveries.removeFirst()
        finishRecording(url: next.output.url, samples: next.output.cursorSamples, attemptID: next.attemptID)
        recoveryNotice = "\(next.message) The recording made so far was saved."
    }

    private func applyCapturePhase(_ new: RecordlyRecordingSession.Phase) {
        if capturePhase != new { feedbackBeganAt = Date() }
        if case .starting = new { clearCompletionNotice() }
        capturePhase = new
        if case .recording = new {} else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
        if case .failed = new {
            startedAt = nil
        }
        if case .idle = new {
            // Deferred so a stop that is returning its own recording opens it first and this finds the page taken.
            Task { @MainActor [weak self] in self?.offerQueuedRecovery() }
        }
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    func topBarFeedback(at date: Date = Date()) -> RecordingFeedback.Snapshot? {
        let key = project?.rawMediaPath ?? String(currentAttemptID ?? 0)
        func status(_ phase: RecordingFeedback.Phase, _ label: String) -> RecordingFeedback.Snapshot {
            .init(producer: .recordly, phase: phase, sessionKey: key,
                  beganAt: feedbackBeganAt.timeIntervalSinceReferenceDate, label: label)
        }
        switch phase {
        case .starting: return status(.starting, "Starting screen recording")
        case .stopping: return status(.finishing, "Saving screen recording")
        case .failed: return status(.failed, "Recording needs attention")
        case .editor:
            if isExporting { return status(.exporting, "Exporting recording") }
            if case .failed = exportState { return status(.failed, "Export needs attention") }
            if exportHasPartialFailure { return status(.failed, "Some exports failed") }
            if checkpointWarning != nil { return status(.failed, "Recording needs saving") }
            return completedNotice?.snapshot(for: .recordly, currentSessionKey: key, now: date)
        case .idle, .recording: return nil
        }
    }

    private func showCompletionNotice(_ label: String) {
        guard let project else { return }
        clearCompletionNotice()
        let notice = RecordingFeedback.Completion(sessionKey: project.rawMediaPath, label: label)
        completedNotice = notice
        completionExpiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(RecordingFeedback.completionDuration)) } catch { return }
            guard self?.completedNotice?.id == notice.id else { return }
            self?.completedNotice = nil
        }
    }

    private func clearCompletionNotice() {
        completionExpiry?.cancel()
        completionExpiry = nil
        completedNotice = nil
    }

    func selectSourceKind(_ kind: RecordlyCaptureSource.Kind) {
        guard phase == .idle, !isCountingDown else { return }
        sourceKind = kind
        sourcePicker.clearSelection()
    }

    func loadSourceCatalog() async {
        if case .failed = phase { retry() }
        if restoreCheckpointIfNeeded() { return }
        guard phase == .idle, sourceKind != .region else { return }
        actionNotice = nil
        screenRecordingGranted = RecordlyPermissionGate.screenRecordingReady()
        if sourceKind == .display {
            // Displays come from AppKit, so they need no Screen Recording permission and no click.
            refreshDisplays()
            return
        }
        let generation = sourcePicker.beginLoading()
        // A catalog that never answers moves the picker to a visible failure; a late answer is then ignored by generation.
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.loadTimeoutSeconds))
            guard !Task.isCancelled, let self else { return }
            self.sourcePicker.finishLoading(.failed(reason: Self.loadTimeoutMessage), generation: generation)
        }
        let result = await catalogProvider.loadCatalog()
        timeout.cancel()
        sourcePicker.finishLoading(result, generation: generation)
    }

    /// Abandons a pending catalog load. The late result is ignored because the picker generation moves on.
    func cancelLoading() {
        guard isLoadingSources else { return }
        sourcePicker.reset()
        actionNotice = "Loading sources was cancelled."
    }

    func selectSource(_ intent: RecordlySourceSelection.SelectionIntent) {
        guard phase == .idle else { return }
        switch intent.kind {
        case .display:
            sourceKind = .display
        case .window:
            sourceKind = .window
        case .region:
            return
        }
        actionNotice = nil
        displayNotice = nil
        if case .catalogUnavailable = sourcePicker.selectSource(intent) {
            actionNotice = "The source list was out of date, so it is reloading. Choose the source again."
            Task { await loadSourceCatalog() }
        } else if case .display(let id) = intent, sourcePicker.canStart {
            // Remember the owner's explicit choice by stable identity, never by the raw display id.
            if let stable = displays.first(where: { $0.id == id })?.stableID {
                defaults.set(stable, forKey: Self.rememberedDisplayKey)
            }
            refreshThumbnail(force: false)
        }
    }

    /// Name of the selected source for captions: the display's name, or the window's title.
    var selectedSourceName: String? {
        guard sourcePicker.canStart, let intent = sourcePicker.selectionIntent else { return nil }
        switch intent {
        case .display(let id):
            return Self.displayName(id, in: displays)
        case .window(let number, _):
            let title = sourcePicker.catalog?.windows.first { $0.number == number }?.title?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? "Window \(number)" : title
        case .region:
            return nil
        }
    }

    // MARK: Displays

    /// Called when the Record page opens: watch for monitors coming and going, then load the sources. Displays
    /// list and the main one is selected without a click and without Screen Recording permission.
    func pageAppeared() {
        installScreenObservers()
        Task {
            await loadSourceCatalog()
            refreshThumbnail(force: true)
        }
    }

    private func installScreenObservers() {
        guard screenObservers.isEmpty else { return }
        let center = NotificationCenter.default
        // The blocks run on the main queue but are Sendable closures, so they hop to the main actor explicitly
        // instead of touching this isolated type directly (see test_source_lint.py).
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.didBecomeActiveNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screensMayHaveChanged() }
            }
            screenObservers.append(token)
        }
    }

    private func screensMayHaveChanged() {
        screenRecordingGranted = RecordlyPermissionGate.screenRecordingReady()
        if phase == .idle, sourceKind == .display {
            refreshDisplays()
        } else {
            displays = displayLister.displays()
        }
    }

    /// Lists displays and keeps the selection valid: the owner's current choice, else the remembered display
    /// (by stable identity), else the main display. A choice that was unplugged moves to the fallback with a notice,
    /// and a countdown that was running for it stops.
    private func refreshDisplays() {
        let before = displays
        let listed = displayLister.displays()
        displays = listed
        guard phase == .idle, sourceKind == .display else { return }
        var currentID: UInt32?
        if case .display(let id)? = sourcePicker.selectionIntent { currentID = id }
        let decision = RecordlyDisplayChoice.decide(
            displays: listed, current: currentID, remembered: defaults.string(forKey: Self.rememberedDisplayKey)
        )
        if decision.lostCurrent {
            var message = "\(Self.displayName(currentID, in: before)) was disconnected."
            if let fallback = decision.selected { message += " Using \(Self.displayName(fallback, in: listed))." }
            if isCountingDown {
                perform(countdown.send(.sourceUnavailable(reason: message)))
            } else {
                displayNotice = message
            }
        }
        let generation = sourcePicker.beginLoading()
        sourcePicker.finishLoading(.loaded(.init(displays: listed, windows: [])), generation: generation)
        if sourcePicker.resolvedSource == nil, let id = decision.selected {
            _ = sourcePicker.selectSource(.display(id: id))
        }
        refreshThumbnail(force: false)
    }

    private static func displayName(_ id: UInt32?, in list: [RecordlySourceSelection.CatalogSnapshot.Display]) -> String {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return "The selected display" }
        return RecordlyDisplayChoice.title(list[index], position: index)
    }

    /// One still of the selected display. Skipped without Screen Recording already granted; never requests it.
    private func refreshThumbnail(force: Bool) {
        guard screenRecordingGranted, case .display(let id)? = sourcePicker.selectionIntent else {
            thumbnailTask?.cancel()
            thumbnail = nil
            thumbnailDisplayID = nil
            return
        }
        if !force, thumbnailDisplayID == id, thumbnail != nil { return }
        if thumbnailDisplayID != id { thumbnail = nil }
        thumbnailDisplayID = id
        thumbnailTask?.cancel()
        thumbnailTask = Task { @MainActor [weak self] in
            let image = await RecordlyDisplays.thumbnail(displayID: id)
            guard !Task.isCancelled, let self, self.thumbnailDisplayID == id else { return }
            self.thumbnail = image
        }
    }

    // MARK: Countdown

    /// The capture control while idle: starts the 3, 2, 1, or cancels it when pressed again.
    func pressRecord(topBar: TopBarModel?) {
        guard phase == .idle else { return }
        countdownTopBar = topBar
        if !isCountingDown {
            screenRecordingGranted = RecordlyPermissionGate.screenRecordingReady()
            guard screenRecordingGranted else {
                actionNotice = "Screen Recording is off for Zeus. Open Screen Recording settings to turn it on."
                return
            }
            actionNotice = nil
            displayNotice = nil
        }
        perform(countdown.send(.press(sourceReady: canStart)))
    }

    /// Escape, or a second press of the control.
    func cancelCountdown() {
        perform(countdown.send(.cancel))
    }

    private func countdownTick(_ token: UInt64) {
        guard phase == .idle else {
            perform(countdown.send(.cancel))
            return
        }
        perform(countdown.send(.tick(token: token, sourceReady: canStart)))
    }

    /// The Record page went away (another page, the notch closed): a countdown must not start a capture the owner can
    /// no longer see or cancel with Escape.
    func pageDisappeared() {
        perform(countdown.send(.cancel))
        thumbnailTask?.cancel()
    }

    private func perform(_ effects: [RecordlyCountdown.Effect]) {
        if countdown.isCounting, countdownBeganAt == nil { countdownBeganAt = Date() }
        for effect in effects {
            switch effect {
            case .scheduleTick(let token):
                scheduleCountdownTick(token)
            case .cancelTick:
                stopCountdownTimer()
            case .startCapture:
                stopCountdownTimer()
                Task { await self.start(topBar: self.countdownTopBar) }
            case .notice(let text):
                actionNotice = text
            }
        }
        if !countdown.isCounting { countdownBeganAt = nil }
    }

    /// One one-shot timer per step, aimed at an absolute time so steps do not drift. No timer exists while idle.
    private func scheduleCountdownTick(_ token: UInt64) {
        guard let began = countdownBeganAt, let remaining = countdown.remaining else { return }
        stopCountdownTimer()
        let fire = began.addingTimeInterval(Double(RecordlyCountdown.seconds - remaining + 1))
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.countdownTick(token) }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: Snapshot harness

    enum SnapshotState {
        case idle
        case countdown(Int)
        case recording(elapsed: TimeInterval)
        case saved
    }

    /// Offscreen QA only: puts a controller built with a fake display lister into one visible state, with no
    /// timers, no capture and no permission request.
    func seedForSnapshot(granted: Bool, thumbnail: CGImage?, state: SnapshotState) {
        screenRecordingGranted = granted
        refreshDisplays()
        self.thumbnail = granted ? thumbnail : nil
        switch state {
        case .idle:
            break
        case .countdown(let remaining):
            _ = countdown.send(.press(sourceReady: canStart))
            for _ in 0..<(RecordlyCountdown.seconds - max(1, min(remaining, RecordlyCountdown.seconds))) {
                if case .counting(_, let token) = countdown.state { _ = countdown.send(.tick(token: token)) }
            }
            countdownBeganAt = Date().addingTimeInterval(-Double(RecordlyCountdown.seconds - remaining) - 0.4)
        case .recording(let elapsed):
            capturePhase = .recording(RecordlyRecordingAttempt(id: 1))
            startedAt = Date().addingTimeInterval(-elapsed)
            self.elapsed = elapsed
        case .saved:
            project = RecordlyProject(
                source: .display(id: displays.first?.id ?? 1), audio: audio, rawMediaPath: "/Users/fixture/Movies/Zeus Recordings/clip.mp4",
                cursorSamples: []
            )
            projectPhase = .editor
            self.elapsed = 74
            lastMediaURL = URL(fileURLWithPath: "/Users/fixture/Movies/Zeus Recordings/clip.mp4")
            previewUnavailableReason = "Preview unavailable in this snapshot."
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func isSelected(_ intent: RecordlySourceSelection.SelectionIntent) -> Bool {
        sourcePicker.selectionIntent == intent && sourcePicker.canStart
    }

    func exclusions() -> RecordlyCaptureExclusions {
        let store = SettingsStore.shared
        return RecordlyCaptureExclusions.fromScreenSharePolicy(
            showInScreenSharing: store.bool(ZeusScreenSharePolicy.showInSharingKey),
            meetingActive: MeetingState.active,
            teleprompterSessionHidden: false
        )
    }

    func start(topBar: TopBarModel?) async {
        guard canStart, let selectionIntent = sourcePicker.selectionIntent else { return }
        ExplanationAudioArbitration.yieldToNewCapture()
        guard RecordlyPermissionGate.screenRecordingReady() else {
            let reason = RecordlyCaptureError.permissionDenied.localizedDescription
            sourcePicker.markDenied(reason: reason)
            topBar?.show(.permission("Screen Recording is off for Zeus.", pane: "Privacy_ScreenCapture"))
            return
        }
        actionNotice = nil
        // Microphone capture is not implemented, so a project must never claim it.
        audio.microphone = false
        let request = RecordlyStartRequest(
            intent: selectionIntent,
            systemAudio: audio.systemAudio,
            excludeZeusWindows: exclusions().excludeZeusWindows,
            directory: Self.qaDirectory()
        )
        // A start that is never acknowledged is cancelled with a visible reason. Cancelled as soon as start returns.
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.startTimeoutSeconds))
            guard !Task.isCancelled, let self else { return }
            await self.session.cancel(failing: Self.startTimeoutMessage)
        }
        let outcome = await session.start(request)
        timeout.cancel()
        switch outcome {
        case .started(let attempt, let resolved):
            let captureSource = RecordlySourceSelection.CaptureAdapter(resolved).source
            source = captureSource
            currentAttemptID = attempt.id
            attemptMeta[attempt.id] = AttemptMeta(
                source: captureSource,
                audio: audio,
                cursorSpace: Self.captureCursorSpace(for: resolved)
            )
            // Only the newest few are kept; older ones belong to results that were handled or can no longer arrive.
            if attemptMeta.count > 8, let oldest = attemptMeta.keys.min() { attemptMeta[oldest] = nil }
            startedAt = Date()
            elapsed = 0
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let startedAt = self.startedAt else { return }
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        case .failed(let failure):
            switch failure {
            case .permissionDenied(let reason):
                sourcePicker.markDenied(reason: reason)
                topBar?.show(.permission("Screen Recording is off for Zeus.", pane: "Privacy_ScreenCapture"))
            case .noSource(let reason):
                sourcePicker.markStale(reason: reason)
            case .engine, .cancelled:
                // The session already holds the failure as `phase`, so the page shows it.
                break
            }
        case .cancelled:
            break
        case .rejected(let reason):
            actionNotice = reason
        }
    }

    /// Cancel while a start is pending. Stays in `stopping` until the engine acknowledges teardown.
    func cancelStart() async {
        guard isStarting else { return }
        await session.cancel()
    }

    func stop() async {
        switch phase {
        case .starting:
            await cancelStart()
            return
        case .recording:
            break
        default:
            return
        }
        switch await session.stop() {
        case .finished(let output):
            finishRecording(url: output.url, samples: output.cursorSamples, attemptID: currentAttemptID)
        case .failed, .ignored:
            break
        }
    }

    private func finishRecording(url: URL, samples: [RecordlyCursorSample], attemptID: UInt64?) {
        let meta = attemptID.flatMap { attemptMeta.removeValue(forKey: $0) }
        let pending = meta?.cursorSpace
        // Cleared first so no early return leaves a stale start time that could bring the Running page back.
        startedAt = nil
        recoveryNotice = nil
        guard let finishedSource = meta?.source ?? self.source else {
            phase = .failed("The selected source could not be saved. Choose it again and retry.")
            return
        }
        let finishedAudio = meta?.audio ?? self.audio
        var built = RecordlyProject(source: finishedSource, audio: finishedAudio, rawMediaPath: url.path, cursorSamples: samples)
        built.applyAutoZoomFromClicks()
        built.export = exportSettings
        built.frameStyle = frameStyle
        abandonExport()
        project = built
        cursorSpace = pending.flatMap {
            $0.space.verified(
                currentBounds: CGDisplayBounds($0.displayID),
                currentPrimaryHeight: Double(CGDisplayBounds(CGMainDisplayID()).height)
            )
        }
        lastMediaURL = url
        acquireMediaAuthority(for: built)
        applyCheckpointCommit(checkpointFlow.finalize(project: built, mediaURL: url, store: Self.checkpointStore()))
        startedAt = nil
    }

    @ObservationIgnored private var checkpointFlow = RecordlyCheckpointFlow()
    /// Pinned descriptor for the current project's media (finalized or restored). The Controller owns and closes it;
    /// previews only borrow it. No path authority is kept beside it. Released on a new recording, restore, and reset.
    private(set) var mediaAuthority: RecordlyValidatedMedia?
    /// Why there is no preview, when `mediaAuthority` is nil.
    private(set) var previewUnavailableReason: String?
    /// Visible, separate from `phase`: the checkpoint could not be saved but the project is still in the editor.
    private(set) var checkpointWarning: String?

    /// Production roots are resolved only here, on a finalize, retry, or first source load.
    private static func checkpointStore() -> RecordlyCheckpointStore? {
        RecordlyCheckpointStore.makeProduction()
    }

    /// Replaces the authority, closing the previous handle if it is a different object.
    private func setMediaAuthority(_ media: RecordlyValidatedMedia?, reason: String?) {
        if let previous = mediaAuthority, previous !== media { previous.close() }
        mediaAuthority = media
        previewUnavailableReason = media == nil ? (reason ?? "No trusted recording is available to preview.") : nil
    }

    /// Pins the project's media under the trusted root. Media outside it (including the temp fallback) gets no
    /// authority and a visible reason; the editor still opens and nothing is copied or deleted.
    private func acquireMediaAuthority(for project: RecordlyProject) {
        guard let store = Self.checkpointStore() else {
            setMediaAuthority(nil, reason: "Zeus's recordings folder is unavailable, so this recording cannot be previewed.")
            return
        }
        do {
            setMediaAuthority(try store.openValidatedMedia(rawPath: project.rawMediaPath), reason: nil)
        } catch {
            setMediaAuthority(nil, reason: "Preview unavailable: \(error.localizedDescription)")
        }
    }

    /// Drops everything bound to the current project: authority, pending save, and warning.
    private func discardProjectBindings(reason: String) {
        abandonExport()
        setMediaAuthority(nil, reason: reason)
        checkpointFlow.discardPending()
        checkpointWarning = nil
    }

    /// The editor stays visible whether or not the checkpoint was written; a failure only sets the warning.
    private func applyCheckpointCommit(_ result: RecordlyCheckpointFlow.CommitResult) {
        switch result {
        case .committed:
            checkpointWarning = nil
            showCompletionNotice("Recording saved")
        case .failed(let reason):
            clearCompletionNotice()
            checkpointWarning = reason
        }
        phase = .editor
    }

    /// Retries the SAME pending project from the editor. Retry never uses the descriptor, so it cannot disturb a preview.
    func retryCheckpoint() {
        guard phase == .editor, let result = checkpointFlow.retryPending(store: Self.checkpointStore()) else { return }
        if mediaAuthority == nil, let project { acquireMediaAuthority(for: project) }
        applyCheckpointCommit(result)
    }

    /// True when a restored editor or a visible failure was set, so the caller skips the provider.
    private func restoreCheckpointIfNeeded() -> Bool {
        guard phase == .idle, project == nil else { return false }
        switch checkpointFlow.restoreIfNeeded(store: Self.checkpointStore()) {
        case .skipped, .noCheckpoint:
            return false
        case .restored(let restored, let media):
            abandonExport()
            project = restored
            exportSettings = restored.export
            frameStyle = restored.frameStyle
            cursorSpace = nil
            setMediaAuthority(media, reason: nil)
            checkpointWarning = nil
            lastMediaURL = nil
            phase = .editor
            startedAt = nil
            return true
        case .failed(let reason):
            phase = .failed(reason)
            return true
        }
    }

    /// Exports the open project's pinned recording in the chosen formats. Reads only through `mediaAuthority`.
    func export() {
        guard phase == .editor, !isExporting, var project else { return }
        guard let media = mediaAuthority, !media.isReleased else {
            exportNotes = []
            exportState = .failed("There is no trusted recording to export. \(previewUnavailableReason ?? "")")
            return
        }
        guard !exportSettings.formats.isEmpty else {
            exportNotes = []
            exportState = .failed("Choose MP4, GIF, or both before exporting.")
            return
        }
        project.export = exportSettings
        self.project = project
        applyCheckpointCommit(checkpointFlow.finalize(
            project: project, mediaURL: URL(fileURLWithPath: project.rawMediaPath), store: Self.checkpointStore()
        ))
        let request = RecordlyExportRequest(
            media: media,
            settings: exportSettings,
            trimStart: project.trimStart,
            trimEnd: project.trimEnd,
            zoomRegions: project.zoomRegions,
            cursorSamples: project.cursorSamples,
            cursorSpace: cursorSpace
        )
        exportGeneration += 1
        let generation = exportGeneration
        exportNotes = []
        exportHasPartialFailure = false
        clearCompletionNotice()
        feedbackBeganAt = Date()
        exportState = .exporting(0)
        let exporter = self.exporter
        exportTask = Task { [weak self] in
            do {
                let output = try await exporter.export(request) { value in
                    Task { @MainActor in self?.applyExportProgress(value, generation: generation) }
                }
                self?.finishExport(output, generation: generation)
            } catch let error as RecordlyExportError {
                if case .cancelled(let completed) = error {
                    self?.finishCancelledExport(completed: completed, generation: generation)
                } else if Task.isCancelled {
                    self?.finishCancelledExport(completed: [], generation: generation)
                } else {
                    self?.failExport(error.localizedDescription, generation: generation)
                }
            } catch {
                if Task.isCancelled {
                    self?.finishCancelledExport(completed: [], generation: generation)
                } else {
                    self?.failExport(error.localizedDescription, generation: generation)
                }
            }
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        exportTask?.cancel()
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openMedia(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Puts the clip file itself on the pasteboard, so it pastes into Finder, Mail or Slack as a file.
    func copyMedia(_ url: URL) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
    }

    /// Size of the pinned recording, for the saved clip card.
    var mediaByteCount: Int64? { mediaAuthority.map { Int64($0.byteCount) } }

    private func applyExportProgress(_ value: Double, generation: Int) {
        guard generation == exportGeneration, case .exporting(let current) = exportState, value > current else { return }
        exportState = .exporting(min(value, 1))
    }

    private func finishExport(_ output: RecordlyExportOutput, generation: Int) {
        guard generation == exportGeneration else { return }
        exportTask = nil
        exportNotes = output.notes + output.failures
        let disposition = RecordingFeedback.exportDisposition(completedFiles: output.urls.count, failedFormats: output.failures.count)
        exportHasPartialFailure = disposition == .partial
        if disposition == .failed {
            exportState = .failed(output.failures.isEmpty ? "The export produced no files." : output.failures.joined(separator: " "))
        } else {
            exportState = .exported(output.urls)
            if disposition == .saved { showCompletionNotice("Export saved") }
        }
    }

    private func finishCancelledExport(completed: [URL], generation: Int) {
        guard generation == exportGeneration else { return }
        exportTask = nil
        exportHasPartialFailure = false
        if completed.isEmpty {
            exportNotes = ["Export cancelled. No files were kept."]
            exportState = .idle
        } else {
            exportNotes = ["Export cancelled. Files that had already finished were kept."]
            exportState = .exported(completed)
        }
    }

    private func failExport(_ message: String, generation: Int) {
        guard generation == exportGeneration else { return }
        exportTask = nil
        exportNotes = []
        exportState = .failed(message)
    }

    /// Cancels any running export and clears its result. Used when the project it belongs to goes away.
    private func abandonExport() {
        clearCompletionNotice()
        exportHasPartialFailure = false
        exportGeneration += 1
        exportTask?.cancel()
        exportTask = nil
        exportState = .idle
        exportNotes = []
    }

    func retry() {
        phase = .idle
        offerQueuedRecovery()
    }

    func requestNew() {
        guard phase == .editor, !isExporting else { return }
        isConfirmingNew = true
    }

    func cancelNew() { isConfirmingNew = false }

    /// Deletes the saved checkpoint record, and the raw recording only when `deleteMedia` was explicitly confirmed.
    /// On any failure nothing is reset, so the person sees the reason and the project is still open.
    func discardRecording(deleteMedia: Bool) {
        guard phase == .editor, !isExporting else { return }
        guard let store = Self.checkpointStore() else {
            checkpointWarning = "Zeus's recordings folder is unavailable, so the saved recording could not be discarded."
            isConfirmingNew = false
            return
        }
        do {
            try RecordlyDiscard.removeCheckpointRecord(store)
            if deleteMedia, let path = project?.rawMediaPath {
                try RecordlyDiscard.removeMedia(store, rawPath: path)
            }
        } catch {
            checkpointWarning = "The recording could not be discarded: \(error.localizedDescription)"
            isConfirmingNew = false
            return
        }
        reset()
    }

    func reset() {
        // A capture that is starting, recording or stopping is never reset out from under its teardown.
        guard session.reset() else { return }
        perform(countdown.send(.cancel))
        isConfirmingNew = false
        actionNotice = nil
        recoveryNotice = nil
        tickTimer?.invalidate()
        tickTimer = nil
        discardProjectBindings(reason: "No recording is open.")
        project = nil
        cursorSpace = nil
        lastMediaURL = nil
        phase = .idle
        startedAt = nil
        elapsed = 0
        source = nil
        sourceKind = .display
        sourcePicker.reset()
        offerQueuedRecovery()
    }

    static func qaDirectory() -> URL {
        // Capture media must land in the same app-owned root the checkpoint store trusts. If that root cannot be
        // resolved, the temp fallback is outside it, so the checkpoint fails truthfully and the project stays in memory.
        if let root = RecordlyCheckpointStore.productionMediaRootURL() {
            return root
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Zeus/Recordly", isDirectory: true)
    }

    func runDebug(plan: RecordlyDebugPlan) async -> String {
        guard RecordlyPermissionGate.screenRecordingReady() else {
            sourcePicker.markDenied(reason: RecordlyCaptureError.permissionDenied.localizedDescription)
            return "BLOCKED-ON-TONY Screen Recording permission needed (preflight false)."
        }
        let directory: URL
        if let out = plan.outputDirectory {
            directory = URL(fileURLWithPath: (out as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            directory = Self.qaDirectory()
        }
        guard canStart, let selectionIntent = sourcePicker.selectionIntent else {
            return "ok=false error=Explicit current source selection required."
        }
        let audio = RecordlyAudioOptions(microphone: false, systemAudio: false)
        do {
            let (mp4, samples, resolved) = try await engine.record(
                intent: selectionIntent,
                audio: audio,
                exclusions: exclusions(),
                duration: plan.seconds,
                to: directory
            )
            let regions = RecordlyZoomPlanner.regions(from: RecordlyCursorLog.clicks(in: samples))
            let captureSource = RecordlySourceSelection.CaptureAdapter(resolved).source
            let mp4Report = await RecordlyExportValidator.validate(
                url: mp4, expectedMinDuration: plan.seconds * 0.8, expectedMaxDuration: plan.seconds * 1.2 + 1
            )
            // This command records raw video. It is not evidence for the editor's export pipeline.
            let gifRequested = plan.exportFormats.contains(.gif)
            var lines = ["ok=\(mp4Report.ok && !gifRequested) mp4=\(mp4.path)", mp4Report.detail]
            if plan.exportFormats.contains(.gif) {
                lines.append("gifExport=not-run: use the Record editor to verify a real GIF export.")
            }
            // The replaced project's authority, pending save and warning must not outlive it.
            discardProjectBindings(reason: "Debug captures are not pinned for preview.")
            cursorSpace = nil
            project = RecordlyProject(source: captureSource, audio: audio, rawMediaPath: mp4.path, cursorSamples: samples, zoomRegions: regions)
            phase = .editor
            return lines.joined(separator: " ")
        } catch {
            if let captureError = error as? RecordlyCaptureError {
                switch captureError {
                case .permissionDenied:
                    sourcePicker.markDenied(reason: captureError.localizedDescription)
                case .noSource(let reason):
                    sourcePicker.markStale(reason: reason)
                case .writer, .stream:
                    break
                }
            }
            return "ok=false error=\(error.localizedDescription)"
        }
    }

}
