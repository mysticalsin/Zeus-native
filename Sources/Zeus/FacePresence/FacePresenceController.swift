// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): LockMonitor.swift, SessionAutoLocker.swift.
import AppKit
import CoreGraphics
import Foundation
import Observation
import ZeusCore

/// Runs face presence: owns one `FacePresenceMachine` value, carries out its effects, and keeps the camera in step
/// with `wantsCamera` after every event, so no path can forget to stop it. All rules live in the machine; this type
/// only listens (switch, notices, frames, the clock) and acts (consent, camera, vault, the event-free lock).
///
/// What it never does: open the camera at launch, unlock anything, type or post an event, store or show an image.
/// Other features read `presence` and nothing else.
@MainActor
@Observable
final class FacePresenceController {
    static let shared = FacePresenceController(environment: .live())

    /// The camera permission calls, wired to `PermissionsModel` by `start(permissions:)`. This is the only way the
    /// feature asks macOS for the camera, so no new permission call site exists.
    struct Permissions {
        var cameraAccess: @MainActor () -> FacePresenceMachine.CameraAccess
        var askCamera: @MainActor () async -> Void
        var openCameraSettings: @MainActor () -> Void

        /// Until `start` wires the real ones: denied, and nothing to ask.
        static let unwired = Permissions(cameraAccess: { .denied }, askCamera: {}, openCameraSettings: {})
    }

    /// The two stored settings, read when they change.
    struct Settings {
        var switchIsOn: @MainActor () -> Bool
        var lockAfterLabel: @MainActor () -> String
    }

    /// Everything outside the machine, so tests run with a fake camera, lock, clock and vault.
    struct Environment {
        var source: any FaceFrameSource
        var vault: FaceVaultStore
        var analyze: @Sendable (CGImage, CGRect?) throws -> FaceVision.FrameAnalysis
        var featurePrintRevision: Int
        /// The one lock call. Live it is `ScreenLock.lockWithoutEvents`, which never posts an event.
        var lock: @MainActor () -> Bool
        var canLock: @MainActor () -> Bool
        var sessionState: @MainActor () -> FacePresenceMachine.SessionLockState
        var uptime: @MainActor () -> Double
        var settings: Settings
        var permissions: Permissions = .unwired
        /// False in tests: no one second timer and no enrollment watchdog is scheduled.
        var usesTimers = true

        @MainActor
        static func live() -> Environment {
            Environment(
                source: FaceCamera(), vault: FaceVaultStore(),
                analyze: { try FaceVision.analyze($0, previousFace: $1) },
                featurePrintRevision: FaceVision.featurePrintRevision,
                lock: { ScreenLock.lockWithoutEvents() },
                canLock: { ScreenLock.canLockWithoutEvents },
                sessionState: { FacePresenceController.systemSessionState() },
                uptime: { ProcessInfo.processInfo.systemUptime },
                settings: Settings(switchIsOn: { SettingsStore.shared.bool(FacePresenceController.switchID) },
                                   lockAfterLabel: { SettingsStore.shared.string(FacePresenceController.lockAfterID) }))
        }
    }

    static let switchID = "face.presence"
    static let lockAfterID = "face.lockAfter"
    /// Frames Vision could not read in a row before the camera is called unavailable.
    static let visionFailureLimit = FaceFrameGate.failureLimit

    // MARK: State

    private(set) var machine = FacePresenceMachine()
    /// The faces in the vault, enabled or not. Embeddings never leave this type except as `EnrolledFace` for matching.
    private(set) var faces: [FaceRecord] = []
    private(set) var vaultReadable = true

    @ObservationIgnored var environment: Environment
    @ObservationIgnored private var frameGate = FaceFrameGate()
    var cameraRun: Int { frameGate.generation }
    @ObservationIgnored private var started = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var spoofWindow = SpoofCues.Window()
    @ObservationIgnored private var previousFace: CGRect?
    @ObservationIgnored private var enrollmentOffer = EnrollmentOfferGate()
    @ObservationIgnored private var enrollment: EnrollmentSession?
    @ObservationIgnored private var enrollmentWatchdog: Task<Void, Never>?
    @ObservationIgnored private(set) var consentTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private struct EnrollmentSession {
        let token: Int
        var plan: EnrollmentPlan
    }

