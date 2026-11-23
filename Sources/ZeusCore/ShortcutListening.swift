/// How many shortcut recorders are listening. The first one pauses the global hot keys.
/// Another one does not hand them back. The last one to stop is the one that resumes them.
/// An end while nothing is listening stays idle.
public struct ShortcutListening: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        case pauseHotkeys
        case resumeHotkeys
    }

    public private(set) var count: Int

    public init() { count = 0 }

    public mutating func begin() -> [Effect] {
        count += 1
        return count == 1 ? [.pauseHotkeys] : []
    }

    public mutating func end() -> [Effect] {
        guard count > 0 else { return [] }
        count -= 1
        return count == 0 ? [.resumeHotkeys] : []
    }
}
