import Foundation

// The rules that decide who may be shaped and when every tap must go. Pure and `Sendable`: facts in, a verdict out.
// Nothing here opens audio, reads a process or touches the main thread; the app reads Core Audio and hands the answers
// to these functions.

/// What Core Audio says about one audio process, read by the app. `bundleID` is nil or empty when the process has none.
/// `runningInput` is nil when the read failed, which is not the same as the input being closed.
public struct AudioProcessFacts: Sendable, Equatable {
    public let objectID: UInt32
    public let pid: Int32
    public let bundleID: String?
    public let runningOutput: Bool
    public let runningInput: Bool?
    /// UIDs of the output devices the process plays to.
    public let devices: [String]

    public init(
        objectID: UInt32, pid: Int32, bundleID: String?, runningOutput: Bool, runningInput: Bool?, devices: [String]
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.runningOutput = runningOutput
        self.runningInput = runningInput
        self.devices = devices
    }
}

/// One app and its helper processes, joined. The tap for an app covers every object id in its group.
public struct EqualiserProcessGroup: Sendable, Equatable {
    public let bundleID: String
    public let objectIDs: [UInt32]
    public let pids: [Int32]
    /// True when any member has output running.
    public let isPlaying: Bool
    /// Every output device UID any member plays to, sorted and without repeats.
    public let devices: [String]

    public init(bundleID: String, objectIDs: [UInt32], pids: [Int32], isPlaying: Bool, devices: [String]) {
        self.bundleID = bundleID
        self.objectIDs = objectIDs
        self.pids = pids
        self.isPlaying = isPlaying
        self.devices = devices
    }
}

public enum EqualiserPolicy {
    // MARK: Grouping

    /// Joins helper processes to their app. A process joins the longest running-app bundle id that equals its own or is
    /// a dotted ancestor of it; with none, it keeps its own bundle id. This is not the WebKit to Safari mapping that call
    /// detection uses: that is right for reading who may be on a call and wrong for muting, because a shared web engine
    /// helper carries audio for every web view. Zeus's own pid and processes with no bundle id never join a group.
    public static func groups(
        _ processes: [AudioProcessFacts], runningAppBundleIDs: [String], ownPID: Int32
    ) -> [EqualiserProcessGroup] {
        struct Pending {
            var objectIDs: [UInt32] = []
            var pids: [Int32] = []
            var isPlaying = false
            var devices = Set<String>()
        }
        var pending: [String: Pending] = [:]
        for process in processes where process.pid != ownPID {
            guard let own = process.bundleID, !own.isEmpty else { continue }
            let key = owningApp(of: own, runningAppBundleIDs: runningAppBundleIDs) ?? own
            var entry = pending[key] ?? Pending()
            entry.objectIDs.append(process.objectID)
            entry.pids.append(process.pid)
            entry.isPlaying = entry.isPlaying || process.runningOutput
            entry.devices.formUnion(process.devices)
            pending[key] = entry
        }
        return pending.keys.sorted().map { key in
            let entry = pending[key]!
            return EqualiserProcessGroup(
                bundleID: key, objectIDs: entry.objectIDs, pids: entry.pids,
                isPlaying: entry.isPlaying, devices: entry.devices.sorted())
        }
    }

    private static func owningApp(of bundleID: String, runningAppBundleIDs: [String]) -> String? {
        let lowered = bundleID.lowercased()
        return runningAppBundleIDs
            .filter { app in
                let appLowered = app.lowercased()
                return !app.isEmpty && (lowered == appLowered || lowered.hasPrefix(appLowered + "."))
            }
            .max { $0.count < $1.count }
    }

    /// The groups that play now, as the list rules take them. A group with no known name is named by its bundle id.
    public static func playingGroups(
        _ groups: [EqualiserProcessGroup], names: [String: String]
    ) -> [EqualiserPlayingGroup] {
        groups.filter(\.isPlaying).map {
            EqualiserPlayingGroup(bundleID: $0.bundleID, displayName: names[$0.bundleID] ?? $0.bundleID)
        }
    }

    // MARK: Exclusion

    /// Why an app is never shaped, judged by its bundle id alone. A shared WebKit helper is checked before the call app
    /// table so a web engine is never mistaken for Safari.
    public static func exclusion(for bundleID: String, ownBundleID: String) -> EqualiserExclusion? {
        guard !bundleID.isEmpty else { return .noBundleID }
        let lowered = bundleID.lowercased()
        let ownLowered = ownBundleID.lowercased()
        if !ownBundleID.isEmpty, lowered == ownLowered || lowered.hasPrefix(ownLowered + ".") { return .zeus }
        if lowered.hasPrefix("com.apple.webkit.") { return .sharedEngine }
        if ScribeCallDetection.identify(bundleID: bundleID) != nil { return .callApp }
        return nil
    }

