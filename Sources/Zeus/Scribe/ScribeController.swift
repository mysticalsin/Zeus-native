import AppKit
import Foundation
import Observation
import SwiftUI
import ZeusCore

/// Default provider when none is injected (tests, previews): it never records, and says so at once.
/// The shipped app uses `ScribeLiveCaptureProvider` (see `ScribeController.shared`).
/// Scribe can therefore never show a fake recording state.
struct ScribeUnavailableCaptureProvider: ScribeCaptureProvider {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { ScribeUnavailableCaptureProvider.reason }
    }

    static let reason = "Meeting capture isn't available in this build yet."

    func start(
        session: ScribeSessionID,
        frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
        events: @escaping @Sendable (ScribeCaptureEvent) -> Void
    ) {
        events(.failed(session, Unavailable()))
    }

    func stop(session: ScribeSessionID) {}
}

// Defaults for a controller built without live services (tests, previews). They are deliberately inert:
// no audio is kept or recognised, and the mic reads as unknown (fail closed). The shipped app injects
// `ScribeMuteDetector` and `ScribeTranscriberBridge`; audio is never stored (`ScribeDiscardingFrameStore`).

/// PLACEHOLDER frame store: discards every frame.
struct ScribeDiscardingFrameStore: ScribeFrameStore {
    func store(_ frame: ScribeAudioFrame) throws {}
}

/// PLACEHOLDER transcriber: recognises nothing. Segments reach the controller only through `receive(_:)`.
struct ScribePlaceholderTranscriber: ScribeTranscriber {
    func ingest(_ frame: ScribeAudioFrame) {}
    func finish(session: ScribeSessionID) {}
}

/// PLACEHOLDER mute source: always unknown, so the gate drops microphone frames.
struct ScribeUnknownMuteSource: ScribeMicMuteSource {
    func currentMuteState() -> ScribeMuteState { .unknown }
}

/// Remembers what the router last read, so the page can say why microphone audio is or isn't recorded.
/// Written from the capture thread, read to decide whether to publish a change to the main actor.
final class ScribeLiveReadout: @unchecked Sendable {
    private let lock = NSLock()
    private var mute: ScribeMuteState?
    private var systemSeen = false

    /// True when the reading differs from the last one.
    func noteMute(_ state: ScribeMuteState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard mute != state else { return false }
        mute = state
        return true
    }

    private var lastSystemFrame: TimeInterval?
    private var recordingStarted: TimeInterval?

    /// True the first time a system-audio frame arrives. Every call also stamps the latest arrival.
    func noteSystemFrame() -> Bool {
        let now = ScribeHostClock.now()
        lock.lock()
        defer { lock.unlock() }
        lastSystemFrame = now
        guard !systemSeen else { return false }
        systemSeen = true
        return true
    }

    /// Capture is acknowledged: silence is counted from here until the first frame.
    func markRecordingStarted() {
        let now = ScribeHostClock.now()
        lock.lock()
        defer { lock.unlock() }
        recordingStarted = now
    }

    /// Seconds since the last system-audio frame (or since recording began, if none came). nil before capture.
    func systemSilentSeconds() -> TimeInterval? {
        let now = ScribeHostClock.now()
        lock.lock()
        defer { lock.unlock() }
        guard let reference = lastSystemFrame ?? recordingStarted else { return nil }
        return max(0, now - reference)
    }
}

/// Wraps a mute source: the router still decides from this reading, and the page learns what it was.
struct ScribeObservingMuteSource: ScribeMicMuteSource {
    let base: any ScribeMicMuteSource
    let readout: ScribeLiveReadout
    let changed: @Sendable (ScribeMuteState) -> Void

    func currentMuteState() -> ScribeMuteState {
        let state = base.currentMuteState()
        if readout.noteMute(state) { changed(state) }
        return state
    }
}

/// A finished meeting in the recap list. Saved as JSON by `ScribeMeetingStore` when the controller has one.
struct ScribeRecap: Identifiable, Equatable {
    let id: ScribeSessionID
    var title: String
    var endedAt: Date
    var duration: TimeInterval
    var notes: ScribeMeetingNotes
    var transcript: [ScribeTranscriptSegment]
    /// Set when part of the meeting couldn't be transcribed, so the notes may be missing speech.
    var transcriptionNote: String? = nil
    /// Set when the microphone was left out while a call app was open (saved with the meeting).
    var micExcludedDuringCall = false
}

/// What the transcriber reports, in the order it happened. One consumer applies them one at a time, so the
/// completion can never overtake the last segment.
enum ScribeTranscriberEvent: Sendable {
    case segment(ScribeTranscriptSegment)
    case turns([ScribeTurnEmbedding])
    case issue(String)
    case finished(ScribeSessionID)
}

/// What the capture side reports, in the order it happened: lifecycle events, capture issues and microphone
/// verdicts all share one stream, so an issue always lands before the `captureEnded` that follows it.
enum ScribeCaptureInput: Sendable {
    case event(ScribeCaptureEvent)
    case issue(ScribeCaptureIssue)
    case microphone(ScribeMuteState)
}

/// A meeting whose file couldn't be written, as the page lists it.
struct ScribeUnsavedMeeting: Identifiable, Equatable {
    let id: ScribeSessionID
    var title: String
    var message: String
}

/// What a retry of a failed save writes.
private struct ScribeFailedSave {
    var recap: ScribeRecap
    var dismissedAt: Date?
}

/// The newest loudness of each source, written from the capture side and read by a main-actor timer, so audio
/// never queues work on the main actor. A source that hasn't reported lately reads as silent.
final class ScribeLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var mic = 0.0
    private var system = 0.0
    private var micAt = -TimeInterval.infinity
    private var systemAt = -TimeInterval.infinity

    func set(_ source: ScribeAudioSource, _ level: Double) {
        let now = ScribeHostClock.now()
        lock.withLock {
            switch source {
            case .microphone:
                mic = level
                micAt = now
            case .system:
                system = level
                systemAt = now
            }
        }
    }

    /// The louder of the two sources, each counted only if it reported within `staleAfter` seconds.
    func current(staleAfter: TimeInterval = 0.3) -> Double {
        let now = ScribeHostClock.now()
        return lock.withLock {
            max(now - micAt <= staleAfter ? mic : 0, now - systemAt <= staleAfter ? system : 0)
        }
    }
}

/// Word-level views of a segment's text, for revealing it a few words at a time.
enum ScribeWordText {
    static func count(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The first `words` words, joined by single spaces; the text itself once every word is shown.
    static func prefix(_ text: String, words: Int) -> String {
        let all = text.split(whereSeparator: \.isWhitespace)
        guard words < all.count else { return text }
        return all.prefix(max(0, words)).joined(separator: " ")
    }
}

/// What a segment's reveal started from the last time its text changed.
private struct ScribeWordRevealEntry {
    var text: String
    var alreadyShown: Int
    var since: Date
    var layout: ScribeIncomingWordLayout
}

/// Cancelled meetings whose transcript file couldn't be removed. Kept in the app's preferences, outside the
/// meetings folder that just failed, so the next launch finishes the deletion and never lists the transcript.
enum ScribeCancelTombstones {
    private static let key = "scribe.cancelledMeetings"

    static var ids: Set<UUID> { ids(in: .standard) }

    static func ids(in defaults: UserDefaults) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap { UUID(uuidString: $0) })
    }

    static func add(_ id: UUID, in defaults: UserDefaults = .standard) { write(ids(in: defaults).union([id]), to: defaults) }

    static func remove(_ id: UUID, in defaults: UserDefaults = .standard) { write(ids(in: defaults).subtracting([id]), to: defaults) }

    private static func write(_ ids: Set<UUID>, to defaults: UserDefaults) {
        if ids.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(ids.map(\.uuidString).sorted(), forKey: key)
        }
    }
}

@MainActor
@Observable
final class ScribeController {
    /// The app's controller: live capture, live mute reading, real transcription, meetings kept on disk.
    /// Creating it (first access) starts the call watcher; nothing is captured until `start()`.
    static let shared = ScribeController.makeProduction()

