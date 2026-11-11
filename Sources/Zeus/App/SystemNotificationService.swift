import AppKit
import CryptoKit
import Observation
import UserNotifications
import ZeusCore

enum SystemNotificationAuthorization: Equatable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

/// Identifiers shared by the notification category, its Open action and the tap handler.
private enum AgentNotificationIDs {
    static let category = "zeus.agent"
    static let openAction = "zeus.agent.open"
    static let sessionKey = "session"
}

struct SystemNotificationPayload: Equatable, Sendable {
    let title: String
    let body: String
    /// Groups an agent's banners in Notification Centre.
    var threadIdentifier: String? = nil
    /// Marks the banner as an agent alert, which carries the Open action.
    var isAgentAlert = false
    /// Same key inside the dedupe window: the banner is not delivered again, and a replacement keeps one entry.
    var dedupeKey: String? = nil
    /// The agent session Open shows in the notch.
    var sessionID: String? = nil

    static func forCue(_ cue: NotchCue) -> SystemNotificationPayload? {
        switch cue {
        case .usageAlert(let text):
            SystemNotificationPayload(title: "Usage limit getting close", body: text)
        case .focusFinished(let name):
            SystemNotificationPayload(title: "Focus round complete", body: name)
        case .rain(let minutes):
            SystemNotificationPayload(title: "Rain soon", body: "Rain may start in \(minutes) minutes.")
        case .hint(let text):
            SystemNotificationPayload(title: "Zeus needs access", body: text)
        case .permission(let text, _):
            SystemNotificationPayload(title: "Zeus needs access", body: text)
        case .keepAwake(let text):
            SystemNotificationPayload(title: "Keep awake", body: text)
        default:
            nil
        }
    }
}

/// Remembers when each alert was last delivered, so the same agent and kind is not repeated too soon.
struct NotificationDedupe: Sendable {
    /// Two minutes: long enough to swallow a retry loop, short enough not to hide a second real event.
    static let defaultWindow: TimeInterval = 120

    var window: TimeInterval = NotificationDedupe.defaultWindow
    private var lastDelivered: [String: Date] = [:]

    /// True (and remembered) when `key` has not been delivered within the window.
    mutating func shouldDeliver(_ key: String, now: Date) -> Bool {
        lastDelivered = lastDelivered.filter { now.timeIntervalSince($0.value) < window }
        if lastDelivered[key] != nil { return false }
        lastDelivered[key] = now
        return true
    }
}

/// An agent that finished, failed or went quiet, for Settings > Notifications.
/// `session` is the agent session an Open tap shows in the notch; nil when unknown.
enum AgentAlert: Equatable, Sendable {
    case finished(agent: String, project: String, summary: String, session: String? = nil)
    case failed(agent: String, project: String, reason: String, session: String? = nil)
    case stalled(agent: String, project: String, minutes: Int, session: String? = nil)

    /// Settings key that turns this alert on.
    var settingKey: String {
        switch self {
        case .finished: "notify.system"
        case .failed, .stalled: "notify.errors"
        }
    }

    /// "Claude Code" reads as "Claude" in a title.
    static func shortName(_ agent: String) -> String {
        agent.hasSuffix(" Code") ? String(agent.dropLast(5)) : agent
    }

