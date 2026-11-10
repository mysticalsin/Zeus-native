import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// One state's sprite animation, read from `Avatar/Anim/<state>.json` (written by
/// tools/mascot/build_animated_zeus.py). Pure timing + geometry: no images, so it is unit tested.
struct MascotClip: Decodable, Equatable, Sendable {
    struct Frame: Decodable, Equatable, Sendable {
        let i: Int, x: Int, y: Int, w: Int, h: Int, ms: Int
    }
    struct Atlas: Decodable, Equatable, Sendable {
        let file: String
        let cell: Int
        let width: Int
        let height: Int
        let frames: [Frame]
    }

    let state: String
    /// "loop" or "one-shot", from the pack manifest.
    let kind: String
    let seconds: Double
    let fps: Int
    let frameCount: Int
    let frameDurationsMs: [Int]
    let sizes: [String: Atlas]

    var isLoop: Bool { kind == "loop" }

    /// Total length of the clip in seconds, from the per-frame durations.
    var length: Double { Double(frameDurationsMs.reduce(0, +)) / 1000 }

    /// Frame on screen `elapsed` seconds after the clip started: loops wrap, one-shots hold the last frame.
    func frameIndex(at elapsed: Double) -> Int {
        let total = length
        guard frameCount > 0, total > 0, elapsed.isFinite else { return 0 }
        var t = max(0, elapsed)
        if isLoop { t = t.truncatingRemainder(dividingBy: total) } else if t >= total { return frameCount - 1 }
        var end = 0.0
        for (index, ms) in frameDurationsMs.enumerated() {
            end += Double(ms) / 1000
            if t < end { return index }
        }
        return frameCount - 1
    }

    /// One-shots are finished (holding their last frame) once `elapsed` passes the clip length.
    func isFinished(at elapsed: Double) -> Bool { !isLoop && elapsed >= length }

    /// The smallest atlas whose cells cover `points` at `pixelScale` (2 on retina, 1 for 1x exports).
    func atlasKey(forPoints points: CGFloat, pixelScale: CGFloat = 2) -> String? {
        let needed = points * pixelScale
        let keys = sizes.keys.compactMap { Int($0) }.sorted()
        guard let largest = keys.last else { return nil }
        return String(keys.first { CGFloat($0) >= needed } ?? largest)
    }
}

/// Loads the atlases and keeps decoded frames per atlas size, a handful at a time.
@MainActor
final class MascotAtlasStore {
    static let shared = MascotAtlasStore(directory: ZeusResources.bundle?.url(forResource: "Anim", withExtension: nil))

    private let directory: URL?
    private var clips: [String: MascotClip?] = [:]
    private var decoded: [String: [CGImage]] = [:]
    private var order: [String] = []
    /// Decoded frame sets kept at once (the notch uses a few 128 px sets; 320 px sets are bigger).
    static let cacheLimit = 8

    init(directory: URL?) { self.directory = directory }

    /// The clip for a manifest state id, or nil if the atlas is not shipped (callers show the still pose).
    func clip(_ id: String) -> MascotClip? {
        if let cached = clips[id] { return cached }
        var clip: MascotClip?
        if let url = directory?.appendingPathComponent("\(id).json"), let data = try? Data(contentsOf: url) {
            clip = try? JSONDecoder().decode(MascotClip.self, from: data)
        }
        clips[id] = .some(clip)
        return clip
    }

    /// The current frame, or nil when the clip or its PNG is missing or unreadable.
    func frame(_ id: String, elapsed: Double, points: CGFloat, pixelScale: CGFloat = 2) -> CGImage? {
        guard let clip = clip(id), let key = clip.atlasKey(forPoints: points, pixelScale: pixelScale), let atlas = clip.sizes[key] else { return nil }
        guard let frames = decodedFrames(id: id, key: key, atlas: atlas) else { return nil }
        let index = clip.frameIndex(at: elapsed)
        return index < frames.count ? frames[index] : nil
    }

    private func decodedFrames(id: String, key: String, atlas: MascotClip.Atlas) -> [CGImage]? {
        let cacheKey = "\(id)@\(key)"
        if let hit = decoded[cacheKey] { return hit }
        guard let url = directory?.appendingPathComponent(atlas.file),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let frames = atlas.frames.compactMap { sheet.cropping(to: CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)) }
        guard frames.count == atlas.frames.count else { return nil }
        decoded[cacheKey] = frames
        order.append(cacheKey)
        if order.count > Self.cacheLimit { decoded[order.removeFirst()] = nil }
        return frames
    }
}
