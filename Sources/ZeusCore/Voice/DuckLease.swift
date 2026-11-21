import Foundation

/// One output Zeus can duck. `id` is the device the volume call addresses.
public struct DuckDevice: Equatable, Sendable {
    public var id: String
    public var volume: Float
    public var muted: Bool

    public init(id: String, volume: Float, muted: Bool) {
        self.id = id
        self.volume = volume
        self.muted = muted
    }
}

public struct DuckVolumeCommand: Equatable, Sendable {
    public var device: String
    public var volume: Float

    public init(device: String, volume: Float) {
        self.device = device
        self.volume = volume
    }
}

/// How many spoken holders are using the ducked output. The volume returns only when the last
/// holder ends. A holder that ended after a newer one began changes nothing. A device change
/// restores the previous output and ducks the new one while any holder is still open.
public struct DuckLease: Equatable, Sendable {
    public private(set) var generation = 0
    public private(set) var deviceID: String?
    private var open: Set<Int> = []
    private var quiet: AudioQuiet?

    public init() {}

    public var isHolding: Bool { !open.isEmpty }

    public struct Begin: Equatable, Sendable {
        public var token: Int
        public var commands: [DuckVolumeCommand]
    }

    public mutating func begin(_ device: DuckDevice, fraction: Float = 0.35) -> Begin {
        generation += 1
        let token = generation
        open.insert(token)
        var commands = retarget(to: device, fraction: fraction)
        if quiet == nil {
            var snap = AudioQuiet(snapshotVolume: device.volume, snapshotMuted: device.muted)
            if let target = snap.beginDuck(fraction: fraction) {
                commands.append(DuckVolumeCommand(device: device.id, volume: target))
            }
            quiet = snap
            deviceID = device.id
        }
        return Begin(token: token, commands: commands)
    }

    /// Ends one holder. Empty when the token is unknown or another holder is still open.
    public mutating func end(token: Int) -> [DuckVolumeCommand] {
        guard open.remove(token) != nil else { return [] }
        guard open.isEmpty else { return [] }
        return release()
    }

    /// Drops every holder. A later end of an old token is a no-op.
    public mutating func endAll() -> [DuckVolumeCommand] {
        guard !open.isEmpty else { return [] }
        open.removeAll()
        return release()
    }

    /// The default output changed while a duck is held.
    public mutating func follow(_ device: DuckDevice, fraction: Float = 0.35) -> [DuckVolumeCommand] {
        guard isHolding, device.id != deviceID else { return [] }
        return retarget(to: device, fraction: fraction)
    }

    private mutating func retarget(to device: DuckDevice, fraction: Float) -> [DuckVolumeCommand] {
        guard let previous = deviceID, previous != device.id else { return [] }
        var commands: [DuckVolumeCommand] = []
        if let restore = quiet?.restoreVolume(currentVolume: quiet?.duckedVolume ?? 0, currentMuted: quiet?.snapshotMuted ?? false) {
            commands.append(DuckVolumeCommand(device: previous, volume: restore))
        }
        quiet?.endDuck()
        quiet = nil
        var snap = AudioQuiet(snapshotVolume: device.volume, snapshotMuted: device.muted)
        if let target = snap.beginDuck(fraction: fraction) {
            commands.append(DuckVolumeCommand(device: device.id, volume: target))
        }
        quiet = snap
        deviceID = device.id
        return commands
    }

    private mutating func release() -> [DuckVolumeCommand] {
        defer {
            quiet = nil
            deviceID = nil
        }
        guard let id = deviceID,
              let restore = quiet?.restoreVolume(currentVolume: quiet?.duckedVolume ?? 0, currentMuted: quiet?.snapshotMuted ?? false) else {
            return []
        }
        quiet?.endDuck()
        return [DuckVolumeCommand(device: id, volume: restore)]
    }
}

/// A stop from a turn that has already been replaced must not close the microphone the new turn opened.
public enum SpeechSessionStop {
    public static func affectsCurrent(stopSession: Int, current: Int) -> Bool {
        stopSession == current
    }
}
