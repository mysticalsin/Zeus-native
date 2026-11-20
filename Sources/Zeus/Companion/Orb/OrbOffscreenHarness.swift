import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
import ZeusCore

// Ported from github.com/mysticalsin/jarvis2.0
// Source path: frontend/src/orb.ts
// Source commit: 16e37bd801eb797798e02540665f8b3804b0fe14
// Copyright (c) 2026 Ethan Rogers
// License: personal non-commercial grant. Full text: LICENSES/jarvis2.0-LICENSE
//
// MAC-PENDING. Linux has no Metal, and this file is not a render result.
// On Tony's Mac, call `OrbOffscreenHarness.writeProof(to:)` from a debug host.
// It writes one PNG per visual state plus frame-times.csv. A green Linux test does not mean those
// files exist, and it does not mean the 60 Hz or 120 Hz frame budget passed.

enum OrbOffscreenHarness {
    struct Proof: Sendable {
        var directory: URL
        var frameLog: URL
        var images: [URL]
    }

    enum Failure: Error, CustomStringConvertible {
        case metalUnavailable
        case textureUnavailable

        var description: String {
            switch self {
            case .metalUnavailable: "No Metal device. Linux has no Metal. Native rendering is MAC-PENDING."
            case .textureUnavailable: "Metal refused the offscreen texture."
            }
        }
    }

    /// Renders each visual state offscreen. `framesPerState` steps the pure simulation at 60 Hz and
    /// records how long each Metal encode took. That log is evidence only after a run on Apple Silicon.
    static func writeProof(to directory: URL, framesPerState: Int = 30, side: Int = 256) throws -> Proof {
        guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.metalUnavailable }
        let renderer = try OrbMetalRenderer(device: device, bands: OrbPlaybackMeter.shared)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure.textureUnavailable }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var log = "state,frame,encode_ms\n"
        var images: [URL] = []
        for state in OrbVisualState.allCases {
            var simulation = OrbSimulation(seed: 1, state: state)
            for frame in 0..<framesPerState {
                simulation.renderFrame(delta: 1.0 / 60.0, audio: .silent, reduceMotion: false)
                let started = Date()
                try renderer.draw(snapshot: simulation, into: texture)
                let elapsed = Date().timeIntervalSince(started) * 1000
                log += "\(state.rawValue),\(frame),\(String(format: "%.3f", elapsed))\n"
            }
            let imageURL = directory.appendingPathComponent("\(state.rawValue).png")
            try writePNG(texture: texture, to: imageURL)
            images.append(imageURL)
        }
        let frameLog = directory.appendingPathComponent("frame-times.csv")
        try log.write(to: frameLog, atomically: true, encoding: .utf8)
        return Proof(directory: directory, frameLog: frameLog, images: images)
    }

    private static func writePNG(texture: MTLTexture, to url: URL) throws {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: rowBytes,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: rowBytes, space: space, bitmapInfo: bitmap),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.textureUnavailable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.textureUnavailable }
    }
}
