import Foundation

/// Which face-camera run the interruption observers are bound to.
public struct CameraRun: Equatable, Sendable {
    public private(set) var session = false
    public private(set) var bound = 0
    private var next = 0

    public init() {}

    public mutating func start() -> Int {
        next += 1
        session = true
        bound = next
        return next
    }

    public func delivers(_ run: Int) -> Bool {
        session && bound == run
    }
}
