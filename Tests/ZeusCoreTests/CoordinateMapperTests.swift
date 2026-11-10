import CoreGraphics
import Testing
@testable import ZeusCore

/// L0: one mapper from screen, display, window, AX, and pixels into overlay points.
@Suite struct CoordinateMapperTests {
    /// 1080p, scale 1, the main display.
    let hd = ScreenCoordinateMapper(displays: [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
    ])

    /// Same logical 1080p panel at Retina 2x: 3840 x 2160 backing pixels.
    let retina = ScreenCoordinateMapper(displays: [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 2),
    ])

    /// Main 1080p, a display to the left (negative x), a display below (negative y), and a 4K panel at scale 1.
    let desk = ScreenCoordinateMapper(displays: [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
        DisplayMap(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 2),
        DisplayMap(id: 3, frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080), scale: 1),
        DisplayMap(id: 4, frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160), scale: 1),
    ])

    @Test func overlayMatchesTheCanvasFlipOnTheMainDisplay() {
        // Screen top-left of the main display is overlay (0, 0) and AX (0, 0).
        let topLeft = CGPoint(x: 0, y: 1080)
        expectPoint(hd.convert(topLeft, from: .screen, to: .overlay, context: MapContext(displayID: 1)), CGPoint(x: 0, y: 0))
        expectPoint(hd.convert(topLeft, from: .screen, to: .ax, context: MapContext()), CGPoint(x: 0, y: 0))

        let bottomLeft = CGPoint(x: 0, y: 0)
        expectPoint(hd.convert(bottomLeft, from: .screen, to: .overlay, context: MapContext(displayID: 1)), CGPoint(x: 0, y: 1080))
        expectPoint(hd.convert(bottomLeft, from: .screen, to: .ax, context: MapContext()), CGPoint(x: 0, y: 1080))
    }

    @Test func axRectMatchesTheExistingQuartzFlip() {
        let appKit = CGRect(x: 40, y: 80, width: 100, height: 50)
        let quartz = CursorAnchor.flipToQuartz(appKit, mainScreenHeight: 1080)
        let mapped = hd.convert(appKit, from: .screen, to: .ax, context: MapContext())
        #expect(mapped == quartz)

        let onTheLeft = CGRect(x: -100, y: 10, width: 20, height: 30)
        let leftQuartz = CursorAnchor.flipToQuartz(onTheLeft, mainScreenHeight: 1080)
        #expect(desk.convert(onTheLeft, from: .screen, to: .ax, context: MapContext()) == leftQuartz)
    }

    @Test func axElementOnTheMainDisplayLandsOnTheSameOverlayRect() {
        let element = CGRect(x: 100, y: 40, width: 80, height: 30)
        let overlay = hd.overlayRect(element, from: .ax, displayID: 1)
        #expect(overlay == element)
        expectPoint(center(overlay), CGPoint(x: 140, y: 55))
    }

    @Test func negativeOriginDisplayRoundTrips() {
        // Top-left of the left display.
        let screen = CGPoint(x: -1920, y: 1080)
        let ctx = MapContext(displayID: 2)
        expectPoint(desk.convert(screen, from: .screen, to: .overlay, context: ctx), CGPoint(x: 0, y: 0))
        expectPoint(desk.convert(screen, from: .screen, to: .display, context: ctx), CGPoint(x: 0, y: 1080))
        expectPoint(desk.convert(screen, from: .screen, to: .ax, context: MapContext()), CGPoint(x: -1920, y: 0))
        expectPoint(desk.convert(CGPoint(x: 0, y: 0), from: .overlay, to: .screen, context: ctx), screen)

        // Bottom-right of the display below the main one.
        let below = CGPoint(x: 1920, y: -1080)
        let belowCtx = MapContext(displayID: 3)
        expectPoint(desk.convert(below, from: .screen, to: .overlay, context: belowCtx), CGPoint(x: 1920, y: 1080))
        expectPoint(desk.convert(CGPoint(x: 1920, y: 1080), from: .overlay, to: .screen, context: belowCtx), below)
    }

    @Test func windowLocalBecomesOverlayOnItsDisplay() {
        let window = WindowMap(frame: CGRect(x: 100, y: -1000, width: 400, height: 300), displayID: 3)
        let ctx = MapContext(displayID: 3, window: window)
        // (10, 20) is 10 pt right and 20 pt up from the window's bottom-left.
        expectPoint(desk.convert(CGPoint(x: 10, y: 20), from: .window, to: .screen, context: ctx), CGPoint(x: 110, y: -980))
        expectPoint(desk.convert(CGPoint(x: 10, y: 20), from: .window, to: .overlay, context: ctx), CGPoint(x: 110, y: 980))
        expectPoint(desk.convert(CGPoint(x: 110, y: 980), from: .overlay, to: .window, context: ctx), CGPoint(x: 10, y: 20))
    }

    @Test func retinaBackingPixelsAreTwiceThePoints() {
        let ctx = MapContext(displayID: 1)
        expectPoint(retina.convert(CGPoint(x: 21, y: 40), from: .pixel, to: .overlay, context: ctx), CGPoint(x: 10.5, y: 20))
        expectPoint(retina.convert(CGPoint(x: 10.5, y: 20), from: .overlay, to: .pixel, context: ctx), CGPoint(x: 21, y: 40))
        // The same overlay point is one pixel at 1x.
        expectPoint(hd.convert(CGPoint(x: 10.5, y: 20), from: .overlay, to: .pixel, context: ctx), CGPoint(x: 10.5, y: 20))
    }

    @Test func capturePixelsUseTheShotGridNotTheBackingStore() {
        // Longest side 1280 of a 1920 x 1080 display, the size ScreenCapture asks for.
        let shot = CaptureMap(displayID: 2, pixelWidth: 1280, pixelHeight: 720)
        let ctx = MapContext(displayID: 2, capture: shot)
        // 192 pt across and 108 pt down the left display.
        expectPoint(desk.convert(CGPoint(x: 128, y: 72), from: .pixel, to: .overlay, context: ctx), CGPoint(x: 192, y: 108))
        expectPoint(desk.convert(CGPoint(x: 192, y: 108), from: .overlay, to: .pixel, context: ctx), CGPoint(x: 128, y: 72))
    }

    @Test func fourKPanelAndRetinaShareThePixelBudgetRule() {
        #expect(hd.ringPixelTolerance(displayID: 1) == 24)
        #expect(hd.ringPointTolerance(displayID: 1) == 24)
        #expect(retina.ringPixelTolerance(displayID: 1) == 48)
        #expect(retina.ringPointTolerance(displayID: 1) == 24)
        // 3840 x 2160 at scale 1 is 4K in real pixels, so the budget is 48 pt as well as 48 px.
        #expect(desk.ringPixelTolerance(displayID: 4) == 48)
        #expect(desk.ringPointTolerance(displayID: 4) == 48)
        // The left display is 2x, so 48 px is still 24 pt.
        #expect(desk.ringPixelTolerance(displayID: 2) == 48)
        #expect(desk.ringPointTolerance(displayID: 2) == 24)

        let target = CGPoint(x: 100, y: 100)
        #expect(hd.withinRing(CGPoint(x: 124, y: 100), of: target, displayID: 1) == true)
        #expect(hd.withinRing(CGPoint(x: 125, y: 100), of: target, displayID: 1) == false)
        #expect(desk.withinRing(CGPoint(x: 148, y: 100), of: target, displayID: 4) == true)
        #expect(desk.withinRing(CGPoint(x: 149, y: 100), of: target, displayID: 4) == false)
    }

    @Test func roundTripKeepsAPointOnEverySpace() {
        let window = WindowMap(frame: CGRect(x: 400, y: 200, width: 640, height: 480), displayID: 1)
        let ctx = MapContext(displayID: 1, window: window)
        let start = CGPoint(x: 30, y: 44)
        for space in [CoordinateSpace.screen, .ax, .display, .window, .pixel, .overlay] {
            let sample = space == .screen ? CGPoint(x: 500, y: 400) : start
            let overlay = hd.convert(sample, from: space, to: .overlay, context: ctx)
            let back = overlay.flatMap { hd.convert($0, from: .overlay, to: space, context: ctx) }
            expectPoint(back, sample)
        }
    }

    @Test func seamBetweenDisplaysBelongsToTheDisplayOnTheRight() {
        // CGRect.contains is max-exclusive, so x = 1920 is the 4K panel, not the main display.
        let hit = desk.display(containing: CGPoint(x: 1920, y: 100))
        #expect(hit?.id == 4)
        let left = desk.display(containing: CGPoint(x: -1, y: 10))
        #expect(left?.id == 2)
        #expect(desk.display(containing: CGPoint(x: 10_000, y: 10)) == nil)
    }

    @Test func missingInputsReturnNil() {
        let empty = ScreenCoordinateMapper(displays: [])
        #expect(empty.convert(CGPoint(x: 1, y: 1), from: .screen, to: .ax, context: MapContext()) == nil)
        #expect(hd.convert(CGPoint(x: 1, y: 1), from: .overlay, to: .screen, context: MapContext()) == nil)
        #expect(hd.convert(CGPoint(x: 1, y: 1), from: .window, to: .screen, context: MapContext(displayID: 1)) == nil)
        #expect(hd.convert(CGPoint(x: 1, y: 1), from: .pixel, to: .overlay, context: MapContext(displayID: 99)) == nil)
        let otherShot = CaptureMap(displayID: 9, pixelWidth: 100, pixelHeight: 100)
        #expect(hd.convert(CGPoint(x: 1, y: 1), from: .pixel, to: .screen, context: MapContext(displayID: 1, capture: otherShot)) == nil)
        #expect(hd.convert(CGPoint(x: CGFloat.nan, y: 1), from: .screen, to: .overlay, context: MapContext(displayID: 1)) == nil)
        #expect(hd.withinRing(.zero, of: .zero, displayID: 99) == nil)
    }

    @Test func protocolSeesTheConcreteMapper() {
        let mapper: any CoordinateMapping = hd
        let point = mapper.overlayPoint(CGPoint(x: 10, y: 20), from: .display, displayID: 1)
        // Display-local (10, 20) is 20 pt up from the bottom, so 1060 pt down the overlay.
        expectPoint(point, CGPoint(x: 10, y: 1060))
    }

    private func center(_ rect: CGRect?) -> CGPoint? {
        guard let rect else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func expectPoint(_ got: CGPoint?, _ want: CGPoint) {
        #expect(got != nil)
        guard let got else { return }
        #expect(abs(got.x - want.x) < 0.001)
        #expect(abs(got.y - want.y) < 0.001)
    }
}
