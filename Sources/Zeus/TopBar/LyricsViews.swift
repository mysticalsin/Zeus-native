import Observation
import SwiftUI
import ZeusCore

/// Time-synced lyrics from LRCLIB for what is playing. Off until Settings > Privacy > Synced lyrics is on,
/// because asking sends the title and artist to lrclib.net. Answers (and misses) are cached on disk; a service
/// failure is never cached, shows `.unavailable`, and holds back every request until the shared wait is over.
/// The one retry after a failure goes out only for the track a lyric view is showing, while it plays; otherwise
/// nothing runs, and the next load from a lyric view starts it again.
@MainActor
@Observable
final class LyricsStore {
    static let shared = LyricsStore()

    enum State: Equatable {
        case off, idle, loading, ready([LyricLine]), plain(String), instrumental
        /// The service answered and has no lyrics for this track.
        case none
        /// The service did not answer (offline, 429, 5xx, a reply over the size limit). Not cached; Zeus asks again when the wait ends.
        case unavailable
    }

    private(set) var state: State = .idle
    private(set) var currentKey: String?

    /// Every decision (load, cache, lookup, retry, privacy) is ZeusCore's `LyricsFlow`; this class runs its effects.
    @ObservationIgnored private var flow = LyricsFlow()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// The track the flow is on, for the effects that need its request URLs or its cache file.
    @ObservationIgnored private var query: LRCLIBQuery?
    /// Whether the track's source lets its lyrics rest on disk. A browser page's never do: its lyrics stay in memory.
    @ObservationIgnored private var persists = true
    @ObservationIgnored private let cache: LyricsCache
    @ObservationIgnored private let session: URLSession
    /// The privacy switch. Tests give their own so no setting is written.
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool

    init(cache: LyricsCache = LyricsCache(), session: URLSession? = nil, enabled: @escaping @MainActor () -> Bool = { LyricsStore.enabled }) {
        self.cache = cache
        isEnabled = enabled
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        self.session = session ?? URLSession(configuration: config)
    }

    static var enabled: Bool { SettingsStore.shared.bool("privacy.lyrics") }

    /// The state for this very track; `.idle` while another track's answer is still current.
    func state(for playing: NowPlaying?) -> State {
        guard isEnabled() else { return .off }
        guard let playing, currentKey == LRCLIBQuery(playing).cacheKey else { return .idle }
        return state
    }

    /// A lyric view appeared or went away. With no view left the retry has nobody to show its answer to, so it stops.
    func viewerAppeared() { send(.viewerAppeared) }
    func viewerLeft() { send(.viewerLeft) }

    func load(for playing: NowPlaying?) {
        var track: LyricsFlow.Track?
        if let playing {
            let asked = LRCLIBQuery(playing)
            query = asked
            persists = playing.source.persistsDerivedData
            // Asks only with the lyrics capability. For a player that is exactly `asked.isAskable`, as before.
            track = LyricsFlow.Track(key: asked.cacheKey, isAskable: playing.capabilities.contains(.lyrics), isPlaying: playing.isPlaying)
        }
        send(.load(enabled: isEnabled(), track: track, now: Date()))
    }

    /// Runs the flow's decision for one event, shows its phase, then runs its effects.
    private func send(_ event: LyricsFlow.Event) {
        let effects = flow.reduce(event)
        // Assign only on a change, so a view that reads these is not invalidated by an event that changed nothing.
        if currentKey != flow.key { currentKey = flow.key }
        let shown = Self.state(from: flow.phase)
        if state != shown { state = shown }
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: LyricsFlow.Effect) {
        switch effect {
        case .cancelLookup:
            task?.cancel(); task = nil
        case .cancelRetry:
            retryTask?.cancel(); retryTask = nil
        case .readCache:
            guard let query else { return }
            send(.cacheRead(key: query.cacheKey, cached: persists ? cache.load(query) : nil, mayAsk: !TopBarStyle.isSnapshot, now: Date()))
        case .sendLookup:
            guard let query else { return }
            task = Task { [weak self] in await self?.run(query) }
        case .scheduleRetry:
            if let query { scheduleRetry(query) }
        case .saveCache(let result):
            if persists, let query { cache.save(result, for: query) }
        }
    }

