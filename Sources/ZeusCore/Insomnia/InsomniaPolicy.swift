import Foundation

/// Which apps a lid-closed session may freeze (SIGSTOP). Zeus, terminals, editors that host
/// agents and the agents themselves are never frozen, nor are the parts of macOS you need.
public enum InsomniaFreezePolicy {
    public static let protectedBundleIDs: Set<String> = [
        ZeusPaths.bundleIdentifier,
        // Terminals
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "io.alacritty", "org.alacritty", "co.zeit.hyper",
        "com.github.wez.wezterm", "org.tabby", "com.raphaelamorim.rio",
        // Editors and agent apps
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "dev.zed.Zed", "com.apple.dt.Xcode",
        "com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.chat",
        // macOS
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter",
        "com.apple.loginwindow", "com.apple.WindowManager", "com.apple.Spotlight", "com.apple.notificationcenterui",
        "com.apple.ActivityMonitor", "com.apple.systempreferences",
    ]

    /// Agent CLI process names; a process with one of these names is never frozen.
    public static let agentProcessNames: Set<String> = ["claude", "codex", "gemini", "cursor-agent", "node", "tmux", "zeus", "Zeus"]

    public static func isProtected(bundleID: String) -> Bool {
        protectedBundleIDs.contains(bundleID) || bundleID.hasPrefix("app.zeus.")
    }

    public struct RunningProcess: Equatable, Sendable {
        public var pid: Int32
        public var bundleID: String
        public var name: String

        public init(pid: Int32, bundleID: String, name: String) {
            self.pid = pid
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// The running processes to freeze: listed by Tony, not protected, not Zeus, not an agent.
    public static func targets(listed: [String], running: [RunningProcess], zeusPID: Int32) -> [RunningProcess] {
        let wanted = Set(listed).subtracting(protectedBundleIDs)
        return running.filter { process in
            process.pid > 1 && process.pid != zeusPID
                && wanted.contains(process.bundleID) && !isProtected(bundleID: process.bundleID)
                && !agentProcessNames.contains(process.name)
        }
    }
}

/// The session length Tony types into the Insomnia tab: hours and minutes, or a clock time to
/// stay awake until. Nil minutes is Indefinitely.
public struct InsomniaDuration: Equatable, Sendable {
    public static let maxHours = 72
    /// Quick chips; nil is ∞.
    public static let chips: [Int?] = [30, 60, 120, 240, 480, nil]

    public var hours: Int
    public var minutes: Int
    public var indefinite: Bool

    public init(hours: Int = 0, minutes: Int = 30, indefinite: Bool = false) {
        self.hours = 0
        self.minutes = 0
        self.indefinite = indefinite
        set(totalMinutes: hours * 60 + minutes)
    }

    /// Nil when Indefinitely; never under one minute otherwise.
    public var totalMinutes: Int? { indefinite ? nil : max(1, hours * 60 + minutes) }

    public mutating func set(totalMinutes: Int) {
        let total = min(max(0, totalMinutes), Self.maxHours * 60)
        hours = total / 60
        minutes = total % 60
    }

    /// A chip fills the fields (∞ switches to Indefinitely).
    public mutating func apply(chip: Int?) {
        if let chip { indefinite = false; set(totalMinutes: chip) } else { indefinite = true }
    }

    /// Arrow keys and steppers: hours by 1, minutes by 5, carrying into hours.
    public mutating func step(hours delta: Int) {
        indefinite = false
        set(totalMinutes: hours * 60 + minutes + delta * 60)
    }

    public mutating func step(minutes delta: Int) {
        indefinite = false
        set(totalMinutes: hours * 60 + minutes + delta)
    }

    /// Typed text: digits only, the rest dropped. Minutes over 59 carry into hours.
    public mutating func type(hours text: String) {
        indefinite = false
        set(totalMinutes: Self.digits(text) * 60 + minutes)
    }

    public mutating func type(minutes text: String) {
        indefinite = false
        set(totalMinutes: hours * 60 + Self.digits(text))
    }

    /// Minutes from `now` until the next `hour:minute` on the clock (tomorrow if it has passed).
    public static func minutes(until hour: Int, _ minute: Int, from now: Date, calendar: Calendar = .current) -> Int {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = min(max(hour, 0), 23)
        parts.minute = min(max(minute, 0), 59)
        guard var target = calendar.date(from: parts) else { return 0 }
        if target <= now { target = calendar.date(byAdding: .day, value: 1, to: target) ?? target }
        return Int((target.timeIntervalSince(now) / 60).rounded(.up))
    }

    /// "23:30", "7:05": a clock time, or nil.
    public static func parseClock(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute), parts[1].count == 2 else { return nil }
        return (hour, minute)
    }

    /// "2 h 30 m", "45 m", "∞".
    public var label: String {
        guard let total = totalMinutes else { return "∞" }
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }

    public static func chipLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "∞" }
        return minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) m"
    }

    private static func digits(_ text: String) -> Int {
        Int(String(text.filter(\.isASCII).filter(\.isNumber).prefix(4))) ?? 0
    }
}
