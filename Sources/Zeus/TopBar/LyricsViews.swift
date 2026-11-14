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
        /// The service did not answer (offline, 429, 5xx). Not cached; Zeus asks again when the wait ends.
        case unavailable
    }

    private(set) var state: State = .idle
    private(set) var currentKey: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// True while `retryTask` is still waiting to decide; false once it asked or stopped.
    @ObservationIgnored private var retryArmed = false
    /// What a lyric view last showed: whether it is playing now is read from here when the wait ends.
    @ObservationIgnored private var watching: NowPlaying?
    /// How many lyric views are on screen.
    @ObservationIgnored private var viewers = 0
    /// The wait after a failure. One for the whole service, so a new track does not skip it.
    @ObservationIgnored private var backoff = LyricsBackoff()
    @ObservationIgnored private let cache: LyricsCache
    @ObservationIgnored private let session: URLSession

    init(cache: LyricsCache = LyricsCache()) {
        self.cache = cache
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    static var enabled: Bool { SettingsStore.shared.bool("privacy.lyrics") }

    /// The state for this very track; `.idle` while another track's answer is still current.
    func state(for playing: NowPlaying?) -> State {
        guard Self.enabled else { return .off }
        guard let playing, currentKey == LRCLIBQuery(playing).cacheKey else { return .idle }
        return state
    }

    /// A lyric view appeared or went away. With no view left the retry has nobody to show its answer to, so it stops.
    func viewerAppeared() { viewers += 1 }
    func viewerLeft() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { cancelRetry() }
    }

    func load(for playing: NowPlaying?) {
        watching = playing
        guard Self.enabled else {
            task?.cancel(); cancelRetry()
            currentKey = nil
            state = .off
            return
        }
        // Nothing is playing: drop the track and its retry, so no request is left for a track that stopped.
        guard let playing else {
            task?.cancel(); cancelRetry()
            currentKey = nil
            return
        }
        let query = LRCLIBQuery(playing)
        guard currentKey != query.cacheKey else {
            // Same track, still unanswered, the retry has stopped and it plays again: start it over.
            if state == .unavailable, !retryArmed, playing.isPlaying { ask(query) }
            return
        }
        currentKey = query.cacheKey
        task?.cancel(); cancelRetry()
        guard query.isAskable else { state = .none; return }
        if let cached = cache.load(query) { state = Self.state(from: cached); return }
        if TopBarStyle.isSnapshot { state = .none; return }
        ask(query)
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryArmed = false
    }

    /// Sends the lookup, or shows `.unavailable` and waits first while the back-off is running.
    private func ask(_ query: LRCLIBQuery) {
        guard backoff.canAsk(now: Date()) else {
            state = .unavailable
            scheduleRetry(query)
            return
        }
        state = .loading
        task = Task { [weak self] in await self?.run(query) }
    }

    /// The three-step lookup, one request at a time. Any failure stops it and starts the wait; only
    /// answers (a body, or a 404 on every step) are cached.
    private func run(_ query: LRCLIBQuery) async {
        let key = query.cacheKey
        var result = LyricsResult.none
        lookup: for request in query.requests {
            let reply = await Self.fetch(request.url, session: session)
            guard !Task.isCancelled, currentKey == key else { return }
            switch LyricsStatus.outcome(status: reply.status, retryAfter: reply.retryAfter) {
            case .failed(let retryAfter):
                backoff.recordFailure(now: Date(), retryAfter: retryAfter)
                state = .unavailable
                scheduleRetry(query)
                return
            case .notFound:
                continue
            case .found:
                let found = request.result(from: reply.data, query: query)
                if found != LyricsResult.none { result = found; break lookup }
            }
        }
        backoff.recordSuccess()
        cache.save(result, for: query)
        state = Self.state(from: result)
    }

    /// Waits out the back-off, then asks once, but only while ZeusCore's rule says the retry still matters:
    /// this track is current and unanswered, it is playing, a lyric view is on screen, lyrics are on.
    private func scheduleRetry(_ query: LRCLIBQuery) {
        retryTask?.cancel()
        retryArmed = true
        let key = query.cacheKey
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let plan = self?.retryPlan(for: key) else { return }
                switch plan {
                case .wait(let seconds): try? await Task.sleep(for: .seconds(seconds))
                case .askNow: self?.retryDue(query); return
                case .stop: self?.retryArmed = false; return
                }
            }
        }
    }

    private func retryPlan(for key: String) -> LyricsRetryPlan {
        LyricsRetry.plan(remaining: backoff.remaining(now: Date()),
                         sameTrack: currentKey == key && state == .unavailable,
                         isPlaying: watching?.isPlaying == true, visible: viewers > 0, enabled: Self.enabled)
    }

    private func retryDue(_ query: LRCLIBQuery) {
        retryArmed = false
        ask(query)
    }

    /// Snapshots and tests: set the answer for a track without the network.
    func seed(_ result: LyricsResult, for playing: NowPlaying) {
        currentKey = LRCLIBQuery(playing).cacheKey
        state = Self.state(from: result)
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
        var retryAfter: TimeInterval?
    }

    /// One request. Status 0 means no answer at all (offline, timeout); the rules in ZeusCore decide what every status means.
    private nonisolated static func fetch(_ url: URL, session: URLSession) async -> Reply {
        var request = URLRequest(url: url)
        request.setValue("Zeus (https://zeus.app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else {
            return Reply(status: 0, data: Data(), retryAfter: nil)
        }
        return Reply(status: http.statusCode, data: data,
                     retryAfter: LyricsStatus.retryAfter(header: http.value(forHTTPHeaderField: "Retry-After"), now: Date()))
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
            note("Not timed for this track", detail: text.split(separator: "\n").first.map(String.init))
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
        .animation(Motion.reduced ? nil : .easeInOut(duration: 0.45), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(index >= 0 && index < lines.count ? lines[index].text : "Lyrics")
    }

    /// A line's text. The current line is lit word by word while the setting is on and the line has words.
    @ViewBuilder
    private func rowText(_ i: Int, current: Bool, wordByWord: Bool) -> some View {
        if current, wordByWord, let playing, !lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
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
    let line: LyricLine
    let lineEnd: Double
    let playing: NowPlaying
    let tick: Date
    /// Bumped at each word change to redraw this view.
    @State private var revision = 0

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
        let words = LyricWordTiming.words(in: line, lineEnd: lineEnd)
        let lit = LyricWordTiming.index(words, at: playing.elapsed() + LyricTiming.lead)
        Text(runs(words, lit: lit))
            .contentTransition(Motion.reduced ? .identity : .opacity)
            .animation(Motion.reduced ? nil : .easeOut(duration: 0.18), value: lit)
            .task(id: WakeKey(tick: tick, isPlaying: playing.isPlaying, positionAt: playing.positionAt)) { await wake(words) }
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
    private func wake(_ words: [LyricWord]) async {
        guard playing.isPlaying, !TopBarStyle.isSnapshot else { return }
        let began = Date()
        while !Task.isCancelled {
            let position = playing.elapsed() + LyricTiming.lead
            guard let next = LyricWordTiming.nextChange(words, after: position) else { return }
            let wait = max(next - position, 0.02)
            guard wait <= Self.window - Date().timeIntervalSince(began) else { return }
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            revision &+= 1
        }
    }
}
