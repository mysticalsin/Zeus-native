import Foundation

/// One look at a tmux pane: what runs in it and a hash of what it shows.
public struct TmuxPaneSnapshot: Equatable, Sendable {
    public var paneID: String
    public var command: String
    public var contentHash: UInt64
    public var time: Date

    public init(paneID: String, command: String, contentHash: UInt64, time: Date) {
        self.paneID = paneID
        self.command = command
        self.contentHash = contentHash
        self.time = time
    }
}

/// Finds agent panes whose screen has not changed for `stallAfter`, and says which to nudge.
/// Only agent CLIs qualify, never a plain shell, and a pane is nudged at most once per stall:
/// it can be nudged again only after its screen changed and then stalled again.
public struct TmuxStallDetector: Sendable {
    /// `pane_current_command` values that are agents.
    public static let agentCommands: Set<String> = ["claude", "codex", "gemini", "cursor-agent", "node"]

    public var stallAfter: TimeInterval
    private var lastChange: [String: (hash: UInt64, since: Date)] = [:]
    private var nudged: Set<String> = []

    public init(stallAfter: TimeInterval) {
        self.stallAfter = stallAfter
    }

    public static func qualifies(_ command: String) -> Bool {
        let name = (command as NSString).lastPathComponent.lowercased()
        return agentCommands.contains(name)
    }

    /// Feed one round of snapshots; returns the pane ids to nudge now, in input order.
    /// Panes that are gone or no longer run an agent are forgotten.
    public mutating func observe(_ snapshots: [TmuxPaneSnapshot]) -> [String] {
        var seen = Set<String>()
        var nudge: [String] = []
        for snapshot in snapshots where Self.qualifies(snapshot.command) {
            let id = snapshot.paneID
            seen.insert(id)
            guard let last = lastChange[id], last.hash == snapshot.contentHash else {
                lastChange[id] = (snapshot.contentHash, snapshot.time)
                nudged.remove(id)
                continue
            }
            if snapshot.time.timeIntervalSince(last.since) >= stallAfter, !nudged.contains(id) {
                nudged.insert(id)
                nudge.append(id)
            }
        }
        lastChange = lastChange.filter { seen.contains($0.key) }
        nudged.formIntersection(seen)
        return nudge
    }
}

/// tmux command lines and what they print.
public enum TmuxCommands {
    public static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    public static let listFormat = "#{pane_id}\t#{pane_current_command}\t#{pane_dead}\t#{pane_in_mode}"

    public static var listPanes: [String] { ["list-panes", "-a", "-F", listFormat] }
    public static func capture(_ pane: String) -> [String] { ["capture-pane", "-p", "-t", pane] }
    /// `continue` typed literally, then Enter as its own key, so it is not read as a paste.
    public static func typeContinue(_ pane: String) -> [String] { ["send-keys", "-t", pane, "-l", "continue"] }
    public static func pressEnter(_ pane: String) -> [String] { ["send-keys", "-t", pane, "Enter"] }

    public struct Pane: Equatable, Sendable {
        public var id: String
        public var command: String
    }

    /// Live panes from `list-panes`: dead panes and panes in copy mode are skipped (keys would not
    /// reach the program).
    public static func parsePanes(_ output: String) -> [Pane] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, fields[0].hasPrefix("%"), fields[2] == "0", fields[3] == "0" else { return nil }
            return Pane(id: fields[0], command: fields[1])
        }
    }

    /// FNV-1a, stable across launches (Swift's Hasher is seeded per process).
    public static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
        return value
    }
}
