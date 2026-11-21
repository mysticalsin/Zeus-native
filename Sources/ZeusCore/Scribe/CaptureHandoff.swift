import Foundation

/// Orders two scribe captures so the next microphone opens only after the previous one has released it.
public struct CaptureHandoff: Equatable, Sendable {
    public private(set) var live: Int?
    public private(set) var queued: Int?
    public private(set) var releasing = false

    public enum Effect: Equatable, Sendable {
        case release(Int)
        case begin(Int)
    }

    public init() {}

    public mutating func start(_ session: Int) -> [Effect] {
        if releasing {
            queued = session
            return []
        }
        if let live {
            queued = session
            let old = live
            self.live = nil
            releasing = true
            return [.release(old)]
        }
        live = session
        return [.begin(session)]
    }

    public mutating func didRelease() -> [Effect] {
        releasing = false
        guard let next = queued else { return [] }
        queued = nil
        live = next
        return [.begin(next)]
    }
}
