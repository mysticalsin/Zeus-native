import AppKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

@Suite struct EngineBrandLogoTests {
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
