import Foundation

// The per-app equaliser's settings model: the band table, the gain rules, the presets, what makes an app neutral, the
// saved book of apps with its cap and its versioned codec, and the ordering of the list the card shows. Pure and
// `Sendable`. It touches no store, no audio and no main thread; the controller reads and writes the raw data.

// MARK: - Bands

/// One equaliser band: where it sits, which filter shape it uses and how wide it is.
public struct EqualiserBand: Sendable, Equatable {
    public let frequency: Double
    public let kind: BiquadKind
    public let q: Double

    public init(frequency: Double, kind: BiquadKind, q: Double) {
        self.frequency = frequency
        self.kind = kind
        self.q = q
    }

    /// Ten ISO 266 octave centres, a shelf at each end and a peak between. It is built from the same layout the
    /// kernel uses, so the card and the filters cannot drift apart.
    public static let standard: [EqualiserBand] = {
        let count = EqualiserBandLayout.tenBandFrequencies.count
        return (0..<count).map { index in
            let kind = EqualiserBandLayout.kind(at: index, count: count)
            return EqualiserBand(
                frequency: EqualiserBandLayout.frequency(at: index, count: count),
                kind: kind,
                q: EqualiserBandLayout.q(for: kind))
        }
    }()
}

// MARK: - Gain

/// The range, the step and the spoken form of one band's gain in decibels.
public enum EqualiserGain {
    public static let range: ClosedRange<Double> = -12...12
    public static let step = 0.5

    /// Inside the range. Not a number becomes 0, so a damaged value is never a loud one.
    public static func clamp(_ gain: Double) -> Double {
        guard !gain.isNaN else { return 0 }
        return min(max(gain, range.lowerBound), range.upperBound)
    }

    /// What VoiceOver says: "plus 3 decibels", "minus 1.5 decibels", "0 decibels".
    public static func spokenValue(_ gain: Double) -> String {
        let rounded = (clamp(gain) * 10).rounded() / 10
        let magnitude = abs(rounded)
        let number = magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(magnitude)
        let unit = magnitude == 1 ? "decibel" : "decibels"
        let sign = rounded > 0 ? "plus " : (rounded < 0 ? "minus " : "")
        return "\(sign)\(number) \(unit)"
    }
}

// MARK: - Presets

/// A named set of ten gains. A set of gains that matches none of them is "Custom".
public enum EqualiserPreset: String, Sendable, CaseIterable {
    case flat
    case moreBass
    case lessBass
    case moreTreble
    case lessTreble
    case clearVoice
    case fullerSound
    case smallSpeakers

    /// What the preset menu shows for gains that match no preset.
    public static let customTitle = "Custom"

    public var title: String {
        switch self {
        case .flat: "Flat"
        case .moreBass: "More bass"
        case .lessBass: "Less bass"
        case .moreTreble: "More treble"
        case .lessTreble: "Less treble"
        case .clearVoice: "Clear voice"
        case .fullerSound: "Fuller sound"
        case .smallSpeakers: "Small speakers"
        }
    }

    /// Gains in decibels for 31.5, 63, 125, 250, 500, 1k, 2k, 4k, 8k and 16k Hz.
    public var gains: [Double] {
        switch self {
        case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .moreBass: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .lessBass: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]
        case .moreTreble: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .lessTreble: [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]
        case .clearVoice: [-4, -3, -1, 0, 1, 2.5, 3, 3, 1, 0]
        case .fullerSound: [3, 3, 2.5, 2, 1, 0, 0, 1, 2, 3]
        case .smallSpeakers: [-6, -4, 0, 2, 3, 2, 1, 0, 0, 0]
        }
    }

    /// Gains closer than this to a preset's still match it, so a value that went through storage still reads as the
    /// preset. A band moved by one step is far outside it.
    private static let matchTolerance = 0.01

    /// The preset these gains are, or nil for Custom.
    public static func matching(_ gains: [Double]) -> EqualiserPreset? {
        guard gains.count == EqualiserParameters.bandCount else { return nil }
        return allCases.first { preset in
            zip(preset.gains, gains).allSatisfy { abs($0 - $1) <= matchTolerance }
        }
    }
}

// MARK: - One app's settings

extension AppSoundSettings {
    /// A copy with every value in range: ten gains (padded with 0 or trimmed), each clamped, and a volume from 0 to 1
    /// where not a number means full volume.
    public func clamped() -> AppSoundSettings {
        var copy = self
        var gains = gainsDB.prefix(EqualiserParameters.bandCount).map(EqualiserGain.clamp)
        gains.append(contentsOf: [Double](repeating: 0, count: EqualiserParameters.bandCount - gains.count))
        copy.gainsDB = gains
        copy.volume = volume.isNaN ? 1 : min(max(volume, 0), 1)
        return copy
    }

    /// True when the app is never tapped: the switch is off, or the clamped gains are all 0 and the volume is full.
    public var isNeutral: Bool {
        guard shapes else { return true }
        let settings = clamped()
        return settings.volume == 1 && settings.gainsDB.allSatisfy { $0 == 0 }
    }

    /// What the render callback gets for this app. With the switch off it is a bypass.
    public var parameters: EqualiserParameters {
        let settings = clamped()
        return EqualiserParameters(gainsDB: settings.gainsDB, volume: settings.volume, bypass: !shapes)
    }
}

// MARK: - The saved book