    /// The same, for a whole group, and a playing group that is not only on the current default output is also excluded.
    /// A playing group whose devices are unknown is excluded rather than guessed.
    public static func exclusion(
        for group: EqualiserProcessGroup, ownBundleID: String, defaultOutputUID: String
    ) -> EqualiserExclusion? {
        if let reason = exclusion(for: group.bundleID, ownBundleID: ownBundleID) { return reason }
        guard group.isPlaying else { return nil }
        let onlyDefault = !group.devices.isEmpty && group.devices.allSatisfy { $0 == defaultOutputUID }
        return onlyDefault ? nil : .otherDevice
    }

    /// The exclusions for the list, keyed by bundle id. Apps that are not excluded have no entry.
    public static func exclusions(
        _ groups: [EqualiserProcessGroup], ownBundleID: String, defaultOutputUID: String
    ) -> [String: EqualiserExclusion] {
        var result: [String: EqualiserExclusion] = [:]
        for group in groups {
            if let reason = exclusion(for: group, ownBundleID: ownBundleID, defaultOutputUID: defaultOutputUID) {
                result[group.bundleID] = reason
            }
        }
        return result
    }

    // MARK: What may be tapped

    /// The apps a tap may exist for: saved, not neutral, not excluded. A neutral app, one with no saved settings and an
    /// excluded app never appear, so nothing downstream can build a tap for them.
    public static func targets(
        _ groups: [EqualiserProcessGroup],
        names: [String: String],
        book: AppSoundBook,
        ownBundleID: String,
        defaultOutputUID: String
    ) -> [EqualiserLifecycle.Target] {
        groups.compactMap { group in
            guard exclusion(for: group, ownBundleID: ownBundleID, defaultOutputUID: defaultOutputUID) == nil,
                  let settings = book.settings(for: group.bundleID),
                  !settings.isNeutral
            else { return nil }
            return EqualiserLifecycle.Target(
                app: EqualiserPlayingGroup(
                    bundleID: group.bundleID, displayName: names[group.bundleID] ?? settings.displayName),
                parameters: settings.parameters,
                isPlaying: group.isPlaying)
        }
    }

    // MARK: Call recording

    /// True when a call app has its microphone input running. Zeus's own pid and an app that is not a call never count:
    /// the same rule the wake word uses. An unreadable input is not recording on its own; see `unreadableCounts`.
    public static func callRecording(_ processes: [AudioProcessFacts], ownPID: Int32) -> Bool {
        processes.contains { process in
            process.runningInput == true && countsAsCall(process, ownPID: ownPID)
        }
    }

    /// The processes whose input could not be read and that would count as a call if it were running. The app reads
    /// them again after `unreadableRecheckDelay` and asks `unreadableCounts`.
    public static func unreadableCallCandidates(_ processes: [AudioProcessFacts], ownPID: Int32) -> [AudioProcessFacts] {
        processes.filter { $0.runningInput == nil && countsAsCall($0, ownPID: ownPID) }
    }

    private static func countsAsCall(_ process: AudioProcessFacts, ownPID: Int32) -> Bool {
        guard let bundleID = process.bundleID else { return false }
        return MicConflict.counts(bundleID: bundleID, pid: process.pid, ownPID: ownPID)
    }

    /// How long to wait before reading an unreadable input again.
    public static let unreadableRecheckDelay: TimeInterval = 0.25

    /// True only when the input is still unreadable after the second read and the process is still alive. One
    /// unreadable read is a transient failure, and a gone process cannot be recording. Scribe treats an unreadable
    /// process as an incomplete scan, not as recording; so does this.
    public static func unreadableCounts(firstRead: Bool?, reRead: Bool?, pidAlive: Bool) -> Bool {
        firstRead == nil && reRead == nil && pidAlive
    }

    // MARK: Zeus capture

    /// True while Zeus records or captions this Mac's sound: Scribe `.starting`, `.recording` or `.ending`, Polyglot
    /// listening or starting, or Recordly with system audio on. The shaped sound would be missing from those captures,
    /// so every tap goes.
    public static func zeusCaptures(scribe: ScribePhase, polyglotActive: Bool, recordlySystemAudio: Bool) -> Bool {
        switch scribe {
        case .starting, .recording, .ending: return true
        case .idle, .processing, .complete, .failed: return polyglotActive || recordlySystemAudio
        }
    }

    // MARK: Pause

    /// The reason every tap must be gone, or nil. When several apply the first of these wins: asleep, another copy of
    /// Zeus shaping, a call recording, Zeus capturing, an unsupported output.
    public static func pauseReason(
        callRecording: Bool,
        zeusCaptures: Bool,
        otherShaper: Bool,
        asleep: Bool,
        format: EqualiserFormat.Verdict
    ) -> EqualiserPause? {
        if asleep { return .asleep }
        if otherShaper { return .otherShaper }
        if callRecording { return .callRecording }
        if zeusCaptures { return .zeusCaptures }
        if case .unsupported(let reason) = format { return .unsupportedOutput(reason: reason) }
        return nil
    }
}

