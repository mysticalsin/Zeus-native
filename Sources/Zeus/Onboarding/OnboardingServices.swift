import AppKit
import CoreLocation
import AVFoundation
import EventKit
import Observation
import UserNotifications
import ZeusCore

/// What the guide's rows read and do. Each permission is asked only from its own Allow button
/// (never all at launch), as in Glance's flow.
@MainActor
@Observable
final class OnboardingServices: OnboardingServing {
    let permissions: PermissionsModel
    func access(_ capability: OnboardingCapability) -> OnboardingAccess {
        guard !Self.fresh else { return .notGranted }
        // Register the observed permission snapshot even for statuses read from an OS enum below.
        _ = permissions.granted
        switch capability {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .allowed
            case .denied, .restricted: return .denied
            default: return .notGranted
            }
        case .calendar, .reminders:
            let status = EKEventStore.authorizationStatus(for: capability == .calendar ? .event : .reminder)
            if status == .denied || status == .restricted { return .denied }
            return granted(capability == .calendar ? .calendar : .reminders) ? .allowed : .notGranted
        case .location:
            if location.authorizationStatus == .denied || location.authorizationStatus == .restricted { return .denied }
            return locationAllowed ? .allowed : .notGranted
        case .accessibility: return granted(.accessibility) ? .allowed : .notGranted
        case .automation: return granted(.automation) ? .allowed : .notGranted
        case .notifications: return notificationsAllowed ? .allowed : .notGranted
        case .fullDiskAccess: return fullDiskAccess ? .allowed : .notGranted
        }
    }

    func request(_ capability: OnboardingCapability) {
        switch capability {
        case .microphone:
            if access(.microphone) == .denied { permissions.open(.microphone) }
            else { permissions.request(.microphone) }
        case .accessibility: permissions.request(.accessibility)
        case .calendar: permissions.request(.calendar)
        case .reminders: permissions.request(.reminders)
        case .automation: requestAutomation()
        case .notifications: allowNotifications()
        case .fullDiskAccess: allowFullDiskAccess()
        case .location: allowLocation()
        }
    }

    func downloadModel() { prepareDictationModel() }

    /// Downloads and loads the on-device dictation model (DictationController.prepareModel).
    @ObservationIgnored var prepareDictationModel: () -> Void = {}

    private(set) var notificationsAllowed = false
    private(set) var fullDiskAccess = false
    private(set) var locationAllowed = false
    private(set) var codexConnected = false
    var connectMessage: String?
    @ObservationIgnored private let location = CLLocationManager()
    /// Only asked `isDownloaded`; the dictation controller owns the engine that downloads and loads.
    @ObservationIgnored private let modelProbe = ParakeetEngine()
    @ObservationIgnored private var diskProbe: Task<Void, Never>?
    @ObservationIgnored private var diskProbeStale = false
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var notificationRefresh: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration: UInt64 = 0

    init(permissions: PermissionsModel) {
        self.permissions = permissions
    }

    isolated deinit {
        polling?.cancel()
        notificationRefresh?.cancel()
    }

    /// `--onboarding-fresh` (parity captures only): draw every row as on a new Mac.
    static let fresh = CommandLine.arguments.contains("--onboarding-fresh")

    func granted(_ kind: PermissionsModel.Kind) -> Bool { !Self.fresh && permissions.granted[kind] == true }

    var modelReady: Bool { !Self.fresh && SpeechEngineStatus.shared.downloaded }
    var modelProgress: Double? { SpeechEngineStatus.shared.progress }
    /// Why the last model download failed (DictationController.prepareModel), shown under the model row.
    var modelProblem: String? { Self.fresh ? nil : SpeechEngineStatus.shared.problem }

    /// Set when Allow was pressed for Automation and nothing could be asked.
    var automationMessage: String?

    /// Automation can only be asked about a running player. With none running, say so instead of doing nothing.
    /// The consent sheet is raised off the main actor (PermissionsModel.requestAutomation), so the guide stays alive.
    func requestAutomation() {
        permissions.requestAutomation()
        automationMessage = permissions.automationMessage
    }

    func refresh() {
        // Reads the files on disk (off the main thread), so the row is right at launch and after a failed download. Never downloads.
        probeDisk()
        permissions.refresh()
        let status = location.authorizationStatus
        locationAllowed = !Self.fresh && (status == .authorizedAlways || status == .authorized)
        guard Self.hasBundle, notificationRefresh == nil else { return }
        let generation = refreshGeneration
        notificationRefresh = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { self?.notificationRefresh = nil; return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard let self else { return }
            self.notificationRefresh = nil
            guard !Task.isCancelled, generation == self.refreshGeneration else { return }
            self.notificationsAllowed = !Self.fresh && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    /// The disk and TCC-protected probes behind `refresh`: the Parakeet model folder, Codex's hook file and the
    /// notification store (a listing that can wait on tccd). They run on a background thread and publish once;
    /// a request that arrives while one is running runs again right after, so the newest state always lands.
    private func probeDisk() {
        guard diskProbe == nil else { diskProbeStale = true; return }
        let fresh = Self.fresh
        let readModel = !fresh && !TopBarStyle.isSnapshot
        let engine = modelProbe
        diskProbe = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { () -> (model: Bool?, codex: Bool, fullDisk: Bool) in
                (readModel ? engine.isDownloaded : nil, AgentHookInstaller.isInstalled(.codex), !fresh && Self.hasFullDiskAccess())
            }.value
            guard let self else { return }
            self.diskProbe = nil
            if let model = found.model, SpeechEngineStatus.shared.downloaded != model { SpeechEngineStatus.shared.downloaded = model }
            if codexConnected != found.codex { codexConnected = found.codex }
            if fullDiskAccess != found.fullDisk { fullDiskAccess = found.fullDisk }
            if diskProbeStale {
                diskProbeStale = false
                probeDisk()
            }
        }
    }

    /// Grants made in System Settings show up without reopening the window; stops when hidden.
    func startPolling() {
        guard polling == nil else { return }
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.refresh()
                do { try await Task.sleep(for: .seconds(1.5)) }
                catch { return }
            }
        }
    }

    func stopPolling() {
        polling?.cancel()
        polling = nil
        refreshGeneration &+= 1
        // The OS read may ignore cancellation. Keep its slot until it returns so a quick
        // hide/show cannot build a backlog; its old generation cannot publish a result.
        notificationRefresh?.cancel()
    }

    // MARK: Actions

    func allowNotifications() {
        Task { @MainActor in await requestNotifications() }
    }

    /// Asks once, or opens the Notifications pane when macOS already has an answer. Returns after the
    /// answer (Allow all waits for it before the next prompt).
    func requestNotifications() async {
        guard Self.hasBundle else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    /// macOS has no prompt for Full Disk Access: open its pane, the row turns green on return.
    func allowFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func allowLocation() {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    func connect(_ agent: OnboardingFlow.AgentChoice) {
        switch agent {
        case .claude:
            permissions.connectClaudeCode()
            connectMessage = permissions.hookMessage
        case .codex:
            do {
                try AgentHookInstaller.install(.codex)
                codexConnected = true
                connectMessage = "Connected."
            } catch {
                connectMessage = error.localizedDescription
            }
        }
        refresh()
    }

    func isConnected(_ agent: OnboardingFlow.AgentChoice) -> Bool {
        !Self.fresh && (agent == .claude ? permissions.claudeHooksInstalled : codexConnected)
    }

    /// UNUserNotificationCenter needs an app bundle (a bare `swift run` binary has none).
    static var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    /// Reading the notification store needs Full Disk Access; the check opens nothing.
    nonisolated static func hasFullDiskAccess() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted")
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }
}