    /// True while a lookup step for `key` may still go out. Lyrics switched off ends the lookup here, whatever
    /// else is going on, so no step after the switch sends the title and artist anywhere.
    private func mayRequest(_ key: String) -> Bool {
        guard !Task.isCancelled else { return false }
        let enabled = isEnabled()
        if !enabled { send(.privacyOff) }
        return flow.accepts(key: key, enabled: enabled)
    }

    /// The three-step lookup, one request at a time. Any failure stops it and starts the wait; only
    /// answers (a body, or a 404 on every step) are cached. The switch and the track are checked before every
    /// request and after every reply.
    private func run(_ query: LRCLIBQuery) async {
        let key = query.cacheKey
        var result = LyricsResult.none
        lookup: for request in query.requests {
            guard mayRequest(key) else { return }
            let reply = await Self.fetch(request.url, session: session)
            guard mayRequest(key) else { return }
            switch LyricsStatus.outcome(status: reply.status, retryAfter: reply.retryAfter, bodyBytes: reply.size) {
            case .failed(let retryAfter):
                send(.failed(key: key, retryAfter: retryAfter, now: Date()))
                return
            case .notFound:
                continue
            case .found:
                let found = request.result(from: reply.data, query: query)
                if found != LyricsResult.none { result = found; break lookup }
            }
        }
        send(.answered(key: key, result))
    }

    /// Waits out the back-off, then asks once, but only while ZeusCore's rule says the retry still matters:
    /// this track is current and unanswered, it is playing, a lyric view is on screen, lyrics are on.
    private func scheduleRetry(_ query: LRCLIBQuery) {
        retryTask?.cancel()
        let key = query.cacheKey
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let plan = self?.flow.retryPlan(for: key, now: Date(), enabled: self?.isEnabled() ?? false) else { return }
                switch plan {
                case .wait(let seconds): try? await Task.sleep(for: .seconds(seconds))
                case .askNow: self?.send(.retryDue(key: key, now: Date())); return
                case .stop: self?.send(.retryStopped); return
                }
            }
        }
    }

    /// Snapshots and tests: set the answer for a track without the network.
    func seed(_ result: LyricsResult, for playing: NowPlaying) {
        send(.seeded(key: LRCLIBQuery(playing).cacheKey, result))
    }

    private static func state(from phase: LyricsFlow.Phase) -> State {
        switch phase {
        case .off: .off
        case .idle: .idle
        case .loading: .loading
        case .answered(let result): state(from: result)
        case .unavailable: .unavailable
        }
    }

    private static func state(from result: LyricsResult) -> State {
        switch result {
        case .synced(let lines): .ready(lines)
        case .plain(let text): .plain(text)
        case .instrumental: .instrumental
        case .none: .none
        }
    }

    private struct Reply: Sendable {
        var status: Int
        var data: Data
        /// Bytes read; one more than `LyricsLimits.maxReplyBytes` when the reply was cut off for being too big.
        var size: Int
        var retryAfter: TimeInterval?
    }

    /// One request. Status 0 means no answer at all (offline, timeout); the rules in ZeusCore decide what every status means.
    /// The body is read as it arrives and dropped once it passes `LyricsLimits.maxReplyBytes`, so a huge reply is never held.
    private nonisolated static func fetch(_ url: URL, session: URLSession) async -> Reply {
        var request = URLRequest(url: url)
        request.setValue("Zeus (https://zeus.app)", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await session.bytes(for: request), let http = response as? HTTPURLResponse else {
            return Reply(status: 0, data: Data(), size: 0, retryAfter: nil)
        }
        let retryAfter = LyricsStatus.retryAfter(header: http.value(forHTTPHeaderField: "Retry-After"), now: Date())
        let limit = LyricsLimits.maxReplyBytes
        if http.expectedContentLength > Int64(limit) {
            return Reply(status: http.statusCode, data: Data(), size: limit + 1, retryAfter: retryAfter)
        }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit { return Reply(status: http.statusCode, data: Data(), size: data.count, retryAfter: retryAfter) }
            }
        } catch {
            return Reply(status: 0, data: Data(), size: 0, retryAfter: nil)
        }
        return Reply(status: http.statusCode, data: data, size: data.count, retryAfter: retryAfter)
    }
}

