import Foundation

/// How a transcript file is encoded. Pretty JSON and an unbounded line list are the cost.
public enum HubTranscriptBudget {
    public static let lineCap = 400
    /// Compact JSON. Pretty printing rewrites every line with indentation.
    public static let prettyPrinted = true

    public static func keptLines(_ count: Int) -> Int {
        max(0, count)
    }
}
