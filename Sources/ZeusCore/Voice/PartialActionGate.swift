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

    /// A collapsed key. A zero-width space stays. The blank check is read from `PartialActionGateBox`.
    public static func key(_ text: String) -> String {
        let collapsed = text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return PartialActionGateBox.trimmedKey(collapsed)
    }
}
