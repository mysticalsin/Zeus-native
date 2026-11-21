import Foundation

/// Local and global key monitors. A second start must not add another pair.
public struct MonitorBook: Equatable, Sendable {
    public private(set) var local = 0
    public private(set) var global = 0

    public init() {}

    public mutating func startLocal() -> Bool {
        if local > 0 { return false }
        local = 1
        return true
    }

    public mutating func startGlobal() -> Bool {
        if global > 0 { return false }
        global = 1
        return true
    }
}
