import AVFoundation
import Foundation
import Testing
@testable import ZeusCore

@Suite struct SoundCatalogTests {
    /// Sources/Zeus/Sounds next to this repo's Tests folder.
    static let folder: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Zeus/Sounds")

    @Test func everyCataloguedSoundIsBundledAtItsTargetDuration() throws {
        for spec in SoundCatalog.everySpec {
            let url = Self.folder.appendingPathComponent("\(spec.file).\(SoundCatalog.fileExtension)")
            #expect(FileManager.default.fileExists(atPath: url.path), "missing \(spec.file)")
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            #expect(abs(seconds - spec.seconds) <= 0.05, "\(spec.file) is \(seconds) s, wanted \(spec.seconds) s")
        }
    }

    @Test func theSetMatchesTheReferenceEventDurations() {
        func seconds(_ slot: SoundSlot, _ style: String) -> Double? { SoundCatalog.spec(slot, style: style)?.seconds }
        #expect(seconds(.runStart, "Classic") == 1.96)
        #expect(seconds(.runStart, "Mystery Game") == 0.96)
        #expect(seconds(.request, "Classic") == 1.96)
        #expect(seconds(.request, "Short Warning") == 2.96)
        #expect(seconds(.answer, "Futuristic 1") == 0.96)
        #expect(seconds(.done, "Success") == 2.96)
        #expect(seconds(.dictationBegin, "") == 0.50)
        #expect(seconds(.dictationEnd, "") == 0.46)
        #expect(seconds(.runningLoop, "") == 4.0)
        #expect(SoundCatalog.spec(.failure, style: nil) != nil)
    }

    @Test func styleNamesMapToDistinctFiles() {
        for slot in SoundSlot.allCases {
            let files = SoundCatalog.styles(for: slot).map(\.file)
            #expect(!files.isEmpty, "\(slot) has no sound")
            #expect(Set(files).count == files.count)
        }
        let all = SoundCatalog.everySpec.map(\.file)
        #expect(Set(all).count == all.count)
        #expect(SoundCatalog.styles(for: .request).count == 6)
    }

    @Test func unknownStylesFallBackAndOffIsSilent() {
        #expect(SoundCatalog.spec(.runStart, style: "Glass")?.style == "Classic")
        #expect(SoundCatalog.spec(.done, style: nil)?.style == "Success")
        #expect(SoundCatalog.spec(.runStart, style: "Off") == nil)
    }

    @Test func theBundledSetStaysSmallAndCleanly16BitDerived() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.fileSizeKey])
        let total = try urls.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(total < 3_000_000)
        #expect(urls.count == SoundCatalog.everySpec.count)
        // No clicks: decode each and look at the first and last samples and the biggest jump.
        for spec in SoundCatalog.everySpec where spec.file != "running_loop" {
            let file = try AVAudioFile(forReading: Self.folder.appendingPathComponent("\(spec.file).m4a"))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            let peak = samples.map(abs).max() ?? 0
            #expect(peak > 0.1 && peak < 0.95, "\(spec.file) peak \(peak)")
            #expect(abs(samples.first ?? 1) < 0.02 && abs(samples.last ?? 1) < 0.02, "\(spec.file) starts or ends abruptly")
            var step: Float = 0
            for i in 1..<samples.count { step = max(step, abs(samples[i] - samples[i - 1])) }
            #expect(step < 0.3, "\(spec.file) has a click (\(step))")
        }
    }
}
