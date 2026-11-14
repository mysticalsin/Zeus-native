import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Answers every request from a closure, so no test reaches the network. State is static, so the suite runs one case at a time.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case image(Data, contentLength: Int? = nil)
        case redirect(to: String)
        case status(Int)
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var requested: [URL] = []
    private static let lock = NSLock()

    static func reset(_ replies: [String: Reply] = [:]) {
        lock.lock(); defer { lock.unlock() }
        self.replies = replies
        requested = []
    }

    static var requests: [URL] {
        lock.lock(); defer { lock.unlock() }
        return requested
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requested.append(url)
        let reply = Self.replies[url.absoluteString]
        Self.lock.unlock()
        switch reply {
        case .image(let data, let length):
            var headers = ["Content-Type": "image/png"]
            if let length { headers["Content-Length"] = String(length) }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
        case .status(let code):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    override func stopLoading() {}
}

@MainActor @Suite("Page covers never touch the disk", .serialized) struct PageArtworkDiskTests {
    private let coverURL = "https://img.example.com/cover.jpg"

    private static func png(side: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<side { for y in 0..<side { rep.setColor(.red, atX: x, y: y) } }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private func makeStore() throws -> (store: ArtworkStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PageArtworkDiskTests-\(UUID().uuidString)", isDirectory: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.timeoutIntervalForRequest = 8
        return (ArtworkStore(directory: directory, session: URLSession(configuration: config)), directory)
    }

    private func tab(_ cover: String?) -> NowPlaying {
        let key = BrowserMediaKey(tabID: 1, documentID: "doc", host: "video.example.com", fingerprint: "f")
        return NowPlaying(source: .browser(key), title: "Clip", artist: "Channel", album: "", isPlaying: true, duration: 90, position: 0,
                          artworkURL: cover.flatMap(URL.init(string:)))
    }

    private func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// Waits for a cover to show, up to two seconds.
    private func waitForCover(_ store: ArtworkStore, _ playing: NowPlaying) async -> NSImage? {
        for _ in 0..<100 {
            if let image = store.image(for: playing) { return image }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// Waits until the stub has seen `count` requests, then a moment more for the store to react.
    private func waitForRequests(_ count: Int) async {
        for _ in 0..<100 where StubProtocol.requests.count < count { try? await Task.sleep(for: .milliseconds(20)) }
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test func aPageCoverShowsAndLeavesTheDirectoryEmpty() async throws {
        StubProtocol.reset([coverURL: .image(Self.png(side: 8))])
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playing = tab(coverURL)
        store.request(for: playing)
        let image = await waitForCover(store, playing)
        #expect(image != nil)
        #expect(StubProtocol.requests.map(\.absoluteString) == [coverURL])
        #expect(files(in: directory).isEmpty, "nothing from a browser item reaches the cache folder")
        #expect(store.glow != nil)
    }

    @Test func aFileSeededAtThePageKeyIsIgnoredAndLeftAlone() async throws {
        StubProtocol.reset([coverURL: .image(Self.png(side: 8))])
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playing = tab(coverURL)
        let key = ArtworkSource.cacheKey(for: playing)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let seeded = Self.png(side: 3)
        let seededFile = directory.appendingPathComponent(key + ".img")
        try seeded.write(to: seededFile)
        store.request(for: playing)
        let image = await waitForCover(store, playing)
        // The picture on screen is the fetched one (8 px), not the file at the key (3 px).
        #expect(image.map { NSBitmapImageRep(data: $0.tiffRepresentation ?? Data())?.pixelsWide } == 8)
        #expect(try Data(contentsOf: seededFile) == seeded)
        #expect(files(in: directory) == [key + ".img"])
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func aLinkThatIsNotAllowedIsNeverRequested() async throws {
        StubProtocol.reset()
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        for link in ["http://img.example.com/c.jpg", "https://127.0.0.1/c.jpg", "https://localhost/c.jpg", "https://nas.local/c.jpg", nil] {
            let playing = tab(link)
            store.request(for: playing)
            try? await Task.sleep(for: .milliseconds(120))
            #expect(store.image(for: playing) == nil, "\(link ?? "no link") shows the hue tile")
        }
        #expect(StubProtocol.requests.isEmpty)
        #expect(files(in: directory).isEmpty)
    }

    @Test func aFailedAnswerLeavesTheTileAndWritesNothing() async throws {
        StubProtocol.reset([coverURL: .status(404)])
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let playing = tab(coverURL)
        store.request(for: playing)
        await waitForRequests(1)
        #expect(store.image(for: playing) == nil)
        #expect(files(in: directory).isEmpty)
        // Bytes that are not an image are no cover either.
        StubProtocol.reset([coverURL: .image(Data("not an image".utf8))])
        let again = try makeStore()
        defer { try? FileManager.default.removeItem(at: again.directory) }
        again.store.request(for: playing)
        await waitForRequests(1)
        #expect(again.store.image(for: playing) == nil)
        #expect(files(in: again.directory).isEmpty)
    }

    @Test func aCoverOverTwoMegabytesIsRefused() async throws {
        let big = Self.png(side: 8)
        // Declared too large: refused from the header alone.
        StubProtocol.reset([coverURL: .image(big, contentLength: 2_000_001)])
        let declared = try makeStore()
        defer { try? FileManager.default.removeItem(at: declared.directory) }
        let playing = tab(coverURL)
        declared.store.request(for: playing)
        await waitForRequests(1)
        #expect(declared.store.image(for: playing) == nil)
        // No length declared, but more than 2 MB arrives: the read stops and nothing is shown.
        StubProtocol.reset([coverURL: .image(big + Data(count: 2_100_000))])
        let streamed = try makeStore()
        defer { try? FileManager.default.removeItem(at: streamed.directory) }
        streamed.store.request(for: playing)
        await waitForRequests(1)
        #expect(streamed.store.image(for: playing) == nil)
        #expect(files(in: streamed.directory).isEmpty)
    }

    @Test func aRedirectToAnythingButAnAllowedHTTPSAddressIsRefused() async throws {
        StubProtocol.reset([coverURL: .redirect(to: "http://img.example.com/plain.jpg"),
                            "http://img.example.com/plain.jpg": .image(Self.png(side: 8))])
        let insecure = try makeStore()
        defer { try? FileManager.default.removeItem(at: insecure.directory) }
        let playing = tab(coverURL)
        insecure.store.request(for: playing)
        await waitForRequests(1)
        #expect(insecure.store.image(for: playing) == nil)
        #expect(!StubProtocol.requests.contains { $0.scheme == "http" })

        StubProtocol.reset([coverURL: .redirect(to: "https://192.168.0.9/inside.jpg"),
                            "https://192.168.0.9/inside.jpg": .image(Self.png(side: 8))])
        let inside = try makeStore()
        defer { try? FileManager.default.removeItem(at: inside.directory) }
        inside.store.request(for: playing)
        await waitForRequests(1)
        #expect(inside.store.image(for: playing) == nil)
        #expect(!StubProtocol.requests.contains { $0.host == "192.168.0.9" })

        // A redirect to another allowed https address is followed.
        StubProtocol.reset([coverURL: .redirect(to: "https://cdn.example.net/moved.jpg"),
                            "https://cdn.example.net/moved.jpg": .image(Self.png(side: 8))])
        let moved = try makeStore()
        defer { try? FileManager.default.removeItem(at: moved.directory) }
        moved.store.request(for: playing)
        #expect(await waitForCover(moved.store, playing) != nil)
        #expect(files(in: moved.directory).isEmpty)
    }
}
