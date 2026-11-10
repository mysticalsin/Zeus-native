import Foundation

/// Read-only search in a Markdown vault for voice and debug hooks.
public enum BrainRecall {
    public struct Hit: Equatable, Sendable {
        public var file: String
        public var snippet: String

        public init(file: String, snippet: String) {
            self.file = file
            self.snippet = snippet
        }
    }

    private static let skipFolders: Set<String> = ["node_modules", "build", "04_Archives", "Archive", "Archives"]

    /// Pulls the topic from "what is in my second brain about …" style asks.
    public static func topic(from transcript: String) -> String? {
        let key = Utterance(transcript).words.joined(separator: " ")
        guard !key.isEmpty else { return nil }
        let leads = [
            "what is in my second brain about ",
            "what's in my second brain about ",
            "whats in my second brain about ",
            "search my second brain for ",
            "search my second brain about ",
            "what do i have in my second brain about ",
        ]
        for lead in leads {
            guard key.hasPrefix(lead) else { continue }
            let topic = String(key.dropFirst(lead.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if topic.count >= 2 { return topic }
        }
        if key.contains("second brain"), key.contains("about ") {
            guard let range = key.range(of: "about ") else { return nil }
            let topic = String(key[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if topic.count >= 2 { return topic }
        }
        return nil
    }

    public static func search(vault: URL, topic: String, limit: Int = 3, maxFiles: Int = 600) -> [Hit] {
        let needles = topic.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !needles.isEmpty else { return [] }
        guard let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var ranked: [(score: Int, hit: Hit)] = []
        var files = 0
        for case let url as URL in walker {
            guard let relative = VaultPathBoundary.relativePath(of: url, in: vault) else {
                walker.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if name.hasPrefix("_") || skipFolders.contains(name) { walker.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md", (values?.fileSize ?? 0) < 400_000 else { continue }
            files += 1
            if files > maxFiles { break }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lower = text.lowercased()
            let score = needles.reduce(0) { partial, needle in
                partial + (lower.contains(needle) ? 1 : 0)
            }
            guard score > 0 else { continue }
            let snippet = snippet(from: text, needles: needles)
            ranked.append((score * 10 + min(text.count, 5000) / 500, Hit(file: relative, snippet: snippet)))
        }
        return ranked.sorted { $0.score == $1.score ? $0.hit.file < $1.hit.file : $0.score > $1.score }
            .prefix(limit).map(\.hit)
    }

    public static func spokenAnswer(vault: URL, topic: String) -> String {
        let hits = search(vault: vault, topic: topic)
        guard let first = hits.first else {
            return "I looked in your vault and didn't find notes about \(topic)."
        }
        if hits.count == 1 {
            return "In \(first.file): \(first.snippet)"
        }
        let others = hits.dropFirst().map(\.file).joined(separator: ", ")
        return "In \(first.file): \(first.snippet) Also see \(others)."
    }

    /// One line for `zeus debug second-brain-lookup` (no model, no vault contents in logs beyond snippets).
    public static func debugReport(vault: URL, topic: String) -> String {
        let hits = search(vault: vault, topic: topic, limit: 5)
        if hits.isEmpty { return "ok hits=0 topic=\(topic) vault=\(vault.path)" }
        let summary = hits.map { "\($0.file):\($0.snippet.prefix(80))" }.joined(separator: " | ")
        return "ok hits=\(hits.count) topic=\(topic) vault=\(vault.path) \(summary)"
    }

    private static func snippet(from text: String, needles: [String]) -> String {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 8 else { continue }
            let lower = trimmed.lowercased()
            if needles.contains(where: { lower.contains($0) }) {
                return PersonaReplyClamp.clamp(trimmed, maxSentences: 2)
            }
        }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return PersonaReplyClamp.clamp(flat, maxSentences: 2)
    }
}
