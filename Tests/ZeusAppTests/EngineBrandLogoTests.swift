import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

@Suite struct EngineBrandLogoTests {
    @MainActor @Test func officialGrokSVGIsExactAndDecodesAtOriginalAspectRatio() throws {
        let mark = EngineBrand.resolve(provider: .grok)
        #expect(mark == .grok)
        #expect(EngineBrand.resolve(engine: .grok) == mark)
        #expect(EngineBrand.resolve("x.ai") == mark)
        let url = try #require(EngineBrandImage.bundledURL(for: mark), "Official SVG must exist in the resource bundle")
        #expect(url.pathExtension == "svg")
        let bytes = try Data(contentsOf: url)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(hash == "8157a9b2e3ff94a690000ee9327156eb28539efe176fcb06cadcc7688fb4df90", "Official artwork bytes changed")
        let image = try #require(EngineBrandImage.load(mark), "Native SVG decoding is required; fallback is not acceptance")
        try #require(image.size.width > 0 && image.size.height > 0)
        #expect(abs(image.size.width / image.size.height - 34.0 / 32.0) < 0.001, "Original Grok aspect ratio changed")
        let decoded = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil), "Official SVG must decode into actual pixels")
        let bitmap = try #require(CGContext(data: nil, width: decoded.width, height: decoded.height,
                                            bitsPerComponent: 8, bytesPerRow: decoded.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let data = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
        #expect(stride(from: 3, to: decoded.width * decoded.height * 4, by: 4).contains { data[$0] > 0 }, "Official Grok mark decoded blank")
    }

    @Test func unverifiedLegacyPNGsAreAbsentFromBundle() throws {
        let grok = try #require(EngineBrandImage.bundledURL(for: .grok))
        let brands = grok.deletingLastPathComponent()
        for name in ["chatgpt.png", "claude.png", "cursor.png", "gemini.png", "grok.png"] {
            #expect(!FileManager.default.fileExists(atPath: brands.appendingPathComponent(name).path), "Unverified legacy image shipped: \(name)")
        }
    }

    @Test func vectorAssetsExistInBundle() {
        for mark in EngineBrandMark.allCases where mark != .fallback {
            let url = EngineBrandImage.url(for: mark)
            #expect(url != nil, "missing URL for \(mark)")
            if let url {
                #expect(FileManager.default.fileExists(atPath: url.path), "missing \(url.lastPathComponent)")
            }
        }
        #expect(FileManager.default.fileExists(atPath: EngineBrandImage.url(for: .fallback)!.path))
    }

    @MainActor @Test func agentLogoRowSnapshots() throws {
        let proof = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-brand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: proof, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proof) }
        let paths = try EngineBrandSnapshotExport.writeRows(to: proof, scales: [2, 4])
        #expect(paths.count == 4)
        for path in paths {
            #expect(FileManager.default.fileExists(atPath: path))
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
            #expect(size > 500, "\(path) looks empty")
        }
    }

    @MainActor @Test func rowRendersEverySampleMark() {
        GlassFonts.register()
        TopBarStyle.isSnapshot = true
        defer { TopBarStyle.isSnapshot = false }
        let view = EngineBrandRowSnapshot(agents: EngineBrand.debugSampleAgents, dark: false)
            .frame(width: 270)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #expect(renderer.cgImage != nil)
    }
}