    /// The machine is the single source of truth. Everything the page shows derives from `machine.phase`.
    private(set) var machine = ScribeSessionMachine()
    /// Transient feedback only after final persistence succeeds. A late expiry cannot clear a newer session.
    private(set) var completedNoticeID: ScribeSessionID?
    @ObservationIgnored private var completedNoticeTask: Task<Void, Never>?
    /// Clock text only. Never read to decide a state.
    private(set) var elapsed: TimeInterval = 0
    private(set) var transcript: ScribeTranscript?
    private(set) var notes: ScribeMeetingNotes?
    private(set) var recaps: [ScribeRecap] = []
    /// When the current phase began (drawing origin for the glow; set only by machine transitions).
    private(set) var stageStart = Date()
    /// When `notesReady` was applied (drawing origin for the wash).
    private(set) var revealStart: Date?
    /// The router's latest microphone mute reading this session (nil until the first microphone frame).
    private(set) var micMute: ScribeMuteState?
    /// Whether any system-audio frame has arrived this session.
    private(set) var systemAudioReceiving = false
    /// Changes on every presentation-state change; the page's focus anchor moves VoiceOver when it does.
    private(set) var focusToken = 0
    /// Why saved meetings couldn't be read (never silent), until dismissed.
    private(set) var loadIssue: String?
    /// Every meeting whose save failed and hasn't succeeded since, oldest first. Each can be retried or
    /// dismissed on its own; a later successful save of another meeting clears none of them.
    private(set) var unsavedMeetings: [ScribeUnsavedMeeting] = []
    /// Problems capturing or recognising speech this session, oldest first, without repeats (a chunk that
    /// couldn't be transcribed, transcription falling behind, audio lost in capture, microphone not recorded).
    /// Any entry means the notes may be missing speech, and is saved with the meeting.
    private(set) var transcriptionIssues: [String] = []
    /// Seconds of microphone audio withheld this session because the mute state couldn't be established.
    private(set) var microphoneUnknownSeconds: Double = 0
    /// The microphone is being dropped right now because a call was detected.
    private(set) var micCallExcludedNow = false
    /// The microphone was dropped because of a call at some point this session; kept with the meeting.
    private(set) var micExcludedDuringCall = false
    /// Why capture stopped before the person ended the meeting (what was captured is still kept and saved).
    private(set) var stoppedEarlyReason: String?
    /// Set when the notes couldn't be written or were cancelled; the transcript is saved without them.
    private(set) var notesIssue: String?
    /// Meeting audio has stopped arriving mid-recording (a live warning; cleared when it resumes).
    private(set) var systemAudioStalled = false
    /// The saved meeting whose notes are open on the idle page, if any.
    private(set) var openedRecapID: ScribeSessionID?
    /// A meeting waiting for the person to confirm "Delete permanently".
    private(set) var pendingDeleteID: ScribeSessionID?
    /// A meeting waiting for the person to confirm discarding an unsaved recap.
    private(set) var pendingDiscardID: ScribeSessionID?
    /// Why the last permanent delete failed, until the next attempt or dismissal.
    private(set) var deleteIssue: String?
    /// Title for the next recording, set by the call popup from the calendar event or call app.
    /// The transcript being kept on disk while notes are written couldn't be saved (retried; shown until it is).
    private(set) var checkpointIssue: String?
    /// A cancelled meeting's transcript checkpoint couldn't be removed from disk (retryable).
    private(set) var cleanupIssue: String?
    /// How loud the meeting audio is, newest last (about 20 values a second, the last 24 kept). Empty when
    /// nothing is recording; decays to zeros when no audio arrives. Drives the meter on the page and the wings.
    private(set) var levelHistory: [Double] = []
    /// Cached only on real transcript revisions, so a display link can stop once incoming text settles.
    private(set) var incomingWordsRevealUntil: Date?
    /// The person pressed the trash button and hasn't confirmed throwing the recording away yet.
    private(set) var discardRequested = false
    @ObservationIgnored var meetingTitleHint: String?
    /// Display names from the calendar invite the call popup matched; for the next recording only.
    @ObservationIgnored var meetingAttendeeHint: [String] = []
    /// This recording's attendee names, and each finished meeting's (display names only). Saved with the meeting file.
    @ObservationIgnored private var sessionAttendees: [String] = []
    @ObservationIgnored private var attendeesByMeeting: [UUID: [String]] = [:]
    /// The voice of each closed turn, per meeting. Saved only inside that meeting's own file (0600) so naming works
    /// after a relaunch, dropped from memory when the meeting is dismissed, and removed with the file on delete.
    @ObservationIgnored private var liveTurns: [ScribeTurnEmbedding] = []
    @ObservationIgnored private var turnVoices: [UUID: [ScribeTurnEmbedding]] = [:]
    @ObservationIgnored var meetingCallHint: ScribeCallProcessIdentity?
    private var endWorkflow = ScribeEndWorkflow()
    private(set) var endingRemaining: Int?
    var endingReason: ScribeEndWorkflow.Reason? { endWorkflow.reason }
    var endStopRequested: Bool { endWorkflow.stopRequested }
    @ObservationIgnored private var levelBox: ScribeLevelBox?
    @ObservationIgnored private var levelTimer: Timer?
    @ObservationIgnored private var wordReveals: [String: ScribeWordRevealEntry] = [:]
    @ObservationIgnored private var notesReadyTask: Task<Void, Never>?
    @ObservationIgnored private var checkpointGate = ScribeCheckpointGate()
    @ObservationIgnored private var checkpointFlushTask: Task<Void, Never>?
    /// Meetings with a checkpoint file written by this run and not yet removed or turned into a recap.
    @ObservationIgnored private var checkpointedMeetings: Set<UUID> = []
    /// Discarded meetings whose checkpoint file still needs deleting.
    @ObservationIgnored private var pendingCleanup: Set<UUID> = []
    @ObservationIgnored private var readout: ScribeLiveReadout?
    @ObservationIgnored private var stallTimer: Timer?
    @ObservationIgnored private var pendingSaves: Set<UUID> = []

    @ObservationIgnored private let provider: any ScribeCaptureProvider
    @ObservationIgnored private let generator: any ScribeNotesGenerator
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let monotonicClock: () -> TimeInterval
    @ObservationIgnored private let store: ScribeMeetingStore?
    @ObservationIgnored private let cancellationDefaults: UserDefaults
    @ObservationIgnored private let transcriptionEngine: () -> TranscriptionEngineKind
    @ObservationIgnored private let writeMeeting: (ScribeMeetingRecord) throws -> Void
    @ObservationIgnored private let muteSourceFactory: () -> any ScribeMicMuteSource
    @ObservationIgnored private let transcriberFactory: (ScribeSessionID, ScribeTranscriberCallbacks) -> any ScribeTranscriber
    @ObservationIgnored private let paceWritingMotion: Bool
    @ObservationIgnored private let endWindow: ScribeEndWindow?
    @ObservationIgnored private var router: ScribeFrameRouter?
    @ObservationIgnored private var transcriber: (any ScribeTranscriber)?
    @ObservationIgnored private var sessionTitle: String?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var recordingSince: TimeInterval?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var transcriberEvents: AsyncStream<ScribeTranscriberEvent>.Continuation?
    @ObservationIgnored private var transcriberEventTask: Task<Void, Never>?
    @ObservationIgnored private var captureInputs: AsyncStream<ScribeCaptureInput>.Continuation?
    @ObservationIgnored private var captureInputTask: Task<Void, Never>?
    @ObservationIgnored private var saveFailures = ScribeSaveFailureTracker<ScribeFailedSave>()

    static let discardQuestion = "Throw this recording away? Nothing will be saved."
    static let audioLostMessage = "Some audio was lost while recording, so these notes may be missing speech."
    static let microphoneUnknownMessage = "Part of your microphone wasn't recorded because its mute state was unknown."
    static let microphoneUnknownNote = "Your microphone isn't being recorded: mute state unknown"
    /// Withheld-unknown microphone time below this (the first reading after start) isn't worth a warning.
    private static let microphoneUnknownThreshold: TimeInterval = 2


    private static let levelHistoryCount = 24

    /// The writing band's whole rise, hold and recede. The surge starts after it so the motion is never cut.
    private static let minimumWritingSeconds =
        ScribeGlow.riseDelay + ScribeGlow.riseDuration + ScribeGlow.holdDuration + ScribeGlow.recedeDuration

    private static let cleanupFailedMessage = "The cancelled meeting's transcript couldn't be deleted from this Mac. Zeus will try again."

