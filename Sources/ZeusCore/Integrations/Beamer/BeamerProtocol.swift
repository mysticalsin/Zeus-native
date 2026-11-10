import Foundation

// What Zeus knows about Beamer (uk.co.kalkman.beamer 1.5.18), read from the signed app on 2026-11-02.
// See docs/BEAMER.md. Beamer is a keyboard-and-mouse sharing app for Mac, Windows, Linux, iPhone and
// Android. It is not Apple Universal Control and it has no iPad role. Its only outside door is a
// Unix socket that opens its window; everything else is its menu bar menu.

/// Where Beamer keeps things on this Mac.
public enum BeamerFiles {
    public static let bundleID = "uk.co.kalkman.beamer"
    public static let appPath = "/Applications/Beamer.app"
    public static let version = "1.5.18"

    public static func support(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Beamer", isDirectory: true)
    }
    /// `instance_socket_path()`: any line that starts with `activate` opens Beamer's window.
    public static func socket(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL { support(home: home).appendingPathComponent("Beamer.sock") }
    public static func settings(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL { support(home: home).appendingPathComponent("settings.json") }
    public static func log(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Logs/Beamer/Beamer.log")
    }
}

/// The one message Beamer's instance socket understands: `activate\n`. The server reads one line and
/// calls its "open the window" callback, whatever the line says; the client sends this exact text.
public enum BeamerMessage {
    /// What goes on the wire.
    public static let activateLine = "activate\n"
    /// `UnixSocket.request` adds the newline itself, so the payload is the word alone.
    public static let activate = Data("activate".utf8)
}

/// The kinds of machine Beamer pairs with (`machines.platform_name`). There is no iPad.
public enum BeamerPlatform: String, Equatable, Sendable {
    case windows, mac, linux, iphone, android, other

    public init(wire: String) { self = BeamerPlatform(rawValue: wire.lowercased()) ?? .other }

    public var title: String {
        switch self {
        case .windows: "Windows"
        case .mac: "Mac"
        case .linux: "Linux"
        case .iphone: "iPhone"
        case .android: "Android"
        case .other: "Other"
        }
    }
    public var symbol: String {
        switch self {
        case .windows, .linux: "pc"
        case .mac: "laptopcomputer"
        case .iphone, .android: "iphone"
        case .other: "display"
        }
    }
}

/// One paired machine from `settings.json` `peers[]`. The pairing token is never read.
public struct BeamerMachine: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var platform: BeamerPlatform
    public var host: String
    public var port: Int
    /// `in_use`: false means "NOT IN USE on this Mac" (the user left it out).
    public var inUse: Bool
    /// `send`: this Mac may send its keyboard and pointer to the machine.
    public var canReceive: Bool
    /// `allow_drive`: the machine may drive this Mac.
    public var canDrive: Bool

    public init(id: String, name: String, platform: BeamerPlatform, host: String = "", port: Int = 0, inUse: Bool = true, canReceive: Bool = true, canDrive: Bool = false) {
        self.id = id; self.name = name; self.platform = platform; self.host = host; self.port = port
        self.inUse = inUse; self.canReceive = canReceive; self.canDrive = canDrive
    }
}

public enum BeamerSettingsFile {
    private struct Root: Decodable { var peers: [Peer]? }
    private struct Peer: Decodable {
        var id: String?
        var name: String?
        var platform: String?
        var host: String?
        var port: Int?
        var in_use: Bool?
        var send: Bool?
        var allow_drive: Bool?
    }

    /// The paired machines. Tokens, hardware addresses and the crossing layout are ignored on purpose.
    public static func machines(from data: Data) -> [BeamerMachine] {
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
        return (root.peers ?? []).enumerated().map { index, peer in
            BeamerMachine(id: peer.id.flatMap { $0.isEmpty ? nil : $0 } ?? "peer-\(index)",
                          name: (peer.name?.isEmpty == false ? peer.name : nil) ?? peer.host ?? "Machine \(index + 1)",
                          platform: BeamerPlatform(wire: peer.platform ?? ""), host: peer.host ?? "", port: peer.port ?? 0,
                          inUse: peer.in_use ?? true, canReceive: peer.send ?? true, canDrive: peer.allow_drive ?? false)
        }
    }
}

/// Where input is, as the tray menu's status line says it (`TrayApp._drive_status`).
public enum BeamerLink: Equatable, Sendable {
    case idle
    /// "Driving <name>": this Mac's keyboard and pointer are on that machine.
    case driving(String)
    /// "Driven by <name>": that machine's keyboard and pointer are on this Mac.
    case drivenBy(String)