    init(environment: Environment) {
        self.environment = environment
    }

    // MARK: What other features may read

    /// The only value other features may read. Read-only: nothing here starts the camera, unlocks or loosens a gate.
    var presence: FacePresenceMachine.Presence { machine.presence }

    var enabledFaceCount: Int { faces.filter(\.isEnabled).count }

    func status() -> FacePresenceStatus { machine.status(at: environment.uptime()) }

    // MARK: Start

    /// Called once from launch. Reads the stored switch and the vault, and starts nothing: with the switch on the
    /// state is `paused(.launch)` until the next unlock.
    func start(permissions: Permissions) {
        guard !TopBarStyle.isSnapshot, !started else { return }
        started = true
        environment.permissions = permissions
        begin()
        installObservers()
    }

    /// The launch step without the system observers.
    func begin() {
        loadVault()
        send(.launch(storedOn: environment.settings.switchIsOn()))
        send(.setLockAfter(seconds: FaceLockAfter.seconds(forLabel: environment.settings.lockAfterLabel())))
        send(.facesChanged(enabledFaces: enabledFaceCount, uptime: environment.uptime()))
    }

    // MARK: Settings

    /// A stored setting changed: the switch in the card, an import or a section reset. The one path from a setting
    /// to the machine, so there is nothing to keep in step by hand.
    func settingChanged(_ id: String) {
        switch id {
        case Self.switchID:
            let on = environment.settings.switchIsOn()
            guard on != machine.switchOn else { return }
            if on { switchOn() } else { send(.switchOff) }
        case Self.lockAfterID:
            send(.setLockAfter(seconds: FaceLockAfter.seconds(forLabel: environment.settings.lockAfterLabel())))
        default:
            break
        }
    }

    private func switchOn() {
        loadVault()
        send(.switchOn(camera: environment.permissions.cameraAccess(), enabledFaces: enabledFaceCount,
                       canLock: environment.canLock(), vaultReadable: vaultReadable, uptime: environment.uptime()))
    }

    // MARK: Owner actions on the card

    func enroll() { send(.enroll) }

    func setFace(_ id: String, enabled: Bool) {
        guard let index = faces.firstIndex(where: { $0.id == id }), faces[index].isEnabled != enabled else { return }
        var updated = faces
        updated[index] = faces[index].with(isEnabled: enabled)
        commit(updated)
    }

    func deleteFace(_ id: String) {
        guard faces.contains(where: { $0.id == id }) else { return }
        commit(faces.filter { $0.id != id })
    }

    /// Saves the new list and only then adopts it, so a refused or failed save leaves what the owner sees equal to what
    /// is stored. Deleting the last face removes the file and the Keychain key.
    private func commit(_ updated: [FaceRecord]) {
        guard environment.vault.save(updated) == .saved else { return }
        faces = updated
        send(.facesChanged(enabledFaces: enabledFaceCount, uptime: environment.uptime()))
    }

    // MARK: Notices

    // Lock, unlock and wake notices can be posted by any process of the same user, so they are hints: each one
    // reads the session dictionary, and only a plainly unlocked session starts anything.

    func screenLockedNotice() { send(.screenLocked) }
    func screenUnlockedNotice() { send(.screenUnlocked(uptime: environment.uptime(), session: environment.sessionState())) }
    func willSleepNotice() { send(.willSleep) }
    func didWakeNotice() { send(.didWake(uptime: environment.uptime(), session: environment.sessionState())) }

    /// The teleprompter holds the camera while it records: face presence pauses, then resumes.
    func teleprompterCapture(active: Bool) {
        send(.zeusCapture(active: active, uptime: environment.uptime()))
    }

    func tick() { send(.tick(uptime: environment.uptime())) }

