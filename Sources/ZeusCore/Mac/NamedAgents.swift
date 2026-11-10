import Foundation

/// A named helper with its own persona and memory ("ask Scout to...", "Scribe, draft...").
public struct AgentProfile: Codable, Equatable, Sendable {
    public var name: String
    public var role: String
    public var instructions: String

    public init(name: String, role: String, instructions: String) {
        self.name = name
        self.role = role
        self.instructions = instructions
    }

    public var slug: String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static let builtIn: [AgentProfile] = [
        AgentProfile(name: "Scout", role: "research",
                     instructions: "You research. Answer with facts first, then the source or where to look. Short."),
        AgentProfile(name: "Scribe", role: "writing",
                     instructions: "You write and edit. Match the user's voice, plain words, no filler, never sign as an AI."),
        AgentProfile(name: "Pilot", role: "driving the Mac",
                     instructions: "You operate Mac apps. Prefer a mac.drive plan or a mac.walkthrough over long explanations."),
    ]
}

/// What one agent remembers: short notes, newest last, capped so prompts stay small.
public struct AgentMemory: Codable, Equatable, Sendable {
    public struct Note: Codable, Equatable, Sendable {
        public var date: Date
        public var text: String
        public var pinned: Bool
    }

    public static let maxNotes = 200
    public static let promptNotes = 12

    public var notes: [Note] = []

    public init(notes: [Note] = []) { self.notes = notes }

    /// Adds a note; old unpinned notes fall off first.
    public mutating func remember(_ text: String, pinned: Bool = false, at date: Date = Date()) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        notes.append(Note(date: date, text: String(clean.prefix(400)), pinned: pinned))
        while notes.count > Self.maxNotes {
            if let old = notes.firstIndex(where: { !$0.pinned }) { notes.remove(at: old) } else { notes.removeFirst() }
        }
    }

    /// Pinned facts plus the latest notes, for the system prompt.
    public var promptBlock: String {
        let pinned = notes.filter(\.pinned)
        let recent = notes.filter { !$0.pinned }.suffix(Self.promptNotes)
        let lines = (pinned + recent).map { "- " + $0.text }
        return lines.isEmpty ? "" : "What you remember:\n" + lines.joined(separator: "\n")
    }
}

/// Reads and writes agents and their memory under `<support>/agents/`. A user file
/// `agents.json` (array of profiles) adds or overrides agents by name.
public struct AgentStore: Sendable {
    public let root: URL

    public init(root: URL = ZeusPaths.supportDirectory.appendingPathComponent("agents", isDirectory: true)) {
        self.root = root
    }

    public func profiles() -> [AgentProfile] {
        var byName = Dictionary(AgentProfile.builtIn.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        if let data = try? Data(contentsOf: root.appendingPathComponent("agents.json")),
           let custom = try? JSONDecoder().decode([AgentProfile].self, from: data) {
            for profile in custom where !profile.slug.isEmpty { byName[profile.slug] = profile }
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    public func memory(for agent: AgentProfile) -> AgentMemory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file(agent)),
              let memory = try? decoder.decode(AgentMemory.self, from: data) else { return AgentMemory() }
        return memory
    }

    public func save(_ memory: AgentMemory, for agent: AgentProfile) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(memory).write(to: file(agent), options: [.atomic])
    }

    func file(_ agent: AgentProfile) -> URL { root.appendingPathComponent("\(agent.slug).memory.json") }
}

/// Finds which agent a turn is for: "ask Scout ...", "hey Scribe, ...", "Pilot: ...".
public enum AgentRouter {
    public struct Route: Equatable, Sendable {
        public var agent: AgentProfile
        public var request: String
        /// "remember that ..." / "remember ...": stored as a pinned note, no model call needed.
        public var remember: String?
    }

    public static func route(_ transcript: String, agents: [AgentProfile]) -> Route? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        for agent in agents {
            let name = agent.name.lowercased()
            for lead in ["ask \(name) to ", "ask \(name) ", "hey \(name), ", "hey \(name) ", "\(name), ", "\(name): "] {
                guard lower.hasPrefix(lead) else { continue }
                let rest = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
                guard !rest.isEmpty else { return nil }
                let restLower = rest.lowercased()
                for cue in ["remember that ", "remember "] where restLower.hasPrefix(cue) {
                    return Route(agent: agent, request: rest, remember: String(rest.dropFirst(cue.count)))
                }
                return Route(agent: agent, request: rest, remember: nil)
            }
        }
        return nil
    }

    /// The system prompt addition for a routed turn.
    public static func preamble(_ agent: AgentProfile, memory: AgentMemory) -> String {
        var lines = ["You are \(agent.name), ZEUS's \(agent.role) agent. \(agent.instructions)"]
        let block = memory.promptBlock
        if !block.isEmpty { lines.append(block) }
        return lines.joined(separator: "\n")
    }
}
