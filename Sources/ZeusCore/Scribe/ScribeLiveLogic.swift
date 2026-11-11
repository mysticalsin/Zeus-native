import Accelerate
import Foundation
import os

// Pure helpers for live Scribe capture. No audio, process or calendar IO happens here, so everything
// is testable with synthetic data. The app target wires these to CoreAudio, NSWorkspace and EventKit.

// MARK: - Transcript checkpoint pacing

/// Decides when the in-progress transcript is written to disk while it is still growing. Updates are coalesced
/// (at most one write per `interval`), and a failed write stays due so the next update or flush retries it.
public struct ScribeCheckpointGate: Equatable, Sendable {
    public let interval: TimeInterval
    public private(set) var dirty = false
    public private(set) var lastWrite: Date?

    public init(interval: TimeInterval = 1) { self.interval = interval }

    /// A segment was accepted. True when a write should happen now; otherwise it stays dirty for a later flush.
    public mutating func segmentAccepted(now: Date) -> Bool {
        dirty = true
        guard let lastWrite else { return true }
        return now.timeIntervalSince(lastWrite) >= interval
    }

    /// Report the write's outcome. Success clears the dirty flag; failure keeps it due.
    public mutating func wrote(success: Bool, now: Date) {
        lastWrite = now
        if success { dirty = false }
    }

    /// A trailing write is owed (a segment arrived inside the interval, or the last write failed).
    public var flushDue: Bool { dirty }

    public mutating func reset() {
        dirty = false
        lastWrite = nil
    }
}

// MARK: - PCM payload

/// `ScribeAudioFrame.payload` is 16 kHz mono Float32 samples in native byte order.
public enum ScribePCM {
    public static let sampleRate = 16_000

    public static func encode(_ samples: [Float]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            data.copyBytes(to: UnsafeMutableRawBufferPointer(buffer), count: count * MemoryLayout<Float>.size)
            initialized = count
        }
    }
}

// MARK: - Mono mix, level

public enum ScribeAudioMath {
    /// Interleaved frames averaged to mono. A trailing partial frame is ignored.
    public static func monoMix(interleaved samples: UnsafeBufferPointer<Float>, channels: Int) -> [Float] {
        let channels = max(1, channels)
        let frames = samples.count / channels
        guard frames > 0 else { return [] }
        if channels == 1 { return Array(samples.prefix(frames)) }
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += samples[frame * channels + channel] }
            mono[frame] = sum / Float(channels)
        }
        return mono
    }

    public static func monoMix(interleaved samples: [Float], channels: Int) -> [Float] {
        samples.withUnsafeBufferPointer { monoMix(interleaved: $0, channels: channels) }
    }

    /// One buffer per channel, averaged to mono. Uses the shortest plane's length.
    public static func monoMix(planar planes: [UnsafeBufferPointer<Float>]) -> [Float] {
        guard let frames = planes.map(\.count).min(), frames > 0 else { return [] }
        if planes.count == 1 { return Array(planes[0].prefix(frames)) }
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for plane in planes { sum += plane[frame] }
            mono[frame] = sum / Float(planes.count)
        }
        return mono
    }

    public static func monoMix(planar planes: [[Float]]) -> [Float] {
        guard let frames = planes.map(\.count).min(), frames > 0 else { return [] }
        if planes.count == 1 { return Array(planes[0].prefix(frames)) }
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for plane in planes { sum += plane[frame] }
            mono[frame] = sum / Float(planes.count)
        }
        return mono
    }

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Digital silence or a dead input. Such a chunk is never sent to speech recognition.
    public static func isSilent(_ samples: [Float], threshold: Float = 0.002) -> Bool {
        rms(samples) < threshold
    }
}

// MARK: - Streaming resampler

/// Streaming mono resampler to a lower or equal rate. Down-sampling by 1.5x or more averages a window
/// of input samples (a box filter, a crude anti-alias); otherwise it interpolates linearly.
/// Keeps its fractional position between calls, so splitting the input never changes the output.
public struct ScribeResampler: Sendable {
    public let inputRate: Double
    public let outputRate: Double
    private let step: Double
    private let window: Int
    private var pending: [Float] = []
    private var position: Double = 0

    public init(inputRate: Double, outputRate: Double = Double(ScribePCM.sampleRate)) {
        let input = inputRate.isFinite && inputRate > 0 ? inputRate : outputRate
        let ratio = input / outputRate
        self.inputRate = input
        self.outputRate = outputRate
        self.step = ratio
        self.window = ratio >= 1.5 ? max(1, Int(ratio.rounded())) : 1
    }

    public mutating func process(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        pending.append(contentsOf: input)
        var output: [Float] = []
        output.reserveCapacity(Int(Double(input.count) / step) + 2)
        while true {
            let index = Int(position)
            if window > 1 {
                guard index + window <= pending.count else { break }
                var sum: Float = 0
                for offset in 0..<window { sum += pending[index + offset] }
                output.append(sum / Float(window))
            } else {
                guard index + 1 < pending.count else { break }
                let fraction = Float(position - Double(index))
                output.append(pending[index] * (1 - fraction) + pending[index + 1] * fraction)
            }
            position += step
        }
        let consumed = min(Int(position), pending.count)
        pending.removeFirst(consumed)
        position -= Double(consumed)
        return output
    }
}

// MARK: - Timeline

/// Stamps each delivered frame with its start time (seconds since the session began).
/// Frames follow each other exactly while the clock agrees; a jump larger than `tolerance` re-syncs
/// to the arrival time, so a gap in the audio stays a gap.
public struct ScribeTimeline: Sendable {
    public let tolerance: TimeInterval
    private var cursor: TimeInterval?

    public init(tolerance: TimeInterval = 0.5) {
        self.tolerance = tolerance
    }

    public mutating func stamp(duration: TimeInterval, arrival: TimeInterval) -> TimeInterval {
        let derived = max(0, arrival - duration)
        let start: TimeInterval
        if let cursor, abs(derived - cursor) <= tolerance {
            start = cursor
        } else {
            start = derived
        }
        cursor = start + duration
        return start
    }
}

// MARK: - Speaker-turn chunker

public struct ScribeChunk: Equatable, Sendable {
    public let index: Int
    public let start: TimeInterval
    public let samples: [Float]

    public init(index: Int, start: TimeInterval, samples: [Float]) {
        self.index = index
        self.start = start
        self.samples = samples
    }

    public var duration: TimeInterval { Double(samples.count) / Double(ScribePCM.sampleRate) }
}

/// The not-yet-closed buffer of a `ScribeChunker`. `index` is the index the chunk will have when it closes,
/// so a provisional segment and the final one share an id.
public struct ScribeChunkPreview: Equatable, Sendable {
    public let index: Int
    public let start: TimeInterval
    public let samples: [Float]

    public init(index: Int, start: TimeInterval, samples: [Float]) {
        self.index = index
        self.start = start
        self.samples = samples
    }

    public var duration: TimeInterval { Double(samples.count) / Double(ScribePCM.sampleRate) }
}

