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

/// Arms one tool action from the latest partial and runs it only when the final words are still that action.
/// A revision drops the armed action. Nothing here launches an app, speaks, or writes.
public struct PartialActionSession: Sendable, Equatable {
    public enum Finish: Equatable, Sendable {
        /// The final words are the armed partial. The caller may run that one action.
        case runArmed(String)
        /// An armed action does not match the final words. Do not run it.
        case droppedArmed
        /// Nothing was armed. The caller interprets the final words from scratch.
        case interpretFinal
    }

    public private(set) var gate = PartialActionGate()
    public private(set) var armedKey: String?

    public init() {}

    /// The latest partial. A changed key drops an action that was armed on the previous one.
    public mutating func observe(_ text: String) {
        let previous = gate.lastPartialKey
        gate.observePartial(text)
        if gate.lastPartialKey != previous {
            armedKey = nil
        }
    }

    /// Arm a tool action for this partial. False when the partial is blank or already revised.
    public mutating func arm(_ text: String) -> Bool {
        let key = PartialActionGate.key(text)
        guard !key.isEmpty, key == gate.lastPartialKey else { return false }
        guard gate.mayActOnPartial(text) else { return false }
        armedKey = key
        return true
    }

    /// Whether a tool may act on `text` while a partial is live. With no partial, the words may act.
    public func allowsToolAction(on text: String) -> Bool {
        guard let last = gate.lastPartialKey else { return true }
        return PartialActionGate.key(text) == last
    }

    /// End the turn. The armed action runs only when the final key is that same partial.
    public mutating func finish(_ text: String) -> Finish {
        let finalKey = PartialActionGate.key(text)
        let armed = armedKey
        let committed = gate.committedPartialKey
        armedKey = nil
        gate = PartialActionGate()
        guard let armed else { return .interpretFinal }
        if committed == armed, armed == finalKey { return .runArmed(armed) }
        return .droppedArmed
    }
}