/// The lyric lines around the one being sung, the current one lit. It follows `NowPlaying`'s position once
/// a second (TickingView, never TimelineView) and slides each new line into place.
struct LyricsView: View {
    let playing: NowPlaying?
    var rows = 3
    var rowHeight: CGFloat = 24
    var fontSize: CGFloat = 13
    var alignment: Alignment = .leading

    var body: some View {
        let store = LyricsStore.shared
        content(store.state(for: playing))
            .onAppear { store.viewerAppeared(); store.load(for: playing) }
            .onDisappear { store.viewerLeft() }
            .onChange(of: playing.map { LRCLIBQuery($0).cacheKey }) { store.load(for: playing) }
            .onChange(of: playing?.isPlaying) { store.load(for: playing) }
            // The privacy switch: turning lyrics off ends the lookup and the retry; turning them on looks the track up.
            .onChange(of: LyricsStore.enabled) { store.load(for: playing) }
    }

    @ViewBuilder
    private func content(_ state: LyricsStore.State) -> some View {
        switch state {
        case .ready(let lines):
            if let playing {
                TickingView(interval: 1, paused: TopBarStyle.isSnapshot) { context in
                    LyricWindow(lines: lines, index: LyricTiming.index(lines, elapsed: playing.elapsed(at: context.date)),
                                rows: rows, rowHeight: rowHeight, fontSize: fontSize, alignment: alignment,
                                playing: playing, tick: context.date)
                }
            }
        case .plain(let text):
            note("Not timed for this track", detail: text.split(separator: "\n").first.map { LyricsLimits.clipped(String($0)) })
        case .off:
            note("Synced lyrics are off", detail: "Turn them on in Settings > Privacy.")
        case .instrumental:
            note("Instrumental", detail: nil)
        case .loading, .idle:
            note("Looking for lyrics", detail: nil)
        case .none:
            note("No synced lyrics for this track", detail: nil)
        case .unavailable:
            note("Lyrics service is not answering", detail: "Zeus will try again shortly.")
        }
    }