/// Every app the owner has saved, keyed by bundle id. Versioned so a later build can read an older book and an older
/// build refuses a newer one without touching it.
public struct AppSoundBook: Sendable, Equatable {
    public static let currentVersion = 1
    /// A 65th app makes room by dropping the oldest neutral entry, or is refused.
    public static let maxApps = 64
    /// The raw store key, a plain key like `audio.capturePermission`.
    public static let storageKey = "equaliser.apps"
    /// Where the controller copies the raw data of a book that failed to decode, before any save.
    public static let unreadableKey = "equaliser.apps.unreadable"
    /// The card's words when `add` returns `.full`.
    public static let fullMessage = "Too many apps saved. Forget one to add another."

    public enum AddResult: Sendable, Equatable {
        case added
        case updated
        /// Sixty-four apps and none neutral. The book is unchanged.
        case full
    }

    public private(set) var apps: [String: AppSoundSettings]

    public init() {
        apps = [:]
    }

    public func settings(for bundleID: String) -> AppSoundSettings? {
        apps[bundleID]
    }

    public func parameters(for bundleID: String) -> EqualiserParameters? {
        apps[bundleID]?.parameters
    }

    /// Save one app's settings, clamped. A new app in a full book takes the place of the oldest neutral entry; with no
    /// neutral entry the book is left alone and the result is `.full`.
    @discardableResult
    public mutating func add(_ settings: AppSoundSettings) -> AddResult {
        let entry = settings.clamped()
        if apps[entry.bundleID] != nil {
            apps[entry.bundleID] = entry
            return .updated
        }
        if apps.count >= Self.maxApps {
            guard let oldest = oldestNeutralBundleID() else { return .full }
            apps[oldest] = nil
        }
        apps[entry.bundleID] = entry
        return .added
    }

    /// Forget an app.
    public mutating func remove(bundleID: String) {
        apps[bundleID] = nil
    }

    private func oldestNeutralBundleID() -> String? {
        apps.values
            .filter(\.isNeutral)
            .min { ($0.lastUsed, $0.bundleID) < ($1.lastUsed, $1.bundleID) }?
            .bundleID
    }

    // MARK: Codec

    private struct Stored: Codable {
        var version: Int
        var apps: [AppSoundSettings]
    }

    /// Stable bytes: entries by bundle id, keys sorted, dates as seconds.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let stored = Stored(
            version: Self.currentVersion,
            apps: apps.values.sorted { $0.bundleID < $1.bundleID })
        return try encoder.encode(stored)
    }

    /// Nil data is an empty book that did not fail. Anything unreadable gives an empty book and `failed` true, and the
    /// raw data is never touched here: bad JSON, an unknown version, an entry without ten gains, a repeated bundle id
    /// or more than 64 apps. Values out of range are clamped, not refused.
    public static func decode(_ data: Data?) -> (book: AppSoundBook, failed: Bool) {
        guard let data else { return (AppSoundBook(), false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let stored = try? decoder.decode(Stored.self, from: data),
              stored.version == currentVersion,
              stored.apps.count <= maxApps,
              stored.apps.allSatisfy({ $0.gainsDB.count == EqualiserParameters.bandCount })
        else { return (AppSoundBook(), true) }

        var book = AppSoundBook()
        for entry in stored.apps {
            guard book.apps[entry.bundleID] == nil else { return (AppSoundBook(), true) }
            book.apps[entry.bundleID] = entry.clamped()
        }
        return (book, false)
    }
}

// MARK: - The list

extension EqualiserExclusion {
    /// The reason shown beside a greyed row.
    public var label: String {
        switch self {
        case .zeus: "Zeus: never shaped"
        case .callApp: "Call app: never shaped"
        case .sharedEngine: "Shared web audio: never shaped"
        case .noBundleID: "No app id: never shaped"
        case .otherDevice: "Plays to another output"
        }
    }
}

/// One app that is playing now, already joined with its helpers. The engine rules make these; a process with no bundle
/// id has nothing to key a setting by, so it never becomes a group.
public struct EqualiserPlayingGroup: Sendable, Equatable {
    public let bundleID: String
    public let displayName: String

    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

public enum EqualiserListRules {
    /// Playing apps first, then saved apps that are quiet, each by name. A playing app that is not saved gets flat
    /// defaults; a saved one keeps its settings and takes the name it plays under now. Only a playing app can carry an
    /// exclusion.
    public static func rows(
        groups: [EqualiserPlayingGroup],
        book: AppSoundBook,
        exclusions: [String: EqualiserExclusion]
    ) -> [EqualiserRow] {
        var seen = Set<String>()
        let playing: [EqualiserRow] = groups
            .sorted(by: precedes)
            .filter { seen.insert($0.bundleID).inserted }
            .map { group in
                var settings = book.settings(for: group.bundleID)
                    ?? AppSoundSettings(bundleID: group.bundleID, displayName: group.displayName)
                settings.displayName = group.displayName
                let exclusion = exclusions[group.bundleID]
                return EqualiserRow(
                    settings: settings, isPlaying: true, exclusion: exclusion, exclusionLabel: exclusion?.label)
            }
        let saved = book.apps.values
            .filter { !seen.contains($0.bundleID) }
            .sorted { precedes($0.displayName, $0.bundleID, $1.displayName, $1.bundleID) }
            .map { EqualiserRow(settings: $0, isPlaying: false) }
        return playing + saved
    }

    private static func precedes(_ a: EqualiserPlayingGroup, _ b: EqualiserPlayingGroup) -> Bool {
        precedes(a.displayName, a.bundleID, b.displayName, b.bundleID)
    }

    /// By name without regard to case or accents, then by bundle id, so equal names keep a stable order.
    private static func precedes(_ nameA: String, _ idA: String, _ nameB: String, _ idB: String) -> Bool {
        let order = nameA.compare(nameB, options: [.caseInsensitive, .diacriticInsensitive])
        return order == .orderedSame ? idA < idB : order == .orderedAscending
    }
}
