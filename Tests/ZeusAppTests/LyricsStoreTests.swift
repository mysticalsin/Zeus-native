import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Answers every lyric request with one plain-lyrics reply and counts them, so no test reaches the network.
private final class LyricsStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var count = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        count = 0
    }

    static var requests: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"plainLyrics":"From the network"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The lyric store with a temporary cache folder and a stub session: a page's lyrics stay off the disk, a player's do not.
@MainActor @Suite("Browser lyrics stay off the disk", .serialized) struct LyricsStoreTests {
    private func makeStore() -> (store: LyricsStore, cache: LyricsCache, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LyricsStoreTests-\(UUID().uuidString)", isDirectory: true)
        let cache = LyricsCache(directory: directory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LyricsStub.self]
        let store = LyricsStore(cache: cache, session: URLSession(configuration: config), enabled: { true })
        return (store, cache, directory)
    }

    private func browserItem(duration: Double = 200) -> NowPlaying {
        let key = BrowserMediaKey(tabID: 1, documentID: "doc", host: "video.example.com", fingerprint: "f")
        return NowPlaying(source: .browser(key), title: "Clip", artist: "Channel", album: "", isPlaying: true, duration: duration, position: 0)
    }

    private func musicItem() -> NowPlaying {
        NowPlaying(player: .music, title: "Song", artist: "Band", album: "Record", isPlaying: true, duration: 200, position: 0)
    }

    private func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// Waits for the store to leave idle and loading for this item, up to two seconds.
    private func settled(_ store: LyricsStore, _ item: NowPlaying) async -> LyricsStore.State {
        for _ in 0..<100 {
            let state = store.state(for: item)
            if state != .idle && state != .loading { return state }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return store.state(for: item)
    }

    @Test func aBrowserItemNeverReadsOrWritesTheLyricCache() async throws {
        LyricsStub.reset()
        let (store, cache, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = browserItem()
        let query = LRCLIBQuery(item)
        cache.save(.plain("Seeded"), for: query)
        let seededFile = directory.appendingPathComponent(query.cacheKey + ".json")
        let seeded = try Data(contentsOf: seededFile)
        store.load(for: item)
        // The answer is the network's, so the file at the key was never read.
        #expect(await settled(store, item) == .plain("From the network"))
        #expect(LyricsStub.requests >= 1)
        // Nothing was written after the answer: the file at the key is as it was, and it is the only file.
        #expect(try Data(contentsOf: seededFile) == seeded)
        #expect(files(in: directory) == [query.cacheKey + ".json"])
    }

    @Test func aBrowserItemLeavesNoFileInAnEmptyCacheFolder() async throws {
        LyricsStub.reset()
        let (store, _, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = browserItem()
        store.load(for: item)
        #expect(await settled(store, item) == .plain("From the network"))
        #expect(files(in: directory).isEmpty)
    }

    @Test func aBrowserItemWithNoDurationAsksNothing() async throws {
        LyricsStub.reset()
        let (store, cache, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = browserItem(duration: 0)
        #expect(!item.capabilities.contains(.lyrics))
        cache.save(.plain("Seeded"), for: LRCLIBQuery(item))
        store.load(for: item)
        #expect(store.state(for: item) == .none)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(LyricsStub.requests == 0)
        #expect(files(in: directory).count == 1, "only the seeded file")
    }

    @Test func aPlayerStillReadsAndWritesTheLyricCache() async throws {
        LyricsStub.reset()
        let (store, cache, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = musicItem()
        let query = LRCLIBQuery(item)
        cache.save(.plain("Seeded"), for: query)
        store.load(for: item)
        // A cached answer is used and nothing is asked.
        #expect(await settled(store, item) == .plain("Seeded"))
        #expect(LyricsStub.requests == 0)
        // Without a cached answer the network's answer is written.
        let other = NowPlaying(player: .music, title: "Other", artist: "Band", album: "Record", isPlaying: true, duration: 180, position: 0)
        store.load(for: other)
        #expect(await settled(store, other) == .plain("From the network"))
        #expect(files(in: directory).contains(LRCLIBQuery(other).cacheKey + ".json"))
    }
}
