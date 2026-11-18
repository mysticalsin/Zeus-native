import AppKit
import SwiftUI
import Testing
@testable import Zeus

/// macOS only. Linux cannot host SwiftUI, so the development gate never runs this
/// file. It flips `MotionCenter` through `testingSetReduced` (no `defaults` and no
/// `com.apple.universalaccess` write) and requires a view, a view modifier, a
/// button style, and a toggle style to publish the new value.
///
/// A style's `makeBody` is not a tracked body. On 5f97d942 the button and toggle
/// styles copy `Motion.reduced` there, so they keep the old value and this test fails.
@MainActor
@Suite("Motion style live update", .serialized)
struct MotionStyleLiveUpdateTests {
    @Test func aReduceMotionFlipRerendersEachKind() async throws {
        defer { MotionCenter.shared.refresh() }
        let starting = false
        let flipped = true
        try await OwnedWindowJourneyLease.perform {
            expectLive("view", LiveMotionView(), starting: starting, flipped: flipped)
            expectLive("modifier", Color.clear.modifier(LiveMotionModifier()), starting: starting, flipped: flipped)
            expectLive("GlassButtonStyle", Button("Go") {}.buttonStyle(GlassButtonStyle()), starting: starting, flipped: flipped)
            expectLive("PressableStyle", Button("Go") {}.buttonStyle(PressableStyle()), starting: starting, flipped: flipped)
            expectLive("GlassHoverRowStyle", Button("Row") {}.buttonStyle(GlassHoverRowStyle()), starting: starting, flipped: flipped)
            expectLive("OBToggleStyle", Toggle(isOn: .constant(false)) { Text("Switch") }.toggleStyle(OBToggleStyle()),
                       starting: starting, flipped: flipped)
            expectLive("GlassToggleStyle", Toggle(isOn: .constant(false)) { Text("Switch") }.toggleStyle(GlassToggleStyle()),
                       starting: starting, flipped: flipped)
        }
    }

    private func expectLive<V: View>(_ kind: String, _ view: V, starting: Bool, flipped: Bool) {
        let sample = publishedSample(of: view, starting: starting, flipped: flipped)
        #expect(sample == flipped, "\(kind) stayed at \(String(describing: sample)) after Reduce Motion became \(flipped)")
    }

    private func publishedSample<V: View>(of view: V, starting: Bool, flipped: Bool) -> Bool? {
        MotionCenter.shared.testingSetReduced(starting)
        let box = SampleBox()
        let root = view
            .frame(width: 120, height: 36)
            .onPreferenceChange(MotionLiveSampleKey.self) { box.value = $0 }
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 36)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        pump { box.value == starting }
        MotionCenter.shared.testingSetReduced(flipped)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        pump { box.value == flipped }
        return box.value
    }

    private func pump(until ready: () -> Bool) {
        let deadline = Date().addingTimeInterval(0.4)
        while !ready(), Date() < deadline {
            RunLoop.main.run(mode: .common, before: Date().addingTimeInterval(0.02))
        }
    }
}

@MainActor
private final class SampleBox {
    var value: Bool?
}

private struct LiveMotionView: View {
    var body: some View {
        Color.clear.preference(key: MotionLiveSampleKey.self, value: Motion.reduced)
    }
}

private struct LiveMotionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.preference(key: MotionLiveSampleKey.self, value: Motion.reduced)
    }
}
