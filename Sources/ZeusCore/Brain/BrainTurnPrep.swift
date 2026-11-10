import Foundation

/// Keeps the first brain answer fast: skip AX and screenshots when the ask is general knowledge.
public enum BrainTurnPrep {
    public static func usesFrontContext(transcript: String) -> Bool {
        if ScreenAwareness.isScreenQuestion(transcript) { return true }
        if LocalLookup.kind(in: transcript) != nil { return true }
        if FastIntent.parse(transcript) != nil { return true }
        let key = Utterance(transcript).words.joined(separator: " ")
        if key.contains("this screen") || key.contains("on screen") || key.contains("this button")
            || key.contains("this window") || key.contains("looking at") {
            return true
        }
        return false
    }
}

/// Launch prewarm: first voice turn waits briefly so HTTP/TLS is already warm.
public enum BrainLaunchWarm {
    public nonisolated(unsafe) static var clock: () -> Date = { Date() }
    private nonisolated(unsafe) static var finishedAt: Date?
    private nonisolated(unsafe) static var waitHook: (@Sendable () async -> Void)?

    public static func registerWait(_ hook: @escaping @Sendable () async -> Void) {
        waitHook = hook
    }

    public static func markFinished(at date: Date = clock()) {
        finishedAt = date
    }

    public static var isFinished: Bool { finishedAt != nil }

    public static func awaitIfNeeded() async {
        if isFinished { return }
        if let waitHook {
            await waitHook()
        }
        markFinished()
    }

    public static func resetForTests() {
        finishedAt = nil
        waitHook = nil
        clock = { Date() }
    }
}
