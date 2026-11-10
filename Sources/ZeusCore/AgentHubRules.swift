import CoreGraphics
import Foundation

// MARK: Notification peek

/// When a mirrored notification from another app gets the slim line under the notch.
public enum NotificationPeekRules {
    public static let visibleSeconds: TimeInterval = 4
    /// A notification older than this was already seen in Notification Center; no peek.
    public static let freshSeconds: TimeInterval = 30

    /// "com.a.b, com.c.d" or one per line → lower-cased ids. Compared case-insensitively.
    public static func mutedSet(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    public static func mutedText(_ ids: Set<String>) -> String { ids.sorted().joined(separator: ",") }

    public static func isMuted(_ app: String, muted: Set<String>) -> Bool { muted.contains(app.lowercased()) }

    public struct Context: Sendable {
        public var lastSeenID: Int64?
        public var muted: Set<String>
        public var ownBundleID: String
        /// A card (approval, completion, failure) or the open panel already holds the notch.
        public var notchBusy: Bool
        /// Full-screen quiet, meeting mode or screen sharing.
        public var quiet: Bool

        public init(lastSeenID: Int64?, muted: Set<String>, ownBundleID: String, notchBusy: Bool, quiet: Bool) {
            self.lastSeenID = lastSeenID; self.muted = muted; self.ownBundleID = ownBundleID
            self.notchBusy = notchBusy; self.quiet = quiet
        }
    }

    /// The notification to peek, or nil. Items are newest first. The first run (no `lastSeenID`)
    /// only records the baseline, so old notifications never flash.
    public static func next(from items: [MirroredNotification], now: Date, context: Context) -> MirroredNotification? {
        guard let lastSeen = context.lastSeenID, !context.notchBusy, !context.quiet else { return nil }
        return items.first { item in
            item.id > lastSeen
                && now.timeIntervalSince(item.date) <= freshSeconds
                && !isMuted(item.app, muted: context.muted)
                && item.app.lowercased() != context.ownBundleID.lowercased()
        }
    }

    /// The newest id, to advance the baseline even when nothing is shown.
    public static func newestID(_ items: [MirroredNotification]) -> Int64? { items.map(\.id).max() }

    /// The line's two texts. With details off only the app is named.
    public static func line(for item: MirroredNotification, appName: String, showDetails: Bool) -> (title: String, detail: String) {
        guard showDetails else { return (appName, "New notification") }
        let title = item.title.isEmpty ? appName : item.title
        let body = [item.subtitle, item.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return (title, body.isEmpty && !item.title.isEmpty ? appName : body)
    }
}

// MARK: Keyboard agent picker

/// ↑↓ pick, Return opens the session's terminal, Esc closes. Pure, so the key table is tested.
public struct AgentPicker: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case up, down, open, close }

    public var count: Int
    public private(set) var index: Int

    public init(count: Int, index: Int = 0) {
        self.count = count
        self.index = count > 0 ? min(max(index, 0), count - 1) : 0
    }

    /// macOS virtual key codes: 126 up, 125 down, 36 and 76 return and enter, 53 escape.
    public static func action(forKeyCode code: UInt16) -> Action? {
        switch code {
        case 126: .up
        case 125: .down
        case 36, 76: .open
        case 53: .close
        default: nil
        }
    }

    /// Up and down wrap around. Returns the action when the caller must open or close.
    @discardableResult
    public mutating func apply(_ action: Action) -> Action? {
        switch action {
        case .up: if count > 0 { index = (index - 1 + count) % count }; return nil
        case .down: if count > 0 { index = (index + 1) % count }; return nil
        case .open: return count > 0 ? .open : .close
        case .close: return .close
        }
    }

    /// The list changed under the picker (a session ended): keep the index in range.
    public mutating func resize(_ newCount: Int) {
        count = newCount
        index = newCount > 0 ? min(index, newCount - 1) : 0
    }
}

// MARK: Displays

