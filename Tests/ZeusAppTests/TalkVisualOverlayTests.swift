import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Own-process panels only: nothing is captured and the panel never takes input. The display is the main
/// screen when there is one, a synthetic frame otherwise, so the check also runs on a machine with no screen.
@MainActor
@Suite("Talk draw overlay", .serialized)
struct TalkVisualOverlayTests {
    private struct Fixture {
        let shot: ScreenShot
        let capture: ExplanationCaptureContext
        let objects: [ExplanationObject]
        let scene: ExplanationScene
    }

    private func fixture(_ marks: [TalkDraw.Mark]) throws -> Fixture {
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let shot = ScreenShot(jpegData: Data(), label: "screen 1", pixelWidth: 1280,
                              pixelHeight: Int((1280 * frame.height / frame.width).rounded()), displayFrame: frame)
        let captureID = UUID()
        let geometry = try TalkDrawScene.geometry(shot: shot, displayID: 7, backingScale: Double(NSScreen.main?.backingScaleFactor ?? 2),
                                                  captureID: captureID)
        let capture = ExplanationCaptureContext(geometry: geometry, currentDisplay: geometry.display)
        let objects = TalkDrawScene.objects(TalkDraw(screen: 1, marks: marks), shot: shot, captureID: captureID)
            .values.flatMap { $0 }
        let scene = ExplanationScene(sessionID: UUID(), sceneID: UUID(), canvasSize: geometry.imageSize, captureID: captureID,
                                     objects: Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) }))
        return Fixture(shot: shot, capture: capture, objects: objects, scene: scene)
    }

    private static let marks: [TalkDraw.Mark] = [
        .init(shape: .ring(center: .init(x: 412, y: 88), radius: 24), at: 0),
        .init(shape: .arrow(from: .init(x: 600, y: 300), to: .init(x: 430, y: 110)), at: 0),
        .init(shape: .card(origin: .init(x: 640, y: 320), text: "Export as PDF"), at: 0),
    ]

    @Test func aRingAnArrowAndALabelAreLaidOutInCaptureSpaceAndHideLeavesNoPanel() throws {
        let f = try fixture(Self.marks)
        let mapping = try #require(ExplanationOverlay.panelTransform(f.capture))
        let size = CGSize(width: f.capture.currentDisplay.frame.width, height: f.capture.currentDisplay.frame.height)
        let layout = ExplanationCanvasLayout(scene: f.scene, size: size, captureContext: f.capture, reduceMotion: true,
                                             captureTransform: mapping)
        #expect(layout.isValid)
        #expect(Set(layout.items.map(\.object.geometry.kind)) == [.ring, .arrow, .card])
        #expect(layout.items.first { $0.object.geometry.kind == .ring }?.object.style.stroke == .ink)
        #expect(layout.hiddenLabelIDs.isEmpty, "the diagram card draws its text inside the rect")

        let overlay = ExplanationOverlay()
        defer { overlay.hide() }
        #expect(overlay.present(scene: f.scene, capture: f.capture, reduceMotion: true))
        #expect(overlay.isVisible)
        #expect(overlay.displayIDs == [7])
        let window = try #require(overlay.ownedWindows.first)
        #expect(window.ignoresMouseEvents && !window.canBecomeKey && !window.canBecomeMain)
        #expect(window.styleMask.contains(.nonactivatingPanel) && window.sharingType == .none)
        #expect(abs(window.frame.origin.x - f.capture.currentDisplay.frame.x) < 0.5)
        #expect(abs(window.frame.width - f.capture.currentDisplay.frame.width) < 0.5)

        overlay.hide()
        #expect(overlay.ownedWindows.isEmpty && !overlay.isVisible && !window.isVisible && window.contentView == nil)
    }

    @Test func revealingMoreMarksReusesThePanelOfTheSameCapture() throws {
        let f = try fixture(Self.marks)
        var first = f.scene
        first.objects = first.objects.filter { $0.value.geometry.kind == .ring }
        let overlay = ExplanationOverlay()
        defer { overlay.hide() }
        #expect(overlay.present(scene: first, capture: f.capture, reduceMotion: false))
        let window = try #require(overlay.ownedWindows.first)
        #expect(overlay.present(scene: f.scene, capture: f.capture, reduceMotion: false))
        #expect(overlay.ownedWindows.first === window)
        #expect(overlay.ownedWindows.count == 1)
    }

    @Test func aSceneWithNoMarkOfThisCaptureShowsNothing() throws {
        let f = try fixture(Self.marks)
        var other = f.scene
        other.captureID = UUID()
        let overlay = ExplanationOverlay()
        #expect(!overlay.present(scene: other, capture: f.capture, reduceMotion: true))
        #expect(overlay.ownedWindows.isEmpty)
    }
}
