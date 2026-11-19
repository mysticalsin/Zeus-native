import AppKit
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// The real closed-bar wings in an owned window at the owner's notch (220 x 38). Each wing and its content is read
/// back as laid out and must stay clear of the centred notch rectangle. Synthetic cues and a synthetic Scribe
/// controller only: no device, permission, capture or user input is involved. Hosted: see qa/closed-loop/native_app_host.py.
@MainActor @Suite("Closed wings clear the notch", .inNativeHost)
struct ClosedWingsNotchTests {
    private static let notch = CGSize(width: 220, height: 38)
    private static let shoulder: CGFloat = 8
    private static let sentence = String(repeating: "Please allow this to carry on. ", count: 4).prefix(120).description

    private final class Capture: ScribeCaptureProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var callback: (@Sendable (ScribeCaptureEvent) -> Void)?
        func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
                   events: @escaping @Sendable (ScribeCaptureEvent) -> Void) { lock.withLock { callback = events } }
        func stop(session: ScribeSessionID) {}
        func acknowledge(_ id: ScribeSessionID) { lock.withLock { callback }?(.captureAcknowledged(id)) }
    }

    private func window(width: CGFloat, content: some View, registry: OwnedWindowControlRegistry) -> NSWindow {
        let root = content
            .padding(.horizontal, Self.shoulder + NotchClosedBodyLayout.contentInset)
            .frame(width: width, height: Self.notch.height)
            .environment(\.ownedWindowControlRegistry, registry)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: width, height: Self.notch.height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func frame(_ id: String, _ registry: OwnedWindowControlRegistry, _ window: NSWindow) async -> CGRect? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let probes = registry.probes(for: id, in: window)
            if probes.count == 1, let probe = probes.first {
                window.contentView?.layoutSubtreeIfNeeded()
                return probe.convert(probe.bounds, to: nil)
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    /// Hosts `content` at the body width for `extra` and checks every wing frame against the notch rectangle.
    private func check(_ name: String, extra: CGFloat, emptyContent: Set<String> = [], @ViewBuilder content: (CGFloat) -> some View) async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let body = NotchClosedBodyLayout.bodyWidth(
                notchWidth: Self.notch.width, shoulder: Self.shoulder, showWings: true, extraWidth: extra,
                hasNotch: true, slimPill: false)
            let registry = OwnedWindowControlRegistry()
            let window = window(width: body, content: content(Self.notch.width), registry: registry)
            defer { OwnedWindowFixtureApplication.close(window) }
            let gap = CGRect(x: body / 2 - Self.notch.width / 2, y: -1000, width: Self.notch.width, height: 2000)
            var found: [String: CGRect] = [:]
            for id in ["left", "right"] {
                if let rect = await frame("closed-wings.\(id)", registry, window) { found[id] = rect }
                else if !emptyContent.contains(id) {
                    Issue.record("\(name): no \(id) wing frame was laid out")
                    return
                }
            }
            // The idle mascot's right side holds nothing, so it has no content view to measure.
            for id in ["left.content", "right.content"] {
                if let rect = await frame("closed-wings.\(id)", registry, window) { found[id] = rect }
                else { #expect(emptyContent.contains(id), "\(name): no \(id) frame was laid out") }
            }
            let left = try #require(found["left"])
            #expect(left.maxX <= gap.minX + 0.5, "\(name): left wing runs into the notch")
            if let right = found["right"] {
                #expect(right.minX >= gap.maxX - 0.5, "\(name): right wing starts under the notch")
                #expect(abs((left.minX) - (body - right.maxX)) < 0.5, "\(name): wings are not mirrored")
                #expect(abs(left.width - right.width) < 0.5, "\(name): wings differ in width")
            }
            for id in ["left", "right"] where found[id] != nil {
                guard let content = found["\(id).content"] else { continue }
                let wing = try #require(found[id])
                #expect(!content.intersects(gap) || content.isEmpty, "\(name): \(id) content reaches the notch")
                #expect(content.minX >= wing.minX - 0.5 && content.maxX <= wing.maxX + 0.5, "\(name): \(id) content leaves its wing")
            }
        }
    }

    private func topBar(_ configure: (TopBarModel) -> Void = { _ in }) -> TopBarModel {
        let model = TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "closed-wings-\(UUID().uuidString)")!)
        configure(model)
        return model
    }

    private func cue(_ cue: NotchCue, _ name: String) async throws {
        let model = topBar { $0.setCueForSnapshot(cue) }
        try await check(name, extra: ClosedWings.extraWidth(for: model)) { gap in
            ClosedWings(topBar: model, notchGap: gap).frame(height: Self.notch.height)
        }
    }

    @Test func aLongHintSentenceStaysClearOfTheNotch() async throws {
        try await cue(.hint(Self.sentence), "hint")
    }

    @Test func aLongCopiedTextStaysClearOfTheNotch() async throws {
        try await cue(.copied(Self.sentence), "copied")
    }

    @Test func aLongTrackChangeStaysClearOfTheNotch() async throws {
        try await cue(.trackChanged(title: "An Extremely Long Song Title That Keeps Going",
                                    artist: "An Artist With A Rather Long Name Too", source: .player(.music), sourceChanged: true),
                      "track changed")
    }

    @Test func thePermissionCueStaysClearOfTheNotch() async throws {
        try await cue(.permission(Self.sentence, pane: "Privacy_Camera"), "permission")
    }

    @Test func theVolumeCueStaysClearOfTheNotch() async throws {
        try await cue(.volume(0.6, muted: false), "volume")
    }

    @Test func theMascotAndItsStateWordStayClearOfTheNotch() async throws {
        let avatar = AvatarStatus.shared
        let before = avatar.pinned
        defer { avatar.pinned = before }
        for state in [AvatarState.thinking, .idle] {
            avatar.pinned = state
            let model = topBar()
            try await check("mascot \(state)", extra: ClosedWings.extraWidth(for: model),
                            emptyContent: state == .idle ? ["right.content"] : []) { gap in
                ClosedWings(topBar: model, notchGap: gap).frame(height: Self.notch.height)
            }
        }
    }

    @Test func theMusicWingsStayClearOfTheNotch() async throws {
        let model = topBar {
            $0.liveMusicWings = true
            $0.nowPlaying = NowPlaying(player: .music, title: "Title", artist: "Artist", album: "Album",
                                       isPlaying: true, duration: 200, position: 10)
        }
        try await check("music", extra: ClosedWings.extraWidth(for: model)) { gap in
            ClosedWings(topBar: model, notchGap: gap).frame(height: Self.notch.height)
        }
    }

    @Test func theScribeTickerStaysClearOfTheNotch() async throws {
        let suite = NSTemporaryDirectory() + "closed-wings-scribe-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let capture = Capture()
        let scribe = ScribeController(provider: capture, clock: { Date(timeIntervalSinceReferenceDate: 1_000) },
            monotonicClock: { 100 }, cancellationDefaults: defaults, transcriptionEngine: { .apple }, motionReduced: { false })
        defer { scribe.cancel() }
        scribe.start()
        let id = try #require(scribe.phase.sessionID)
        capture.acknowledge(id)
        for _ in 0..<200 where !scribe.isRecording { try await Task.sleep(for: .milliseconds(5)) }
        #expect(scribe.isRecording)
        scribe.receive(ScribeTranscriptSegment(id: "long", session: id, speaker: .participant("Fixture"), start: 0, end: 9,
            text: Self.sentence, isFinal: true))
        let model = topBar()
        for extra: CGFloat in [230, 300] {
            try await check("scribe ticker \(extra)", extra: extra) { gap in
                ClosedWingsRow(notchGap: gap, extra: extra,
                               left: ScribeWings.Leading(elapsed: 12),
                               right: ScribeWings.Trailing(scribe: scribe, topBar: model))
                    .frame(height: Self.notch.height)
            }
        }
    }

    // MARK: The whole closed island at the owner's notch

    /// The real `NotchView` in a 700 x 120 window at the 220 x 38 notch, read back: the body must hang from the top
    /// of the screen and end `belowNotch` under the hardware notch, so the bottom outline is not covered by it.
    private func bodyFrame(presentation: NotchModel.Presentation, background: NotchBackground, cue: NotchCue?) async throws -> (CGRect, CGFloat) {
        var result: (CGRect, CGFloat)?
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let model = NotchModel()
            model.presentation = presentation
            let bar = topBar { if let cue { $0.setCueForSnapshot(cue) } }
            let registry = OwnedWindowControlRegistry()
            let root = NotchView(model: model, topBar: bar, footprintOverride: .hardware(Self.notch),
                                 topOffsetOverride: 0, backgroundOverride: background)
                .environment(\.ownedWindowControlRegistry, registry)
                .frame(width: 960, height: 400)
            let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 960, height: 400),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.makeKeyAndOrderFront(nil)
            defer { OwnedWindowFixtureApplication.close(window) }
            if let rect = await frame("notch.body", registry, window) {
                let height = window.contentView?.bounds.height ?? 0
                result = (rect, height)
            }
        }
        return try #require(result, "no notch body frame was laid out")
    }

    @Test(arguments: [NotchBackground.black, .transparent])
    func theClosedBodyHangsFromTheTopAndEndsBelowTheHardwareNotch(background: NotchBackground) async throws {
        let cue = NotchCue.hint("Allow")
        for (name, shown) in [("idle", nil), ("wings", cue)] as [(String, NotchCue?)] {
            let (rect, height) = try await bodyFrame(presentation: .closed, background: background, cue: shown)
            #expect(abs(height - rect.maxY) < 0.5, "\(name) \(background): the body leaves a gap at the top of the screen")
            let bottom = height - rect.minY
            #expect(bottom >= Self.notch.height + NotchClosedBodyLayout.belowNotch - 0.5,
                    "\(name) \(background): the body ends at \(bottom), not below the notch")
            #expect(abs(rect.height - (Self.notch.height + NotchClosedBodyLayout.belowNotch)) < 0.5)
        }
    }

    @Test func theOpenPanelStaysFlushWithTheTopAndItsTabRowIsBelowTheBar() async throws {
        let (rect, height) = try await bodyFrame(presentation: .panel, background: .transparent, cue: nil)
        #expect(abs(height - rect.maxY) < 0.5)
        let expected = NotchView.topBarPanelSize(barHeight: Self.notch.height, hasApproval: false, home: true,
                                                 homeStrip: TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "closed-wings-\(UUID().uuidString)")!).homeExtraHeight)
        #expect(abs(rect.height - expected.height) < 0.5, "the open panel kept its own height")
        #expect(GlanceTopBar.tabRowTop >= Self.notch.height, "the tab row starts below the 38 pt bar")
    }
}