public enum NotchDisplayMode: String, CaseIterable, Sendable {
    case builtIn = "Built-in display"
    case pointer = "Display with the pointer"
    case all = "All displays"

    public static let `default` = NotchDisplayMode.builtIn

    public init(label: String) { self = NotchDisplayMode(rawValue: label) ?? .builtIn }
}

/// One screen as the selection logic sees it.
public struct DisplayDescriptor: Equatable, Sendable {
    public var id: Int
    public var frame: CGRect
    public var hasNotch: Bool
    public var isBuiltIn: Bool

    public init(id: Int, frame: CGRect, hasNotch: Bool, isBuiltIn: Bool) {
        self.id = id; self.frame = frame; self.hasNotch = hasNotch; self.isBuiltIn = isBuiltIn
    }
}

public enum DisplaySelection {
    /// The screens that show the notch, in order. Never empty while any screen exists.
    /// Built-in: the notched screen, else the built-in panel, else the first screen.
    /// Pointer: the screen holding the pointer, else as built-in. All: every screen.
    public static func targets(mode: NotchDisplayMode, screens: [DisplayDescriptor], pointer: CGPoint) -> [DisplayDescriptor] {
        guard !screens.isEmpty else { return [] }
        let builtIn = screens.first { $0.hasNotch } ?? screens.first { $0.isBuiltIn } ?? screens[0]
        switch mode {
        case .builtIn: return [builtIn]
        case .pointer: return [screens.first { $0.frame.contains(pointer) } ?? builtIn]
        case .all: return [builtIn] + screens.filter { $0.id != builtIn.id }
        }
    }

    /// Whether the windows must be rebuilt: the set of target screens or any frame changed.
    public static func needsRebuild(current: [DisplayDescriptor], next: [DisplayDescriptor]) -> Bool { current != next }

    /// Screens without a notch get a slim pill when closed and idle.
    public static func showsPill(_ display: DisplayDescriptor) -> Bool { !display.hasNotch }
}

// MARK: Trusted chats

/// "Allow this whole chat": per-session auto-approve that never covers risky commands.
/// Held in memory only, so every trust ends when ZEUS quits.
public struct TrustedChats: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public var id: String
        public var agent: String
        public var project: String
        public var since: Date

        public init(id: String, agent: String, project: String, since: Date) {
            self.id = id; self.agent = agent; self.project = project; self.since = since
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public func isTrusted(_ session: String) -> Bool { entries.contains { $0.id == session } }

    public mutating func trust(_ session: String, agent: String, project: String, at date: Date = Date()) {
        guard !isTrusted(session) else { return }
        entries.append(Entry(id: session, agent: agent, project: project, since: date))
    }

    public mutating func revoke(_ session: String) { entries.removeAll { $0.id == session } }
    public mutating func clear() { entries.removeAll() }

    /// Tools that need a person: plans and questions.
    static let humanTools: Set<String> = ["ExitPlanMode", "AskUserQuestion"]

    /// Whether a request in this session may be approved without a card. Risky ones always ask:
    /// anything the hook marked high risk, and shell commands that delete, overwrite or reach the network.
    public func autoApproves(session: String?, tool: String?, input: JSONValue?, risk: HookEvent.Risk?) -> Bool {
        guard let session, isTrusted(session) else { return false }
        if risk == .high { return false }
        if let tool, Self.humanTools.contains(tool) { return false }
        if tool == "Bash" {
            guard let command = input?["command"]?.stringValue else { return false }
            let assessment = ShellRiskClassifier.assess(command)
            return assessment.risk < .network
        }
        return true
    }

    /// Whether the card may offer "Allow this whole chat" for this request.
    public static func canOffer(tool: String?, input: JSONValue?, risk: HookEvent.Risk?) -> Bool {
        var probe = TrustedChats()
        probe.trust("probe", agent: "", project: "")
        return probe.autoApproves(session: "probe", tool: tool, input: input, risk: risk)
    }
}
