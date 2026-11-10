import AppKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// Real hosted production controls, inert capture/transcription, synthetic persistence only.
/// Uses the fixture's own accessibility objects; no AXUIElement, input injection or screen capture.
@MainActor @Suite("Scribe native component journey", .serialized)
struct ScribeComponentJourneyTests {
    private final class Clock { var time: TimeInterval = 100 }

    private final class Capture: ScribeCaptureProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var sink: (@Sendable (ScribeCaptureEvent) -> Void)?
        private var id: ScribeSessionID?
        private var starts = 0
        private var stops = 0
        var startCount: Int { lock.withLock { starts } }
        var stopCount: Int { lock.withLock { stops } }

        func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
                   events: @escaping @Sendable (ScribeCaptureEvent) -> Void) {
            lock.withLock { starts += 1; id = session; sink = events }
            events(.captureAcknowledged(session))
        }

        func stop(session: ScribeSessionID) {
            let callback = lock.withLock { () -> (@Sendable (ScribeCaptureEvent) -> Void)? in
                guard id == session else { return nil }
                stops += 1
                return sink
            }
            callback?(.captureEnded(session))
        }
    }

    private struct Transcriber: ScribeTranscriber {
        let callbacks: ScribeTranscriberCallbacks
        func ingest(_ frame: ScribeAudioFrame) { }
        func finish(session: ScribeSessionID) {
            callbacks.onSegment(.init(id: "synthetic-journey", session: session, speaker: .participant("Fixture"),
                start: 0, end: 1, text: "We decided to test the native meeting controls.", isFinal: true))
            callbacks.onFinished(session)
        }
    }

    private final class Writes {
        var rejectFinal = true
        var attemptedFinal = 0
        var savedFinal = 0
        func write(_ record: ScribeMeetingRecord, to store: ScribeMeetingStore) throws {
            if record.generatedAt != nil {
                attemptedFinal += 1
                if rejectFinal { throw ScenarioFailure.injectedFinalWrite }
            }
            try store.save(record)
            if record.generatedAt != nil { savedFinal += 1 }
        }
    }

    private enum ScenarioFailure: Error, CustomStringConvertible {
        case injectedFinalWrite
        case missingControl(String, [String])
        case ambiguousControl(String)
        case unavailableControl(String)
        case rejectedPress(String)
        case traversalLimit
        case transitionTimeout(String)
        var description: String {
            switch self {
            case .injectedFinalWrite: return "Synthetic final-write failure"
            case .missingControl(let id, let tree): return "Missing fixture control \(id). Own tree: \(tree.joined(separator: "; "))"
            case .ambiguousControl(let id): return "Multiple fixture controls have \(id)"
            case .unavailableControl(let id): return "Fixture control is hidden, disabled, or not a button: \(id)"
            case .rejectedPress(let id): return "Fixture control rejected accessibilityPerformPress: \(id)"
            case .traversalLimit: return "Fixture accessibility tree exceeded its bound"
            case .transitionTimeout(let expected): return "Fixture did not reach \(expected)"
            }
        }
    }

    private let allowedControls: Set<String> = [
        "scribe.start", "scribe.stop", "scribe.notes.close",
        "scribe.endWindow.keep", "scribe.endWindow.endNow", "scribe.endWindow.retrySave", "scribe.endWindow.hide"
    ]

    private func preferences() throws -> (String, UserDefaults) {
        let suite = "scribe-component-\(UUID().uuidString)"
        return (suite, try #require(UserDefaults(suiteName: suite)))
    }

    private func waitFor(_ name: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ScenarioFailure.transitionTimeout(name)
    }

    /// Resolve a fresh tree for every action. There is no application-wide tree or controller fallback.
    private func controls(in window: NSWindow) throws -> [any NSAccessibilityProtocol] {
        guard let root = window.contentView else { return [] }
        root.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        var pending: [(Any, Int)] = [(root, 0)]
        var seen = Set<ObjectIdentifier>()
        var result: [any NSAccessibilityProtocol] = []
        while let (value, depth) = pending.popLast() {
            guard depth <= 32, seen.count < 1_024 else { throw ScenarioFailure.traversalLimit }
            let object = value as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            guard let element = object as? any NSAccessibilityProtocol else { continue }
            result.append(element)
            let children = element.accessibilityChildren() ?? []
            pending.append(contentsOf: children.map { ($0, depth + 1) })
            // Native hosting wrappers can have ignored physical children around their AX children.
            if children.isEmpty, let view = object as? NSView {
                pending.append(contentsOf: view.subviews.map { ($0, depth + 1) })
            }
        }
        return result
    }

    private func press(_ id: String, in window: NSWindow, trace: inout [String]) async throws {
        guard allowedControls.contains(id), window.isVisible else { throw ScenarioFailure.unavailableControl(id) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        var diagnostic: [String] = []
        while ContinuousClock.now < deadline {
            let tree = try controls(in: window)
            diagnostic = tree.prefix(80).map {
                "\($0.accessibilityRole()?.rawValue ?? "?"):\($0.accessibilityIdentifier() ?? "-"):\($0.accessibilityLabel() ?? "-")"
            }
            let matches = tree.filter { $0.accessibilityIdentifier() == id }
            if matches.count > 1 { throw ScenarioFailure.ambiguousControl(id) }
            if let button = matches.first {
                let frame = button.accessibilityFrame()
                let finite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
                guard button.accessibilityRole() == .button, button.isAccessibilityEnabled(),
                      finite, !frame.isEmpty, frame.intersects(window.frame) else {
                    throw ScenarioFailure.unavailableControl(id)
                }
                if let view = button as? NSView, view.isHiddenOrHasHiddenAncestor {
                    throw ScenarioFailure.unavailableControl(id)
                }
                guard button.accessibilityPerformPress() else { throw ScenarioFailure.rejectedPress(id) }
                trace.append("pressed \(id)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ScenarioFailure.missingControl(id, diagnostic)
    }

    @Test func realButtonsDriveStartKeepStopFailedSaveRetryAndClose() async throws {
        _ = NSApplication.shared // Own test-process application; ZeusMain/AppDelegate are never launched.
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-component-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScribeMeetingStore(directory: root)
        let clock = Clock(), capture = Capture(), writes = Writes()
        let endWindow = ScribeEndWindow()
        let controller = ScribeController(provider: capture, monotonicClock: { clock.time }, store: store,
            transcriberFactory: { _, callbacks in Transcriber(callbacks: callbacks) }, showsEndWindow: true,
            writeMeeting: { try writes.write($0, to: store) }, cancellationDefaults: defaults,
            endWindow: endWindow, transcriptionEngine: { .apple })
        let topBar = TopBarModel(defaults: defaults)
        let host = NSHostingView(rootView: ScribePage(topBar: topBar, scribe: controller)
            .environment(\.cardFinishOverride, .liquidGlass)
            .frame(width: 870, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 870, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Synthetic Scribe component fixture"
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer {
            // Teardown is not an asserted user action. Release the actual hosted controller/window cycle.
            controller.cancel()
            endWindow.close()
            window.contentView = nil
            window.close()
        }
        window.orderFront(nil)
        var trace: [String] = []

        try await press("scribe.start", in: window, trace: &trace)
        try await waitFor("recording") { controller.isRecording }
        let id = try #require(controller.phase.sessionID)
        #expect(capture.startCount == 1)
        #expect(capture.stopCount == 0)

        try await press("scribe.stop", in: window, trace: &trace)
        try await waitFor("visible end window") { endWindow.panel?.isVisible == true && controller.endingRemaining == 9 }
        let endPanel = try #require(endWindow.panel)
        try await press("scribe.endWindow.keep", in: endPanel, trace: &trace)
        try await waitFor("recording after Keep") { controller.phase == .recording(id, since: clock.time) }
        #expect(!endPanel.isVisible)
        #expect(capture.stopCount == 0)

        try await press("scribe.stop", in: window, trace: &trace)
        try await waitFor("second end window") { endPanel.isVisible && controller.endingRemaining == 9 }
        try await press("scribe.endWindow.endNow", in: endPanel, trace: &trace)
        try await waitFor("recoverable final-save failure") { controller.completionSaveIssue != nil }
        #expect(controller.phase == .processing(id))
        #expect(capture.stopCount == 1)
        #expect(writes.attemptedFinal == 1)
        #expect(writes.savedFinal == 0)
        #expect(controller.completedNoticeID == nil)
        #expect(controller.topBarFeedback()?.phase == .failed)

        writes.rejectFinal = false // Change the injected storage dependency, not the UI/controller state.
        try await press("scribe.endWindow.retrySave", in: endPanel, trace: &trace)
        try await waitFor("durably saved completion") { controller.phase == .complete(id) }
        #expect(writes.savedFinal == 1)
        #expect(controller.completedNoticeID == id)
        #expect(controller.topBarFeedback()?.phase == .completed)
        #expect(store.loadAll().records.first(where: { $0.id == id.rawValue })?.generatedAt != nil)

        try await press("scribe.endWindow.hide", in: endPanel, trace: &trace)
        #expect(!endPanel.isVisible)
        #expect(controller.phase == .complete(id))
        // Respect either OS accessibility preference; do not press the notes controls while their
        // real production reveal still gives them zero opacity.
        try await waitFor("visible completed notes") {
            controller.revealElapsed(at: Date()) >= max(ScribeGlow.revealDuration(reduceMotion: false),
                                                       ScribeGlow.revealDuration(reduceMotion: true))
        }
        try await press("scribe.notes.close", in: window, trace: &trace)
        try await waitFor("idle after Done") { controller.phase == .idle }
        #expect(controller.completedNoticeID == nil)
        #expect(controller.recaps.contains(where: { $0.id == id }))
        #expect(capture.stopCount == 1)
        #expect(trace == ["pressed scribe.start", "pressed scribe.stop", "pressed scribe.endWindow.keep",
                          "pressed scribe.stop", "pressed scribe.endWindow.endNow", "pressed scribe.endWindow.retrySave",
                          "pressed scribe.endWindow.hide", "pressed scribe.notes.close"])
        print("Synthetic Scribe component interaction completed: " + trace.joined(separator: " → "))
    }

    @Test func modelPreferencesReadAndWriteOnlyTheInjectedSuite() throws {
        let (suite, defaults) = try preferences()
        let (otherSuite, other) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite); other.removePersistentDomain(forName: otherSuite) }
        defaults.set("Synthetic initial note", forKey: "topBar.note")
        defaults.set("Synthetic initial script", forKey: "prompter.script")
        other.set("Independent fixture", forKey: "topBar.note")
        let model = TopBarModel(defaults: defaults)
        #expect(model.note == "Synthetic initial note")
        #expect(model.script == "Synthetic initial script")
        model.note = "Synthetic edited note"
        model.script = "Synthetic edited script"
        model.cuesEnabled = false
        model.liveMusicWings = false
        model.weatherCity = "Fixture city"
        model.useCelsius = false
        model.selectedModeKey = "fixture-mode"
        model.prompterTextSize = 21
        model.roll.speed = 17
        model.roll.voiceFollow = false
        #expect(defaults.string(forKey: "topBar.note") == "Synthetic edited note")
        #expect(defaults.string(forKey: "prompter.script") == "Synthetic edited script")
        #expect(defaults.bool(forKey: "topBar.cues") == false)
        #expect(defaults.bool(forKey: "topBar.musicWings") == false)
        #expect(defaults.string(forKey: "topBar.weatherCity") == "Fixture city")
        #expect(defaults.string(forKey: "dictation.mode") == "fixture-mode")
        #expect(defaults.double(forKey: "prompter.size") == 21)
        #expect(defaults.double(forKey: "prompter.speed") == 17)
        #expect(defaults.bool(forKey: "prompter.voice") == false)
        #expect(other.string(forKey: "topBar.note") == "Independent fixture")
    }

    @Test func temporaryMeetingStoreCannotClearAnotherCancellationJournal() throws {
        let (suite, defaults) = try preferences()
        let (otherSuite, other) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite); other.removePersistentDomain(forName: otherSuite) }
        let localID = UUID(), otherID = UUID()
        ScribeCancelTombstones.add(localID, in: defaults)
        ScribeCancelTombstones.add(otherID, in: other)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ScribeController(store: ScribeMeetingStore(directory: root), cancellationDefaults: defaults,
                                          transcriptionEngine: { .apple })
        #expect(controller.recaps.isEmpty)
        #expect(ScribeCancelTombstones.ids(in: defaults).isEmpty)
        #expect(ScribeCancelTombstones.ids(in: other) == [otherID])
    }
}