    /// `store` nil keeps meetings in memory only (tests). The factories default to inert stand-ins.
    /// `paceWritingMotion` (the shipped app) holds the notes reveal until the writing band has played;
    /// tests leave it off so a finished transcript completes at once.
    init(
        provider: any ScribeCaptureProvider = ScribeUnavailableCaptureProvider(),
        generator: any ScribeNotesGenerator = ScribeExtractiveNotesGenerator(),
        clock: @escaping () -> Date = { Date() },
        monotonicClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        store: ScribeMeetingStore? = nil,
        muteSourceFactory: @escaping () -> any ScribeMicMuteSource = { ScribeUnknownMuteSource() },
        transcriberFactory: @escaping (ScribeSessionID, ScribeTranscriberCallbacks) -> any ScribeTranscriber = { _, _ in
            ScribePlaceholderTranscriber()
        },
        paceWritingMotion: Bool = false,
        showsEndWindow: Bool = false,
        writeMeeting: ((ScribeMeetingRecord) throws -> Void)? = nil,
        cancellationDefaults: UserDefaults = .standard,
        endWindow: ScribeEndWindow? = nil,
        transcriptionEngine: @escaping () -> TranscriptionEngineKind = { DictationSettings.shared.engine },
        motionReduced: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.provider = provider
        self.generator = generator
        self.clock = clock
        self.monotonicClock = monotonicClock
        self.store = store
        self.cancellationDefaults = cancellationDefaults
        self.transcriptionEngine = transcriptionEngine
        self.motionReduced = motionReduced
        self.writeMeeting = writeMeeting ?? { record in try store?.save(record) }
        self.muteSourceFactory = muteSourceFactory
        self.transcriberFactory = transcriberFactory
        self.paceWritingMotion = paceWritingMotion
        self.endWindow = showsEndWindow ? (endWindow ?? .shared) : nil
        loadSavedMeetings()
    }

    private static func makeProduction() -> ScribeController {
        // One monitor: the capture drain admits microphone intervals against its history, and the router's
        // detector reads the same readings.
        let monitor = ScribeMuteMonitor()
        let controller = ScribeController(
            provider: ScribeLiveCaptureProvider(monitor: monitor),
            store: ScribeMeetingStore.standard,
            muteSourceFactory: { ScribeMuteDetector(monitor: monitor) },
            transcriberFactory: { session, callbacks in
                ScribeTranscriberBridge(session: session, callbacks: callbacks)
            },
            paceWritingMotion: true,
            showsEndWindow: true
        )
        ScribeCallWatcher.shared.start()
        return controller
    }

    // MARK: State

    var phase: ScribePhase { machine.phase }

    /// Capturing (recording or waiting on the end confirmation): the top bar shows its recording wings.
    var isRecording: Bool {
        switch machine.phase {
        case .recording, .ending: return true
        default: return false
        }
    }

    /// Why capture can't work right now, or nil. With the live provider this is macOS's microphone denial;
    /// system-audio denial can only be known once capture starts, and then surfaces as a failed state.
    var unavailableReason: String? {
        if provider is ScribeUnavailableCaptureProvider { return ScribeUnavailableCaptureProvider.reason }
        if provider is ScribeLiveCaptureProvider { return ScribeLiveCaptureProvider.microphoneIssue }
        return nil
    }

    var captureAvailable: Bool { unavailableReason == nil }

    /// Honest availability line for the idle page; nil when capture can work fully.
    var availabilityNote: String? { unavailableReason ?? systemAudioNote }

    /// Always nil: Package.swift targets macOS 14.2, which has the system-audio tap, so there is no
    /// microphone-only fallback to explain. Kept so the page's line stays harmless.
    var systemAudioNote: String? { nil }

    /// Why the storage banner is showing: load problems first, then the oldest unsaved meeting.
    var storageIssue: String? { loadIssue ?? cleanupIssue ?? checkpointIssue ?? unsavedMeetings.first?.message }

    var completionSaveIssue: String? {
        guard case .processing(let id) = phase else { return nil }
        return unsavedMeetings.first(where: { $0.id == id })?.message
    }

    /// True while a failed save or a failed cleanup can be retried.
    var storageRetryAvailable: Bool { !unsavedMeetings.isEmpty || !pendingCleanup.isEmpty }

    /// Shown while recording when the microphone is being dropped because its mute state is unknown.
    var microphoneNote: String? {
        if micCallExcludedNow { return ScribeMicCallText.excludedNotice }
        return micMute == .unknown ? Self.microphoneUnknownNote : nil
    }

    /// All transcription problems of this session as one sentence, or nil.
    var transcriptionIssue: String? {
        transcriptionIssues.isEmpty ? nil : transcriptionIssues.joined(separator: " ")
    }

    /// The glow and wash are drawn from a clock only while processing or showing the finished notes; the live
    /// transcript's word reveal needs one while recording.
    var needsFrameClock: Bool {
        switch machine.phase {
        case .recording, .processing: return true
        case .complete: return completedNoticeID != nil
        default: return false
        }
    }

    var micIndicator: ScribeMicIndicator { ScribeMicIndicator(micMute) }

    var systemIndicator: ScribeSystemIndicator { ScribeSystemIndicator(framesReceived: systemAudioReceiving) }

    /// The newest transcript segments, final and provisional, oldest first.
    func liveSegments(limit: Int = 4) -> [ScribeTranscriptSegment] {
        Array((transcript?.segments ?? []).suffix(limit))
    }

    /// The newest segment (final or provisional) that holds real words, for the closed-notch ticker; nil before any.
    func latestWordsSegment() -> ScribeTranscriptSegment? {
        (transcript?.segments ?? []).last { ScribeTickerText.hasWords($0.text) }
    }

    /// How many words of `segment` to show at `date`: all of them, unless its text just changed while recording,
    /// in which case the new words appear a few at a time (`ScribeWordReveal`).
    func visibleWordCount(for segment: ScribeTranscriptSegment, at date: Date, reduceMotion: Bool) -> Int {
        guard let entry = wordReveals[segment.id], entry.text == segment.text else { return ScribeWordText.count(segment.text) }
        return ScribeWordReveal.visibleWords(
            total: entry.layout.words.count,
            alreadyShown: entry.alreadyShown,
            since: max(0, date.timeIntervalSince(entry.since)),
            reduceMotion: reduceMotion
        )
    }

    /// Tokenization and fade origins are cached when real transcript text changes, never per frame.
    func incomingWordLayout(for segment: ScribeTranscriptSegment) -> ScribeIncomingWordLayout? {
        guard machine.phase.sessionID == segment.session,
              let entry = wordReveals[segment.id], entry.text == segment.text else { return nil }
        return entry.layout
    }

    var failureReason: String? {
        if case .failed(_, let reason) = machine.phase { return reason }
        return nil
    }

    /// The presentation at `date`. Only `.complete` -> `.revealing` depends on time, and only for drawing the wash.
    func presentation(at date: Date, reduceMotion: Bool) -> ScribePresentation {
        ScribePresentation.state(
            for: machine.phase,
            elapsed: elapsed,
            revealElapsed: revealStart.map { date.timeIntervalSince($0) },
            reduceMotion: reduceMotion
        )
    }

    func stageElapsed(at date: Date) -> TimeInterval { max(0, date.timeIntervalSince(stageStart)) }

    func revealElapsed(at date: Date) -> TimeInterval { revealStart.map { max(0, date.timeIntervalSince($0)) } ?? 0 }

    // MARK: Actions

