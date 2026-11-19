import Foundation

/// Spots "Hey Zeus" in a running transcript, including the ways Apple's recogniser tends to hear
/// it ("hey zoos", "hey Seuss", "hey Zeus's", "heyzeus"), and returns what was said after it, so
/// "Hey Zeus open Spotify" is one request. Pure text: the audio side lives in the app.
public enum WakePhrase {
    public struct Match: Equatable, Sendable {
        /// What followed the wake phrase, as said ("open Spotify"); empty when nothing yet.
        public let request: String
        /// Words before the wake phrase, which are ignored.
        public let skippedWords: Int
    }

    // "the" was dropped from here (item 6, QA7): "the zeus pantheon" is ordinary talk, not a wake
    // phrase, and nothing in the mishearing tests needed "the" as a greeting.
    static let greetings: Set<String> = ["hey", "hi", "okay", "a", "hay", "he", "hei", "ei", "oi", "eh", "hej", "ay", "aye", "yo"]
    static let names: Set<String> = [
        "zeus", "zoos", "zuse", "zues", "zeuss", "zoose", "zous", "zus", "zeuz", "seuss", "suess", "soos", "zeuce", "theus", "ceus", "zeas",
    ]
    /// Said as one word by the recogniser.
    static let fused: Set<String> = ["heyzeus", "hayzeus", "heyzoos", "heyseuss", "heyjesus"]
    /// Mishearings real enough to matter, but common enough as ordinary words ("the juice is
    /// cold", "a zest of lemon") that they only count directly after "hey" or "hi" -- never after
    /// any of the looser `greetings` -- so casual talk is never mistaken for the wake phrase
    /// (item 6, QA7). "jesus" counts only after hey or hi, where it is a mishearing of Zeus.
    /// Bare "jesus open calculator" is ordinary talk and does not wake.
    static let qualifiedGreetings: Set<String> = ["hey", "hi"]
    static let qualifiedNames: Set<String> = ["juice", "zest", "deus", "jesus"]
    /// First word after the wake phrase when the user is talking *about* someone, not to Zeus.
    static let narrativeTailStarters: Set<String> = ["was", "is", "are", "were", "am", "has", "had", "have", "been", "being"]

    /// Finds the last wake phrase in `transcript`.
    public static func spot(_ transcript: String) -> Match? {
        let utterance = Utterance(transcript)
        let words = utterance.words
        var found: (start: Int, end: Int)?
        var i = 0
        while i < words.count {
            if fused.contains(words[i]), acceptsTail(words: words, end: i + 1, utterance: utterance) { found = (i, i + 1) }
            else if i + 1 < words.count, greetings.contains(words[i]), names.contains(words[i + 1]),
                    acceptsTail(words: words, end: i + 2, utterance: utterance) { found = (i, i + 2) }
            else if i + 1 < words.count, qualifiedGreetings.contains(words[i]), qualifiedNames.contains(words[i + 1]),
                    acceptsTail(words: words, end: i + 2, utterance: utterance) { found = (i, i + 2) }
            i += 1
        }
        guard let found else { return nil }
        let request = utterance.source(found.end..<words.count)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return Match(request: request, skippedWords: found.start)
    }

    /// Empty tail is a hands-free wake; otherwise reject "hey jesus was her neighbor" style chatter.
    static func acceptsTail(words: [String], end: Int, utterance: Utterance) -> Bool {
        let request = utterance.source(end..<words.count)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !request.isEmpty else { return true }
        guard let first = Utterance(request).words.first else { return true }
        return !narrativeTailStarters.contains(first)
    }

    /// How many leading normalised words are a wake phrase ("hey zeus", "okay zeus"), if any.
    public static func prefixLength(_ words: [String]) -> Int? {
        guard let first = words.first else { return nil }
        if fused.contains(first) { return 1 }
        if words.count >= 2, greetings.contains(first) || first == "ok", names.contains(words[1]) { return 2 }
        if words.count >= 2, qualifiedGreetings.contains(first), qualifiedNames.contains(words[1]) { return 2 }
        return nil
    }
}