    func cameraEvent(_ event: FaceCameraEvent, run: Int) {
        guard frameGate.accepts(run) else { return }
        switch event {
        case .deviceLost, .interrupted, .runtimeError: send(.cameraFailed)
        case .interruptionEnded: send(.cameraReturned(uptime: environment.uptime()))
        }
    }

    // MARK: Events and effects

    private func send(_ event: FacePresenceMachine.Event) {
        let before = machine.state
        let effects = machine.handle(event)
        if machine.state != before { NSLog("[ZEUS] face presence: %@ to %@", before.logName, machine.state.logName) }
        // The camera first: when the machine stops wanting it, it is off before anything else runs.
        reconcile()
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: FacePresenceMachine.Effect) {
        switch effect {
        case .askCameraConsent:
            consentTask = Task { [weak self] in
                guard let self else { return }
                await environment.permissions.askCamera()
                send(.consentAnswered(granted: environment.permissions.cameraAccess() == .authorized,
                                      enabledFaces: enabledFaceCount, uptime: environment.uptime()))
            }
        case .openCameraSettings:
            environment.permissions.openCameraSettings()
        case .beginEnrollment(let token):
            spoofWindow.reset()
            enrollmentOffer.begin(token)
            enrollment = EnrollmentSession(token: token, plan: EnrollmentPlan(revision: environment.featurePrintRevision,
                                                                              startedAt: environment.uptime()))
            watchEnrollmentWindow()
        case .cancelEnrollment(let token):
            guard enrollmentOffer.offer(token) else { return }
            endEnrollmentSession()
        case .lockNow:
            // The one lock call, asked for once. The result goes back as an event; a failure is never retried.
            send(.lockFinished(ok: environment.lock()))
        }
    }

    /// Keeps the camera and the one second timer in step with the machine.
    private func reconcile() {
        switch frameGate.setCamera(machine.wantsCamera) {
        case .unchanged:
            break
        case .started(let run):
            spoofWindow.reset()
            previousFace = nil
            environment.source.start(
                deliver: { [weak self] frame in Task { @MainActor in await self?.process(frame, run: run) } },
                report: { [weak self] event in Task { @MainActor in self?.cameraEvent(event, run: run) } })
        case .stopped:
            environment.source.stop()
        }
        setTicking(machine.wantsTicks && environment.usesTimers)
    }

    private func setTicking(_ on: Bool) {
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else if !on, let timer {
            timer.invalidate()
            self.timer = nil
        }
    }

    // MARK: Frames

    /// One admitted frame: analyzed off the main actor, then judged here. A frame that arrives after the camera was
    /// stopped, or after the run it belonged to ended, is dropped without being looked at.
    func process(_ frame: FaceFrame, run: Int) async {
        guard frameGate.accepts(run) else {
            environment.source.analysisFinished()
            return
        }
        let analyze = environment.analyze
        let previous = previousFace
        let result = await Task.detached(priority: .utility) { Result { try analyze(frame.image, previous) } }.value
        environment.source.analysisFinished()
        guard frameGate.accepts(run) else { return }

        switch result {
        case .failure:
            if frameGate.visionFailed() == .failCamera { send(.cameraFailed) }
        case .success(let analysis):
            frameGate.visionOk()
            previousFace = analysis.faceBox
            let latched = spoofWindow.observe(analysis.spoofFrame)
            switch machine.state {
            case .enrolling(let token):
                offerToEnrollment(token: token, analysis: analysis, spoofCues: latched, uptime: frame.uptime)
            case .watching, .present, .away:
                let verdict = FacePresenceVerdict.decide(observation: analysis.observation, faces: faces.map(\.enrolledFace),
                                                         spoofCues: latched)
                send(.observed(verdict, uptime: frame.uptime))
            default:
                break
            }
        }
    }

    // MARK: Enrollment

    private func offerToEnrollment(token: Int, analysis: FaceVision.FrameAnalysis, spoofCues: Set<SpoofCue>, uptime: Double) {
        guard enrollmentOffer.offer(token), var session = enrollment else { return }
        let candidate = analysis.observation.map {
            EnrollmentCandidate(embedding: $0.embedding, revision: $0.revision, quality: analysis.quality,
                                alignment: analysis.alignment ?? .paddedCrop, spoofCues: spoofCues)
        }
        let outcome = session.plan.offer(candidate, at: uptime)
        enrollment = session
        switch outcome {
        case .completed(let result): finishEnrollment(token: token, result: result)
        case .expired: finishEnrollment(token: token, result: nil)
        case .accepted, .refused, .finished: break
        }
    }