    /// The first sentence, trimmed to one line of banner body.
    static func oneSentence(_ text: String, limit: Int = 110) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var sentence = flat
        if let end = flat.firstIndex(where: { ".!?".contains($0) }) {
            let next = flat.index(after: end)
            if next == flat.endIndex || flat[next] == " " { sentence = String(flat[...end]) }
        }
        return sentence.count > limit ? String(sentence.prefix(limit - 1)) + "…" : sentence
    }

    private var parts: (kind: String, agent: String, project: String, session: String?) {
        switch self {
        case .finished(let agent, let project, _, let session): ("finished", agent, project, session)
        case .failed(let agent, let project, _, let session): ("failed", agent, project, session)
        case .stalled(let agent, let project, _, let session): ("stalled", agent, project, session)
        }
    }

    /// What distinguishes one event from another of the same kind: the reason or summary text, or the quiet minutes.
    private var eventText: String {
        switch self {
        case .finished(_, _, let summary, _): summary
        case .failed(_, _, let reason, _): reason
        case .stalled(_, _, let minutes, _): "\(minutes)"
        }
    }

    /// Same kind, agent, project, session and event: one banner per two minutes. A second session
    /// (or a different failure) in the same project is a different event and still delivers.
    /// Internal only: it holds project and session text, so it never reaches the OS (see `opaqueID`).
    var dedupeKey: String { "\(parts.kind)|\(parts.agent)|\(parts.project)|\(parts.session ?? "")|\(eventText)" }

    /// A stable, opaque notification identifier for `key`: the same event replaces its banner, and
    /// no agent, project, session or task text reaches the notification store.
    static func opaqueID(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return "zeus.alert." + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Project names stay out of the banner (and its thread) when details are hidden (Settings > Privacy, meeting mode).
    func payload(showDetails: Bool) -> SystemNotificationPayload {
        let name = Self.shortName(parts.agent)
        let titled = showDetails && !parts.project.isEmpty ? " \u{00B7} \(parts.project)" : ""
        let thread = "zeus.agent" + (showDetails ? ".\(parts.agent).\(parts.project)" : "")
        let title: String
        let body: String
        switch self {
        case .finished(_, _, let summary, _):
            title = "\(name) finished\(titled)"
            body = showDetails ? Self.oneSentence(summary) : "Open the notch to review."
        case .failed(_, _, let reason, _):
            title = "\(name) failed\(titled)"
            body = showDetails ? Self.oneSentence(reason) : "Open the notch for details."
        case .stalled(_, _, let minutes, _):
            title = "\(name) went quiet\(titled)"
            body = "No activity for \(minutes) min."
        }
        return SystemNotificationPayload(title: title, body: body, threadIdentifier: thread, isAgentAlert: true,
                                         dedupeKey: dedupeKey, sessionID: parts.session)
    }
}

@MainActor
protocol SystemNotificationClient: AnyObject {
    func authorizationStatus() async -> SystemNotificationAuthorization
    func requestAuthorization() async -> Bool
    func deliver(_ payload: SystemNotificationPayload) async
    func openSystemSettings()
}

@MainActor
private final class UserNotificationCenterClient: NSObject, SystemNotificationClient, UNUserNotificationCenterDelegate {
    /// Lazy: never touches `UNUserNotificationCenter` until something actually asks. A stored
    /// `let` built it the moment `SystemNotificationService.shared` was first referenced, which
    /// crashed with "bundleProxyForCurrentProcess is nil" the first time any code (not just the
    /// Notifications page) ran unbundled (snapshot rendering, `swift test`, a dev `swift run`).
    private lazy var center = UNUserNotificationCenter.current()

    /// `UNUserNotificationCenter` needs a real, installed `.app` bundle; every method below
    /// returns a safe no-op instead of calling it when that's not the case.
    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Installed as soon as the service exists, so tapping a banner that outlived a relaunch still
    /// routes. Only attaches the delegate: no permission request, no delivery, and a no-op unbundled.
    override init() {
        super.init()
        if isBundled { center.delegate = self }
    }