/// Cuts one source's 16 kHz stream into chunks, one speaker turn each where it can. A pause closes the chunk
/// early (once it holds `pauseCutAfterSeconds` and its last `pauseSeconds` are quieter than `silenceRMS`);
/// continuous speech is cut at `chunkSeconds`. A timing gap (the mic was muted, frames were dropped) closes
/// the current chunk first, so a chunk never spans silence that was never heard.
/// Chunks shorter than `minimumSeconds` are discarded when closed early.
public struct ScribeChunker: Sendable {
    public let chunkSamples: Int
    public let minimumSamples: Int
    public let gapTolerance: TimeInterval
    public let pauseCutSamples: Int
    public let pauseSamples: Int
    public let silenceRMS: Float
    private let rate: Double
    /// Appended audio is examined in steps this long, so a pause inside a large append is still found.
    private let stepSamples: Int
    private var buffer: [Float] = []
    private var bufferStart: TimeInterval = 0
    private var nextIndex = 0

    public init(
        chunkSeconds: Double = 8,
        minimumSeconds: Double = 0.5,
        gapTolerance: TimeInterval = 0.25,
        sampleRate: Int = ScribePCM.sampleRate,
        pauseCutAfterSeconds: Double = 1.5,
        pauseSeconds: Double = 0.45,
        silenceRMS: Float = 0.006
    ) {
        self.rate = Double(sampleRate)
        self.chunkSamples = max(1, Int(chunkSeconds * Double(sampleRate)))
        let minimum = max(1, Int(minimumSeconds * Double(sampleRate)))
        self.minimumSamples = minimum
        self.gapTolerance = gapTolerance
        let pause = max(1, Int(pauseSeconds * Double(sampleRate)))
        self.pauseSamples = pause
        // A non-finite `pauseCutAfterSeconds` turns pause cuts off.
        self.pauseCutSamples = pauseCutAfterSeconds.isFinite
            ? max(pause, minimum, Int(pauseCutAfterSeconds * Double(sampleRate)))
            : Int.max
        self.silenceRMS = silenceRMS
        self.stepSamples = max(1, sampleRate / 10)
    }

    public var bufferedSamples: Int { buffer.count }

    public mutating func append(_ samples: [Float], at start: TimeInterval) -> [ScribeChunk] {
        guard !samples.isEmpty else { return [] }
        var chunks: [ScribeChunk] = []
        if !buffer.isEmpty {
            let expected = bufferStart + Double(buffer.count) / rate
            if abs(start - expected) > gapTolerance, let closed = closeBuffer() {
                chunks.append(closed)
            }
        }
        var offset = 0
        while offset < samples.count {
            if buffer.isEmpty { bufferStart = start + Double(offset) / rate }
            let end = min(samples.count, offset + stepSamples)
            buffer.append(contentsOf: samples[offset..<end])
            offset = end
            while buffer.count >= chunkSamples {
                let chunk = ScribeChunk(index: nextIndex, start: bufferStart, samples: Array(buffer.prefix(chunkSamples)))
                nextIndex += 1
                buffer.removeFirst(chunkSamples)
                bufferStart += Double(chunkSamples) / rate
                chunks.append(chunk)
            }
            if endsInPause, let closed = closeBuffer() {
                chunks.append(closed)
            }
        }
        return chunks
    }

    /// Whatever is buffered, if it is long enough to be worth recognising.
    public mutating func flush() -> ScribeChunk? {
        closeBuffer()
    }

    /// The in-progress buffer, or nil when it is shorter than `minimumSeconds`.
    public func preview(minimumSeconds: Double = 1.0) -> ScribeChunkPreview? {
        guard !buffer.isEmpty, buffer.count >= Int(minimumSeconds * rate) else { return nil }
        return ScribeChunkPreview(index: nextIndex, start: bufferStart, samples: buffer)
    }

    /// The buffer is long enough for a pause cut and its trailing `pauseSamples` are quiet.
    private var endsInPause: Bool {
        guard buffer.count >= pauseCutSamples, buffer.count >= pauseSamples else { return false }
        var level: Float = 0
        buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            vDSP_rmsqv(base + (pointer.count - pauseSamples), 1, &level, vDSP_Length(pauseSamples))
        }
        return level < silenceRMS
    }

    private mutating func closeBuffer() -> ScribeChunk? {
        defer {
            buffer.removeAll(keepingCapacity: true)
        }
        guard buffer.count >= minimumSamples else { return nil }
        let chunk = ScribeChunk(index: nextIndex, start: bufferStart, samples: buffer)
        nextIndex += 1
        return chunk
    }
}

// MARK: - Speakers

public enum ScribeLiveSpeakers {
    /// System audio carries every remote participant mixed together, so one label covers it.
    public static let systemLabel = "Speaker"

    public static func speaker(for source: ScribeAudioSource) -> ScribeSpeaker {
        ScribeSpeaker.forSource(source, label: source == .system ? systemLabel : nil)
    }

    /// Stable per source and chunk, so the final text replaces its provisional one.
    public static func segmentID(source: ScribeAudioSource, chunkIndex: Int) -> String {
        "\(source == .microphone ? "mic" : "sys")-\(chunkIndex)"
    }
}

// MARK: - Preview engine

/// Which engine reads a rolling preview. Previews re-read the same audio again and again, so they only ever use
/// an on-device engine that is ready right now: never a cloud engine, whatever is chosen, and nothing when no
/// on-device engine is ready (the closed chunk is still recognised by the normal routing).
public enum ScribePreviewEngine {
    /// The chosen engine when it is on-device and ready, else the first ready on-device engine of the dictation
    /// fallback order, else nil.
    public static func pick(
        preferred: TranscriptionEngineKind,
        availability: [TranscriptionEngineKind: EngineAvailability]
    ) -> TranscriptionEngineKind? {
        func usable(_ kind: TranscriptionEngineKind) -> Bool {
            !kind.isCloud && availability[kind]?.isReady == true
        }
        if usable(preferred) { return preferred }
        return EngineSelection.fallbackOrder.first(where: usable)
    }
}

// MARK: - Call-app identification

public enum ScribeCallDetection {
    private enum Kind {
        case teams, zoom, browser, other(String)
    }

    private struct Entry {
        let prefix: String
        let app: String
        let kind: Kind
    }

