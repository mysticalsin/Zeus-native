import Foundation
import Testing
@testable import ZeusCore

@Suite("Desktop card anchors: app-issued protected regions in global points")
struct PointingCardAnchorsTests {
    /// A 1920 x 1080 point display at a negative x origin, captured at 2x and delivered at 1920 x 1080.
    private func captureContext() throws -> ExplanationCaptureContext {
        let display = try ExplanationDisplayContext(displayID: 7, frame: .init(x: -1920, y: 0, width: 1920, height: 1080), backingScale: 2)
        let geometry = try ExplanationCaptureGeometry(display: display, fullImageSize: .init(width: 3840, height: 2160),
                                                      crop: .init(x: 0, y: 0, width: 3840, height: 2160),
                                                      imageSize: .init(width: 1920, height: 1080))
        return ExplanationCaptureContext(geometry: geometry, currentDisplay: display)
    }

    private func near(_ a: ExplanationRect?, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Bool {
        guard let a else { return false }
        return abs(a.x - x) < 0.001 && abs(a.y - y) < 0.001 && abs(a.width - width) < 0.001 && abs(a.height - height) < 0.001
    }

    private func ring(_ capture: ExplanationCaptureContext, x: Double, y: Double, radius: Double = 20) -> ExplanationObject {
        ExplanationObject(id: "ring", space: .capture, captureID: capture.geometry.captureID,
                          geometry: .init(kind: .ring, radius: radius),
                          transform: .init(position: .init(x: x, y: y)), accessibleDescription: "d")
    }

    @Test func cardAnchorUsesTheCandidateRectangleConvertedToGlobalPointsOnANegativeDisplay() throws {
        let capture = try captureContext()
        let context = PointingContext(captureID: capture.geometry.captureID, imageSize: capture.geometry.imageSize,
                                      candidates: [.init(id: "t0", role: "AXButton", imageRect: .init(x: 100, y: 200, width: 300, height: 50))])
        let anchors = PointingCardAnchorBuilder.make(context: context, marks: [], capture: capture, inputArea: nil)
        #expect(near(anchors.anchor, -1820, 830, 300, 50))
        #expect(anchors.protected.count == 1)
    }

    @Test func cardAnchorPrefersAdmittedMarksAndProtectsBothMarksAndCandidates() throws {
        let capture = try captureContext()
        let context = PointingContext(captureID: capture.geometry.captureID, imageSize: capture.geometry.imageSize,
                                      candidates: [.init(id: "t0", role: "AXButton", imageRect: .init(x: 100, y: 200, width: 300, height: 50))])
        let anchors = PointingCardAnchorBuilder.make(context: context, marks: [ring(capture, x: 150, y: 225)],
                                                     capture: capture, inputArea: nil)
        #expect(near(anchors.anchor, -1790, 835, 40, 40))
        #expect(anchors.protected.count == 2)
    }

    @Test func cardAnchorProtectsThePointerTrailBoundingBoxAndTheInputArea() throws {
        let capture = try captureContext()
        let path: [ExplanationVector3] = [.init(x: 10, y: 10), .init(x: 110, y: 60)]
        let context = PointingContext(captureID: capture.geometry.captureID, imageSize: capture.geometry.imageSize,
                                      pointerImagePath: path)
        let input = ExplanationRect(x: -1500, y: 100, width: 400, height: 60)
        let anchors = PointingCardAnchorBuilder.make(context: context, marks: [], capture: capture, inputArea: input)
        #expect(anchors.anchor == nil)
        #expect(anchors.protected.count == 2)
        #expect(near(anchors.protected.first, -1918, 1012, 116, 66))
        #expect(anchors.protected.last == input)
    }

    @Test func cardAnchorClampsARectangleThatSpillsOffTheCapturedImageNeverStretchingIt() throws {
        let capture = try captureContext()
        let context = PointingContext(captureID: capture.geometry.captureID, imageSize: capture.geometry.imageSize,
                                      candidates: [.init(id: "t0", role: "AXButton", imageRect: .init(x: 1900, y: 1070, width: 100, height: 100))])
        let anchors = PointingCardAnchorBuilder.make(context: context, marks: [], capture: capture, inputArea: nil)
        #expect(near(anchors.anchor, -20, 0, 20, 10))
    }

    @Test func cardAnchorIsEmptyWhenNothingWasPointedAt() throws {
        let capture = try captureContext()
        let context = PointingContext(captureID: capture.geometry.captureID, imageSize: capture.geometry.imageSize)
        let anchors = PointingCardAnchorBuilder.make(context: context, marks: [], capture: capture, inputArea: nil)
        #expect(anchors.anchor == nil && anchors.protected.isEmpty)
    }

    @Test func cardAnchorIgnoresMarksThatAreNotOnTheCapture() throws {
        let capture = try captureContext()
        let canvasObject = ExplanationObject(id: "box", space: .canvas, geometry: .init(kind: .roundedRectangle, size: .init(x: 50, y: 50)),
                                             accessibleDescription: "d")
        let context = PointingContext(captureID: capture.geometry.captureID, imageSize: capture.geometry.imageSize)
        let anchors = PointingCardAnchorBuilder.make(context: context, marks: [canvasObject], capture: capture, inputArea: nil)
        #expect(anchors.anchor == nil && anchors.protected.isEmpty)
    }

    @Test func cardAnchorFallsBackToAPointerSquareWhenThereIsNoCapture() {
        let input = ExplanationRect(x: 10, y: 10, width: 100, height: 20)
        let anchors = PointingCardAnchorBuilder.make(pointer: .init(x: 500, y: 300), inputArea: input)
        #expect(near(anchors.anchor, 476, 276, 48, 48))
        #expect(anchors.protected.count == 2 && anchors.protected.last == input)
        let empty = PointingCardAnchorBuilder.make(pointer: nil, inputArea: nil)
        #expect(empty.anchor == nil && empty.protected.isEmpty)
    }
}