    func authorizationStatus() async -> SystemNotificationAuthorization {
        guard isBundled else { return .unknown }
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined: SystemNotificationAuthorization.notDetermined
        case .authorized, .provisional, .ephemeral: SystemNotificationAuthorization.authorized
        case .denied: SystemNotificationAuthorization.denied
        @unknown default: SystemNotificationAuthorization.unknown
        }
    }

    func requestAuthorization() async -> Bool {
        guard isBundled else { return false }
        center.delegate = self
        return (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    func deliver(_ payload: SystemNotificationPayload) async {
        guard isBundled else { return }
        center.delegate = self
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        if let thread = payload.threadIdentifier { content.threadIdentifier = thread }
        var identifier = "zeus.\(UUID().uuidString)"
        if payload.isAgentAlert {
            registerAgentCategory()
            content.categoryIdentifier = AgentNotificationIDs.category
            if let session = payload.sessionID { content.userInfo = [AgentNotificationIDs.sessionKey: session] }
            // A repeat of the same alert replaces the banner instead of stacking another.
            if let key = payload.dedupeKey { identifier = AgentAlert.opaqueID(key) }
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// The "Open" action on agent banners; tapping it (or the banner) shows that agent in the notch.
    private func registerAgentCategory() {
        let open = UNNotificationAction(identifier: AgentNotificationIDs.openAction, title: "Open", options: [.foreground])
        let category = UNNotificationCategory(identifier: AgentNotificationIDs.category, actions: [open], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let opens = content.categoryIdentifier == AgentNotificationIDs.category
            && (response.actionIdentifier == AgentNotificationIDs.openAction || response.actionIdentifier == UNNotificationDefaultActionIdentifier)
        let session = content.userInfo[AgentNotificationIDs.sessionKey] as? String
        completionHandler()
        guard opens else { return }
        Task { @MainActor in NotchControllerBridge.openAgent(sessionID: session) }
    }

    func openSystemSettings() {
        guard isBundled, let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Used in snapshot mode (`TopBarStyle.isSnapshot`) instead of `UserNotificationCenterClient`, so
/// rendering the Notifications settings page never touches `UNUserNotificationCenter` at all.
@MainActor
final class NoopNotificationClient: SystemNotificationClient {
    func authorizationStatus() async -> SystemNotificationAuthorization { .unknown }
    func requestAuthorization() async -> Bool { false }
    func deliver(_ payload: SystemNotificationPayload) async {}
    func openSystemSettings() {}
}

/// Permission is requested only by the Settings toggle. Delivery and refresh only inspect status.
@MainActor
@Observable
final class SystemNotificationService {
    /// `TopBarStyle.isSnapshot` is set at the very start of `SnapshotRenderer.runIfRequested()`,
    /// before anything else can reach `.shared` (a static `let`'s initializer runs lazily, on
    /// first access), so a snapshot run never builds a real `UNUserNotificationCenter`.
    static let shared = SystemNotificationService(
        client: TopBarStyle.isSnapshot ? NoopNotificationClient() : UserNotificationCenterClient(),
        isEnabled: { SettingsStore.shared.bool("notify.system") },
        setEnabled: { SettingsStore.shared.set("notify.system", $0 ? "true" : "false") }
    )

    @ObservationIgnored private let client: any SystemNotificationClient
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let setEnabled: @MainActor (Bool) -> Void
    private(set) var authorization: SystemNotificationAuthorization = .unknown
    private(set) var isRequesting = false
    @ObservationIgnored private var dedupe = NotificationDedupe()
    @ObservationIgnored private let clock: @MainActor () -> Date

    init(client: any SystemNotificationClient,
         isEnabled: @escaping @MainActor () -> Bool,
         setEnabled: @escaping @MainActor (Bool) -> Void,
         clock: @escaping @MainActor () -> Date = { Date() }) {
        self.client = client
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
        self.clock = clock
    }

    var permissionNote: String {
        if isRequesting { return "Waiting for macOS notification permission…" }
        return switch authorization {
        case .unknown, .notDetermined: "Turn on to ask macOS for permission."
        case .authorized: isEnabled() ? "Focused banners appear while the notch is closed." : "Allowed by macOS; turn on to show banners."
        case .denied: "Allow Zeus notifications in System Settings."
        }
    }

    /// Reads the current status without prompting. Safe when the Settings page appears.
    func refreshAuthorization() async {
        authorization = await client.authorizationStatus()
    }

    /// Called only by the explicit Settings toggle action. A denied choice is never re-prompted.
    func setEnabledFromUserAction(_ enabled: Bool) async {
        guard enabled else {
            setEnabled(false)
            return
        }
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        authorization = await client.authorizationStatus()
        switch authorization {
        case .authorized:
            setEnabled(true)
        case .notDetermined:
            let granted = await client.requestAuthorization()
            authorization = await client.authorizationStatus()
            setEnabled(granted && authorization == .authorized)
        case .denied, .unknown:
            setEnabled(false)
        }
    }

    /// Call once at launch: touching `shared` builds the client, which attaches the tap handler
    /// (bundled builds only). Never prompts and never delivers.
    static func installResponseHandler() { _ = shared }

    /// Opens the OS pane only after the user presses the Settings button.
    func openSystemSettingsAfterUserAction() { client.openSystemSettings() }

    /// Delivers only already-authorized, explicitly enabled cues. This path never requests access.
    func deliver(_ cue: NotchCue) async {
        guard isEnabled(), let payload = SystemNotificationPayload.forCue(cue) else { return }
        authorization = await client.authorizationStatus()
        guard authorization == .authorized, isEnabled() else { return }
        await client.deliver(payload)
    }

    /// A banner for a finished, failed or stalled agent when its Settings > Notifications switch is on
    /// and macOS already allows ZEUS notifications. Never asks for permission. The same agent and kind
    /// is not delivered again within two minutes, and details stay out of the banner while hidden.
    func deliverAgentAlert(_ alert: AgentAlert) async {
        guard SettingsStore.shared.bool(alert.settingKey), !TopBarStyle.isSnapshot else { return }
        authorization = await client.authorizationStatus()
        guard authorization == .authorized else { return }
        guard dedupe.shouldDeliver(alert.dedupeKey, now: clock()) else { return }
        await client.deliver(alert.payload(showDetails: !MeetingState.hideDetails))
    }
}
