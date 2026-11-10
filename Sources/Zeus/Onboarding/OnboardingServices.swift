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
    private(set) var codexConnected = AgentHookInstaller.isInstalled(.codex)
    var connectMessage: String?
    @ObservationIgnored private let location = CLLocationManager()
    /// Only asked `isDownloaded`; the dictation controller owns the engine that downloads and loads.
    @ObservationIgnored private let modelProbe = ParakeetEngine()
    @ObservationIgnored private var polling: Task<Void, Never>?

    init(permissions: PermissionsModel) {
        self.permissions = permissions
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
        // Reads the files on disk, so the row is right at launch and after a failed download. Never downloads.
        if !Self.fresh, !TopBarStyle.isSnapshot { SpeechEngineStatus.shared.refresh(modelProbe) }
        permissions.refresh()
        codexConnected = AgentHookInstaller.isInstalled(.codex)
        fullDiskAccess = !Self.fresh && Self.hasFullDiskAccess()
        let status = location.authorizationStatus
        locationAllowed = !Self.fresh && (status == .authorizedAlways || status == .authorized)
        guard Self.hasBundle else { return }
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = !Self.fresh && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    /// Grants made in System Settings show up without reopening the window; stops when hidden.
    func startPolling() {
        polling?.cancel()
        polling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func stopPolling() {
        polling?.cancel()
        polling = nil
    }

    // MARK: Actions

    func allowNotifications() {
        guard Self.hasBundle else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
            refresh()
        }
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
    static func hasFullDiskAccess() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted")
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }
}