    func start() {
        guard !machine.phase.isActive else { return }
        ExplanationAudioArbitration.yieldToNewCapture()
        clearCompletedNotice()
        hideEndWindow()
        cancelTranscriber()
        checkpointGate.reset()
        checkpointIssue = nil
        retryCleanup()
        let id = ScribeSessionID()
        endWorkflow.begin(session: id, boundCall: meetingCallHint)
        meetingCallHint = nil
        endingRemaining = nil
        transcript = ScribeTranscript(session: id)
        notes = nil
        revealStart = nil
        elapsed = 0
        recordingSince = nil
        micMute = nil
        systemAudioReceiving = false
        transcriptionIssues = []
        microphoneUnknownSeconds = 0
        micCallExcludedNow = false
        micExcludedDuringCall = false
        stoppedEarlyReason = nil
        notesIssue = nil
        systemAudioStalled = false
        levelHistory = []
        discardRequested = false
        wordReveals = [:]
        incomingWordsRevealUntil = nil
        notesReadyTask?.cancel()
        notesReadyTask = nil
        let levels = ScribeLevelBox()
        levelBox = levels
        flushPendingSaves()
        openedRecapID = nil
        pendingDeleteID = nil
        sessionTitle = meetingTitleHint
        meetingTitleHint = nil
        sessionAttendees = meetingAttendeeHint
        meetingAttendeeHint = []
        liveTurns = []
        let readout = ScribeLiveReadout()
        self.readout = readout
        // One ordered stream for everything the capture side says (see `ScribeCaptureInput`).
        cancelCaptureInputs()
        let (inputs, inputContinuation) = AsyncStream<ScribeCaptureInput>.makeStream()
        captureInputs = inputContinuation
        captureInputTask = Task { @MainActor [weak self] in
            for await input in inputs {
                self?.handleCaptureInput(input, session: id)
            }
        }
        // One stream, one MainActor consumer: segments, issues and completion are applied in the order the
        // transcriber produced them (separate unstructured tasks could reorder them).
        let (events, continuation) = AsyncStream<ScribeTranscriberEvent>.makeStream()
        transcriberEvents = continuation
        transcriberEventTask = Task { @MainActor [weak self] in
            for await event in events {
                self?.handleTranscriber(event, session: id)
            }
        }
        let transcriber = transcriberFactory(
            id,
            ScribeTranscriberCallbacks(
                onSegment: { segment in continuation.yield(.segment(segment)) },
                onFinished: { session in continuation.yield(.finished(session)) },
                onIssue: { message in continuation.yield(.issue(message)) },
                onLevel: { source, level in levels.set(source, level) },
                onTurns: { turns in continuation.yield(.turns(turns)) }
            )
        )
        self.transcriber = transcriber
        let router = ScribeFrameRouter(
            session: id,
            muteSource: ScribeObservingMuteSource(
                base: muteSourceFactory(),
                readout: readout,
                changed: { state in inputContinuation.yield(.microphone(state)) }
            ),
            store: ScribeDiscardingFrameStore(),
            transcriber: transcriber
        )
        self.router = router
        guard run({ $0.start(id, now: nowSeconds()) }).isApplied else { return }
        // The prompt has done its job; the watcher won't offer another while a session is active.
        ScribeCallWatcher.shared.recordingDidStart()
        let frames: @Sendable (ScribeAudioFrame) -> Void = { [weak self] frame in
            _ = router.route(frame)
            if frame.source == .system, readout.noteSystemFrame() {
                Task { @MainActor in self?.publishSystemAudio(session: id) }
            }
        }
        let captureEvents: @Sendable (ScribeCaptureEvent) -> Void = { event in inputContinuation.yield(.event(event)) }
        if let reporting = provider as? any ScribeIssueReportingCaptureProvider {
            reporting.start(
                session: id,
                frames: frames,
                events: captureEvents,
                issues: { issue in inputContinuation.yield(.issue(issue)) }
            )
        } else {
            provider.start(session: id, frames: frames, events: captureEvents)
        }
    }

    /// Explicit Stop starts a nine-second end window. Only the provider's acknowledgment ends capture.
    func requestEnd() {
        guard case .recording(let id, _) = machine.phase else { return }
        discardRequested = false
        let now = nowSeconds()
        guard endWorkflow.requestEnd(session: id, now: now) else { return }
        run { $0.requestEnd(id, now: now, grace: ScribeEndWorkflow.grace) }
        updateEndingCountdown(now: now)
        endWindow?.present(scribe: self)
    }

    /// Positive termination of the exact native call-app instance bound when Record was chosen.
    /// This reports that the app closed; it does not pretend to detect a remote participant hanging up.
    func boundCallApplicationDidTerminate(_ identity: ScribeCallProcessIdentity) {
        let id: ScribeSessionID
        switch machine.phase {
        case .recording(let current, _), .ending(let current, _): id = current
        default: return
        }
        let now = nowSeconds()
        guard endWorkflow.applicationTerminated(identity, session: id, now: now) else { return }
        discardRequested = false
        run { $0.requestEnd(id, now: now, grace: ScribeEndWorkflow.grace) }
        updateEndingCountdown(now: now)
        endWindow?.present(scribe: self)
    }

    /// Trash button, step one: asks the page to confirm throwing the recording away.
    func requestDiscard() {
        guard case .recording = machine.phase else { return }
        discardRequested = true
        // The Trash button is replaced by the question: move VoiceOver to it and say it.
        focusToken &+= 1
        announce(Self.discardQuestion)
    }

    /// The person kept recording after pressing the trash button.
    func keepAfterDiscardRequest() {
        discardRequested = false
        focusToken &+= 1
    }

    /// Trash button, step two: stops capture and saves nothing (the same path as `cancel()`).
    func confirmDiscard() {
        guard discardRequested else { return }
        cancel()
    }

    func confirmEnd() {
        guard case .ending(let id, _) = machine.phase, endWorkflow.endNow(session: id) else { return }
        provider.stop(session: id)
    }

    func keepRecording() {
        guard case .ending(let id, _) = machine.phase, endWorkflow.keepRecording(session: id) else { return }
        run { $0.keepRecording(id) }
        endingRemaining = nil
        hideEndWindow()
    }

    func cancel() {
        guard let id = machine.phase.sessionID, machine.phase.isActive else { return }
        discardRequested = false
        hideEndWindow()
        // Processing has already received captureEnded. An expired/confirmed end likewise owns its
        // one stop request; cancelling that session must not send a second producer command.
        switch machine.phase {
        case .starting, .recording: provider.stop(session: id)
        case .ending: if !endWorkflow.stopRequested { provider.stop(session: id) }
        default: break
        }
        // Cancelling throws the meeting away on purpose, so a transcript checkpoint must not come back at launch.
        if recaps.contains(where: { $0.id == id }) == false { discardCheckpoint(id) }
        run { $0.cancel(id) }
        cancelTranscriber()
        cancelCaptureInputs()
        transcript = nil
        notes = nil
        wordReveals = [:]
        incomingWordsRevealUntil = nil
    }

    /// Clears a failure and starts again.
    func retry() {
        guard case .failed = machine.phase else { return }
        resetToIdle()
        start()
    }

    /// Stops waiting for the notes. What was transcribed so far is saved as a meeting without generated notes.
    func cancelProcessing() {
        guard case .processing(let id) = machine.phase, var finished = transcript else { return }
        // No more recognition: a chunk still in flight is left out rather than waited for.
        cancelTranscriber()
        finished.finalize()
        transcript = finished
        guard run({ $0.transcriptFinalized(id) }).isApplied else { return }
        notesIssue = "You stopped the notes early, so only the transcript was saved."
        notes = ScribeMeetingNotes(privateNotes: notes?.privateNotes ?? "")
        completeNotes(id)
    }

    /// Leaves the notes view (or a failure) and returns to the idle page. The recap stays in the list.
    func closeNotes() {
        switch machine.phase {
        case .complete, .failed:
            flushPendingSaves()
            resetToIdle()
        default: break
        }
    }

    /// Takes the recap off the list. The meeting file stays on disk, marked dismissed; only
    /// `deletePermanently` removes it.
    func dismissRecap(_ id: ScribeSessionID) {
        if let recap = recaps.first(where: { $0.id == id }) {
            flushPendingSaves()
            persist(recap, dismissedAt: clock())
        }
        recaps.removeAll { $0.id == id }
        forgetVoices(of: id)
        if openedRecapID == id { openedRecapID = nil }
        if pendingDeleteID == id { pendingDeleteID = nil }
    }

    // MARK: Open, edit, delete

    @discardableResult
    func openRecap(_ id: ScribeSessionID) -> Bool {
        let decision = ScribeRecapNavigation.decision(
            phase: machine.phase, recapExists: recaps.contains(where: { $0.id == id }),
            isCancelled: ScribeCancelTombstones.ids(in: cancellationDefaults).contains(id.rawValue)
        )
        switch decision {
        case .busy, .unavailable: return false
        case .closeNotesAndOpen: closeNotes()
        case .open: break
        }
        openedRecapID = id
        pendingDeleteID = nil
        focusToken &+= 1
        return true
    }

    func closeRecap() {
        flushPendingSaves()
        openedRecapID = nil
        pendingDeleteID = nil
        focusToken &+= 1
    }

    var openedRecap: ScribeRecap? {
        guard let openedRecapID else { return nil }
        return recaps.first { $0.id == openedRecapID }
    }

    /// Asks for confirmation before `deletePermanently`.
    func requestDelete(_ id: ScribeSessionID) {
        deleteIssue = nil
        pendingDeleteID = id
    }

    func cancelDelete() {
        pendingDeleteID = nil
    }

    func dismissDeleteIssue() {
        deleteIssue = nil
    }

