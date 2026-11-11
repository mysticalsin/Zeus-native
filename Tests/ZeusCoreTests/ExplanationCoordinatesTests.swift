import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation coordinate identities and transforms")
struct ExplanationCoordinatesTests {
    private func display(_ scale: Double = 2, contextID: UUID = UUID()) throws -> ExplanationDisplayContext {
        try .init(contextID: contextID, displayID: 42, frame: .init(x: -1920, y: -200, width: 1920, height: 1080), backingScale: scale)
    }
    @Test func croppedResizedImageMapsThroughItsOriginalOriginAndRoundTrips() throws {
        let screen = try display()
        let capture = try ExplanationCaptureGeometry(display: screen, fullImageSize: .init(width: 1280, height: 720),
            crop: .init(x: 400, y: 120, width: 200, height: 160), imageSize: .init(width: 100, height: 80))
        let point = ExplanationVector3(x: 50, y: 40)
        let mapped = try #require(capture.globalPoint(fromImage: point, current: screen))
        #expect(mapped.x == -1170) // (400 + 100) * 1920/1280, NOT stretched across the full display.
        #expect(mapped.y == 580)
        #expect(capture.imagePoint(fromGlobal: mapped, current: screen) == point)
        #expect(capture.imagePoint(fromGlobal: .init(x: -1919, y: 879), current: screen) == nil)
    }
    @Test func backingScaleDoesNotReplaceDeliveredScreenshotPixelDimensions() throws {
        for scale in [1.0, 2.0] {
            let screen = try display(scale)
            let shot = try ExplanationCaptureGeometry(display: screen, fullImageSize: .init(width: 3840, height: 2160),
                crop: .init(x: 0, y: 0, width: 3840, height: 2160), imageSize: .init(width: 1280, height: 720))
            #expect(shot.globalPoint(fromImage: .init(x: 640, y: 360), current: screen) == .init(x: -960, y: 340))
        }
    }
    @Test func changedContentDisplayFrameScaleOrCaptureIdentityCannotAuthorizeOverlay() throws {
        let screen = try display(), id = UUID()
        let shot = try ExplanationCaptureGeometry(captureID: id, display: screen, fullImageSize: .init(width: 1280, height: 720),
            crop: .init(x: 0, y: 0, width: 1280, height: 720), imageSize: .init(width: 1280, height: 720))
        let others = [try display(), try display(1, contextID: screen.contextID),
            try ExplanationDisplayContext(contextID: screen.contextID, displayID: 43, frame: screen.frame, backingScale: 2),
            try ExplanationDisplayContext(contextID: screen.contextID, displayID: 42, frame: .init(x: 0, y: 0, width: 1920, height: 1080), backingScale: 2)]
        for other in others {
            #expect(shot.globalPoint(fromImage: .zero, current: other) == nil)
            #expect(!ExplanationCaptureContext(geometry: shot, currentDisplay: other).isCurrent(captureID: id))
        }
        #expect(!shot.isCurrent(captureID: UUID(), display: screen))
    }
    @Test func aspectFitLetterboxAndZoomPanHaveAnExactClippedInverse() throws {
        let id = UUID()
        let fit = try ExplanationViewportTransform(id: id, canvasSize: .init(width: 200, height: 100),
            viewport: .init(x: 10, y: 20, width: 400, height: 400))
        #expect(fit.viewPoint(fromCanvas: .zero) == .init(x: 10, y: 120))
        #expect(fit.canvasPoint(fromView: .init(x: 210, y: 220), viewportID: id) == .init(x: 100, y: 50))
        #expect(fit.canvasPoint(fromView: .init(x: 210, y: 30), viewportID: id) == nil)
        #expect(fit.canvasPoint(fromView: .init(x: 210, y: 220), viewportID: UUID()) == nil)
        let zoom = try ExplanationViewportTransform(id: id, canvasSize: .init(width: 200, height: 100),
            viewport: .init(x: 10, y: 20, width: 400, height: 400), zoom: 2, pan: .init(x: 5, y: -10))
        let middle = try #require(zoom.viewPoint(fromCanvas: .init(x: 100, y: 50)))
        #expect(zoom.canvasPoint(fromView: middle, viewportID: id) == .init(x: 100, y: 50))
        #expect(zoom.canvasPoint(fromView: .init(x: -100, y: 200), viewportID: id) == nil)
    }
    @Test func mixedCanvasCaptureProjectionUsesSameScaleForGeometryAndManualEdits() throws {
        let screen = try display(), id = UUID()
        let shot = try ExplanationCaptureGeometry(display: screen, fullImageSize: .init(width: 1280, height: 720),
            crop: .init(x: 400, y: 120, width: 200, height: 160), imageSize: .init(width: 100, height: 80))
        let context = ExplanationCaptureContext(geometry: shot, currentDisplay: screen)
        let projection = try #require(try context.projection(canvasSize: .init(width: 400, height: 400),
            viewport: .init(x: 0, y: 0, width: 800, height: 400), viewportID: id))
        #expect(projection.scale == 4)
        let point = ExplanationVector3(x: 20, y: 30)
        let view = try #require(projection.viewPoint(fromImage: point))
        #expect(projection.imagePoint(fromView: view, viewportID: id) == point)
        #expect(projection.imageDelta(fromView: .init(x: 20, y: -12)) == .init(x: 5, y: -3))
        #expect(projection.imagePoint(fromView: view, viewportID: UUID()) == nil)
    }
    @Test func malformedMetadataAndNonfiniteHitsAreRejected() throws {
        #expect(throws: ExplanationFailure.self) { try display(.nan) }
        #expect(throws: ExplanationFailure.self) {
            try ExplanationDisplayContext(displayID: 42, frame: .init(x: .infinity, y: 0, width: 10, height: 10), backingScale: 2)
        }
        // A valid rectangle must keep its far edge inside the inverse's point
        // domain, not merely validate its origin and positive dimensions.
        #expect(throws: ExplanationFailure.self) {
            try ExplanationDisplayContext(displayID: 42, frame: .init(x: 10_000_000, y: 0, width: 10, height: 10), backingScale: 2)
        }
        let screen = try display()
        #expect(throws: ExplanationFailure.self) {
            try ExplanationCaptureGeometry(display: screen, fullImageSize: .init(width: 100, height: 100),
                crop: .init(x: 90, y: 0, width: 20, height: 20), imageSize: .init(width: 20, height: 20))
        }
        let fit = try ExplanationViewportTransform(canvasSize: .init(width: 100, height: 100), viewport: .init(x: 0, y: 0, width: 100, height: 100))
        #expect(fit.viewPoint(fromCanvas: .init(x: .nan, y: 0)) == nil)
        #expect(fit.viewPoint(fromCanvas: .init(x: 1, y: 1, z: 2)) == nil)
        let invalid = #"{"contextID":"00000000-0000-0000-0000-000000000001","displayID":42,"frame":{"x":0,"y":0,"width":0,"height":10},"backingScale":2}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ExplanationDisplayContext.self, from: Data(invalid.utf8)) }
    }
}
