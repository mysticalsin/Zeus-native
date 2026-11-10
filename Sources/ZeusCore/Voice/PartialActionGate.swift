import Foundation

/// Ensures tool actions never commit from a partial that later changes (O2).
public struct PartialActionGate: Sendable, Equatable {
    public private(set) var lastPartialKey: String?
    public private(set) var committedPartialKey: String?

    public init() {}

    public mutating func observePartial(_ text: String) {
        lastPartialKey = Self.key(text)
    }

    /// Call when a fast path or tool would act on the current partial. Returns false if the partial
    /// was superseded before the final transcript landed.
    public mutating func mayActOnPartial(_ text: String) -> Bool {
        let key = Self.key(text)
        guard key == lastPartialKey else { return false }
        committedPartialKey = key
        return true
    }

    public mutating func finalize(_ text: String) {
        let key = Self.key(text)
        if committedPartialKey != nil, committedPartialKey != key {
            committedPartialKey = nil
        }
        lastPartialKey = key
    }

    public static func key(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