    public var summary: String {
        switch self {
        case .idle: "Idle: input is on this Mac"
        case .driving(let name): "Your keyboard and mouse are on \(name)"
        case .drivenBy(let name): "\(name) is driving this Mac"
        }
    }
    public var machine: String? {
        switch self {
        case .idle: nil
        case .driving(let name), .drivenBy(let name): name
        }
    }
}

/// What the tray menu shows right now. The menu is the only live status Beamer has: its titles are
/// `Beamer <version>`, the drive status, `Send input` / `Send input to <name>` / `Return input to Mac`,
/// `Pause crossing` or `Resume crossing`, then the toggles and `Settings…`.
public struct BeamerMenuState: Equatable, Sendable {
    public var version: String?
    public var link: BeamerLink
    /// nil when the menu has neither pause title.
    public var paused: Bool?
    /// Machines named by `Send input to <name>` items.
    public var targets: [String]
    public var canSend: Bool

    public static func parse(titles raw: [String]) -> BeamerMenuState {
        let titles = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "missing value" }
        var state = BeamerMenuState(version: nil, link: .idle, paused: nil, targets: [], canSend: false)
        for title in titles {
            if title.hasPrefix("Beamer "), state.version == nil, let first = title.split(separator: " ").dropFirst().first, first.first?.isNumber == true {
                state.version = String(first)
            } else if title.hasPrefix("Driving ") {
                state.link = .driving(String(title.dropFirst("Driving ".count)))
            } else if title.hasPrefix("Driven by ") {
                state.link = .drivenBy(String(title.dropFirst("Driven by ".count)))
            } else if title == "Pause crossing" {
                state.paused = false
            } else if title == "Resume crossing" {
                state.paused = true
            } else if title.hasPrefix("Send input to ") {
                state.targets.append(String(title.dropFirst("Send input to ".count)))
                state.canSend = true
            } else if title == "Send input" {
                state.canSend = true
            }
        }
        return state
    }
}

/// Why Zeus can or cannot talk to Beamer right now.
public enum BeamerAvailability: Equatable, Sendable {
    case notInstalled
    case notRunning
    /// Running, but reading its menu needs Accessibility (and Automation of System Events).
    case needsPermission
    case ready
}

/// Everything the Settings page, the Continuity tab and the voice commands read.
public struct BeamerStatus: Equatable, Sendable {
    public var availability: BeamerAvailability
    public var version: String?
    public var machines: [BeamerMachine]
    public var link: BeamerLink
    public var paused: Bool?

    public static let missing = BeamerStatus(availability: .notInstalled, version: nil, machines: [], link: .idle, paused: nil)

    public var isRunning: Bool { availability == .needsPermission || availability == .ready }
    /// Input is on another machine, or another machine is driving this one.
    public var isCrossed: Bool { link != .idle }
    public var inUse: [BeamerMachine] { machines.filter(\.inUse) }

    /// One line for a subtitle.
    public var headline: String {
        switch availability {
        case .notInstalled: "Beamer is not installed"
        case .notRunning: machines.isEmpty ? "Beamer is not running" : "Beamer is not running · \(machines.count) paired"
        case .needsPermission: "Running · allow Accessibility to see where input is"
        case .ready: paused == true ? "Crossing is paused" : link.summary
        }
    }
}

/// A request Zeus can make of Beamer.
public enum BeamerCommand: Equatable, Sendable {
    case start
    case showWindow
    case pause
    case resume
    case switchTo(String)
    case returnHome
}

/// Spoken or typed names matched to paired machines.
public enum BeamerMatching {
    /// "iPad", "my ipad" and "Tony's iPad" all name the same machine; names compare without case,
    /// punctuation, "my" or "the".
    public static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}s", with: "").replacingOccurrences(of: "'s", with: "")
        let words = folded.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.filter { !["my", "the", "a"].contains($0) }.joined(separator: " ")
    }

    public static func machine(named spoken: String, in names: [String]) -> String? {
        let want = normalise(spoken)
        guard !want.isEmpty else { return nil }
        if let exact = names.first(where: { normalise($0) == want }) { return exact }
        let close = names.filter { normalise($0).contains(want) || want.contains(normalise($0)) }
        return close.count == 1 ? close[0] : nil
    }

    /// Beamer pairs Windows, Mac, Linux, iPhone and Android machines. An iPad is Apple's Universal
    /// Control, which no app can drive.
    public static func isIPad(_ spoken: String) -> Bool { normalise(spoken).contains("ipad") }
}

/// AppleScript text for the menu bar menu (System Events). Needs Accessibility, and macOS asks once
/// for Automation of System Events. Titles go in through `quoted`, never raw.
public enum BeamerScripts {
    public static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static let menu = "menu 1 of menu bar item 1 of menu bar 2 of process \"Beamer\""

    /// The titles of every item in the tray menu, one per line.
    public static let menuTitles = """
    tell application "System Events"
        set found to name of every menu item of \(menu)
        set output to ""
        repeat with t in found
            set output to output & (t as text) & linefeed
        end repeat
        return output
    end tell
    """

    public static func click(title: String) -> String {
        """
        tell application "System Events"
            click menu item \(quoted(title)) of \(menu)
        end tell
        """
    }

    /// Menu item titles from `menuTitles` output.
    public static func titles(fromOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { String($0) }
    }
}
