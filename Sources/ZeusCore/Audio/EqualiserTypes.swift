import Foundation

// Shared values for the per-app equaliser. Pure and `Sendable`, so the filter maths, the settings model and the engine
// rules compile apart and meet only here. Nothing in this file touches audio, the store or the main thread.

/// The three second-order filter shapes the equaliser uses: peaking between, a shelf at each end.
public enum BiquadKind: String, Sendable, Codable, CaseIterable {
    case peaking
    case lowShelf
    case highShelf
}

/// What the render callback needs for one app: ten band gains in decibels, a volume from 0 to 1, and a bypass.
/// The preamp is not a field; it is worked out from the smoothed gains each buffer.
public struct EqualiserParameters: Sendable, Equatable {
    /// Ten octave bands, 31.5 Hz to 16 kHz.
    public static let bandCount = 10

    public var gainsDB: [Double]
    /// 0 is silent, 1 is unchanged.
    public var volume: Double
    public var bypass: Bool

    public static let flat = EqualiserParameters()

    public init(
        gainsDB: [Double] = [Double](repeating: 0, count: EqualiserParameters.bandCount),
        volume: Double = 1,
        bypass: Bool = false
    ) {
        self.gainsDB = gainsDB
        self.volume = volume
        self.bypass = bypass
    }
}

/// What the owner chose for one app, keyed by bundle id. The model clamps and judges it; this is only the shape.
public struct AppSoundSettings: Sendable, Codable, Equatable, Hashable {
    public var bundleID: String
    public var displayName: String
    public var gainsDB: [Double]
    /// 0 is silent, 1 is unchanged.
    public var volume: Double
    /// The "Shape this app" switch. Off means the app is never tapped.
    public var shapes: Bool
    public var lastUsed: Date

    public init(
        bundleID: String,
        displayName: String,
        gainsDB: [Double] = [Double](repeating: 0, count: EqualiserParameters.bandCount),
        volume: Double = 1,
        shapes: Bool = false,
        lastUsed: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.gainsDB = gainsDB
        self.volume = volume
        self.shapes = shapes
        self.lastUsed = lastUsed
    }
}

/// Why a playing app is never shaped.
public enum EqualiserExclusion: String, Sendable, Codable, CaseIterable {
    /// Zeus itself.
    case zeus
    /// A call app: it records the microphone, and muting it would break the call.
    case callApp
    /// A shared web engine helper, which carries audio for every web view, not one app.
    case sharedEngine
    /// A process with no bundle id, so no setting can belong to it.
    case noBundleID
    /// The app plays to an output other than the current default.
    case otherDevice
}

/// Why every tap is destroyed for now. The engine resumes by itself when the reason ends.
public enum EqualiserPause: Sendable, Equatable {
    case callRecording
    case zeusCaptures
    case otherShaper
    case asleep
    case unsupportedOutput(reason: String)
}

/// Why shaping stopped until the owner presses "Try again". `app` is the display name, as the state line names it.
public enum EqualiserStop: Sendable, Equatable {
    case silentWhilePlaying(app: String)
    case repeatedFailures(app: String)
    /// A Core Audio status (`OSStatus`) from the first build.
    case startFailed(status: Int32)
}

/// One line of the per-app list.
public struct EqualiserRow: Sendable, Equatable, Identifiable {
    public var id: String { settings.bundleID }
    /// The saved settings, or flat defaults for an app that is playing and not saved yet.
    public let settings: AppSoundSettings
    public let isPlaying: Bool
    public let exclusion: EqualiserExclusion?
    /// The reason shown beside a greyed row, nil when the app is not excluded.
    public let exclusionLabel: String?

    public var bundleID: String { settings.bundleID }
    public var displayName: String { settings.displayName }

    public init(
        settings: AppSoundSettings,
        isPlaying: Bool,
        exclusion: EqualiserExclusion? = nil,
        exclusionLabel: String? = nil
    ) {
        self.settings = settings
        self.isPlaying = isPlaying
        self.exclusion = exclusion
        self.exclusionLabel = exclusionLabel
    }
}

/// What the card shows: one line of words, a symbol that repeats it, and the rows.
public struct EqualiserStatus: Sendable, Equatable {
    public let line: String
    /// An SF Symbol name. The line carries the meaning; the symbol only repeats it.
    public let symbol: String
    public let rows: [EqualiserRow]
    /// Why shaping stopped, when it did. The card shows "Try again" for any stop and a System Settings link for a
    /// silent one.
    public let stop: EqualiserStop?

    public init(line: String, symbol: String, rows: [EqualiserRow], stop: EqualiserStop? = nil) {
        self.line = line
        self.symbol = symbol
        self.rows = rows
        self.stop = stop
    }

    /// Fixed content for snapshots, so a render never starts the controller or reads a real app list.
    public static let snapshotSample = EqualiserStatus(
        line: "Shaping 2 apps.",
        symbol: "waveform",
        rows: [
            EqualiserRow(
                settings: AppSoundSettings(
                    bundleID: "com.apple.Music", displayName: "Music",
                    gainsDB: [4, 3, 2, 0, 0, 0, 0, 0, 0, 0], volume: 1, shapes: true,
                    lastUsed: Date(timeIntervalSince1970: 1_700_000_000)),
                isPlaying: true),
            EqualiserRow(
                settings: AppSoundSettings(
                    bundleID: "com.apple.podcasts", displayName: "Podcasts",
                    gainsDB: [-3, -2, 0, 1, 2, 3, 3, 2, 0, 0], volume: 0.8, shapes: true,
                    lastUsed: Date(timeIntervalSince1970: 1_699_999_000)),
                isPlaying: true),
        ])
}

/// What the Settings card and the app delegate use to drive the equaliser. Main-actor isolated so a main-actor
/// controller and a main-actor test fake can both conform.
@MainActor
public protocol EqualiserControlling: AnyObject {
    var status: EqualiserStatus { get }
    /// The owner's switch. Turning it on is the only way to the System Audio Recording prompt.
    func setSwitch(_ on: Bool)
    /// Apply and save one app's settings.
    func update(_ settings: AppSoundSettings)
    /// Remove an app's saved settings.
    func forget(bundleID: String)
    /// Start again after a stop.
    func tryAgain()
}
