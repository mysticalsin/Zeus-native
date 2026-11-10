import Observation
import SwiftUI
import ZeusCore

/// Time-synced lyrics from LRCLIB for what is playing. Off until Settings > Privacy > Synced lyrics is on,
/// because asking sends the title and artist to lrclib.net. Answers (and misses) are cached on disk.
@MainActor
@Observable
final class LyricsStore {
    static let shared = LyricsStore()

    enum State: Equatable {
        case off, idle, loading, ready([LyricLine]), plain(String), instrumental, none
    }

    private(set) var state: State = .idle
    private(set) var currentKey: String?

    @ObservationIgnored private var task: Task<Void, Never>?
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

    func load(for playing: NowPlaying?) {
        guard Self.enabled else { state = .off; return }
        guard let playing else { return }
        let query = LRCLIBQuery(playing)
        guard currentKey != query.cacheKey else { return }
        currentKey = query.cacheKey
        task?.cancel()
        guard query.isAskable else { state = .none; return }
        if let cached = cache.load(query) { state = Self.state(from: cached); return }
        if TopBarStyle.isSnapshot { state = .none; return }
        state = .loading
        let key = query.cacheKey
        task = Task { [weak self, session, cache] in
            var answer = await Self.fetch(query.url, session: session)
            if answer == LyricsResult.none, !Task.isCancelled { answer = await Self.fetch(query.looseURL, session: session) }
            guard !Task.isCancelled else { return }
            // A network failure (nil) is shown as "none" but never cached, so the next play asks again.
            if let answer { cache.save(answer, for: query) }
            let result = answer ?? LyricsResult.none
            await MainActor.run {
                guard let self, self.currentKey == key else { return }
                self.state = Self.state(from: result)
            }
        }
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

    /// nil: the request failed (offline, server error). `.none`: LRCLIB answered 404.
    private nonisolated static func fetch(_ url: URL?, session: URLSession) async -> LyricsResult? {
        guard let url else { return LyricsResult.none }
        var request = URLRequest(url: url)
        request.setValue("Zeus (https://zeus.app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 404 { return LyricsResult.none }
        return status == 200 ? LRCLIBResponse.parse(data) : nil
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
            .onAppear { store.load(for: playing) }
            .onChange(of: playing.map { LRCLIBQuery($0).cacheKey }) { store.load(for: playing) }
    }

    @ViewBuilder
    private func content(_ state: LyricsStore.State) -> some View {
        switch state {
        case .ready(let lines):
            if let playing {
                TickingView(interval: 1, paused: TopBarStyle.isSnapshot) { context in
                    LyricWindow(lines: lines, index: LyricTiming.index(lines, elapsed: playing.elapsed(at: context.date)),
                                rows: rows, rowHeight: rowHeight, fontSize: fontSize, alignment: alignment)
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

    var body: some View {
        let before = (rows - 1) / 2
        let visible = Array(max(0, index - before - 1)...max(0, min(lines.count - 1, index + rows)))
        ZStack {
            ForEach(visible, id: \.self) { i in
                let distance = i - index
                let current = distance == 0
                Text(lines[i].text.isEmpty ? "\u{266A}" : lines[i].text)
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
}