    private static let entries: [Entry] = [
        Entry(prefix: "com.microsoft.teams2", app: "com.microsoft.teams2", kind: .teams),
        Entry(prefix: "com.microsoft.teams", app: "com.microsoft.teams", kind: .teams),
        Entry(prefix: "us.zoom.xos", app: "us.zoom.xos", kind: .zoom),
        Entry(prefix: "com.google.Chrome", app: "com.google.Chrome", kind: .browser),
        Entry(prefix: "com.google.Chrome.canary", app: "com.google.Chrome.canary", kind: .browser),
        Entry(prefix: "com.apple.Safari", app: "com.apple.Safari", kind: .browser),
        Entry(prefix: "com.apple.WebKit.WebContent", app: "com.apple.Safari", kind: .browser),
        Entry(prefix: "com.apple.WebKit.GPU", app: "com.apple.Safari", kind: .browser),
        Entry(prefix: "org.mozilla.firefox", app: "org.mozilla.firefox", kind: .browser),
        Entry(prefix: "com.microsoft.edgemac", app: "com.microsoft.edgemac", kind: .browser),
        Entry(prefix: "com.brave.Browser", app: "com.brave.Browser", kind: .browser),
        Entry(prefix: "company.thebrowser.Browser", app: "company.thebrowser.Browser", kind: .browser),
        Entry(prefix: "com.operasoftware.Opera", app: "com.operasoftware.Opera", kind: .browser),
        Entry(prefix: "com.vivaldi.Vivaldi", app: "com.vivaldi.Vivaldi", kind: .browser),
        Entry(prefix: "com.apple.FaceTime", app: "com.apple.FaceTime", kind: .other("FaceTime")),
        Entry(prefix: "com.tinyspeck.slackmacgap", app: "com.tinyspeck.slackmacgap", kind: .other("Slack")),
        Entry(prefix: "com.hnc.Discord", app: "com.hnc.Discord", kind: .other("Discord")),
        Entry(prefix: "com.cisco.webexmeetingsapp", app: "com.cisco.webexmeetingsapp", kind: .other("Webex")),
        Entry(prefix: "Cisco-Systems.Spark", app: "Cisco-Systems.Spark", kind: .other("Webex")),
        Entry(prefix: "net.whatsapp.WhatsApp", app: "net.whatsapp.WhatsApp", kind: .other("WhatsApp")),
        Entry(prefix: "com.skype.skype", app: "com.skype.skype", kind: .other("Skype")),
        Entry(prefix: "org.whispersystems.signal-desktop", app: "org.whispersystems.signal-desktop", kind: .other("Signal")),
        Entry(prefix: "ru.keepcoder.Telegram", app: "ru.keepcoder.Telegram", kind: .other("Telegram")),
    ]

    /// The longest known entry that equals `bundleID` or is a dotted ancestor of it (helper processes).
    private static func entry(for bundleID: String) -> Entry? {
        let lowered = bundleID.lowercased()
        return entries
            .filter { lowered == $0.prefix.lowercased() || lowered.hasPrefix($0.prefix.lowercased() + ".") }
            .max { $0.prefix.count < $1.prefix.count }
    }

    /// The bundle ID of the app a helper process belongs to (Chrome helper -> Chrome). Nil when unknown.
    public static func appBundleID(for bundleID: String) -> String? {
        entry(for: bundleID)?.app
    }

    public static func isBrowser(_ bundleID: String) -> Bool {
        if case .browser? = entry(for: bundleID)?.kind { return true }
        return false
    }

    /// Google Meet tab titles read "Meet – abc-defg-hij" (en dash) or with a hyphen or em dash.
    public static func isMeetTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("meet.google.com") { return true }
        for dash in ["–", "-", "—"] where trimmed.hasPrefix("Meet \(dash)") { return true }
        return false
    }

    /// A window title that suggests a web call (Meet, Zoom, Teams, Webex, a huddle). Wider than `isMeetTitle`
    /// on purpose: it only decides that a browser might be in a call, which makes the mute state unknown.
    public static func indicatesBrowserCall(_ title: String) -> Bool {
        if isMeetTitle(title) { return true }
        let lowered = title.lowercased()
        return ["zoom meeting", "zoom.us", "teams.microsoft.com", "microsoft teams", "webex", "huddle"]
            .contains { lowered.contains($0) }
    }

    /// A call app for this process. Native apps are identified by bundle ID alone; a browser only counts
    /// when one of its window titles is a Meet tab.
    public static func identify(bundleID: String, windowTitles: [String] = []) -> ScribeCallApp? {
        guard let entry = entry(for: bundleID) else { return nil }
        switch entry.kind {
        case .teams: return .teams
        case .zoom: return .zoom
        case .browser: return windowTitles.contains(where: isMeetTitle) ? .meet : nil
        case .other(let name): return .other(name)
        }
    }

    public static func displayName(_ app: ScribeCallApp) -> String {
        switch app {
        case .teams: return "Teams"
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .other(let name): return name
        }
    }
}

// MARK: - Microphone-excluded wording

public enum ScribeMicCallText {
    /// Shown while recording when the microphone is dropped because a call was detected, and kept with the meeting.
    public static let excludedNotice =
        "Your microphone stays excluded after another app uses it, because Zeus can't confirm its mute state. System audio is still recorded."
    /// The recap row's short line for a meeting saved with the microphone left out.
    public static let recapLine = "Your microphone was excluded after another app used it."
}

// MARK: - Recap notes, cloud disclosure, system-audio stall

/// Wording kept with a saved meeting when it is incomplete, and how the list labels it.
public enum ScribeRecapNote {
    public static let stoppedEarlyPrefix = "Recording stopped early"

    /// Kept with a transcript saved before the notes were finished, so a crash or quit while processing still
    /// leaves the meeting on disk (and says why it has no notes). Replaced when the real recap is saved.
    public static let checkpointNote = "Zeus closed before the notes were finished, so only the transcript was saved."

