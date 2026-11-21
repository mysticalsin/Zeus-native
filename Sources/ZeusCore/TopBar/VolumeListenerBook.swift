import Foundation

/// One Core Audio volume listener: device, selector, element.
public struct VolumeListenerID: Equatable, Hashable, Sendable {
    public var device: UInt32
    public var selector: UInt32
    public var element: UInt32

    public init(device: UInt32, selector: UInt32, element: UInt32) {
        self.device = device
        self.selector = selector
        self.element = element
    }
}

/// Which volume listeners are installed.
///
/// Changing the default output removes the previous device's listeners before adding the new ones.
public struct VolumeListenerBook: Equatable, Sendable {
    public private(set) var installed: [VolumeListenerID] = []

    public init() {}

    public mutating func replace(with next: [VolumeListenerID]) -> (remove: [VolumeListenerID], add: [VolumeListenerID]) {
        var unique: [VolumeListenerID] = []
        for id in next where !unique.contains(id) { unique.append(id) }
        let remove = installed.filter { !unique.contains($0) }
        let add = unique.filter { !installed.contains($0) }
        installed = unique
        return (remove, add)
    }
}