    private func note(_ title: String, detail: String?) -> some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 2) {
            Text(title).font(.system(size: fontSize, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
            if let detail { Text(detail).font(.system(size: fontSize - 2)).foregroundStyle(Color.white.opacity(0.38)).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight * CGFloat(rows), alignment: alignment)
        .accessibilityElement(children: .combine)
    }
}

/// Which line is lit at a playback position. A short lead (the line lights as it is sung, not after).
enum LyricTiming {
    static let lead = 0.25
    static func index(_ lines: [LyricLine], elapsed: Double) -> Int { lines.currentIndex(at: elapsed + lead) ?? -1 }
}

private struct LyricWindow: View {
    let lines: [LyricLine]
    let index: Int
    let rows: Int
    let rowHeight: CGFloat
    let fontSize: CGFloat
    let alignment: Alignment
    /// What is playing and when this tick fired, for lighting the current line word by word.
    var playing: NowPlaying?
    var tick = Date.distantPast

    var body: some View {
        let wordByWord = SettingsStore.shared.bool("lyrics.wordByWord")
        let before = (rows - 1) / 2
        let visible = Array(max(0, index - before - 1)...max(0, min(lines.count - 1, index + rows)))
        ZStack {
            ForEach(visible, id: \.self) { i in
                let distance = i - index
                let current = distance == 0
                rowText(i, current: current, wordByWord: wordByWord)
                    .font(.system(size: current ? fontSize + 1.5 : fontSize, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Color.white : Color.white.opacity(distance < 0 ? 0.28 : 0.42))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .frame(height: rowHeight)
                    .offset(y: (CGFloat(before) + 0.5 - CGFloat(rows) / 2) * rowHeight + CGFloat(distance) * rowHeight)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight * CGFloat(rows))
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22), .init(color: .black, location: 0.78), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .animation(Motion.reduced ? nil : .easeInOut(duration: MotionTokens.lyricsLineMove), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(index >= 0 && index < lines.count ? lines[index].text : "Lyrics")
    }

    /// A line's text. The current line is lit word by word while the setting is on and the line has words and is short enough.
    @ViewBuilder
    private func rowText(_ i: Int, current: Bool, wordByWord: Bool) -> some View {
        if current, wordByWord, let playing, LyricsLimits.lightsWords(in: lines[i].text),
           !lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
            WordLitText(line: lines[i], lineEnd: lines.lineEnd(at: i, trackEnd: playing.duration), playing: playing, tick: tick)
        } else {
            Text(lines[i].text.isEmpty ? "\u{266A}" : lines[i].text)
        }
    }
}

/// The current line as one Text built from word runs, so wrapping, the two-line limit and the row height are
/// the same as the whole-line Text. Sung words and the word being sung are white, words to come the next-line tone.
/// It wakes at word changes with a sleeping task, not a fast timer: the task covers the stretch until the next
/// once-a-second tick (which restarts it and re-reads the playback position), and it does nothing while
/// paused, in snapshots, or after the view goes away. A pause or a seek restarts it at once. The row's accessibility
/// label already reads the whole line.
private struct WordLitText: View {
    /// The line's words, timed once when the row is made: a redraw at a word change only moves the lit word.
    let words: [LyricWord]
    let playing: NowPlaying
    let tick: Date
    /// Bumped at each word change to redraw this view.
    @State private var revision = 0

    init(line: LyricLine, lineEnd: Double, playing: NowPlaying, tick: Date) {
        words = LyricWordTiming.words(in: line, lineEnd: lineEnd)
        self.playing = playing
        self.tick = tick
    }

    /// What the wake-up task was planned from: a new tick, a pause or a seek replaces it.
    private struct WakeKey: Equatable {
        var tick: Date
        var isPlaying: Bool
        var positionAt: Date
    }

    /// How long one wake-up task runs at most; the next tick replaces it.
    private static let window: TimeInterval = 1.5
    private static let upcoming = Color.white.opacity(0.42)

    var body: some View {
        let _ = revision
        let lit = LyricWordTiming.index(words, at: playing.elapsed() + LyricTiming.lead)
        Text(runs(words, lit: lit))
            .contentTransition(Motion.reduced ? .identity : .opacity)
            .animation(Motion.reduced ? nil : .easeOut(duration: MotionTokens.topBarLabelOut), value: lit)
            .task(id: WakeKey(tick: tick, isPlaying: playing.isPlaying, positionAt: playing.positionAt)) { await wake() }
    }

    private func runs(_ words: [LyricWord], lit: Int?) -> AttributedString {
        var text = AttributedString()
        for (i, word) in words.enumerated() {
            var run = AttributedString(word.text)
            run.foregroundColor = lit.map { i <= $0 } == true ? Color.white : Self.upcoming
            text.append(run)
        }
        return text
    }

    /// Sleeps to each word change inside this tick's window and redraws there.
    private func wake() async {
        guard playing.isPlaying, !TopBarStyle.isSnapshot else { return }
        let began = Date()
        while !Task.isCancelled {
            let position = playing.elapsed() + LyricTiming.lead
            guard let next = LyricWordTiming.nextChange(words, after: position) else { return }
            let wait = max(next - position, LyricsLimits.minimumWordWake)
            guard wait <= Self.window - Date().timeIntervalSince(began) else { return }
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            revision &+= 1
        }
    }
}
