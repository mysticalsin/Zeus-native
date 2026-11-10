import AppKit
import Observation
import SwiftUI
import ZeusCore

/// Album art for what is playing. Spotify: the public oEmbed thumbnail of the track in its
/// notification. Apple Music: the iTunes Search API. Both need no key and no permission; Apple
/// Events (`artwork url of current track`, `data of artwork 1`) are only a fallback when
/// Automation is already allowed. Covers are cached in ~/Library/Caches/Zeus/artwork (LRU, 50 MB).
@MainActor
@Observable
final class ArtworkStore {
    static let shared = ArtworkStore()

    /// The cover for `currentKey`; nil while it loads or when nothing could be found.
    private(set) var image: NSImage?
    private(set) var currentKey: String?
    /// The cover's own colour, lifted for light on black.
    private(set) var glow: ArtworkColor.RGB?

    @ObservationIgnored private var memory: [String: (image: NSImage, glow: ArtworkColor.RGB?)] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let directory: URL

    init(directory: URL? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zeus/artwork", isDirectory: true)
    }

    // MARK: Reading

    /// The cover only when it belongs to this very track, so a slow fetch never paints the last song's art.
    func image(for playing: NowPlaying?) -> NSImage? {
        guard let playing, currentKey == ArtworkSource.cacheKey(for: playing) else { return nil }
        return image
    }

    /// The colour the music light takes: the cover's, else the player's own hue.
    func tint(for playing: NowPlaying?, saturation: Double = 0.5, brightness: Double = 1, scale: Double = 1) -> Color {
        if let playing, currentKey == ArtworkSource.cacheKey(for: playing), let glow {
            return Color(red: glow.red * scale, green: glow.green * scale, blue: glow.blue * scale)
        }
        return Color(hue: playing?.hue ?? 0.3, saturation: saturation, brightness: brightness * scale)
    }

    // MARK: Requests

    /// Call whenever the track changes (and with nil when playback ends).
    func request(for playing: NowPlaying?) {
        guard let playing else {
            task?.cancel()
            currentKey = nil
            image = nil
            glow = nil
            return
        }
        let key = ArtworkSource.cacheKey(for: playing)
        guard key != currentKey else { return }
        task?.cancel()
        currentKey = key
        image = nil
        glow = nil
        if let hit = memory[key] {
            image = hit.image
            glow = hit.glow
            return
        }
        guard !failed.contains(key) else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let data = await self.load(playing, key: key)
            guard !Task.isCancelled, let data, let image = NSImage(data: data) else {
                if !Task.isCancelled { self.failed.insert(key) }
                return
            }
            let glow = Self.glow(of: image)
            self.remember(key, image: image, glow: glow)
            if self.currentKey == key {
                self.image = image
                self.glow = glow
            }
        }
    }

    /// Snapshots and tests: a cover without the network.
    func seed(_ image: NSImage, for playing: NowPlaying) {
        let key = ArtworkSource.cacheKey(for: playing)
        let glow = Self.glow(of: image)
        remember(key, image: image, glow: glow)
        currentKey = key
        self.image = image
        self.glow = glow
    }

    private func remember(_ key: String, image: NSImage, glow: ArtworkColor.RGB?) {
        memory[key] = (image, glow)
        order.removeAll { $0 == key }
        order.append(key)
        if order.count > 12, let old = order.first {
            order.removeFirst()
            memory[old] = nil
        }
    }

    // MARK: Loading

    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".img") }

    private func load(_ playing: NowPlaying, key: String) async -> Data? {
        if let cached = try? Data(contentsOf: file(key)), NSImage(data: cached) != nil {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file(key).path)
            return cached
        }
        let data: Data?
        switch playing.player {
        case .spotify: data = await spotifyCover(playing)
        case .music: data = await musicCover(playing)
        }
        if let data, NSImage(data: data) != nil {
            save(data, key: key)
            return data
        }
        return nil
    }

    private func spotifyCover(_ playing: NowPlaying) async -> Data? {
        if let id = ArtworkSource.spotifyTrackID(playing.trackID), let oembed = ArtworkSource.spotifyOEmbedURL(trackID: id),
           let json = await fetch(oembed), let thumb = ArtworkSource.parseOEmbed(json) {
            if let big = await fetchImage(ArtworkSource.spotifyFullSize(thumb)) { return big }
            if let small = await fetchImage(thumb) { return small }
        }
        // Fallback: ask Spotify itself, only when Automation is already allowed (never prompts).
        guard Automation.allowed(NowPlaying.Player.spotify.bundleID),
              let text = Self.script("tell application id \"com.spotify.client\" to return artwork url of current track")?.stringValue,
              let url = URL(string: text), url.scheme == "https" else { return nil }
        return await fetchImage(url)
    }

    private func musicCover(_ playing: NowPlaying) async -> Data? {
        if let search = ArtworkSource.iTunesSearchURL(artist: playing.artist, album: playing.album, title: playing.title),
           let json = await fetch(search), let url = ArtworkSource.parseITunes(json) {
            if let data = await fetchImage(url) { return data }
        }
        // Fallback: the cover embedded in the track, when Automation is already allowed.
        guard Automation.allowed(NowPlaying.Player.music.bundleID),
              let descriptor = Self.script("tell application id \"com.apple.Music\" to return data of artwork 1 of current track") else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    private nonisolated static func script(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func fetchImage(_ url: URL) async -> Data? {
        guard let data = await fetch(url), NSImage(data: data) != nil else { return nil }
        return data
    }

    // MARK: Disk

    private func save(_ data: Data, key: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
        trim()
    }

    private func trim() {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let entries = urls.compactMap { url -> ArtworkCachePolicy.Entry? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let size = values.fileSize else { return nil }
            return .init(name: url.lastPathComponent, bytes: size, lastUsed: values.contentModificationDate ?? .distantPast)
        }
        for name in ArtworkCachePolicy.evictions(entries) { try? manager.removeItem(at: directory.appendingPathComponent(name)) }
    }

    // MARK: Colour

    /// Average colour from an 8 x 8 copy of the cover.
    static func glow(of image: NSImage) -> ArtworkColor.RGB? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard drawn, let average = ArtworkColor.average(rgba: pixels) else { return nil }
        return ArtworkColor.glow(average)
    }
}
