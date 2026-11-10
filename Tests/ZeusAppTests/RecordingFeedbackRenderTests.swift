import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ZeusCore
@testable import Zeus

/// Generated frames of the actual production view, not screenshots or donor-parity evidence.
/// No app/delegate/controller, capture device, permission API, event injection or network runs.
@MainActor
@Suite("Recording feedback temporal rendering", .serialized)
struct RecordingFeedbackRenderTests {
    private let producers: [RecordingFeedback.Producer] = [.recordly, .meetings]
    private let busyPhases: [RecordingFeedback.Phase] = [.starting, .finishing, .writing, .exporting]
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)
    private let framesPerSecond = 20
    private let scale: CGFloat = 2
    private let size = CGSize(width: 360, height: 48)

    @Test func normalFramesEvolveForBothProducers() throws {
        try withArtifacts { directory in
            let empty = try render(nil, elapsed: 0)
            for producer in producers {
                for phase in busyPhases {
                    let snapshot = snapshot(producer, phase: phase)
                    let frames = try sequence(snapshot, count: 33)
                    #expect(frames.allSatisfy { $0.pixelSHA256 != empty.pixelSHA256 }, "\(producer)/\(phase) drew an empty frame")
                    #expect(Set(frames.map(\.pixelSHA256)).count > 3, "\(producer)/\(phase) remained static")
                    try write(frames, snapshot: snapshot, reduceMotion: false, reduceTransparency: false, to: directory)
                }
            }
        }
    }

    @Test func reducedMotionFramesStayStableWithinPhase() throws {
        try withArtifacts { directory in
            let empty = try render(nil, elapsed: 0)
            for producer in producers {
                for phase in busyPhases + [.completed, .failed] {
                    let snapshot = snapshot(producer, phase: phase)
                    // Exercise both transparency settings with motion disabled, over a full busy cycle.
                    for reduceTransparency in [false, true] {
                        let frames = try sequence(snapshot, count: 33, reduceMotion: true, reduceTransparency: reduceTransparency)
                        #expect(frames.allSatisfy { $0.pixelSHA256 != empty.pixelSHA256 })
                        #expect(Set(frames.map(\.pixelSHA256)).count == 1,
                                "Reduced Motion changed pixels within \(producer)/\(phase)")
                        try write(frames, snapshot: snapshot, reduceMotion: true, reduceTransparency: reduceTransparency, to: directory)
                    }
                }
            }
        }
    }

    @Test func completionFramesExpireAtBoundedDeadline() throws {
        try withArtifacts { directory in
            let empty = try render(nil, elapsed: 0)
            let deadline = RecordingFeedback.completionDuration
            for producer in producers {
                let snapshot = snapshot(producer, phase: .completed)
                // Include two ticks beyond the real completion deadline in each animated fixture.
                for reduceMotion in [false, true] {
                    let count = Int(deadline * Double(framesPerSecond)) + 3
                    let frames = try sequence(snapshot, count: count, reduceMotion: reduceMotion)
                    let before = frames.filter { $0.elapsed < deadline }
                    let expired = frames.filter { $0.elapsed >= deadline }
                    #expect(!before.isEmpty && !expired.isEmpty)
                    #expect(before.allSatisfy { $0.pixelSHA256 != empty.pixelSHA256 })
                    #expect(expired.allSatisfy { $0.pixelSHA256 == empty.pixelSHA256 }, "Completed feedback outlived its deadline")
                    if reduceMotion {
                        #expect(Set(before.map(\.pixelSHA256)).count == 1)
                    } else {
                        #expect(Set(before.map(\.pixelSHA256)).count > 3, "Completion reveal remained static")
                    }
                    try write(frames, snapshot: snapshot, reduceMotion: reduceMotion, reduceTransparency: false,
                              suffix: "expiry", to: directory)
                }
            }
        }
    }

    @Test func failedFramesRemainVisibleAndStill() throws {
        let empty = try render(nil, elapsed: 0)
        for producer in producers {
            let snapshot = snapshot(producer, phase: .failed)
            let early = try render(snapshot, elapsed: 0)
            let later = try render(snapshot, elapsed: 60)
            #expect(early.pixelSHA256 != empty.pixelSHA256)
            #expect(early.pixelSHA256 == later.pixelSHA256)
        }
    }

    @Test func statusSwapFramesRetargetWithoutShowingDiscardedText() throws {
        try withArtifacts { directory in
            for producer in producers {
                func state(_ text: String) -> RecordingFeedback.Snapshot {
                    .init(producer: producer, phase: .failed, sessionKey: "status-fixture",
                          beganAt: epoch.timeIntervalSinceReferenceDate, label: text)
                }
                let first = state("Recording needs attention")
                let discarded = state("Export needs attention")
                let latest = state("Some exports failed")
                var transition = RecordingFeedback.StatusTransition(first)
                var frames: [RenderedFrame] = []
                for index in 0...13 {
                    let elapsed = Double(index) / Double(framesPerSecond)
                    let date = epoch.timeIntervalSinceReferenceDate + elapsed
                    if index == 2 { transition.update(discarded, at: date, reduceMotion: false) }
                    if index == 3 { transition.update(latest, at: date, reduceMotion: false) }
                    let status = transition.frame(at: date, reduceMotion: false)
                    #expect(status.text != discarded.label, "An interrupted pending status must never appear")
                    frames.append(try render(transition.target, elapsed: elapsed, status: status))
                }
                let settled = frames.filter { $0.elapsed >= 0.45 }
                #expect(Set(frames.map(\.pixelSHA256)).count > 3, "The supplied status transition was static")
                #expect(Set(settled.map(\.pixelSHA256)).count == 1, "A finished status transition kept moving")
                #expect(settled.allSatisfy { $0.displayedStatus == latest.label })
                try write(frames, snapshot: latest, reduceMotion: false, reduceTransparency: false,
                          suffix: "interrupted-status", to: directory)
            }
        }
    }

    @Test func reducedMotionStatusSwapShowsLatestTextImmediately() throws {
        for producer in producers {
            let first = snapshot(producer, phase: .failed)
            let next = RecordingFeedback.Snapshot(producer: producer, phase: .failed, sessionKey: first.sessionKey,
                                                 beganAt: first.beganAt, label: "Save needs attention")
            var transition = RecordingFeedback.StatusTransition(first)
            transition.update(next, at: epoch.timeIntervalSinceReferenceDate, reduceMotion: false)
            let pending = transition.frame(at: epoch.timeIntervalSinceReferenceDate + 0.05, reduceMotion: false)
            let reduced = try render(next, elapsed: 0.05, reduceMotion: true, status: pending)
            let settled = try render(next, elapsed: 0.05, reduceMotion: true, status: .settled(next.label))
            #expect(reduced.pixelSHA256 == settled.pixelSHA256, "Reduced Motion must remove the pending swap in the actual renderer")
        }
    }

    @Test func completionDriverStopsFrameRequestsBeforeTheNoticeExpires() async throws {
        let began = Date.timeIntervalSinceReferenceDate
        let completed = RecordingFeedback.Snapshot(producer: .recordly, phase: .completed,
                                                    sessionKey: "completion-clock-fixture", beganAt: began, label: "Recording saved")
        let driver = RecordingFeedbackStatusDriver(snapshot: completed)
        defer { driver.stop() }
        driver.update(completed, reduceMotion: false)
        #expect(driver.isAnimating, "The completion reveal must receive frames before settling")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while driver.isAnimating && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!driver.isAnimating, "Completed feedback must release its display-link request after the reveal")
        #expect(RecordingFeedback.frame(completed, at: began + 1, reduceMotion: false, reduceTransparency: false).visible,
                "Stopping decorative frames must not dismiss the still-valid completion notice")
    }

    private func snapshot(_ producer: RecordingFeedback.Producer, phase: RecordingFeedback.Phase) -> RecordingFeedback.Snapshot {
        .init(producer: producer, phase: phase, sessionKey: "synthetic-\(producer.rawValue)",
              beganAt: epoch.timeIntervalSinceReferenceDate,
              label: "\(producer == .meetings ? "Meeting notes" : "Recording") · \(phase.rawValue)")
    }

    private struct RenderedFrame {
        let elapsed: TimeInterval
        let image: CGImage
        let pixelSHA256: String
        let displayedStatus: String?
    }

    private func sequence(_ snapshot: RecordingFeedback.Snapshot, count: Int, reduceMotion: Bool = false,
                          reduceTransparency: Bool = false) throws -> [RenderedFrame] {
        try (0..<count).map { index in
            try render(snapshot, elapsed: Double(index) / Double(framesPerSecond),
                       reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        }
    }

    private func render(_ snapshot: RecordingFeedback.Snapshot?, elapsed: TimeInterval,
                        reduceMotion: Bool = false, reduceTransparency: Bool = false,
                        status: RecordingFeedback.StatusFrame? = nil) throws -> RenderedFrame {
        var openCalls = 0
        let content = ZStack {
            Color.black
            if let snapshot {
                RecordingFeedbackFrameView(snapshot: snapshot, date: epoch.addingTimeInterval(elapsed),
                                           reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                                           status: status, open: { openCalls += 1 })
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = true
        let image = try #require(renderer.cgImage, "The production frame could not render")
        #expect(image.width == Int(size.width * scale) && image.height == Int(size.height * scale))
        #expect(openCalls == 0, "Rendering must never invoke the production open action")
        return RenderedFrame(elapsed: elapsed, image: image, pixelSHA256: Self.digest(try pixels(image)),
                             displayedStatus: reduceMotion ? snapshot?.label : status?.text ?? snapshot?.label)
    }

    /// Canonical RGBA bytes avoid differences in the renderer's chosen provider/row padding.
    private func pixels(_ image: CGImage) throws -> Data {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data)
        return Data(bytes: bytes, count: image.width * image.height * 4)
    }

    private struct FrameMetadata: Encodable {
        let index: Int
        let elapsedSeconds: Double
        let referenceDateSeconds: Double
        let rgbaSHA256: String
        let decodedGIFRGBASHA256: String
        let displayedStatus: String?
    }

    private struct SequenceMetadata: Encodable {
        let schemaVersion = 1
        let evidenceKind = "synthetic-production-view-frames"
        let scope = "ImageRenderer of RecordingFeedbackFrameView; no screen/device capture or reference-motion parity claim"
        let samplingPurpose = "20 Hz GIF preview; not a measurement of display refresh rate or delivered frame pacing"
        let producer: String
        let phase: String
        let reduceMotion: Bool
        let reduceTransparency: Bool
        let framesPerSecond: Int
        let frameDelaySeconds: Double
        let widthPoints: Double
        let heightPoints: Double
        let widthPixels: Int
        let heightPixels: Int
        let scale: Double
        let gifFile: String
        let gifSHA256: String
        let sourceEnvironmentSHA: [String: String]
        let sourceFileSHA256: [String: String]
        let operatingSystem: String
        let frames: [FrameMetadata]
    }

    private func write(_ frames: [RenderedFrame], snapshot: RecordingFeedback.Snapshot, reduceMotion: Bool,
                       reduceTransparency: Bool, suffix: String = "phase", to directory: URL) throws {
        let first = try #require(frames.first)
        let name = "\(snapshot.producer.rawValue)-\(snapshot.phase.rawValue)-motion\(reduceMotion ? "reduced" : "normal")-transparency\(reduceTransparency ? "reduced" : "normal")-\(suffix)"
        let gif = directory.appendingPathComponent(name + ".gif")
        let delay = 1 / Double(framesPerSecond)
        let destination = try #require(CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, frames.count, nil))
        let fileProperties: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let properties: [String: Any] = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay,
                                                                               kCGImagePropertyGIFUnclampedDelayTime as String: delay]]
        for frame in frames { CGImageDestinationAddImage(destination, frame.image, properties as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination), "Animated fixture could not be finalized")
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == frames.count, "GIF lost temporal frames")
        var decodedHashes: [String] = []
        for index in frames.indices {
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            #expect(decoded.width == first.image.width && decoded.height == first.image.height)
            decodedHashes.append(Self.digest(try pixels(decoded)))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
            let gifProperties = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            let recordedDelay = try #require(gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
                                            ?? gifProperties[kCGImagePropertyGIFDelayTime as String] as? NSNumber)
            #expect(abs(recordedDelay.doubleValue - delay) < 0.001, "GIF playback rate drifted")
        }
        if Set(frames.map(\.pixelSHA256)).count > 1 {
            #expect(Set(decodedHashes).count > 1, "GIF encoding flattened an evolving sequence")
        } else {
            #expect(Set(decodedHashes).count == 1, "GIF encoding introduced motion into a stationary sequence")
        }
        let environment = ProcessInfo.processInfo.environment
        let metadata = SequenceMetadata(
            producer: snapshot.producer.rawValue, phase: snapshot.phase.rawValue,
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
            framesPerSecond: framesPerSecond, frameDelaySeconds: delay,
            widthPoints: Double(size.width), heightPoints: Double(size.height),
            widthPixels: first.image.width, heightPixels: first.image.height, scale: Double(scale),
            gifFile: gif.lastPathComponent, gifSHA256: Self.digest(try Data(contentsOf: gif)),
            sourceEnvironmentSHA: Dictionary(uniqueKeysWithValues: ["ZEUS_TESTED_SHA", "ZEUS_HEAD_SHA", "GITHUB_SHA"].map { ($0, environment[$0] ?? "unavailable") }),
            sourceFileSHA256: try sourceHashes(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            frames: frames.enumerated().map {
                .init(index: $0.offset, elapsedSeconds: $0.element.elapsed,
                      referenceDateSeconds: epoch.timeIntervalSinceReferenceDate + $0.element.elapsed,
                      rgbaSHA256: $0.element.pixelSHA256, decodedGIFRGBASHA256: decodedHashes[$0.offset],
                      displayedStatus: $0.element.displayedStatus)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
    }

    private func sourceHashes() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = ["Sources/Zeus/TopBar/RecordingFeedbackView.swift", "Sources/ZeusCore/TopBar/RecordingFeedback.swift",
                     "Sources/Zeus/Voice/AssistantBeamView.swift", "Sources/ZeusCore/Voice/AssistantBeam.swift",
                     "Tests/ZeusAppTests/RecordingFeedbackRenderTests.swift"]
        return try Dictionary(uniqueKeysWithValues: paths.map { ($0, Self.digest(try Data(contentsOf: root.appendingPathComponent($0)))) })
    }

    private func withArtifacts(_ operation: (URL) throws -> Void) throws {
        let supplied = ProcessInfo.processInfo.environment["ZEUS_QA_ARTIFACT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistent = supplied?.isEmpty == false
        let parent: URL
        if persistent, let supplied {
            try #require(supplied.hasPrefix("/"), "ZEUS_QA_ARTIFACT_DIR must be an explicit absolute directory")
            parent = URL(fileURLWithPath: supplied, isDirectory: true)
        } else { parent = FileManager.default.temporaryDirectory }
        let directory = parent.appendingPathComponent("RecordingFeedbackRenderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if !persistent { try? FileManager.default.removeItem(at: directory) } }
        try operation(directory)
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