// MARK: - Format

/// The parts of an `AudioStreamBasicDescription` the verdict needs, without the framework type so it can be tested.
public struct EqualiserStreamFormat: Sendable, Equatable {
    public let isLinearPCM: Bool
    public let isFloat: Bool
    public let bitsPerChannel: Int
    public let sampleRate: Double
    public let channelCount: Int

    public init(isLinearPCM: Bool, isFloat: Bool, bitsPerChannel: Int, sampleRate: Double, channelCount: Int) {
        self.isLinearPCM = isLinearPCM
        self.isFloat = isFloat
        self.bitsPerChannel = bitsPerChannel
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    public static func float32(sampleRate: Double, channelCount: Int) -> EqualiserStreamFormat {
        EqualiserStreamFormat(
            isLinearPCM: true, isFloat: true, bitsPerChannel: 32, sampleRate: sampleRate, channelCount: channelCount)
    }

    var isFloat32: Bool { isLinearPCM && isFloat && bitsPerChannel == 32 }
}

public enum EqualiserFormat {
    public enum Verdict: Sendable, Equatable {
        case supported
        /// `reason` is short plain words for the log; the state line does not show it.
        case unsupported(reason: String)
    }

    /// Supported when both streams are 32-bit float linear PCM at the same positive rate with at least one channel, and
    /// the output is not an aggregate or multi-output device. Anything else would be rendered wrongly or not at all, so
    /// the engine pauses instead of muting.
    public static func verdict(
        tap: EqualiserStreamFormat, output: EqualiserStreamFormat, outputIsAggregate: Bool
    ) -> Verdict {
        if outputIsAggregate { return .unsupported(reason: "the output is a combined device") }
        if output.channelCount < 1 { return .unsupported(reason: "the output has no channels") }
        if tap.channelCount < 1 { return .unsupported(reason: "the tap has no channels") }
        if !tap.isFloat32 { return .unsupported(reason: "the tap is not 32-bit float sound") }
        if !output.isFloat32 { return .unsupported(reason: "the output is not 32-bit float sound") }
        if !(tap.sampleRate > 0) || tap.sampleRate != output.sampleRate {
            return .unsupported(reason: "the sample rates differ")
        }
        return .supported
    }
}

// MARK: - Routing

/// Where one output channel gets its sound.
public enum EqualiserChannelSource: Sendable, Equatable {
    case silence
    /// One channel of the tap, by zero-based index.
    case tap(Int)
    /// The mean of every tap channel.
    case average
}

public enum EqualiserRouting {
    /// One source per output channel. Stereo goes to the device's stereo pair, a mono tap fills both sides of it, a mono
    /// device gets the average, and every other channel is silent. A tap with more than two channels contributes its
    /// first two. A pair that does not fit the device falls back to the first two channels.
    public static func channelMap(
        tapChannels: Int, outputChannels: Int, stereoPair: (left: Int, right: Int)
    ) -> [EqualiserChannelSource] {
        guard outputChannels > 0 else { return [] }
        var map = [EqualiserChannelSource](repeating: .silence, count: outputChannels)
        guard tapChannels > 0 else { return map }
        if outputChannels == 1 {
            map[0] = tapChannels == 1 ? .tap(0) : .average
            return map
        }
        let fits = stereoPair.left != stereoPair.right
            && (0..<outputChannels).contains(stereoPair.left)
            && (0..<outputChannels).contains(stereoPair.right)
        let pair = fits ? stereoPair : (left: 0, right: 1)
        map[pair.left] = .tap(0)
        map[pair.right] = .tap(tapChannels >= 2 ? 1 : 0)
        return map
    }

    /// The index of the tap's input stream in the aggregate device. The tap's stream follows the sub-device's input
    /// streams, so it sits after them. Nil when the counts do not add up or the tap has other than one stream: the
    /// caller destroys what it built and backs off.
    public static func tapStreamIndex(deviceInputStreams: Int, aggregateInputStreams: Int, tapStreams: Int) -> Int? {
        guard deviceInputStreams >= 0, tapStreams == 1, aggregateInputStreams == deviceInputStreams + tapStreams
        else { return nil }
        return deviceInputStreams
    }
}

// MARK: - Own devices

public enum ZeusAudioDevices {
    /// The UID prefix of every aggregate the equaliser builds.
    public static let equaliserUIDPrefix = "app.zeus.eq."
    /// The names of the two listen-only aggregates Zeus already builds for the spectrum and for Scribe.
    public static let ownNames: Set<String> = ["Zeus spectrum", "Zeus Scribe"]

    /// True for an aggregate Zeus made, so no picker offers it.
    public static func isOwnAggregate(uid: String, name: String) -> Bool {
        uid.hasPrefix(equaliserUIDPrefix) || ownNames.contains(name)
    }
}