    /// One saved note from everything that went wrong this session, or nil when nothing did.
    public static func compose(issues: [String], stoppedEarly: String?, notesIssue: String?) -> String? {
        var parts: [String] = []
        if let stoppedEarly {
            let reason = stoppedEarly.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("\(stoppedEarlyPrefix)\(reason.isEmpty ? "." : ": \(reason)") Everything captured up to then was saved.")
        }
        if !issues.isEmpty {
            parts.append("Part of this meeting wasn't transcribed, so these notes may be missing speech. \(issues.joined(separator: " "))")
        }
        if let notesIssue { parts.append(notesIssue) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The short line a recap row shows for a saved note.
    public static func badge(for note: String?) -> String? {
        guard let note else { return nil }
        if note.hasPrefix(stoppedEarlyPrefix) { return "Recording stopped early. Saved what was captured." }
        return "Transcription incomplete. Notes may be missing speech."
    }
}

/// Tells the person when meeting audio would leave this Mac, from the dictation engine they chose.
public enum ScribeCloudDisclosure {
    public static func text(for engine: TranscriptionEngineKind) -> String? {
        guard engine.isCloud else { return nil }
        let provider: String
        switch engine {
        case .elevenLabs: provider = "ElevenLabs"
        case .openAI: provider = "OpenAI"
        default: provider = "a cloud service"
        }
        return "Meeting audio is sent to \(provider) to be transcribed, because that's your dictation engine. Choose an on-device engine in Dictation settings to keep it on this Mac."
    }
}

/// How long meeting (system) audio has been missing, as a warning level.
public enum ScribeSystemStall {
    public enum Level: Equatable, Sendable {
        case ok
        /// Show a live warning.
        case warning
        /// Long enough that remote speech is probably missing: keep it with the meeting.
        case lost
    }

    public static let warningAfter: TimeInterval = 6
    public static let lostAfter: TimeInterval = 20

    public static let warningText = "No meeting audio is arriving. If the call is quiet, ignore this. If you changed speakers or headphones, stop and start Scribe again."
    public static let lostText = "Meeting audio stopped arriving for a while, so other participants' speech may be missing."

    public static func level(silentSeconds: TimeInterval) -> Level {
        guard silentSeconds.isFinite else { return .ok }
        if silentSeconds >= lostAfter { return .lost }
        if silentSeconds >= warningAfter { return .warning }
        return .ok
    }
}

// MARK: - Popup wording

public enum ScribeCallPromptText {
    public static func headline(for decision: ScribePromptDecision, now: Date) -> String? {
        switch decision {
        case .none:
            return nil
        case .callDetected(let app):
            return "Meeting detected: \(ScribeCallDetection.displayName(app))"
        case .upcoming(let slot):
            let title = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = title.isEmpty ? "Meeting" : title
            let until = slot.start.timeIntervalSince(now)
            if until <= 0 { return "Started: \(name)" }
            let minutes = max(1, Int((until / 60).rounded(.up)))
            return "Starts in \(minutes) min: \(name)"
        }
    }

    /// Meeting title for the recap when recording starts from this prompt.
    public static func meetingTitle(for decision: ScribePromptDecision) -> String? {
        switch decision {
        case .upcoming(let slot):
            let title = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        case .callDetected(let app):
            return "\(ScribeCallDetection.displayName(app)) call"
        case .none:
            return nil
        }
    }
}

// MARK: - Mute evidence (fail closed)

/// One mute reading and when its read began (`ProcessInfo.systemUptime`). Evidence is only good for
/// `timeToLive`: an older reading, even `.unmuted`, counts as `.unknown`, which the gate treats as muted.
public struct ScribeMuteEvidence: Equatable, Sendable {
    public static let timeToLive: TimeInterval = 1.5

    public var state: ScribeMuteState
    public var takenAt: TimeInterval

    public init(state: ScribeMuteState, takenAt: TimeInterval) {
        self.state = state
        self.takenAt = takenAt
    }

    public func effectiveState(now: TimeInterval, timeToLive: TimeInterval = ScribeMuteEvidence.timeToLive) -> ScribeMuteState {
        let age = now - takenAt
        guard age >= 0, age <= timeToLive else { return .unknown }
        return state
    }

    public static func effectiveState(
        _ evidence: ScribeMuteEvidence?,
        now: TimeInterval,
        timeToLive: TimeInterval = ScribeMuteEvidence.timeToLive
    ) -> ScribeMuteState {
        evidence?.effectiveState(now: now, timeToLive: timeToLive) ?? .unknown
    }
}

public enum ScribeMuteRefreshPolicy {
    /// Whether to begin a new read. A read still in flight blocks another only until `watchdog` passes, so a
    /// stalled Accessibility call can't freeze refreshing (its late result is ignored if fresher evidence exists).
    public static func shouldStart(
        now: TimeInterval,
        evidenceTakenAt: TimeInterval?,
        inFlightSince: TimeInterval?,
        interval: TimeInterval,
        watchdog: TimeInterval
    ) -> Bool {
        if let inFlightSince, now - inFlightSince < watchdog { return false }
        guard let evidenceTakenAt else { return true }
        return now - evidenceTakenAt >= interval
    }
}

/// The default input device's own mute switch, as read. `noSwitch` (the device has no mute property at all,
/// confirmed by asking) is not muted; a device that can't be found or read is `unreadable`.
public enum ScribeDeviceMute: Equatable, Sendable {
    case muted, notMuted, noSwitch, unreadable
}

/// One CoreAudio process object. An object whose properties can't be read is not "idle": it is `unreadable`.
public enum ScribeProcessRead: Equatable, Sendable {
    case unreadable
    case idle
    case input(pid: Int32, bundleID: String)

    /// Preserve positive input activity even when its owner cannot be resolved. Losing that fact as a
    /// generic unreadable scan would allow a later empty scan to silently unmute the local microphone.
    public static func activeInput(pid: Int32?, bundleID: String?) -> Self {
        .input(pid: pid ?? -1, bundleID: bundleID ?? "")
    }

    public func isExternalInput(excluding ownPID: Int32) -> Bool {
        if case .input(let pid, _) = self { return pid != ownPID }
        return false
    }
}

/// A running GUI app. `windowTitles` is only meaningful for browsers: nil when the window list couldn't be read.
/// An empty list also counts as unavailable (titles are hidden without Screen Recording permission), and so
/// does a list that is `titlesComplete == false` (some window of this process had no readable title or number).
/// `windowNumbers` (`kCGWindowNumber`) runs parallel to `windowTitles`; a missing entry is given a distinct
/// stand-in by the reducer, so windows are never merged for lack of a number.
public struct ScribeRunningApp: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String
    public var windowTitles: [String]?
    public var windowNumbers: [Int]
    public var titlesComplete: Bool

    public init(pid: Int32, bundleID: String, windowTitles: [String]?, windowNumbers: [Int] = [], titlesComplete: Bool = true) {
        self.pid = pid
        self.bundleID = bundleID
        self.windowTitles = windowTitles
        self.windowNumbers = windowNumbers
        self.titlesComplete = titlesComplete
    }
}

/// One detected call: the process, what it is, and where it lives. Distinct calls stay distinct (two browser
/// windows in calls are two identities, even with identical titles). Any identity at all keeps the microphone out.
public struct ScribeCallIdentity: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// A running native call app (or a process capturing audio for one).
        case native
        /// A call in a browser window.
        case browserWindow
    }

    public var pid: Int32
    public var kind: String
    public var source: Source
    /// The window title for a browser call; empty for a native app.
    public var detail: String
    /// The CoreGraphics window number (`kCGWindowNumber`) for a browser call; 0 for a native app.
    public var windowNumber: Int

    public init(pid: Int32, kind: String, source: Source, detail: String = "", windowNumber: Int = 0) {
        self.pid = pid
        self.kind = kind
        self.source = source
        self.detail = detail
        self.windowNumber = windowNumber
    }
}

/// What the CoreAudio / running-app scan found. An incomplete scan is not the same as nothing found.
public enum ScribeInputScan: Equatable, Sendable {
    case incomplete
    /// `calls` is every detected call; `browserUnknown` is true when any running browser's titles can't be fully
    /// read, or a browser uses the microphone without a call title.
    case completed(calls: [ScribeCallIdentity], browserUnknown: Bool)
}

public enum ScribeScanReducer {
    /// Folds per-process reads and the running-app list into one scan. Any unreadable process makes the scan
    /// `.incomplete`, as does an active microphone owner whose identity Zeus doesn't recognise: an unsupported
    /// call app is not proof that no call exists. Only apps that are capturing the microphone right now (CoreAudio's per-process input
    /// flag, which needs no extra permission) can be in a call: an idle Discord, Slack or Zoom, or a browser
    /// that isn't using the mic, is not. A muted call counts only while its app keeps the input open; input
    /// ownership alone cannot establish per-app mute state or prove when a call ended. A capturing browser is
    /// `browserUnknown` unless ALL its window titles were read and one names a call.
    public static func reduce(reads: [ScribeProcessRead], running: [ScribeRunningApp], ownPID: Int32) -> ScribeInputScan {
        if reads.contains(.unreadable) { return .incomplete }
        for case .input(let pid, let bundleID) in reads where pid != ownPID {
            guard ScribeCallDetection.appBundleID(for: bundleID) != nil else { return .incomplete }
        }
        let found = collect(reads: reads, running: running, ownPID: ownPID)
        return .completed(calls: found.calls, browserUnknown: found.browserUnknown)
    }

