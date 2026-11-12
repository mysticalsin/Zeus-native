import CoreGraphics
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// Synthetic controller events and generated text frames only. No app delegate, device, permission,
/// provider credential, private store, screen capture or user-input event is involved.
@MainActor @Suite("Scribe incoming word integration")
struct ScribeIncomingWordTests {
    private final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
    }

    private final class Capture: ScribeCaptureProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var callback: (@Sendable (ScribeCaptureEvent) -> Void)?
        func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
                   events: @escaping @Sendable (ScribeCaptureEvent) -> Void) {
            lock.withLock { callback = events }
        }
        func stop(session: ScribeSessionID) {}
        func acknowledge(_ id: ScribeSessionID) { lock.withLock { callback }?(.captureAcknowledged(id)) }
    }

    private enum Failure: Error { case acknowledgementTimedOut }

    private func start(_ controller: ScribeController, _ capture: Capture) async throws -> ScribeSessionID {
        controller.start()
        let id = try #require(controller.phase.sessionID)
        capture.acknowledge(id)
        for _ in 0..<200 {
            if controller.isRecording { return id }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Failure.acknowledgementTimedOut
    }

    @Test func realBatchRevisionsUseInjectedTimeWithoutRestartingEligibleWords() async throws {
        let suite = "scribe-words-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(), capture = Capture()
        let controller = ScribeController(provider: capture, clock: { clock.now }, monotonicClock: { 100 },
            cancellationDefaults: defaults, transcriptionEngine: { .apple }, motionReduced: { false })
        defer { controller.cancel() }
        let id = try await start(controller, capture)
        let first = ScribeTranscriptSegment(id: "batch", session: id, speaker: .participant("Fixture"),
            start: 0, end: 1, text: "One  two\nthree", isFinal: false)
        controller.receive(first)
        let initial = try #require(controller.incomingWordLayout(for: first))
        #expect(initial.runs.map(\.text).joined() == first.text)
        #expect(controller.visibleWordCount(for: first, at: clock.now.addingTimeInterval(0.12), reduceMotion: false) == 1)
        #expect(try #require(controller.incomingWordsRevealUntil) < clock.now.addingTimeInterval(1))
        clock.now.addTimeInterval(0.12)
        let revised = ScribeTranscriptSegment(id: "batch", session: id, speaker: first.speaker,
            start: 0, end: 1.1, text: "One  two\nthree four", isFinal: false)
        controller.receive(revised)
        let layout = try #require(controller.incomingWordLayout(for: revised))
        let now = clock.now.timeIntervalSinceReferenceDate + 0.02
        #expect(layout.frame(forWord: 0, shownWords: 1, at: now) == initial.frame(forWord: 0, shownWords: 1, at: now))
        #expect(layout.revision > initial.revision)
        #expect(controller.incomingWordLayout(for: first) == nil)
        #expect(controller.transcript?.segments.first?.text == revised.text)
    }

    @Test func cancellationClearsRevealStateAndRejectsLateTranscriptBatches() async throws {
        let suite = "scribe-words-cancel-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(), capture = Capture()
        let controller = ScribeController(provider: capture, clock: { clock.now }, monotonicClock: { 100 },
            cancellationDefaults: defaults, transcriptionEngine: { .apple }, motionReduced: { false })
        defer { controller.cancel() }
        let id = try await start(controller, capture)
        let first = ScribeTranscriptSegment(id: "cancelled", session: id, speaker: .participant("Fixture"),
            start: 0, end: 1, text: "Synthetic text", isFinal: false)
        controller.receive(first)
        #expect(controller.incomingWordLayout(for: first) != nil)
        controller.cancel()
        controller.receive(first)
        #expect(controller.incomingWordLayout(for: first) == nil)
        #expect(controller.incomingWordsRevealUntil == nil)
        #expect(controller.transcript == nil)
    }

    @Test func productionTextRendererChangesOnlyIncomingFramesAndReducedMotionIsSettled() throws {
        guard #available(macOS 15.0, *) else {
            Issue.record("The production TextRenderer path requires macOS 15; macOS 14.2 uses the existing prefix fallback.")
            return
        }
        let layout = ScribeIncomingWordLayout(text: "Hello, 你好 👩🏽‍💻\nمرحبا", alreadyShown: 0, since: 10)
        let hidden = try render(layout, shown: 0, time: 10)
        let entering = try render(layout, shown: 1, time: 10.13)
        let settled = try render(layout, shown: layout.words.count, time: 11)
        let still = try render(layout, shown: 0, time: 10, reduceMotion: true)
        #expect(hidden != entering)
        #expect(entering != settled)
        #expect(hidden != settled)
        #expect(still == settled)
        #expect(try render(layout, shown: layout.words.count, time: 12) == settled)
    }

    @available(macOS 15.0, *)
    @Test func longBatchLaysOutOnlyTheActualEligiblePrefix() throws {
        let text = "First visible " + Array(repeating: "future", count: 200).joined(separator: " ")
        let layout = ScribeIncomingWordLayout(text: text, alreadyShown: 0, since: 10)
        func height(shown: Int, time: TimeInterval) throws -> Int {
            let content = ScribeIncomingWords(layout: layout, shownWords: shown,
                date: Date(timeIntervalSinceReferenceDate: time), reduceMotion: false)
                .font(.system(size: 14)).frame(width: 120, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            return try #require(renderer.cgImage).height
        }
        let admitted = try height(shown: 2, time: 10.2)
        let complete = try height(shown: layout.words.count, time: 100)
        #expect(admitted > 0 && admitted < 60)
        #expect(complete > admitted * 3)
    }

    @available(macOS 15.0, *)
    private func render(_ layout: ScribeIncomingWordLayout, shown: Int, time: TimeInterval,
                        reduceMotion: Bool = false) throws -> Data {
        let content = ScribeIncomingWords(layout: layout, shownWords: shown,
            date: Date(timeIntervalSinceReferenceDate: time), reduceMotion: reduceMotion)
            .font(.system(size: 14)).foregroundStyle(.white)
            .frame(width: 320, height: 80, alignment: .topLeading)
            .background(Color.black)
            .transaction { $0.animation = nil }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = true
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height == 80)
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }
}