/// Whether the always-on "Hey Zeus" listener may run right now. Pure, so the rules are tested.
public struct WakeGate: Equatable, Sendable {
    public var enabled = true
    public var micAllowed = false
    public var speechAllowed = false
    public var onDeviceSupported = true
    public var talkKeyActive = false
    public var dictating = false
    public var speaking = false
    public var turnRunning = false
    public var otherAppRecording = false
    public var screenLocked = false
    public var cooldown = false

    public init() {}

    /// nil when listening is allowed, else why not (logged and shown in Settings).
    public var pauseReason: String? {
        if !enabled { return "off" }
        if !micAllowed || !speechAllowed { return "needs microphone and speech recognition" }
        if !onDeviceSupported { return "on-device recognition isn't available for this language" }
        if screenLocked { return "Mac locked" }
        if talkKeyActive { return "talk key" }
        if dictating { return "dictation" }
        if speaking { return "Zeus is speaking" }
        if turnRunning { return "turn running" }
        if otherAppRecording { return "another app is using the microphone" }
        if cooldown { return "just woke" }
        return nil
    }

    public var mayListen: Bool { pauseReason == nil }

    /// The `zeus status` line: "listening", "paused (dictation)", "no permission", "off".
    public func statusLine(listening: Bool) -> String {
        guard let reason = pauseReason else { return listening ? "listening" : "starting" }
        if reason == "off" { return "off" }
        if !micAllowed || !speechAllowed { return "no permission" }
        return "paused (\(reason))"
    }
}

/// Whether another process recording from the microphone should pause "Hey Zeus" (item 6, QA7).
/// Pure decision, so the Core Audio walk in `MicUsage.otherAppRecording()` can stay a thin
/// wrapper around it. The bug: that walk used to treat *any* non-"com.apple." bundle ID as a
/// conflict, which included a second Zeus instance and headless recorders with no bundle ID at
/// all (ffmpeg, sox, ad hoc QA tooling) -- the exact things QA's own recorder looked like.
public enum MicConflict {
    /// Apps where "recording" really means "on a call": only these (plus Apple's own small
    /// `callServices` list) pause the wake word. Everything else recording -- a second Zeus, a
    /// headless recorder, some other unrelated app -- does not.
    public static let callApps: Set<String> = [
        "com.apple.FaceTime", "com.apple.avconferenced", "com.apple.TelephonyUtilities",
        "com.apple.VoiceMemos", "com.apple.QuickTimePlayerX", "com.apple.PhotoBooth",
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap",
        "com.webex.meetingmanager", "com.cisco.webexmeetingsapp", "com.hnc.Discord",
        "com.skype.skype", "com.google.Chrome", "com.apple.Safari",
    ]

    /// True when `bundleID`'s microphone use should count as a conflict and pause "Hey Zeus".
    public static func counts(bundleID: String, pid: pid_t, ownPID: pid_t) -> Bool {
        guard pid != ownPID else { return false }
        guard !bundleID.isEmpty else { return false }
        guard !bundleID.hasPrefix("app.zeus") else { return false }
        // Calls usually capture through helper processes (a browser's audio or WebKit GPU helper, a call
        // app's helper), whose bundle IDs never match exactly. Map them to their app as Scribe does.
        return callApps.contains(bundleID) || ScribeCallDetection.appBundleID(for: bundleID) != nil
    }
}

/// macOS's answer for one privacy permission, without the framework types so it can be tested.
public enum PermissionState: Equatable, Sendable { case notDetermined, denied, authorized }

/// What voice should do about the microphone and speech recognition permissions.
public enum VoiceAccess: Equatable, Sendable {
    case ready
    /// Neither was refused: ask now (once per permission, ever).
    case needsPrompt
    /// At least one was refused: only System Settings can change it.
    case denied(mic: Bool, speech: Bool)