    /// Whether any call identity (or browser doubt) is visible, whatever else couldn't be read. Independent of
    /// admission: an unreadable process is skipped here (it makes `reduce` incomplete, not this blind), and the
    /// device's mute state plays no part. Never admits anything; it only keeps known call evidence from being lost.
    public static func callPresence(reads: [ScribeProcessRead], running: [ScribeRunningApp], ownPID: Int32) -> Bool {
        let found = collect(reads: reads, running: running, ownPID: ownPID)
        return !found.calls.isEmpty || found.browserUnknown
    }

    private static func collect(
        reads: [ScribeProcessRead], running: [ScribeRunningApp], ownPID: Int32
    ) -> (calls: [ScribeCallIdentity], browserUnknown: Bool) {
        var calls: [ScribeCallIdentity] = []
        func add(_ call: ScribeCallIdentity) {
            if !calls.contains(call) { calls.append(call) }
        }
        var browserUnknown = false
        var capturing: Set<String> = []
        for case .input(let pid, let bundleID) in reads where pid != ownPID {
            if let appID = ScribeCallDetection.appBundleID(for: bundleID) { capturing.insert(appID) }
        }
        for app in running where app.pid != ownPID && capturing.contains(ScribeCallDetection.appBundleID(for: app.bundleID) ?? app.bundleID) {
            if ScribeCallDetection.isBrowser(app.bundleID) {
                guard app.titlesComplete, let titles = app.windowTitles, !titles.isEmpty else {
                    browserUnknown = true
                    continue
                }
                for (index, title) in titles.enumerated() where ScribeCallDetection.indicatesBrowserCall(title) {
                    // A missing window number gets a distinct negative stand-in: windows are never merged.
                    let number = index < app.windowNumbers.count ? app.windowNumbers[index] : -(index + 1)
                    add(ScribeCallIdentity(pid: app.pid, kind: "Browser", source: .browserWindow, detail: title, windowNumber: number))
                }
            } else if let identified = ScribeCallDetection.identify(bundleID: app.bundleID) {
                add(ScribeCallIdentity(pid: app.pid, kind: ScribeCallDetection.displayName(identified), source: .native))
            }
        }
        for case .input(let pid, let bundleID) in reads where pid != ownPID {
            guard let appID = ScribeCallDetection.appBundleID(for: bundleID) else { continue }
            if ScribeCallDetection.isBrowser(bundleID) {
                // A browser capturing the microphone must show a call title (already counted above); otherwise
                // it is capturing for something unidentified.
                let titles = running.first { $0.bundleID == appID }?.windowTitles ?? []
                if !titles.contains(where: ScribeCallDetection.indicatesBrowserCall) { browserUnknown = true }
            } else if !running.contains(where: { $0.bundleID == appID && $0.pid != ownPID }),
                      let identified = ScribeCallDetection.identify(bundleID: bundleID) {
                // Capturing, but no running-app entry: identify it by the audio process itself.
                add(ScribeCallIdentity(pid: pid, kind: ScribeCallDetection.displayName(identified), source: .native))
            }
        }
        return (calls, browserUnknown)
    }
}

/// What one mute reading carries: whether the microphone is admitted, and (independently) whether a known
/// call app or browser call evidence was present.
public struct ScribeMuteSample: Equatable, Sendable {
    public var admission: ScribeMuteState
    public var callPresent: Bool

    public init(admission: ScribeMuteState, callPresent: Bool) {
        self.admission = admission
        self.callPresent = callPresent
    }
}

public enum ScribeMuteResolver {
    /// Positive evidence only. `.unmuted` needs BOTH:
    /// (a) the default input device is not muted, and
    /// (b) a COMPLETE scan with ZERO call identities and no browser uncertainty.
    /// A muted device is `.muted`. Any detected call, any unknown browser state, an
    /// incomplete scan or an unreadable device is `.unknown`. Nothing else can admit the microphone.
    public static func resolve(device: ScribeDeviceMute, scan: ScribeInputScan) -> ScribeMuteState {
        switch device {
        case .muted: return .muted
        case .unreadable: return .unknown
        case .notMuted, .noSwitch: break
        }
        guard case .completed(let calls, let browserUnknown) = scan, !browserUnknown, calls.isEmpty else { return .unknown }
        return .unmuted
    }

    /// One reading: the admission verdict (fail-closed, unchanged) and, separately, whether a call was seen.
    /// `callPresent` comes from `ScribeScanReducer.callPresence`, so it survives a muted device and an
    /// incomplete scan; it never influences `admission`.
    public static func sample(device: ScribeDeviceMute, scan: ScribeInputScan, callPresent: Bool) -> ScribeMuteSample {
        ScribeMuteSample(admission: resolve(device: device, scan: scan), callPresent: callPresent)
    }

    /// True when a call (or a browser that might be in one) is named by a COMPLETE scan. An incomplete scan names
    /// no call here; use `ScribeScanReducer.callPresence` for presence that doesn't depend on completeness.
    public static func callDetected(scan: ScribeInputScan) -> Bool {
        guard case .completed(let calls, let browserUnknown) = scan else { return false }
        return !calls.isEmpty || browserUnknown
    }
}

// MARK: - Mute evidence timeline

/// One reading and when its read began and ended (`ScribeHostClock` seconds).
public struct ScribeMuteReading: Equatable, Sendable {
    public var state: ScribeMuteState
    public var readStart: TimeInterval
    public var readEnd: TimeInterval
    /// A call (or a browser that might be in one) was detected by this reading's scan.
    public var callDetected: Bool

    public init(state: ScribeMuteState, readStart: TimeInterval, readEnd: TimeInterval, callDetected: Bool = false) {
        self.state = state
        self.readStart = readStart
        self.readEnd = readEnd
        self.callDetected = callDetected
    }
}

public struct ScribeEvidenceWindow: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

public enum ScribeMicCoverage: Equatable, Sendable {
    case admitted
    /// The sample interval isn't covered by fresh unmuted evidence. The state is `.muted` when the newest
    /// reading says so, otherwise `.unknown`.
    case dropped(ScribeMuteState)
}

/// A history of mute readings. A microphone sample interval is admitted only when it lies fully inside
/// fresh `.unmuted` evidence. An `.unmuted` reading vouches for `[readEnd, readStart + timeToLive]`, clipped
/// where a later non-unmuted reading began. It never vouches for time before its read finished, so audio
/// captured while the state was muted or unknown can't be admitted by a later fresh reading.
public struct ScribeMuteTimeline: Sendable {
    public let timeToLive: TimeInterval
    public let retention: TimeInterval
    public private(set) var readings: [ScribeMuteReading] = []

    public init(timeToLive: TimeInterval = ScribeMuteEvidence.timeToLive, retention: TimeInterval = 30) {
        self.timeToLive = timeToLive
        self.retention = retention
    }

