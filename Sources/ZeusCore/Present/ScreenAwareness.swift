import Foundation

/// L7 / O7: text-first screen reads; pixels only when the ask needs them.
public enum ScreenAwareness {
    public struct Plan: Equatable, Sendable {
        public var needsCapture: Bool
        public var preferPixels: Bool
        public var axTokenEstimate: Int
        public var promptPrefix: String

        public init(needsCapture: Bool, preferPixels: Bool, axTokenEstimate: Int, promptPrefix: String) {
            self.needsCapture = needsCapture
            self.preferPixels = preferPixels
            self.axTokenEstimate = axTokenEstimate
            self.promptPrefix = promptPrefix
        }
    }

    private static let screenPhrases = [
        "what's on my screen", "whats on my screen", "what is on my screen",
        "what am i looking at", "what am i looking", "look at my screen",
        "explain this", "what is this", "describe my screen", "read my screen",
        "what do you see", "what can you see on my screen",
    ]

    public static func isScreenQuestion(_ transcript: String) -> Bool {
        let t = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !t.isEmpty else { return false }
        return screenPhrases.contains(where: { t.contains($0) })
    }

    public static func estimateTokens(_ text: String) -> Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return max(1, Int((Double(words) * 1.3).rounded()))
    }

    public static func plan(
        transcript: String,
        axSummary: String?,
        tab: TabContext?
    ) -> Plan {
        let question = isScreenQuestion(transcript)
        var chunks: [String] = []
        if let tab, let page = tab.text, !page.isEmpty {
            chunks.append(page)
        }
        if let ax = axSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !ax.isEmpty {
            chunks.append(ax)
        }
        let text = chunks.joined(separator: "\n")
        let tokens = estimateTokens(text)
        let visualCue = transcript.lowercased().contains("this")
            || transcript.lowercased().contains("that button")
            || transcript.lowercased().contains("highlighted")
        let sparse = text.count < 400
        let preferPixels = question && (visualCue || sparse || tab == nil && text.isEmpty)
        let prefix: String
        if question {
            prefix = "Screen question. axTokens=\(tokens). preferPixels=\(preferPixels). Answer from text when it is enough."
        } else if !text.isEmpty {
            prefix = "Front context. axTokens=\(tokens)."
        } else {
            prefix = ""
        }
        return Plan(
            needsCapture: question || preferPixels,
            preferPixels: preferPixels,
            axTokenEstimate: tokens,
            promptPrefix: prefix
        )
    }
}
