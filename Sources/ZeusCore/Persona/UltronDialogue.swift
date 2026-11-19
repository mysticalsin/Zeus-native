import Foundation

/// The versioned dialogue asset (ultron_dialogue.json): original generated lines grouped by situation tag.
/// Nothing in it comes from a film, show or comic, so a file with canonical or transcript keys is refused.
public struct UltronDialogue: Sendable {
    public enum Humour: String, Sendable, CaseIterable, Comparable {
        case none, low, moderate, high

        private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
        public static func < (lhs: Humour, rhs: Humour) -> Bool { lhs.rank < rhs.rank }
    }

    public struct Line: Equatable, Sendable {
        public let id: String
        public let text: String
        public let situations: [String]
        public let humour: Humour

        public init(id: String, text: String, situations: [String], humour: Humour) {
            self.id = id
            self.text = text
            self.situations = situations
            self.humour = humour
        }

        /// An "Ah" or "Interesting" opener: the pair the personality must not lean on.
        var isHeavyOpener: Bool {
            let first = text.split(separator: " ").first.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            return first == "ah" || first == "interesting"
        }
    }

    public let version: Int
    public let lines: [Line]

    public init(version: Int, lines: [Line]) {
        self.version = version
        self.lines = lines
    }

    /// Reads the asset. Nil for anything malformed, for an unknown humour level and for a file with
    /// canonical or transcript content.
    public static func decode(_ data: Data) -> UltronDialogue? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = object["version"] as? Int,
              let entries = object["generated_lines"] as? [[String: Any]],
              object.keys.allSatisfy({ !$0.lowercased().contains("canonical") && !$0.lowercased().contains("transcript") })
        else { return nil }
        var lines: [Line] = []
        for entry in entries {
            guard let id = entry["id"] as? String, let text = entry["text"] as? String, !id.isEmpty, !text.isEmpty,
                  let situations = entry["situations"] as? [String], !situations.isEmpty,
                  let humourName = entry["humour"] as? String, let humour = Humour(rawValue: humourName) else { return nil }
            lines.append(Line(id: id, text: text, situations: situations, humour: humour))
        }
        return UltronDialogue(version: version, lines: lines)
    }

    /// The dialogue situation tag a stock-line situation draws from, nil when the compiled bank keeps it.
    /// Approvals and failures keep their exact compiled wording.
    public static func tag(for situation: ZeusVoiceLines.Situation) -> String? {
        switch situation {
        case .thinking: "filler"
        case .ackDone: "ack"
        case .errorSpoken: "error"
        case .agentDone: "completion"
        default: nil
        }
    }
}

/// Picks a line for a situation: never the same line twice in a row, and an "Ah" or "Interesting" opener
/// at most one time in five (after one, the next four picks skip them).
public struct UltronDialogueSelector: Sendable {
    private var recent: [UltronDialogue.Line] = []

    public init() {}

    public mutating func pick(situation: String, from dialogue: UltronDialogue,
                              maxHumour: UltronDialogue.Humour = .high, random: (Int) -> Int) -> UltronDialogue.Line? {
        let pool = dialogue.lines.filter { $0.situations.contains(situation) && $0.humour <= maxHumour }
        guard !pool.isEmpty else { return nil }
        var candidates = pool
        if pool.count > 1, let last = recent.last {
            candidates = pool.filter { $0.id != last.id }
        }
        if recent.suffix(4).contains(where: \.isHeavyOpener) {
            let calm = candidates.filter { !$0.isHeavyOpener }
            if !calm.isEmpty { candidates = calm }
        }
        let chosen = candidates[min(max(random(candidates.count), 0), candidates.count - 1)]
        recent.append(chosen)
        if recent.count > 4 { recent.removeFirst(recent.count - 4) }
        return chosen
    }
}

/// The persona prompt block, read from between markers in the bundled personality document.
public enum UltronPersonaSource {
    public static let beginMarker = "<!-- ZEUS-PROMPT:BEGIN -->"
    public static let endMarker = "<!-- ZEUS-PROMPT:END -->"

    /// The trimmed text between the markers, or `fallback` when the document, a marker or the block is missing.
    public static func promptBlock(markdown: String?, fallback: String) -> String {
        guard let markdown, let begin = markdown.range(of: beginMarker),
              let end = markdown.range(of: endMarker, range: begin.upperBound..<markdown.endIndex) else { return fallback }
        let block = markdown[begin.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return block.isEmpty ? fallback : block
    }
}