    public mutating func record(_ reading: ScribeMuteReading) {
        let index = readings.firstIndex { $0.readStart > reading.readStart } ?? readings.count
        readings.insert(reading, at: index)
        if let newest = readings.last?.readEnd {
            readings.removeAll { $0.readStart < newest - retention }
        }
    }

    public mutating func record(state: ScribeMuteState, readStart: TimeInterval, readEnd: TimeInterval, callDetected: Bool = false) {
        record(ScribeMuteReading(state: state, readStart: readStart, readEnd: max(readStart, readEnd), callDetected: callDetected))
    }

    /// Whether the newest reading that began by the end of the interval saw a call. Unknown timing reads the
    /// newest reading overall.
    public func callDetected(start: TimeInterval?, seconds: TimeInterval) -> Bool {
        guard let start else { return readings.last?.callDetected ?? false }
        return latestReading(startedBy: start + seconds)?.callDetected ?? false
    }

    public func unmutedWindows() -> [ScribeEvidenceWindow] {
        var windows: [ScribeEvidenceWindow] = []
        for (index, reading) in readings.enumerated() where reading.state == .unmuted {
            var end = reading.readStart + timeToLive
            if let clip = readings[(index + 1)...].first(where: { $0.state != .unmuted }) {
                end = min(end, clip.readStart)
            }
            if end > reading.readEnd { windows.append(ScribeEvidenceWindow(start: reading.readEnd, end: end)) }
        }
        return windows
    }

    public func coverage(start: TimeInterval, end: TimeInterval) -> ScribeMicCoverage {
        ScribeMicAdmission.coverage(start: start, end: end, windows: unmutedWindows(), latest: latest(startedBy: end))
    }

    /// A nil `start` (capture time unknown) is dropped, never estimated.
    public func coverage(start: TimeInterval?, seconds: TimeInterval) -> ScribeMicCoverage {
        guard let start else { return .dropped(.unknown) }
        return coverage(start: start, end: start + seconds)
    }

    private func latest(startedBy time: TimeInterval) -> ScribeMuteState? {
        latestReading(startedBy: time)?.state
    }

    private func latestReading(startedBy time: TimeInterval) -> ScribeMuteReading? {
        readings.last { $0.readStart <= time }
    }
}

public enum ScribeMicStamp {
    /// The capture time of a microphone block's first frame, from the tap's host time. An invalid host time
    /// is nil: callback time is not capture time, and a delayed block must not be placed in a later window.
    public static func captureStart(hostTimeValid: Bool, hostTime: UInt64) -> TimeInterval? {
        hostTimeValid ? ScribeHostClock.seconds(hostTime: hostTime) : nil
    }
}

public enum ScribeMicAdmission {
    /// Admits `[start, end]` only when the union of `windows` covers all of it. `latest` is the newest
    /// reading's state at the end of the interval, used only to word a drop as muted or unknown.
    public static func coverage(
        start: TimeInterval,
        end: TimeInterval,
        windows: [ScribeEvidenceWindow],
        latest: ScribeMuteState? = nil
    ) -> ScribeMicCoverage {
        let dropped = ScribeMicCoverage.dropped(latest == .muted ? .muted : .unknown)
        guard start.isFinite, end.isFinite, end >= start else { return dropped }
        var cursor = start
        for window in windows.sorted(by: { $0.start < $1.start }) {
            if window.end < cursor { continue }
            if window.start > cursor { break }
            cursor = max(cursor, window.end)
            if cursor >= end { return .admitted }
        }
        return dropped
    }
}

// MARK: - Host clock

/// Seconds on the machine's monotonic clock (`mach_absolute_time`), the clock audio host times use. Cheap
/// and allocation-free after the first call, so audio callbacks may use it.
public enum ScribeHostClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(max(1, info.denom)) / 1_000_000_000
    }()

    public static func seconds(hostTime: UInt64) -> TimeInterval {
        Double(hostTime) * secondsPerTick
    }

    public static func now() -> TimeInterval {
        seconds(hostTime: mach_absolute_time())
    }
}

// MARK: - Save failures

/// Failed meeting saves, one entry per meeting. A later success clears only its own meeting.
public struct ScribeSaveFailureTracker<Payload> {
    public struct Entry {
        public let id: UUID
        public var message: String
        public var payload: Payload
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(for id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Replaces an earlier failure of the same meeting in place.
    public mutating func recordFailure(id: UUID, message: String, payload: Payload) {
        let entry = Entry(id: id, message: message, payload: payload)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    /// True when `id` had a recorded failure.
    @discardableResult
    public mutating func recordSuccess(id: UUID) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != before
    }

    public mutating func dismissAll() {
        entries.removeAll()
    }
}

extension ScribeSaveFailureTracker: Sendable where Payload: Sendable {}
extension ScribeSaveFailureTracker.Entry: Sendable where Payload: Sendable {}

// MARK: - System audio support

public enum ScribeSystemAudioSupport {
    public static let unavailableMessage = "System audio capture needs macOS 14.2 or later."

    /// The CoreAudio process tap and process-object APIs arrived in macOS 14.2.
    public static func isSupported(major: Int, minor: Int) -> Bool {
        major > 14 || (major == 14 && minor >= 2)
    }
}

// MARK: - Realtime sample ring

/// A bounded, preallocated ring of interleaved Float frames for one audio producer and one consumer.
/// The producer (an audio callback) never allocates and never blocks: it try-locks, and when the lock is
/// busy it adds the lost frames to a lock-free atomic counter; when the ring is full it drops the whole write
/// and counts the dropped frames. The consumer drains on a worker queue, where blocking briefly is fine.
public final class ScribeSampleRing: @unchecked Sendable {
    /// A run of drained frames that were captured contiguously, with the host time (seconds) of its first
    /// frame, or nil when the producer gave none (such audio can't be placed in time).
    public struct Block: Equatable, Sendable {
        public var frames: Int
        public var start: TimeInterval?

        public init(frames: Int, start: TimeInterval?) {
            self.frames = frames
            self.start = start
        }
    }

    public struct Drained: Sendable {
        /// Interleaved samples; `blocks` partition them in order (`frames * channels` samples each).
        public var samples: [Float]
        public var blocks: [Block]
    }

    private struct Marker {
        var frames: Int
        /// NaN when unknown.
        var start: Double
    }

    public let channels: Int
    public let capacityFrames: Int
    public let sampleRate: Double

    private static let markerCapacity = 512

    private let storage: UnsafeMutablePointer<Float>
    private let markers: UnsafeMutablePointer<Marker>
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    // Guarded by `lock`.
    private var head = 0
    private var stored = 0
    private var dropped = 0
    private var markerHead = 0
    private var markerCount = 0
    // Frames lost to lock contention: a lock-free atomic counter, allocated once. The producer only adds (never
    // blocks); the consumer reads and clears it directly, so a loss is reported even when no later write happens.
    private let contentionDrops: UnsafeMutablePointer<Int64>

