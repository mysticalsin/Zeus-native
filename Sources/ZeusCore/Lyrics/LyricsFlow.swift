import Foundation

/// The decisions of the lyrics store as a pure reducer: an event goes in, the state changes and a list of effects
/// comes out. The store only runs the effects (cancel a task, read or write the cache, send the lookup, arm the
/// retry) and feeds the results back as events, so load, retry and lookup are testable without a network or a clock.
public struct LyricsFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Lyrics are switched off.
        case off
        /// Nothing is known for the current track yet.
        case idle
        /// The lookup is out.
        case loading
        /// The service answered (a body, or nothing on every step). `.none` is a cached miss.
        case answered(LyricsResult)
        /// The service did not answer. Never cached; the retry or a later load asks again.
        case unavailable
    }

    /// What a lyric view knows about the track it shows.
    public struct Track: Equatable, Sendable {
        public var key: String
        public var isAskable: Bool
        public var isPlaying: Bool
        public init(key: String, isAskable: Bool = true, isPlaying: Bool = true) {
            self.key = key; self.isAskable = isAskable; self.isPlaying = isPlaying
        }
    }

    public enum Event: Equatable, Sendable {
        /// A lyric view shows `track` (nil: nothing is playing). `enabled` is the privacy switch.
        case load(enabled: Bool, track: Track?, now: Date)
        /// The answer to `.readCache`: `cached` is nil for no entry. `mayAsk` is false where nothing may be sent (snapshots).
        case cacheRead(key: String, cached: LyricsResult?, mayAsk: Bool, now: Date)
        /// Every step of the lookup ran and this is what it found.
        case answered(key: String, LyricsResult)
        /// A step failed: no answer, 408, 429, 5xx or a reply over the size limit.
        case failed(key: String, retryAfter: TimeInterval?, now: Date)
        /// The retry task's wait is over and its plan said to ask.
        case retryDue(key: String, now: Date)
        /// The retry task decided to send nothing.
        case retryStopped
        case viewerAppeared
        case viewerLeft
        /// The privacy switch went off, from a lyric view or from a step that found it off.
        case privacyOff
        /// Snapshots and tests: the answer for a track, without the network.
        case seeded(key: String, LyricsResult)
    }

    public enum Effect: Equatable, Sendable {
        case cancelLookup
        case cancelRetry
        /// Read the disk cache for the current track and answer with `.cacheRead`.
        case readCache
        case sendLookup
        /// Arm the one retry (replacing a pending one).
        case scheduleRetry
        case saveCache(LyricsResult)
    }

    public private(set) var phase: Phase = .idle
    /// The track the answer is for. Nil when off or when nothing is playing.
    public private(set) var key: String?
    /// True while the retry is waiting to decide; false once it asked or stopped.
    public private(set) var retryArmed = false
    /// The wait after a failure. One for the whole service, so a new track does not skip it.
    public private(set) var backoff = LyricsBackoff()
    public private(set) var viewers = 0
    /// Whether the track a lyric view last showed is playing.
    public private(set) var isPlaying = false

    public init() {}

    public mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .load(let enabled, let track, let now):
            isPlaying = track?.isPlaying ?? false
            guard enabled else { return switchOff() }
            // Nothing is playing: drop the track and its retry, so no request is left for a track that stopped.
            guard let track else { key = nil; retryArmed = false; return [.cancelLookup, .cancelRetry] }
            guard key != track.key else {
                // Same track, still unanswered, the retry has stopped and it plays again: start it over.
                if phase == .unavailable, !retryArmed, track.isPlaying { return ask(now: now) }
                return []
            }
            key = track.key
            retryArmed = false
            guard track.isAskable else { phase = .answered(.none); return [.cancelLookup, .cancelRetry] }
            phase = .idle
            return [.cancelLookup, .cancelRetry, .readCache]

        case .cacheRead(let readKey, let cached, let mayAsk, let now):
            guard readKey == key, phase == .idle else { return [] }
            if let cached { phase = .answered(cached); return [] }
            guard mayAsk else { phase = .answered(.none); return [] }
            return ask(now: now)

        case .answered(let answerKey, let result):
            guard answerKey == key, phase == .loading else { return [] }
            backoff.recordSuccess()
            phase = .answered(result)
            return [.saveCache(result)]

        case .failed(let failedKey, let retryAfter, let now):
            guard failedKey == key, phase == .loading else { return [] }
            backoff.recordFailure(now: now, retryAfter: retryAfter)
            phase = .unavailable
            retryArmed = true
            return [.scheduleRetry]

        case .retryDue(let dueKey, let now):
            guard dueKey == key, phase == .unavailable else { return [] }
            retryArmed = false
            return ask(now: now)

        case .retryStopped:
            retryArmed = false
            return []

        case .viewerAppeared:
            viewers += 1
            return []

        case .viewerLeft:
            viewers = max(0, viewers - 1)
            // With no view left the retry has nobody to show its answer to, so it stops.
            guard viewers == 0 else { return [] }
            retryArmed = false
            return [.cancelRetry]

        case .privacyOff:
            return switchOff()

        case .seeded(let seededKey, let result):
            key = seededKey
            phase = .answered(result)
            return []
        }
    }

    /// Whether a lookup step for `key` may still go out: lyrics are on, the track is still current and still loading.
    /// Checked before every request and after every reply.
    public func accepts(key requested: String, enabled: Bool) -> Bool {
        enabled && key == requested && phase == .loading
    }

    /// What the retry does at a wake-up, from the rules in `LyricsRetry`.
    public func retryPlan(for requested: String, now: Date, enabled: Bool) -> LyricsRetryPlan {
        LyricsRetry.plan(remaining: backoff.remaining(now: now), sameTrack: key == requested && phase == .unavailable,
                         isPlaying: isPlaying, visible: viewers > 0, enabled: enabled)
    }

    /// Sends the lookup, or shows `.unavailable` and waits first while the back-off is running.
    private mutating func ask(now: Date) -> [Effect] {
        guard backoff.canAsk(now: now) else {
            phase = .unavailable
            retryArmed = true
            return [.scheduleRetry]
        }
        phase = .loading
        return [.sendLookup]
    }

    private mutating func switchOff() -> [Effect] {
        key = nil
        phase = .off
        retryArmed = false
        return [.cancelLookup, .cancelRetry]
    }
}