    public static func decide(mic: PermissionState, speech: PermissionState) -> VoiceAccess {
        if mic == .authorized, speech == .authorized { return .ready }
        if mic == .denied || speech == .denied { return .denied(mic: mic == .denied, speech: speech == .denied) }
        return .needsPrompt
    }

    /// Whether ZEUS should raise the system prompt on this occasion. `wakeOn` is the launch case:
    /// the wake word is enabled, so asking is expected; the other entry points (turning the
    /// switch on, the talk key, onboarding) pass `explicit`.
    public func shouldPrompt(wakeOn: Bool, explicit: Bool) -> Bool {
        guard self == .needsPrompt else { return false }
        return explicit || wakeOn
    }

    /// The notch cue when denied; nil otherwise.
    public var deniedCue: String? {
        guard case .denied(let mic, let speech) = self else { return nil }
        if mic { return "Zeus can't hear you: allow the microphone" }
        if speech { return "Zeus can't hear you: allow speech recognition" }
        return nil
    }

    /// Which Privacy pane fixes it.
    public var deniedPane: String? {
        guard case .denied(let mic, _) = self else { return nil }
        return mic ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
    }
}

/// Energy-based voice activity with an adaptive noise floor, so the recogniser only runs while
/// someone is talking. Each call takes one buffer's RMS; cheap enough for the audio thread.
public struct VoiceActivity: Sendable {
    public private(set) var floor: Float = 0.002
    public private(set) var active = false
    /// Buffers above the threshold in a row before speech counts as started.
    public var attack = 2
    /// Seconds of quiet before speech counts as over.
    public var hangover: Double = 1.2
    public var ratio: Float = 2.2
    public var minimum: Float = 0.003
    private var loud = 0
    private var quietSeconds: Double = 0

    public init() {}

    public var threshold: Float { max(floor * ratio, minimum) }

    /// Feeds one buffer (its RMS and length in seconds). Returns true while speech is active.
    @discardableResult
    public mutating func feed(rms: Float, seconds: Double) -> Bool {
        if rms > threshold {
            loud += 1
            quietSeconds = 0
            if loud >= attack { active = true }
        } else {
            loud = 0
            quietSeconds += seconds
            if active, quietSeconds >= hangover { active = false }
            // The floor follows the room slowly, only while quiet, so speech never raises it.
            floor = floor * 0.95 + max(rms, 0.0005) * 0.05
        }
        return active
    }

    /// Seconds since the last loud buffer.
    public var silence: Double { quietSeconds }
}

/// Offline speech-activity segmentation: the same `VoiceActivity` the live listener uses, run
/// over a recording. The voice self-test prints these, and tests feed it generated tones.
public enum VoiceSegments {
    public struct Segment: Equatable, Sendable {
        public let start: Double
        public let end: Double
        public var length: Double { end - start }
    }

    /// `frames` per step mirrors the live tap (4096 frames per buffer).
    public static func find(samples: [Float], sampleRate: Double, frames: Int = 4096) -> [Segment] {
        guard sampleRate > 0, frames > 0 else { return [] }
        var vad = VoiceActivity()
        var segments: [Segment] = []
        var openedAt: Double?
        var index = 0
        while index < samples.count {
            let count = min(frames, samples.count - index)
            var sum: Float = 0
            for i in index..<(index + count) { sum += samples[i] * samples[i] }
            let rms = (sum / Float(count)).squareRoot()
            let seconds = Double(count) / sampleRate
            let now = Double(index + count) / sampleRate
            let speaking = vad.feed(rms: rms, seconds: seconds)
            if speaking, openedAt == nil { openedAt = now - seconds }
            if !speaking, let start = openedAt {
                segments.append(Segment(start: start, end: now - vad.silence))
                openedAt = nil
            }
            index += count
        }
        if let start = openedAt { segments.append(Segment(start: start, end: Double(samples.count) / sampleRate)) }
        return segments
    }
}
