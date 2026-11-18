import Foundation

public enum CanopyPermission: Equatable, Sendable {
    case bluetooth
    case fullDiskAccess
    case localNetwork
}

/// One optional playback feature. Anything that needs a new permission starts off.
public struct CanopyFeature: Equatable, Sendable {
    public var enabled: Bool
    public var permission: CanopyPermission?
    public var usageStringKey: String?

    public init(enabled: Bool, permission: CanopyPermission? = nil, usageStringKey: String? = nil) {
        self.enabled = enabled
        self.permission = permission
        self.usageStringKey = usageStringKey
    }
}

public enum CanopyFeatures {
    /// System-wide now playing, read through the perl adapter. Off until the owner turns it on.
    public static let systemNowPlaying = CanopyFeature(enabled: false)
    /// Earbud overlay. Needs Bluetooth and starts off.
    public static let airPodsOverlay = CanopyFeature(enabled: false, permission: .bluetooth,
                                                      usageStringKey: "NSBluetoothAlwaysUsageDescription")
    /// A player on the lock screen. It uses a private window-server space and asks for no permission.
    public static let lockScreenPlayer = CanopyFeature(enabled: false)
    /// The active Focus name. Needs Full Disk Access and starts off. That permission has no usage string.
    public static let focusName = CanopyFeature(enabled: false, permission: .fullDiskAccess)
    /// Names of AirPlay receivers. Needs Local Network and starts off.
    public static let airPlayNames = CanopyFeature(enabled: false, permission: .localNetwork,
                                                    usageStringKey: "NSLocalNetworkUsageDescription")
}

public struct SystemNowPlayingLine: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var playing: Bool
    public var position: Double
    public var duration: Double

    public init(title: String, artist: String, album: String, playing: Bool, position: Double, duration: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        self.playing = playing
        self.position = position
        self.duration = duration
    }
}

/// The perl adapter prints one tab-separated line: title, artist, album, 1 or 0, position, duration.
public enum SystemNowPlayingAdapter {
    public static let command = ["perl", "scripts/now-playing.pl"]

    public static func parse(_ text: String) -> SystemNowPlayingLine? {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 6, let playing = Int(fields[3]), let position = Double(fields[4]), let duration = Double(fields[5]) else { return nil }
        return SystemNowPlayingLine(title: fields[0], artist: fields[1], album: fields[2], playing: playing != 0, position: position, duration: duration)
    }
}

public enum LockScreenPlayerSpace {
    /// Drawn on a private window-server space, not on the owner's desktop.
    public static let isPrivateWindowServer = true
    /// The space shows the player. It does not collect clicks or typing.
    public static let collectsInput = false
}

public enum FocusNameReader {
    public static func parse(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum AirPlayNames {
    public static let bonjourTypes = ["_airplay._tcp", "_raop._tcp"]

    /// A record that starts with a device hex prefix still shows the service name.
    public static func displayName(service: String, recordHexPrefix: String) -> String {
        if let at = recordHexPrefix.firstIndex(of: "@") {
            let tail = recordHexPrefix[recordHexPrefix.index(after: at)...]
            if !tail.isEmpty { return String(tail) }
        }
        return service
    }
}

public enum FacePresenceSecretPolicy {
    public static let storesPassword = false
}

public enum PlaybackCollapse {
    public static func collapsed(paused: Bool, enabled: Bool) -> Bool { enabled && paused }
}

public enum OutputDeviceKind: Equatable, Sendable { case speakers, headphones, airPlay }

public enum OutputDeviceIcon {
    public static func symbol(for kind: OutputDeviceKind) -> String {
        switch kind {
        case .speakers: "speaker.wave.2.fill"
        case .headphones: "headphones"
        case .airPlay: "airplayaudio"
        }
    }
}

public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
}

public enum WordTiming {
    /// Splits a line into words that share its interval exactly, with no gap and no overlap.
    public static func words(_ line: String, start: Double, end: Double) -> [TimedWord] {
        let parts = line.split(separator: " ").map(String.init)
        guard !parts.isEmpty, end >= start else { return [] }
        let span = (end - start) / Double(parts.count)
        return parts.enumerated().map { index, text in
            let wordStart = start + span * Double(index)
            let wordEnd = index == parts.count - 1 ? end : wordStart + span
            return TimedWord(text: text, start: wordStart, end: wordEnd)
        }
    }
}