    /// Saves a completed enrollment as the next face, or saves nothing. Either way the machine hears how it ended.
    private func finishEnrollment(token: Int, result: EnrollmentPlan.Result?) {
        var saved = false
        if let result {
            let face = FaceRecord(id: UUID().uuidString, name: FaceNameSequence.next(taken: Set(faces.map(\.name))), isEnabled: true, revision: result.revision,
                                  samples: result.samples, threshold: result.threshold)
            if environment.vault.save(faces + [face]) == .saved {
                faces.append(face)
                saved = true
            }
        }
        endEnrollmentSession()
        send(.enrollmentEnded(token: token, saved: saved, enabledFaces: enabledFaceCount, uptime: environment.uptime()))
    }

    private func endEnrollmentSession() {
        enrollmentOffer.end()
        enrollment = nil
        enrollmentWatchdog?.cancel()
        enrollmentWatchdog = nil
    }

    /// An enrollment whose camera sends no frames still has to end: this closes it when its window has passed.
    func checkEnrollmentWindow() {
        guard var session = enrollment, case .enrolling(let token) = machine.state, enrollmentOffer.offer(token),
              session.plan.tick(at: environment.uptime()) != nil else { return }
        enrollment = session
        finishEnrollment(token: token, result: nil)
    }

    private func watchEnrollmentWindow() {
        enrollmentWatchdog?.cancel()
        guard environment.usesTimers else { return }
        enrollmentWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(EnrollmentPlan.window + 1))
            guard !Task.isCancelled else { return }
            self?.checkEnrollmentWindow()
        }
    }

    // MARK: Vault

    private func loadVault() {
        switch environment.vault.load() {
        case .empty: faces = []; vaultReadable = true
        case .faces(let stored): faces = stored; vaultReadable = true
        case .unreadable: faces = []; vaultReadable = false
        }
    }

    // MARK: System observers

    private func installObservers() {
        func add(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (FacePresenceController) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action(FacePresenceController.shared) }
            }
            observers.append((center, token))
        }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        add(distributed, .init("com.apple.screenIsLocked")) { $0.screenLockedNotice() }
        add(distributed, .init("com.apple.screenIsUnlocked")) { $0.screenUnlockedNotice() }
        add(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.screenLockedNotice() }
        add(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.screenUnlockedNotice() }
        add(workspace, NSWorkspace.screensDidSleepNotification) { $0.willSleepNotice() }
        add(workspace, NSWorkspace.screensDidWakeNotification) { $0.didWakeNotice() }
        add(workspace, NSWorkspace.willSleepNotification) { $0.willSleepNotice() }
        add(workspace, NSWorkspace.didWakeNotification) { $0.didWakeNotice() }
    }

    /// The session dictionary is the authority on whether the Mac is locked. A session that cannot be read is treated
    /// as locked, and so is one that is not on the console (another user's session is in front).
    static func systemSessionState() -> FacePresenceMachine.SessionLockState {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return .unknown }
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true { return .locked }
        if (session["kCGSSessionOnConsoleKey"] as? Bool) == false { return .locked }
        return .unlocked
    }
}

extension FacePresenceController.Permissions {
    /// The camera permission calls on the app's one `PermissionsModel`. Asking goes through `requestCamera`, which
    /// shares the prompt with every other camera user; denied opens System Settings through `request(.camera)`.
    @MainActor
    static func live(_ model: PermissionsModel) -> Self {
        Self(
            cameraAccess: {
                switch model.cameraPermissionState {
                case .authorized: .authorized
                case .notDetermined: .notDetermined
                case .denied: .denied
                }
            },
            askCamera: { await model.requestCamera() },
            openCameraSettings: { model.request(.camera) })
    }
}