    /// Removes the meeting's file (transcript and private notes included). If the file can't be removed the
    /// meeting stays listed and the reason is shown; nothing is reported as deleted that still exists.
    func deletePermanently(_ id: ScribeSessionID) {
        pendingDeleteID = nil
        if let store {
            do {
                try store.delete(id: id.rawValue)
            } catch {
                // The recap stays, so an edit still waiting for its pause must still be written.
                deleteIssue = error.localizedDescription
                announce(error.localizedDescription)
                return
            }
        }
        pendingSaves.remove(id.rawValue)
        recaps.removeAll { $0.id == id }
        forgetVoices(of: id)
        if openedRecapID == id { openedRecapID = nil }
        if saveFailures.recordSuccess(id: id.rawValue) { refreshUnsavedMeetings() }
        if pendingDiscardID == id { pendingDiscardID = nil }
        announce("Meeting deleted.")
    }

    func setPrivateNotes(_ text: String) {
        guard case .complete(let id) = machine.phase else { return }
        setPrivateNotes(text, for: id)
    }

    /// Edits the private notes of a saved (or just finished) meeting; the file is rewritten once typing pauses.
    func setPrivateNotes(_ text: String, for id: ScribeSessionID) {
        if case .complete(let current) = machine.phase, current == id { notes?.privateNotes = text }
        guard let index = recaps.firstIndex(where: { $0.id == id }) else { return }
        recaps[index].notes.privateNotes = text
        scheduleSave(id)
    }

    /// Ticks or unticks one action item of a saved (or just finished) meeting.
    func setActionItem(_ index: Int, done: Bool, for id: ScribeSessionID) {
        if case .complete(let phaseID) = machine.phase, phaseID == id,
           var live = notes, live.actionItems.indices.contains(index) {
            live.actionItems[index].done = done
            notes = live
        }
        guard let position = recaps.firstIndex(where: { $0.id == id }),
              recaps[position].notes.actionItems.indices.contains(index) else { return }
        recaps[position].notes.actionItems[index].done = done
        scheduleSave(id)
    }

    /// Where the meeting audio goes when the dictation engine is a cloud one, else nil.
    var cloudDisclosure: String? {
        ScribeCloudDisclosure.text(for: transcriptionEngine())
    }

    // MARK: Pipeline inputs (called by a real transcriber later; also used by tests and previews)

    func receive(_ segment: ScribeTranscriptSegment) {
        guard let id = machine.phase.sessionID, var current = transcript, current.session == id else { return }
        let result = current.upsert(segment)
        guard result == .inserted || result == .replaced else { return }
        transcript = current
        noteWordReveal(segment)
        run { $0.transcriptUpdated(id) }
        // Segments that arrive while the notes are being prepared are kept on disk as they come.
        if case .processing(let processing) = machine.phase, processing == id {
            if checkpointGate.segmentAccepted(now: clock()) {
                checkpointTranscript(id)
            } else {
                armCheckpointFlush(id)
            }
        }
    }

    /// Remembers where a changed segment's reveal starts: the words already on screen stay, the new ones follow.
    private func noteWordReveal(_ segment: ScribeTranscriptSegment) {
        guard case .recording = machine.phase else { return }
        let previous = wordReveals[segment.id]
        if previous?.text == segment.text { return }
        let now = clock()
        var shown = 0
        // The "…" placeholder is not text anyone has read.
        if let previous, previous.text != "…" {
            shown = ScribeWordReveal.visibleWords(
                total: ScribeWordText.count(previous.text),
                alreadyShown: previous.alreadyShown,
                since: max(0, now.timeIntervalSince(previous.since)),
                reduceMotion: reduceMotion
            )
        }
        wordReveals[segment.id] = ScribeWordRevealEntry(
            text: segment.text,
            alreadyShown: min(shown, ScribeWordText.count(segment.text)),
            since: now,
            layout: ScribeIncomingWordLayout(text: segment.text,
                alreadyShown: min(shown, ScribeWordText.count(segment.text)),
                since: now.timeIntervalSinceReferenceDate, previous: previous?.layout)
        )
        let lastEnd = transcript?.segments.suffix(60).reduce(-TimeInterval.infinity) {
            max($0, wordReveals[$1.id]?.layout.revealEndsAt ?? -.infinity)
        } ?? -.infinity
        incomingWordsRevealUntil = lastEnd.isFinite ? Date(timeIntervalSinceReferenceDate: lastEnd) : nil
    }

    @ObservationIgnored private let motionReduced: () -> Bool
    private var reduceMotion: Bool { motionReduced() }

    /// The transcriber has produced its final segments. Notes are generated from the final transcript only.
    func transcriptDidFinish(session id: ScribeSessionID) {
        guard case .processing(let current) = machine.phase, current == id, var finished = transcript else { return }
        // The second look: with the whole meeting in hand, turns the live pass split or merged are relabelled.
        let corrected = ScribeSpeakerCorrection.corrected(segments: finished.segments, turns: liveTurns)
        let speakerByID = Dictionary(corrected.map { ($0.id, $0.speaker) }, uniquingKeysWith: { first, _ in first })
        finished.relabelSpeakers { speakerByID[$0.id] ?? $0.speaker }
        finished.finalize()
        transcript = finished
        guard run({ $0.transcriptFinalized(id) }).isApplied else { return }
        // The full transcript is safe on disk before notes generation can fail or the app can close.
        checkpointTranscript(id)
        do {
            let generated = try generator.generate(from: finished)
            notes = ScribeNotes.merge(generated: generated, into: notes ?? ScribeMeetingNotes())
        } catch {
            // The transcript is already in hand: keep and save it rather than failing and losing it.
            notesIssue = "The notes couldn't be written (\(error.localizedDescription)), so only the transcript was saved."
            notes = ScribeMeetingNotes(privateNotes: notes?.privateNotes ?? "")
        }
        completeNotes(id)
    }