    public init(capacityFrames: Int, channels: Int, sampleRate: Double = Double(ScribePCM.sampleRate)) {
        self.channels = max(1, channels)
        self.capacityFrames = max(1, capacityFrames)
        self.sampleRate = sampleRate > 0 ? sampleRate : Double(ScribePCM.sampleRate)
        let total = self.capacityFrames * self.channels
        storage = UnsafeMutablePointer<Float>.allocate(capacity: total)
        storage.initialize(repeating: 0, count: total)
        markers = UnsafeMutablePointer<Marker>.allocate(capacity: Self.markerCapacity)
        markers.initialize(repeating: Marker(frames: 0, start: .nan), count: Self.markerCapacity)
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        contentionDrops = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        contentionDrops.initialize(to: 0)
    }

    deinit {
        storage.deallocate()
        markers.deallocate()
        contentionDrops.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Realtime-safe. `sample(frame, channel)` is read once per sample while the lock is held. `start` is the
    /// host time (seconds) at which the first frame of this write was captured.
    /// Returns false when the write was dropped (lock busy or not enough room).
    @discardableResult
    public func write(frames: Int, at start: TimeInterval? = nil, sample: (_ frame: Int, _ channel: Int) -> Float) -> Bool {
        guard frames > 0 else { return true }
        guard os_unfair_lock_trylock(lock) else {
            recordContentionLoss(frames: frames)
            return false
        }
        defer { os_unfair_lock_unlock(lock) }
        guard frames <= capacityFrames - stored, markerCount < Self.markerCapacity else {
            dropped &+= frames
            return false
        }
        markers[(markerHead + markerCount) % Self.markerCapacity] = Marker(frames: frames, start: start ?? .nan)
        markerCount += 1
        var slot = (head + stored) % capacityFrames
        for frame in 0..<frames {
            let base = slot * channels
            for channel in 0..<channels { storage[base + channel] = sample(frame, channel) }
            slot += 1
            if slot == capacityFrames { slot = 0 }
        }
        stored += frames
        return true
    }

    /// What `write` does when the ring's lock is busy (public so a test can stage a contended final write).
    /// Realtime-safe: one atomic add, no lock, no allocation. OSAtomicAdd64Barrier is deprecated, but it is
    /// lock-free and available on the macOS 14.2 target (Swift's `Atomic` needs macOS 15); the deprecation
    /// warning is expected and deliberately left in place.
    public func recordContentionLoss(frames: Int) {
        _ = OSAtomicAdd64Barrier(Int64(frames), contentionDrops)
    }

    /// Reads and clears the contention counter. Adds that land between the read and the subtraction are kept
    /// for the next call, never lost.
    private func takeContentionLoss() -> Int {
        let seen = OSAtomicAdd64Barrier(0, contentionDrops)
        guard seen != 0 else { return 0 }
        _ = OSAtomicAdd64Barrier(-seen, contentionDrops)
        return Int(seen)
    }

    /// Consumer side: up to `maxFrames` frames, interleaved, oldest first. Empty when nothing is stored.
    public func drain(maxFrames: Int = Int.max) -> [Float] {
        drainBlocks(maxFrames: maxFrames).samples
    }

    /// Like `drain`, with the capture time of each contiguous run of frames.
    public func drainBlocks(maxFrames: Int = Int.max) -> Drained {
        os_unfair_lock_lock(lock)
        let wanted = min(stored, max(0, maxFrames))
        os_unfair_lock_unlock(lock)
        guard wanted > 0 else { return Drained(samples: [], blocks: []) }
        let width = channels
        var blocks: [Block] = []
        blocks.reserveCapacity(16)
        let samples = [Float](unsafeUninitializedCapacity: wanted * width) { buffer, initialized in
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            // `stored` only grows between the two locks, so `take` equals `wanted`.
            let take = min(wanted, stored)
            let firstRun = min(take, capacityFrames - head)
            if let out = buffer.baseAddress {
                out.initialize(from: storage + head * width, count: firstRun * width)
                if take > firstRun {
                    (out + firstRun * width).initialize(from: storage, count: (take - firstRun) * width)
                }
            }
            head = (head + take) % capacityFrames
            stored -= take
            initialized = take * width
            var remaining = take
            while remaining > 0, markerCount > 0 {
                var marker = markers[markerHead]
                let used = min(marker.frames, remaining)
                blocks.append(Block(frames: used, start: marker.start.isNaN ? nil : marker.start))
                remaining -= used
                if used == marker.frames {
                    markerHead = (markerHead + 1) % Self.markerCapacity
                    markerCount -= 1
                } else {
                    marker.frames -= used
                    if !marker.start.isNaN { marker.start += Double(used) / sampleRate }
                    markers[markerHead] = marker
                }
            }
        }
        return Drained(samples: samples, blocks: blocks)
    }

    public var storedFrames: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return stored
    }

    /// Frames dropped since the last call (full ring, or the lock was busy when they arrived). Needs no later
    /// write: after the producers have stopped, the final drain still sees every contention loss.
    public func takeDroppedFrames() -> Int {
        os_unfair_lock_lock(lock)
        let full = dropped
        dropped = 0
        os_unfair_lock_unlock(lock)
        return full &+ takeContentionLoss()
    }
}

// MARK: - Bounded queue

/// FIFO with a fixed capacity. Pushing into a full queue drops the oldest element (and counts it), so the
/// producer never blocks and the newest audio is kept.
public struct ScribeBoundedQueue<Element: Sendable>: Sendable {
    public let capacity: Int
    public private(set) var droppedCount = 0
    private var items: [Element] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    public var first: Element? { items.first }

    /// Returns the element dropped to make room, if any.
    @discardableResult
    public mutating func push(_ element: Element) -> Element? {
        var dropped: Element?
        if items.count >= capacity {
            dropped = items.removeFirst()
            droppedCount += 1
        }
        items.append(element)
        return dropped
    }

    public mutating func pop() -> Element? {
        items.isEmpty ? nil : items.removeFirst()
    }

    public mutating func removeAll() {
        items.removeAll()
    }
}

// MARK: - Shutdown order

public enum ScribeShutdownStep: Equatable, Sendable {
    case stopProducers
    case synchronizeProducers
    case drainRemaining
    case closeDelivery
    case emitEnded
}

public enum ScribeShutdown {
    /// Producers stop and are waited on before the final drain, and `captureEnded` is the last thing said,
    /// so no frame can follow it and none still held by a producer is lost.
    public static let order: [ScribeShutdownStep] = [
        .stopProducers, .synchronizeProducers, .drainRemaining, .closeDelivery, .emitEnded,
    ]
}

// MARK: - Meeting record and store

/// A finished meeting as kept on disk. Audio is never part of it.
public struct ScribeMeetingRecord: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var text: String
        public var done: Bool

        public init(text: String, done: Bool) {
            self.text = text
            self.done = done
        }
    }

    public struct Line: Codable, Equatable, Sendable {
        public var id: String
        /// "you", "participant" or "unknown".
        public var speakerKind: String
        public var speakerLabel: String?
        public var start: TimeInterval
        public var end: TimeInterval
        public var text: String

