import Foundation

/// One transcript: a session's, or a Zeus conversation's. A caller that has both uses two stores.
/// The machine is pure. The store writes only into the directory it was given.
public struct HubTranscript: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var status: HubTranscriptStatus
    public var lines: [HubTranscriptLine]

    public init(id: UUID = UUID(), status: HubTranscriptStatus = .idle, lines: [HubTranscriptLine] = []) {
        self.id = id
        self.status = status
        self.lines = lines
    }

    public var isEmpty: Bool {
        !lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// A stored line. `failed` is set for a turn that did not produce an answer. That line is plain text.
public struct HubTranscriptLine: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var role: HubLineRole
    public var text: String
    public var failed: Bool

    public init(id: UUID = UUID(), role: HubLineRole, text: String, failed: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.failed = failed
    }
}

/// What one event did. `writes` is false for a delta and for any pair the target table does not save.
public struct HubTranscriptEffect: Equatable, Sendable {
    public var transcript: HubTranscript
    public var writes: Bool

    public init(transcript: HubTranscript, writes: Bool) {
        self.transcript = transcript
        self.writes = writes
    }
}

/// How a line is drawn. A failed line is the plain string. An agent line is the existing markdown blocks.
public enum HubTranscriptPresentation: Equatable, Sendable {
    case plain(String)
    case markdown([MarkdownBlock])
}

public enum HubTranscriptRendering {
    public static func render(_ line: HubTranscriptLine) -> HubTranscriptPresentation {
        if line.failed || line.role != .agent {
            return .plain(line.text)
        }
        return .markdown(MarkdownBlock.parse(line.text))
    }
}

/// The transcript table in the target. A pair that is not in the table leaves the transcript as it was.
public enum HubTranscriptMachine {
    public static func reduce(
        _ transcript: HubTranscript,
        _ event: HubTranscriptEvent,
        text: String = "",
        lineID: UUID = UUID()
    ) -> HubTranscriptEffect {
        switch (transcript.status, event) {
        case (.idle, .send), (.settled, .send), (.failed, .send):
            return send(transcript, text: text, lineID: lineID)
        case (.streaming, .delta):
            return delta(transcript, text: text, lineID: lineID)
        case (.streaming, .finish):
            return finish(transcript, text: text, lineID: lineID)
        case (.streaming, .finishEmpty):
            return fail(transcript, text: HubTranscriptNotice.noAnswer.storedLabel, lineID: lineID)
        case (.streaming, .stop):
            return stop(transcript, lineID: lineID)
        case (.streaming, .failure):
            return fail(transcript, text: text, lineID: lineID)
        default:
            return HubTranscriptEffect(transcript: transcript, writes: false)
        }
    }

    private static func send(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return HubTranscriptEffect(transcript: transcript, writes: false) }
        var next = transcript
        next.status = .streaming
        next.lines.append(HubTranscriptLine(id: lineID, role: .person, text: spoken))
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    /// The text replaces the open agent line. It is not appended, and it is not written.
    private static func delta(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        var next = transcript
        next.lines = replaceOpenLine(in: next.lines, id: lineID, role: .agent, text: text, failed: false)
        return HubTranscriptEffect(transcript: next, writes: false)
    }

    private static func finish(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = transcript
        if !spoken.isEmpty {
            next.status = .settled
            next.lines = replaceOpenLine(in: next.lines, id: lineID, role: .agent, text: spoken, failed: false)
            return HubTranscriptEffect(transcript: next, writes: true)
        }
        guard let open = openAgentLine(in: transcript.lines),
              !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HubTranscriptEffect(transcript: transcript, writes: false)
        }
        next.status = .settled
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    private static func stop(_ transcript: HubTranscript, lineID: UUID) -> HubTranscriptEffect {
        var next = transcript
        next.status = .settled
        if let open = openAgentLine(in: transcript.lines),
           !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HubTranscriptEffect(transcript: next, writes: true)
        }
        next.lines = replaceOpenLine(
            in: next.lines,
            id: lineID,
            role: .stopped,
            text: HubTranscriptNotice.stopped.storedLabel,
            failed: false
        )
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    private static func fail(_ transcript: HubTranscript, text: String, lineID: UUID) -> HubTranscriptEffect {
        var next = transcript
        next.status = .failed
        next.lines = replaceOpenLine(in: next.lines, id: lineID, role: .failed, text: text, failed: true)
        return HubTranscriptEffect(transcript: next, writes: true)
    }

    /// The open line is the last line, and only while it is still an agent line.
    private static func openAgentLine(in lines: [HubTranscriptLine]) -> HubTranscriptLine? {
        guard let last = lines.last, last.role == .agent, !last.failed else { return nil }
        return last
    }

    private static func replaceOpenLine(
        in lines: [HubTranscriptLine],
        id: UUID,
        role: HubLineRole,
        text: String,
        failed: Bool
    ) -> [HubTranscriptLine] {
        var lines = lines
        if let index = lines.indices.last, lines[index].role == .agent, !lines[index].failed {
            lines[index].role = role
            lines[index].text = text
            lines[index].failed = failed
            return lines
        }
        lines.append(HubTranscriptLine(id: id, role: role, text: text, failed: failed))
        return lines
    }
}

/// Applies the machine and writes only when the effect says to. A delta leaves the directory untouched.
public enum HubTranscriptDriver {
    public static func apply(
        _ transcript: inout HubTranscript,
        _ event: HubTranscriptEvent,
        text: String = "",
        store: HubTranscriptStore,
        lineID: UUID = UUID()
    ) throws {
        let effect = HubTranscriptMachine.reduce(transcript, event, text: text, lineID: lineID)
        transcript = effect.transcript
        if effect.writes {
            try store.write(transcript)
        }
    }
}

/// One JSON file per transcript, under a directory the caller supplies. An empty transcript is not written.
public struct HubTranscriptStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func write(_ transcript: HubTranscript) throws {
        guard !transcript.isEmpty else { return }
        var copy = transcript
        let kept = HubTranscriptBudget.keptLines(copy.lines.count)
        if copy.lines.count > kept {
            copy.lines.removeFirst(copy.lines.count - kept)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder().encode(copy).write(to: url(for: transcript.id), options: .atomic)
    }

    /// A missing file is nil. A second store on the same directory reads what an earlier one wrote.
    public func load(_ id: UUID) -> HubTranscript? {
        guard let data = try? Data(contentsOf: url(for: id)),
              let transcript = try? Self.decoder().decode(HubTranscript.self, from: data),
              transcript.id == id else { return nil }
        return transcript
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func encoder() -> JSONEncoder { storedEncoder }

    private static let storedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = HubTranscriptBudget.prettyPrinted
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        return encoder
    }()

    private static func decoder() -> JSONDecoder { JSONDecoder() }
}
