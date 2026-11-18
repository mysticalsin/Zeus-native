import Foundation

public enum MediaIslandPermission: Equatable, Sendable {
    case bluetooth
    case fullDiskAccess
    case localNetwork
}

/// One optional playback feature. Anything that needs a new permission starts off.
public struct MediaIslandFeature: Equatable, Sendable {
    public var enabled: Bool
    public var permission: MediaIslandPermission?
    public var usageStringKey: String?

    public init(enabled: Bool, permission: MediaIslandPermission? = nil, usageStringKey: String? = nil) {
        self.enabled = enabled
        self.permission = permission
        self.usageStringKey = usageStringKey
    }
}

public enum MediaIslandFeatures {
    /// System-wide now playing. Off until the owner turns it on.
    /// The perl script prints the line `SystemNowPlayingAdapter` reads. The app launches it only while the setting is on.
    public static let systemNowPlaying = MediaIslandFeature(enabled: false)
    /// Earbud overlay. Needs Bluetooth and starts off. The notch shows a connected audio device, then dismisses it.
    public static let earbudOverlay = MediaIslandFeature(enabled: false, permission: .bluetooth,
                                                          usageStringKey: "NSBluetoothAlwaysUsageDescription")
    /// Lock-screen player contract: a private window-server space that collects no input.
    /// No window is created.
    public static let lockScreenPlayer = MediaIslandFeature(enabled: false)
    /// The active Focus name. Needs Full Disk Access and starts off. That permission has no usage string.
    /// `FocusNameReader` only trims text. It does not read the system Focus setting.
    public static let focusName = MediaIslandFeature(enabled: false, permission: .fullDiskAccess)
    /// Receiver names. Needs Local Network and starts off.
    /// The service types are declared. Nothing browses them.
    public static let receiverNames = MediaIslandFeature(enabled: false, permission: .localNetwork,
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

/// The perl script prints one tab-separated line: title, artist, album, 1 or 0, position, duration.
public enum SystemNowPlayingLaunch {
    public static let settingID = "music.systemNowPlaying"
    public static let timeout: TimeInterval = 2
    public static let maxOutputBytes = 4096
    public static let executable = "/usr/bin/perl"
}

public enum SystemNowPlayingAdapter {
    public static let command = ["perl", "scripts/now-playing.pl"]

    public static func parse(_ text: String) -> SystemNowPlayingLine? {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 6, let playing = Int(fields[3]), let position = Double(fields[4]), let duration = Double(fields[5]) else { return nil }
        return SystemNowPlayingLine(title: fields[0], artist: fields[1], album: fields[2], playing: playing != 0, position: position, duration: duration)
    }
}

public enum LockScreenPlayerSpace {
    /// The intended space is private to the window server. No panel is opened.
    public static let isPrivateWindowServer = true
    /// The space would show the player and not collect clicks or typing. Nothing is shown.
    public static let collectsInput = false
}

public struct EarbudReading: Equatable, Sendable {
    public var name: String
    public var left: Int?
    public var right: Int?
    public var casePercent: Int?

    public init(name: String, left: Int?, right: Int?, casePercent: Int?) {
        self.name = name
        self.left = left
        self.right = right
        self.casePercent = casePercent
    }
}

public enum EarbudOverlayRule {
    public static let settingID = "music.earbudOverlay"
    public static let visibleFor: TimeInterval = 8

    /// A connected audio device. A battery value outside 0...100 is treated as not exposed.
    public static func reading(name: String, audio: Bool, connected: Bool, left: Int?, right: Int?, casePercent: Int?) -> EarbudReading? {
        guard audio, connected else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        func level(_ value: Int?) -> Int? {
            guard let value, (0...100).contains(value) else { return nil }
            return value
        }
        return EarbudReading(name: trimmed, left: level(left), right: level(right), casePercent: level(casePercent))
    }

    public static func visible(reading: EarbudReading?, enabled: Bool, now: Date, shownAt: Date?) -> Bool {
        guard enabled, reading != nil, let shownAt else { return false }
        return now < shownAt.addingTimeInterval(visibleFor)
    }
}

public enum FocusNameReader {
    public static func parse(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ReceiverService: Equatable, Sendable {
    public var name: String
    public var type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public enum ReceiverCatalog {
    public static let settingID = "music.receiverNames"

    /// Names from the two receiver service types, in the order they were found. A repeated name is kept once.
    public static func names(_ services: [ReceiverService]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for service in services {
            let type = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
            guard ReceiverNames.bonjourTypes.contains(type) else { continue }
            let shown = ReceiverNames.displayName(service: service.name, recordHexPrefix: service.name)
            guard !shown.isEmpty, seen.insert(shown).inserted else { continue }
            result.append(shown)
        }
        return result
    }
}

public enum ReceiverNames {
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
    public static let settingID = "music.collapseOnPause"

    public static func collapsed(paused: Bool, enabled: Bool) -> Bool { enabled && paused }

    /// Nothing on screen is not a pause, so the player stays open.
    public static func collapsed(isPlaying: Bool?, settingOn: Bool) -> Bool {
        guard let isPlaying else { return false }
        return collapsed(paused: !isPlaying, enabled: settingOn)
    }

    /// The collapse uses the existing page spring. Reduce Motion skips it.
    public static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }
}

public enum OutputDeviceKind: Equatable, Sendable { case speakers, headphones, receiver }

public enum OutputDeviceIcon {
    public static func symbol(for kind: OutputDeviceKind) -> String {
        switch kind {
        case .speakers: "speaker.wave.2.fill"
        case .headphones: "headphones"
        case .receiver: "airplayaudio"
        }
    }

    /// CoreAudio `kAudioDevicePropertyTransportType` values, as four-character codes.
    /// Bluetooth and its low-energy form are headphones. The network receiver transport is a receiver.
    /// Everything else, including the built-in output, is a speaker.
    public static func kind(transport: UInt32) -> OutputDeviceKind {
        switch transport {
        case 0x626C7565, 0x626C6561: .headphones
        case 0x61697270: .receiver
        default: .speakers
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