        public init(id: String, speakerKind: String, speakerLabel: String?, start: TimeInterval, end: TimeInterval, text: String) {
            self.id = id
            self.speakerKind = speakerKind
            self.speakerLabel = speakerLabel
            self.start = start
            self.end = end
            self.text = text
        }
    }

    /// One closed speech turn's voice, saved with the meeting so "Remember this voice" and the post-meeting
    /// corrections still work after a relaunch. It lives only in this meeting's file (0600), is removed with
    /// the file and is never uploaded. `vector` is little-endian Float32 (Codable stores it as base64).
    /// Conversion to and from `ScribeTurnEmbedding` is in `ScribeMeetingVoices.swift`.
    public struct TurnVoice: Codable, Equatable, Sendable {
        public var segmentID: String
        /// "microphone" or "system".
        public var source: String
        /// "handBuilt" or "wespeaker".
        public var kind: String
        public var vector: Data
        public var duration: TimeInterval

        public init(segmentID: String, source: String, kind: String, vector: Data, duration: TimeInterval) {
            self.segmentID = segmentID
            self.source = source
            self.kind = kind
            self.vector = vector
            self.duration = duration
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var title: String
    public var endedAt: Date
    public var duration: TimeInterval
    public var summary: String
    public var decisions: [String]
    public var actionItems: [Item]
    public var privateNotes: String
    public var generatedAt: Date?
    public var method: String?
    public var transcript: [Line]
    /// Set when the person dismissed the recap card. The file stays on disk.
    public var dismissedAt: Date?
    /// Set when part of the meeting could not be transcribed, so the notes may be missing speech.
    public var transcriptionNote: String?
    /// True when the microphone was left out during a detected call. Absent in older files.
    public var micExcludedDuringCall: Bool?
    /// Display names from the calendar invite (never email addresses). Absent in older files.
    public var attendees: [String]?
    /// Each closed turn's voice, for speaker naming after a relaunch. Absent in older files.
    public var turnVoices: [TurnVoice]?
    /// Who each name came from (typed, call window, invite, introduction, saved voice), how sure, names the
    /// person declined, and folded tiny voices. Absent in older files: their names then count as typed.
    public var speakerBook: ScribeSpeakerBook?

    public init(
        id: UUID,
        title: String,
        endedAt: Date,
        duration: TimeInterval,
        notes: ScribeMeetingNotes,
        transcript: [ScribeTranscriptSegment],
        dismissedAt: Date? = nil,
        transcriptionNote: String? = nil,
        micExcludedDuringCall: Bool = false,
        attendees: [String] = [],
        turnVoices: [TurnVoice] = [],
        speakerBook: ScribeSpeakerBook? = nil
    ) {
        self.attendees = attendees.isEmpty ? nil : attendees
        self.turnVoices = turnVoices.isEmpty ? nil : turnVoices
        self.speakerBook = speakerBook
        self.transcriptionNote = transcriptionNote
        self.micExcludedDuringCall = micExcludedDuringCall ? true : nil
        self.version = Self.currentVersion
        self.id = id
        self.title = title
        self.endedAt = endedAt
        self.duration = duration
        self.summary = notes.summary
        self.decisions = notes.decisions
        self.actionItems = notes.actionItems.map { Item(text: $0.text, done: $0.done) }
        self.privateNotes = notes.privateNotes
        self.generatedAt = notes.generatedAt
        self.method = notes.method.map { _ in "extractive" }
        self.transcript = transcript.map(Self.line(from:))
        self.dismissedAt = dismissedAt
    }

    public var meetingNotes: ScribeMeetingNotes {
        ScribeMeetingNotes(
            summary: summary,
            decisions: decisions,
            actionItems: actionItems.map { ScribeActionItem(text: $0.text, done: $0.done) },
            privateNotes: privateNotes,
            generatedAt: generatedAt,
            method: method == "extractive" ? .extractive : nil
        )
    }

    /// The saved lines as final segments of `session`.
    public func segments(session: ScribeSessionID) -> [ScribeTranscriptSegment] {
        transcript.map { line in
            let speaker: ScribeSpeaker
            switch line.speakerKind {
            case "you": speaker = .you
            case "participant": speaker = .participant(line.speakerLabel ?? "Speaker")
            default: speaker = .unknown
            }
            return ScribeTranscriptSegment(
                id: line.id, session: session, speaker: speaker,
                start: line.start, end: line.end, text: line.text, isFinal: true
            )
        }
    }

    public static func fileName(for id: UUID) -> String {
        "\(id.uuidString.lowercased()).json"
    }

    public var fileName: String { Self.fileName(for: id) }

    private static func line(from segment: ScribeTranscriptSegment) -> Line {
        let kind: String
        var label: String?
        switch segment.speaker {
        case .you: kind = "you"
        case .participant(let name): kind = "participant"; label = name
        case .unknown: kind = "unknown"
        }
        return Line(id: segment.id, speakerKind: kind, speakerLabel: label, start: segment.start, end: segment.end, text: segment.text)
    }
}

public enum ScribeMeetingStoreError: LocalizedError, Equatable {
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .write(let detail): return detail
        }
    }
}

/// JSON files, one per meeting, written 0600 into a 0700 directory. Writes are atomic: a temporary file
/// is created with its final permissions and then swapped in, so a crash never leaves half a meeting.
public struct ScribeMeetingStore: Sendable {
    public struct LoadResult: Sendable {
        public var records: [ScribeMeetingRecord]
        /// One line per file that could not be read. Never silently dropped.
        public var failures: [String]
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var standard: ScribeMeetingStore {
        ScribeMeetingStore(directory: ZeusPaths.supportDirectory
            .appendingPathComponent("scribe", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true))
    }

    public func save(_ record: ScribeMeetingRecord) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try Self.encoder().encode(record)
            let target = directory.appendingPathComponent(record.fileName)
            let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
            guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw ScribeMeetingStoreError.write("Couldn't create \(temporary.lastPathComponent).")
            }
            do {
                if fileManager.fileExists(atPath: target.path) {
                    _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: target)
                }
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        } catch let error as ScribeMeetingStoreError {
            throw error
        } catch {
            throw ScribeMeetingStoreError.write("Couldn't save the meeting: \(error.localizedDescription)")
        }
    }

    /// Removes the meeting's file for good (the transcript and private notes with it). A file that is
    /// already gone counts as deleted; any other failure is thrown so the caller can say it still exists.
    public func delete(id: UUID) throws {
        let target = directory.appendingPathComponent(ScribeMeetingRecord.fileName(for: id))
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw ScribeMeetingStoreError.write("Couldn't delete the meeting: \(error.localizedDescription)")
        }
    }

    public func loadAll() -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return LoadResult(records: [], failures: []) }
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            return LoadResult(records: [], failures: ["Couldn't read the meetings folder: \(error.localizedDescription)"])
        }
        var records: [ScribeMeetingRecord] = []
        var failures: [String] = []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                records.append(try Self.decoder().decode(ScribeMeetingRecord.self, from: data))
            } catch {
                failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        records.sort { $0.endedAt > $1.endedAt }
        return LoadResult(records: records, failures: failures.sorted())
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
