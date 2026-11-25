import Foundation

/// Whether a turn should act before it speaks a preamble.
public enum ActFirst {
    /// Pointer, window, and draw questions act first. A plain question can still use one preamble.
    public static func suppressesFiller(_ transcript: String) -> Bool {
        let key = transcript.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'", with: "")
        let words = key.split { $0.isWhitespace || $0.isPunctuation && $0 != "%" }.map(String.init)
        guard !words.isEmpty else { return false }
        let joined = words.joined(separator: " ")
        if words.first == "draw" { return true }
        if joined.contains("where do i click") || joined.contains("where do i tap") || joined.contains("where should i click") {
            return true
        }
        if joined.contains("this window") || joined.contains("what window") { return true }
        if joined.contains("point at") || joined.contains("point to") { return true }
        return false
    }
}
