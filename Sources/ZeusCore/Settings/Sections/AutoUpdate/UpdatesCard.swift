import Foundation

public enum UpdatesPhase: Equatable, Sendable {
    case notConfigured
    case disabled
    case loading
    case ready
    case error
}

public enum UpdatesControl: Equatable, Sendable {
    case toggle(Bool)
    case button(title: String, enabled: Bool)
    case text(String)
}

public struct UpdatesCardRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var helper: String
    public var control: UpdatesControl
    public var accessibilityLabel: String
    public var keyboardReachable: Bool

    public init(id: String, title: String, helper: String, control: UpdatesControl, accessibilityLabel: String, keyboardReachable: Bool) {
        self.id = id
        self.title = title
        self.helper = helper
        self.control = control
        self.accessibilityLabel = accessibilityLabel
        self.keyboardReachable = keyboardReachable
    }
}

public struct UpdatesPreview: Equatable, Sendable {
    public var versionLine: String
    public var statusLine: String
    public var accessibilityLabel: String

    public init(versionLine: String, statusLine: String, accessibilityLabel: String) {
        self.versionLine = versionLine
        self.statusLine = statusLine
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum UpdateInstallPrompt: Equatable, Sendable {
    case hidden
    case confirm(version: String)
}

public struct UpdatesCardModel: Equatable, Sendable {
    public var title: String
    public var rows: [UpdatesCardRow]
    public var notes: [String]
    public var notesEmpty: String
    public var preview: UpdatesPreview
    public var panelPadding: Double
    public var cardSpacing: Double
    public var rowHeight: Double
    public var animationDuration: Double
    public var showsIndeterminateMotion: Bool
    public var status: String
    public var phase: UpdatesPhase

    public init(
        title: String,
        rows: [UpdatesCardRow],
        notes: [String],
        notesEmpty: String,
        preview: UpdatesPreview,
        panelPadding: Double,
        cardSpacing: Double,
        rowHeight: Double,
        animationDuration: Double,
        showsIndeterminateMotion: Bool,
        status: String,
        phase: UpdatesPhase
    ) {
        self.title = title
        self.rows = rows
        self.notes = notes
        self.notesEmpty = notesEmpty
        self.preview = preview
        self.panelPadding = panelPadding
        self.cardSpacing = cardSpacing
        self.rowHeight = rowHeight
        self.animationDuration = animationDuration
        self.showsIndeterminateMotion = showsIndeterminateMotion
        self.status = status
        self.phase = phase
    }
}

public enum UpdatesCard {
    public static let panelPadding = GlassSettingsMetrics.panelPadding
    public static let cardSpacing = GlassSettingsMetrics.cardSpacing
    public static let rowHeight = GlassSettingsMetrics.controlRow

    public static func model(state: UpdateSessionState, context: UpdateContext, lastChecked: Date?, confirmingInstall: Bool, rememberedNotes: [String] = []) -> UpdatesCardModel {
        let configured = context.canAct
        let phase = phase(state, configured: configured)
        let status = statusLine(state, context: context, configured: configured)
        let offer = offered(state)
        let versionLine = offer.map { "Version \($0.version.displayFull)" } ?? "Version \(context.currentVersion.displayFull)"
        let duration = context.reduceMotion ? 0 : 0.22
        let checked = UpdateClock.checkedLine(lastChecked)
        let current = context.currentVersion.displayFull
        let rows = [
            row(
                id: UpdateConfiguration.automaticChecksKey,
                title: "Check automatically",
                helper: "Off until you turn it on. Zeus does not check or install by itself.",
                control: .toggle(configured && context.configuration.automaticChecks),
                label: "Check for updates automatically"
            ),
            row(
                id: "updates.feed",
                title: "Update feed",
                helper: "Comes with this build. A settings file cannot change it.",
                control: .text(context.configuration.feedURL.isEmpty ? "Not configured" : context.configuration.feedURL),
                label: "Update feed from this build"
            ),
            row(
                id: UpdateConfiguration.checkNowKey,
                title: "Check now",
                helper: "Checks the feed once. Nothing is downloaded until you ask.",
                control: .button(title: "Check now", enabled: configured && !isBusy(state)),
                label: "Check for updates now"
            ),
            row(
                id: "updates.currentVersion",
                title: "Current version",
                helper: "The version running on this Mac.",
                control: .text(current),
                label: "Current version \(current)"
            ),
            row(
                id: "updates.lastChecked",
                title: "Last checked",
                helper: "The last time a check finished.",
                control: .text(checked),
                label: "Last checked \(checked)"
            ),
            row(
                id: "updates.download",
                title: "Download",
                helper: "Downloads the update and checks its signature.",
                control: .button(title: "Download", enabled: isAvailable(state)),
                label: "Download the update"
            ),
            row(
                id: "updates.install",
                title: "Install",
                helper: "Installs the verified update and relaunches. You confirm it here.",
                control: .button(title: "Install and relaunch", enabled: isReady(state)),
                label: "Install the update and relaunch"
            ),
        ]
        return UpdatesCardModel(
            title: AutoUpdateSectionSlot.cardTitle,
            rows: rows,
            notes: offer?.notes ?? rememberedNotes,
            notesEmpty: "No release notes yet.",
            preview: UpdatesPreview(
                versionLine: versionLine,
                statusLine: status,
                accessibilityLabel: "\(versionLine). \(status)"
            ),
            panelPadding: panelPadding,
            cardSpacing: cardSpacing,
            rowHeight: rowHeight,
            animationDuration: duration,
            showsIndeterminateMotion: phase == .loading && duration > 0,
            status: status,
            phase: phase
        )
    }

    public static func installPrompt(state: UpdateSessionState, confirming: Bool) -> UpdateInstallPrompt {
        guard confirming, case .readyToInstall(let candidate) = state else { return .hidden }
        return .confirm(version: candidate.version.displayFull)
    }

    private static func row(id: String, title: String, helper: String, control: UpdatesControl, label: String) -> UpdatesCardRow {
        UpdatesCardRow(id: id, title: title, helper: helper, control: control, accessibilityLabel: label, keyboardReachable: true)
    }

    private static func phase(_ state: UpdateSessionState, configured: Bool) -> UpdatesPhase {
        guard configured else { return .notConfigured }
        switch state {
        case .checking, .downloading, .verifying, .installing: return .loading
        case .failed: return .error
        case .disabled: return .disabled
        default: return .ready
        }
    }

    private static func statusLine(_ state: UpdateSessionState, context: UpdateContext, configured: Bool) -> String {
        guard configured else { return "updates not configured" }
        switch state {
        case .disabled: return "Automatic checks are off."
        case .idle: return "Automatic checks are on."
        case .checking: return "Checking for updates."
        case .upToDate: return "This copy is up to date."
        case .available(let item): return "Version \(item.version.displayFull) is available."
        case .downloading(let item): return "Downloading version \(item.version.displayFull)."
        case .verifying: return "Verifying the signature."
        case .readyToInstall(let item): return "Version \(item.version.displayFull) is verified and ready to install."
        case .installing(let item): return "Installing version \(item.version.displayFull)."
        case .failed(let reason): return failure(reason)
        }
    }

    private static func failure(_ reason: UpdateFailureReason) -> String {
        switch reason {
        case .network: return "The update feed could not be reached."
        case .signature: return "The signature check failed. Nothing was installed."
        case .downgrade: return "That version is not newer. Nothing was installed."
        case .insecureFeed: return "The feed is not a secure address. Nothing was downloaded."
        case .unreadable: return "The update feed could not be read."
        case .installRefused: return "The update was not installed."
        case .installFailed: return "Install did not finish. This copy was left in place."
        }
    }

    private static func offered(_ state: UpdateSessionState) -> UpdateCandidate? {
        switch state {
        case .available(let item), .downloading(let item), .verifying(let item), .readyToInstall(let item), .installing(let item):
            return item
        default:
            return nil
        }
    }

    private static func isBusy(_ state: UpdateSessionState) -> Bool {
        switch state {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    private static func isAvailable(_ state: UpdateSessionState) -> Bool {
        if case .available = state { return true }
        return false
    }

    private static func isReady(_ state: UpdateSessionState) -> Bool {
        if case .readyToInstall = state { return true }
        return false
    }
}