    /// Applies `notesReady`. In the shipped app it waits until the writing band has played its rise, hold and
    /// recede, so a meeting whose notes are ready at once still shows the motion before the surge. This only
    /// paces the drawing. Completion is emitted only after the final notes are durably saved; a failed
    /// save leaves the session processing with its recoverable payload and Retry save banner.
    private func completeNotes(_ id: ScribeSessionID) {
        let remaining = Self.minimumWritingSeconds - clock().timeIntervalSince(stageStart)
        guard paceWritingMotion, !reduceMotion, remaining > 0.05 else {
            finishSavedNotes(id)
            return
        }
        notesReadyTask?.cancel()
        notesReadyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.notesReadyTask = nil
            guard case .processing(let current) = self.machine.phase, current == id else { return }
            self.finishSavedNotes(id)
        }
    }

    private func finishSavedNotes(_ id: ScribeSessionID) {
        run { candidate in candidate.saveAndCompleteNotes(id) { self.archive(id) } }
    }

    // MARK: Events

    private func handleTranscriber(_ event: ScribeTranscriberEvent, session id: ScribeSessionID) {
        switch event {
        case .segment(let segment): receive(segment)
        case .turns(let turns): liveTurns = turns
        case .issue(let message): noteTranscriptionIssue(message, session: id)
        case .finished(let session): transcriptDidFinish(session: session)
        }
    }

    private func handleCaptureInput(_ input: ScribeCaptureInput, session id: ScribeSessionID) {
        switch input {
        case .event(let event):
            handle(event)
        case .microphone(let state):
            publishMic(state, session: id)
        case .issue(let issue):
            guard machine.phase.sessionID == id else { return }
            switch issue {
            case .audioLost:
                noteTranscriptionIssue(Self.audioLostMessage, session: id)
            case .microphone(let state):
                publishMic(state, session: id)
            case .microphoneExcludedByCall(let excluded):
                micCallExcludedNow = excluded
                if excluded, !micExcludedDuringCall {
                    micExcludedDuringCall = true
                    announce(ScribeMicCallText.excludedNotice)
                }
            case .microphoneWithheld(let state, let seconds):
                // A muted microphone withheld on purpose isn't missing speech; an unknown one might be.
                guard state == .unknown else { return }
                microphoneUnknownSeconds += seconds
                if microphoneUnknownSeconds >= Self.microphoneUnknownThreshold {
                    noteTranscriptionIssue(Self.microphoneUnknownMessage, session: id)
                }
            }
        }
    }

    private func cancelCaptureInputs() {
        captureInputs?.finish()
        captureInputs = nil
        captureInputTask?.cancel()
        captureInputTask = nil
    }

    /// Router readings for the live session only; a late one from a replaced session is dropped.
    private func publishMic(_ state: ScribeMuteState, session id: ScribeSessionID) {
        guard machine.phase.sessionID == id else { return }
        micMute = state
    }

    private func publishSystemAudio(session id: ScribeSessionID) {
        guard machine.phase.sessionID == id else { return }
        systemAudioReceiving = true
    }

    // MARK: System-audio stall

    private func startStallWatch() {
        stopStallWatch()
        stallTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSystemStall() }
        }
    }

    private func stopStallWatch() {
        stallTimer?.invalidate()
        stallTimer = nil
        systemAudioStalled = false
    }

    /// Frames stop arriving when the output device changes under the tap, and nothing else says so.
    private func checkSystemStall() {
        guard isRecording, let id = machine.phase.sessionID,
              let silent = readout?.systemSilentSeconds() else { return }
        switch ScribeSystemStall.level(silentSeconds: silent) {
        case .ok:
            if systemAudioStalled { systemAudioStalled = false }
        case .warning:
            if !systemAudioStalled {
                systemAudioStalled = true
                announce(ScribeSystemStall.warningText)
            }
        case .lost:
            if !systemAudioStalled { systemAudioStalled = true }
            noteTranscriptionIssue(ScribeSystemStall.lostText, session: id)
        }
    }

    // MARK: Audio level (display only)

    private func startLevelWatch() {
        stopLevelWatch()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleLevel() }
        }
    }

    private func stopLevelWatch() {
        levelTimer?.invalidate()
        levelTimer = nil
        if !levelHistory.isEmpty { levelHistory = [] }
    }

    /// One meter step: rises at once, falls quickly, and reads exactly 0 once audio has stopped arriving.
    private func sampleLevel() {
        guard isRecording, let box = levelBox else { return }
        let incoming = box.current()
        let previous = levelHistory.last ?? 0
        var level = incoming >= previous ? incoming : previous * 0.7 + incoming * 0.3
        if level < 0.01 { level = 0 }
        if level == 0, levelHistory.allSatisfy({ $0 == 0 }) { return }
        levelHistory.append(level)
        if levelHistory.count > Self.levelHistoryCount {
            levelHistory.removeFirst(levelHistory.count - Self.levelHistoryCount)
        }
    }

    private func nowSeconds() -> TimeInterval { monotonicClock() }

    @discardableResult
    private func run(_ command: (inout ScribeSessionMachine) -> ScribeTransition) -> ScribeTransition {
        let before = machine.phase
        // Commands may synchronously persist a recap. Work on a value copy so persistence/observation
        // never re-enters an exclusive access to the observed machine property.
        var candidate = machine
        let transition = command(&candidate)
        guard transition.isApplied else { return transition }
        machine = candidate
        if machine.phase != before { stageStart = clock() }
        for event in transition.events { react(to: event) }
        if machine.phase != before {
            if let line = announcement(for: machine.phase) { announce(line) }
            focusToken &+= 1
        }
        return transition
    }

    /// Facts from the capture provider. Stale ones (another session) are rejected by the machine.
    private func handle(_ event: ScribeCaptureEvent) {
        switch event {
        case .captureAcknowledged(let id):
            run { $0.acknowledgeCapture(id, now: self.nowSeconds()) }
        case .captureEnded(let id):
            run { $0.captureEnded(id) }
        case .failed(let id, let error):
            // Capture died after it had started: keep what was captured. The provider has already torn
            // everything down, so the session moves on to processing (transcript, notes, save) with a note.
            if machine.phase.sessionID == id, isRecording {
                stoppedEarlyReason = error.localizedDescription
                announce("Recording stopped early. Saving what was captured.")
                run { $0.captureEnded(id) }
            } else {
                run { $0.fail(id, reason: error.localizedDescription) }
            }
        }
    }

    private func react(to event: ScribeLifecycleEvent) {
        switch event {
        case .recordingStarted:
            recordingSince = nowSeconds()
            elapsed = 0
            startClock()
            readout?.markRecordingStarted()
            startStallWatch()
            startLevelWatch()
        case .recordingEnded:
            endingRemaining = nil
            tickClock()
            stopClock()
            stopStallWatch()
            stopLevelWatch()
            router?.finish()
            if let id = machine.phase.sessionID { checkpointTranscript(id) }
        case .notesReady(let id):
            endWindow?.present(scribe: self)
            completedNoticeID = id
            completedNoticeTask?.cancel()
            completedNoticeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.completedNoticeID == id,
                      self.machine.phase.sessionID == id else { return }
                self.completedNoticeID = nil
                self.completedNoticeTask = nil
            }
            revealStart = clock()
            notesReadyTask = nil
            stopCheckpointFlush()
            transcriber = nil
            // Completion was the last event of this session's stream.
            transcriberEvents?.finish()
            transcriberEvents = nil
        case .failed:
            hideEndWindow()
            stopClock()
            stopStallWatch()
            stopLevelWatch()
            notesReadyTask?.cancel()
            notesReadyTask = nil
            router?.setActiveSession(nil)
            cancelTranscriber()
        case .cancelled:
            stopClock()
            stopStallWatch()
            stopLevelWatch()
            notesReadyTask?.cancel()
            notesReadyTask = nil
            router?.setActiveSession(nil)
            cancelTranscriber()
        case .endingCountdown, .endingCancelled, .transcriptUpdated, .transcriptFinalized:
            break
        }
    }

    /// Writes the transcript captured so far, with no generated notes, under the meeting's own file name, so a
    /// crash or quit while processing never loses it. The final `archive` overwrites the same file. A failed
    /// write is shown and stays due: it is retried with the next segment, on a short timer, and at the end.
    @discardableResult
    private func checkpointTranscript(_ id: ScribeSessionID) -> Bool {
        guard store != nil, let record = checkpointRecord(id, dismissedAt: nil) else { return true }
        do {
            try writeMeeting(record)
            checkpointedMeetings.insert(id.rawValue)
            checkpointGate.wrote(success: true, now: clock())
            checkpointIssue = nil
            return true
        } catch {
            checkpointGate.wrote(success: false, now: clock())
            let message = "Couldn't keep the transcript safe on disk while the notes are written: \(error.localizedDescription) Zeus will try again."
            if checkpointIssue == nil { announce(message) }
            checkpointIssue = message
            if case .processing(let current) = machine.phase, current == id { armCheckpointFlush(id) }
            return false
        }
    }

    /// The meeting as a transcript-only record; nil while there are no final segments.
    private func checkpointRecord(_ id: ScribeSessionID, dismissedAt: Date?) -> ScribeMeetingRecord? {
        guard let segments = transcript?.finalSegments, !segments.isEmpty else { return nil }
        return ScribeMeetingRecord(
            id: id.rawValue,
            title: sessionTitle ?? "Meeting notes",
            endedAt: clock(),
            duration: elapsed,
            notes: ScribeMeetingNotes(privateNotes: notes?.privateNotes ?? ""),
            transcript: segments,
            dismissedAt: dismissedAt,
            transcriptionNote: ScribeRecapNote.compose(
                issues: transcriptionIssues, stoppedEarly: stoppedEarlyReason, notesIssue: ScribeRecapNote.checkpointNote
            ),
            micExcludedDuringCall: micExcludedDuringCall
        )
    }

    /// One trailing write, shortly after a segment that arrived inside the write interval (or after a failure).
    private func armCheckpointFlush(_ id: ScribeSessionID) {
        guard checkpointFlushTask == nil else { return }
        checkpointFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.checkpointFlushTask = nil
            guard case .processing(let current) = self.machine.phase, current == id, self.checkpointGate.flushDue else { return }
            self.checkpointTranscript(id)
        }
    }

    private func stopCheckpointFlush() {
        checkpointFlushTask?.cancel()
        checkpointFlushTask = nil
    }

    /// Removes a thrown-away meeting's checkpoint. If the file can't be removed (retried once), the meeting is
    /// also marked dismissed so it doesn't come back as a recap at launch, and the person is told it is still on
    /// disk; `retryCleanup` tries again. A tombstone is written before the first attempt: if the file stays and
    /// even the dismissal can't be written, the next launch still hides the transcript and retries the deletion.
    private func discardCheckpoint(_ id: ScribeSessionID) {
        guard let store, checkpointedMeetings.contains(id.rawValue) else { return }
        pendingCleanup.insert(id.rawValue)
        ScribeCancelTombstones.add(id.rawValue, in: cancellationDefaults)
        if removeCheckpoint(id.rawValue) { return }
        if let record = checkpointRecord(id, dismissedAt: clock()) { try? store.save(record) }
        cleanupIssue = Self.cleanupFailedMessage
        announce(Self.cleanupFailedMessage)
    }

    /// Deletes one checkpoint file, with one immediate retry. True when it is gone.
    private func removeCheckpoint(_ raw: UUID) -> Bool {
        guard let store else { return true }
        for _ in 0..<2 {
            do {
                try store.delete(id: raw)
                pendingCleanup.remove(raw)
                checkpointedMeetings.remove(raw)
                ScribeCancelTombstones.remove(raw, in: cancellationDefaults)
                if pendingCleanup.isEmpty { cleanupIssue = nil }
                return true
            } catch { continue }
        }
        return false
    }

    /// Tries every pending checkpoint deletion again.
    func retryCleanup() {
        for raw in pendingCleanup { _ = removeCheckpoint(raw) }
    }

    /// Hides the banner only; the deletion stays pending and is retried when the next meeting starts.
    func dismissCleanupIssue() {
        cleanupIssue = nil
    }

    func dismissCheckpointIssue() {
        checkpointIssue = nil
    }

    @discardableResult
    private func archive(_ id: ScribeSessionID) -> Bool {
        guard let notes else { return false }
        let recap = ScribeRecap(
            id: id,
            title: sessionTitle ?? "Meeting notes",
            endedAt: clock(),
            duration: elapsed,
            notes: notes,
            transcript: transcript?.finalSegments ?? [],
            // Saved with the meeting, so the recap and the saved file both say speech may be missing.
            transcriptionNote: ScribeRecapNote.compose(
                issues: transcriptionIssues, stoppedEarly: stoppedEarlyReason, notesIssue: notesIssue
            ),
            micExcludedDuringCall: micExcludedDuringCall
        )
        if let index = recaps.firstIndex(where: { $0.id == id }) { recaps[index] = recap }
        else { recaps.insert(recap, at: 0) }
        // Only what speaker naming needs, kept in memory: this meeting's turn voices and invitee names.
        if !liveTurns.isEmpty { turnVoices[id.rawValue] = liveTurns }
        if !sessionAttendees.isEmpty { attendeesByMeeting[id.rawValue] = sessionAttendees }
        let saved = persist(recap)
        // A failed final save can leave the transcript checkpoint on disk. Keep its identity so an
        // explicit discard removes that private transcript too, rather than resurrecting it at launch.
        if saved {
            checkpointedMeetings.remove(id.rawValue)
            checkpointIssue = nil
        }
        return saved
    }

    // MARK: Speaker names

    private func forgetVoices(of id: ScribeSessionID) {
        turnVoices[id.rawValue] = nil
        attendeesByMeeting[id.rawValue] = nil
    }

    /// Names Zeus suggests for this meeting's unnamed speakers. Suggestions only: nothing renames itself.
    func speakerSuggestions(for id: ScribeSessionID) -> [ScribeNameSuggestion] {
        guard let recap = recaps.first(where: { $0.id == id }) else { return [] }
        let owner = UserDefaults.standard.string(forKey: "aboutYou.name") ?? NSFullUserName()
        return ScribeNameSuggester.suggestions(
            segments: recap.transcript, attendees: attendeesByMeeting[id.rawValue] ?? [],
            savedNames: SavedVoicesModel.shared.names, ownerName: owner
        )
    }

    /// Invitee display names for this meeting (saved with the meeting, so they survive a relaunch).
    func attendeeNames(for id: ScribeSessionID) -> [String] { attendeesByMeeting[id.rawValue] ?? [] }

    /// A voice can be remembered only from this session's trained embeddings, for a speaker other than "You".
    func canRememberVoice(_ speaker: ScribeSpeaker, in id: ScribeSessionID) -> Bool {
        speaker != .you && voiceCentroid(of: speaker, in: id)?.embedding.kind == .wespeaker
    }

    private func voiceCentroid(of speaker: ScribeSpeaker, in id: ScribeSessionID) -> (embedding: ScribeVoiceEmbedding, turns: Int)? {
        guard let recap = recaps.first(where: { $0.id == id }), let turns = turnVoices[id.rawValue] else { return nil }
        let owner = Dictionary(recap.transcript.map { ($0.id, $0.speaker) }, uniquingKeysWith: { first, _ in first })
        let mine = turns.filter { owner[$0.segmentID] == speaker }
        guard let centroid = ScribeEmbeddingMath.centroid(of: mine.map { (embedding: $0.embedding, weight: $0.duration) }) else { return nil }
        return (centroid, mine.count)
    }

    /// Renames a speaker in one meeting: every line, the speaker statistics, the saved file and any copied or
    /// exported text follow. A name another speaker already has merges the two. `rememberVoice` (off unless the
    /// person ticked it) also saves the voice locally under that name.
    func renameSpeaker(_ speaker: ScribeSpeaker, to name: String, in id: ScribeSessionID, rememberVoice: Bool = false) {
        guard let index = recaps.firstIndex(where: { $0.id == id }) else { return }
        let before = recaps[index].transcript
        let after = ScribeSpeakerNames.rename(speaker, to: name, in: before)
        guard after != before else { return }
        // The voice is read before the lines change: it is the turns the speaker had under the old label.
        if rememberVoice, let voice = voiceCentroid(of: speaker, in: id),
           case .participant(let saveAs)? = ScribeSpeakerNames.target(for: name, in: before) {
            if !SavedVoicesModel.shared.remember(name: saveAs, embedding: voice.embedding, sampleCount: voice.turns) {
                announce(SavedVoicesModel.shared.problem ?? "Couldn't save the voice.")
            }
        }
        recaps[index].transcript = after
        let speakerByID = Dictionary(after.map { ($0.id, $0.speaker) }, uniquingKeysWith: { first, _ in first })
        if case .complete(let current) = machine.phase, current == id {
            transcript?.relabelSpeakers { speakerByID[$0.id] ?? $0.speaker }
        }
        scheduleSave(id)
    }

    /// The meeting's transcript as text for the clipboard, with the current names.
    func transcriptText(for id: ScribeSessionID, markdown: Bool) -> String {
        guard let recap = recaps.first(where: { $0.id == id }) else { return "" }
        return markdown
            ? ScribeTranscriptExport.markdown(title: recap.title, segments: recap.transcript)
            : ScribeTranscriptExport.plainText(segments: recap.transcript)
    }

    /// What the recap offers for naming this meeting's speakers. The closures run on user clicks, on the main actor.
    func speakerTools(for id: ScribeSessionID) -> ScribeSpeakerTools {
        ScribeSpeakerTools(
            suggestions: speakerSuggestions(for: id),
            attendeeNames: attendeeNames(for: id),
            canRemember: { [unowned self] speaker in self.canRememberVoice(speaker, in: id) },
            rename: { [unowned self] speaker, name, remember in self.renameSpeaker(speaker, to: name, in: id, rememberVoice: remember) },
            copyTranscript: { [unowned self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.transcriptText(for: id, markdown: false), forType: .string)
            }
        )
    }

    // MARK: Saved meetings

    private func loadSavedMeetings() {
        guard let store else { return }
        // A meeting cancelled in an earlier run whose file couldn't be removed then: finish that deletion now, and
        // never list it as a recap while the file is still there.
        let cancelled = ScribeCancelTombstones.ids(in: cancellationDefaults)
        for raw in cancelled {
            pendingCleanup.insert(raw)
            _ = removeCheckpoint(raw)
        }
        if !pendingCleanup.isEmpty {
            cleanupIssue = Self.cleanupFailedMessage
            announce(Self.cleanupFailedMessage)
        }
        let result = store.loadAll()
        recaps = result.records
            .filter { $0.dismissedAt == nil && !cancelled.contains($0.id) }
            .map { record in
                let id = ScribeSessionID(rawValue: record.id)
                if !record.attendeeNames.isEmpty { attendeesByMeeting[record.id] = record.attendeeNames }
                if !record.turnEmbeddings.isEmpty { turnVoices[record.id] = record.turnEmbeddings }
                return ScribeRecap(
                    id: id,
                    title: record.title,
                    endedAt: record.endedAt,
                    duration: record.duration,
                    notes: record.meetingNotes,
                    transcript: record.segments(session: id),
                    transcriptionNote: record.transcriptionNote,
                    micExcludedDuringCall: record.micExcludedDuringCall ?? false
                )
            }
        if !result.failures.isEmpty {
            let message = "Couldn't read \(result.failures.count) saved meeting(s): " + result.failures.joined(separator: "; ")
            loadIssue = message
            announce(message)
        }
    }

    /// Writes the recap now. A failure is tracked for that meeting alone (listed on the page until retried or
    /// dismissed) and announced; it never passes silently. A success clears only its own meeting's failure.
    @discardableResult
    private func persist(_ recap: ScribeRecap, dismissedAt: Date? = nil) -> Bool {
        // A nil store is an explicitly in-memory test/preview controller, never production.
        guard store != nil else { return true }
        let record = ScribeMeetingRecord(
            id: recap.id.rawValue,
            title: recap.title,
            endedAt: recap.endedAt,
            duration: recap.duration,
            notes: recap.notes,
            transcript: recap.transcript,
            dismissedAt: dismissedAt,
            transcriptionNote: recap.transcriptionNote,
            micExcludedDuringCall: recap.micExcludedDuringCall,
            attendees: attendeesByMeeting[recap.id.rawValue] ?? [],
            turnVoices: turnVoices[recap.id.rawValue] ?? []
        )
        do {
            try writeMeeting(record)
            if saveFailures.recordSuccess(id: recap.id.rawValue) { refreshUnsavedMeetings() }
            return true
        } catch {
            let message = "Couldn't save “\(recap.title)”: \(error.localizedDescription)"
            saveFailures.recordFailure(
                id: recap.id.rawValue, message: message,
                payload: ScribeFailedSave(recap: recap, dismissedAt: dismissedAt)
            )
            refreshUnsavedMeetings()
            announce(message)
            return false
        }
    }

    private func refreshUnsavedMeetings() {
        unsavedMeetings = saveFailures.entries.map {
            ScribeUnsavedMeeting(id: ScribeSessionID(rawValue: $0.id), title: $0.payload.recap.title, message: $0.message)
        }
    }

    /// Tries one meeting's failed save again.
    func retrySave(_ id: ScribeSessionID) {
        guard let failed = saveFailures.entry(for: id.rawValue) else { return }
        // A recovered in-memory recap may have newer private-note edits than the failed write payload.
        let latest = recaps.first(where: { $0.id == id }) ?? failed.payload.recap
        let saved = persist(latest, dismissedAt: failed.payload.dismissedAt)
        if saved, case .processing(let current) = machine.phase, current == id {
            // The exact failed final payload just committed. Do not regenerate or replace private notes.
            notes = latest.notes
            checkpointedMeetings.remove(id.rawValue)
            checkpointIssue = nil
            run { $0.saveAndCompleteNotes(id, save: { true }) }
        }
    }

    /// Tries every failed save again.
    func retrySave() {
        for meeting in unsavedMeetings { retrySave(meeting.id) }
    }

    /// Asks the person to confirm throwing away a meeting that couldn't be saved. Until then, or if they
    /// keep it, the meeting stays in memory with its Retry save banner.
    func requestDiscardUnsaved(_ id: ScribeSessionID) {
        guard saveFailures.entry(for: id.rawValue) != nil else { return }
        pendingDiscardID = id
    }

    func keepUnsaved() {
        pendingDiscardID = nil
    }

    /// Throws an unsaved meeting away for good (only after `requestDiscardUnsaved`). Nothing is on disk to recover.
    func discardUnsaved(_ id: ScribeSessionID) {
        guard pendingDiscardID == id else { return }
        pendingDiscardID = nil
        pendingSaves.remove(id.rawValue)
        // A final-note save can fail after a transcript checkpoint succeeded. Explicit discard must
        // also remove that checkpoint, or it would return as a saved meeting at the next launch.
        discardCheckpoint(id)
        saveFailures.recordSuccess(id: id.rawValue)
        refreshUnsavedMeetings()
        recaps.removeAll { $0.id == id }
        if openedRecapID == id { openedRecapID = nil }
        if case .processing(let current) = machine.phase, current == id { resetToIdle() }
        announce("Meeting discarded.")
    }

    func dismissLoadIssue() {
        loadIssue = nil
    }

    /// Kept for callers of the old API: it no longer drops an unsaved meeting, it asks first.
    func dismissUnsaved(_ id: ScribeSessionID) {
        requestDiscardUnsaved(id)
    }

    /// Hides the "couldn't read saved meetings" banner. Unsaved meetings keep theirs until saved or discarded.
    func dismissStorageIssue() {
        loadIssue = nil
    }

    /// Private notes and ticks change on every keystroke; the file is rewritten once typing pauses.
    private func scheduleSave(_ id: ScribeSessionID) {
        guard store != nil else { return }
        pendingSaves.insert(id.rawValue)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.flushPendingSaves()
        }
    }

    /// Writes every meeting with an edit still waiting for its pause, now.
    private func flushPendingSaves() {
        saveTask?.cancel()
        saveTask = nil
        let ids = pendingSaves
        pendingSaves = []
        for raw in ids {
            if case .processing(let current) = machine.phase, current.rawValue == raw,
               saveFailures.entry(for: raw) != nil {
                // A pending private-note edit can be the write that finally succeeds. Use the same
                // completion transition as Retry, otherwise the failure banner clears but writing sticks.
                retrySave(current)
            } else if let recap = recaps.first(where: { $0.id.rawValue == raw }) {
                persist(recap)
            }
        }
    }

    private func noteTranscriptionIssue(_ message: String, session id: ScribeSessionID) {
        guard machine.phase.sessionID == id, !transcriptionIssues.contains(message) else { return }
        transcriptionIssues.append(message)
        announce(message)
    }

    private func cancelTranscriber() {
        (transcriber as? ScribeTranscriberBridge)?.cancel()
        stopCheckpointFlush()
        transcriber = nil
        transcriberEvents?.finish()
        transcriberEvents = nil
        transcriberEventTask?.cancel()
        transcriberEventTask = nil
    }

    private func resetToIdle() {
        clearCompletedNotice()
        hideEndWindow()
        endingRemaining = nil
        stopClock()
        stopStallWatch()
        stopLevelWatch()
        notesReadyTask?.cancel()
        notesReadyTask = nil
        wordReveals = [:]
        incomingWordsRevealUntil = nil
        discardRequested = false
        stoppedEarlyReason = nil
        notesIssue = nil
        readout = nil
        cancelTranscriber()
        cancelCaptureInputs()
        router?.setActiveSession(nil)
        router = nil
        machine = ScribeSessionMachine()
        stageStart = clock()
        revealStart = nil
        transcript = nil
        notes = nil
        elapsed = 0
        recordingSince = nil
        micMute = nil
        systemAudioReceiving = false
        transcriptionIssues = []
        microphoneUnknownSeconds = 0
        micCallExcludedNow = false
        micExcludedDuringCall = false
    }

    // MARK: Clock text (display only)

    private func clearCompletedNotice() {
        completedNoticeTask?.cancel()
        completedNoticeTask = nil
        completedNoticeID = nil
    }

    private func hideEndWindow() {
        endWindow?.hide()
    }

    private func startClock() {
        stopClock()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickClock() }
        }
    }

    private func stopClock() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Same deterministic tick used by the timer and automated lifecycle scenarios with an injected clock.
    func tickClock() {
        guard let since = recordingSince else { return }
        switch machine.phase {
        case .recording, .ending: elapsed = max(0, nowSeconds() - since)
        case .processing: elapsed = max(elapsed, nowSeconds() - since)
        default: break
        }
        updateEndingCountdown(now: nowSeconds())
    }

    private func updateEndingCountdown(now: TimeInterval) {
        guard case .ending(let id, _) = machine.phase else { return }
        if let remaining = endWorkflow.remaining(now: now) {
            endingRemaining = Int(ceil(remaining))
        }
        if endWorkflow.stopIfDue(session: id, now: now) { provider.stop(session: id) }
    }

    // MARK: VoiceOver

    private func announcement(for phase: ScribePhase) -> String? {
        // `.complete` is only entered by the accepted `notesReady` event, so it is announced as the reveal
        // (revealElapsed 0 maps it to `.revealing`, "Notes are ready") rather than as the silent settled state.
        let revealElapsed: TimeInterval? = { if case .complete = phase { return 0 } else { return nil } }()
        return ScribePresentation.state(for: phase, elapsed: elapsed, revealElapsed: revealElapsed).announcement
    }

    private func announce(_ text: String) {
        if #available(macOS 14, *) {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
