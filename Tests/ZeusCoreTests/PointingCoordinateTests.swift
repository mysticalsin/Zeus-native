import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing coordinates: AX Quartz to AppKit to delivered-image pixels")
struct PointingCoordinateTests {
    // Main display is 1440x900 points at 2x. A 1920x1080 1x display sits to its left (negative
    // origin, taller than main), and a 1440x900 display sits above it.
    private static let main = DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private static let left = DisplayMap(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
    private static let above = DisplayMap(id: 3, frame: CGRect(x: 0, y: 900, width: 1440, height: 900), scale: 2)
    private let mapper = ScreenCoordinateMapper(displays: [main, left, above], mainDisplayID: 1)

    private func capture(_ map: DisplayMap, full: ExplanationSize2, delivered: ExplanationSize2) throws
        -> (ExplanationCaptureGeometry, ExplanationDisplayContext) {
        let display = try ExplanationDisplayContext(displayID: UInt32(map.id),
            frame: .init(x: map.frame.minX, y: map.frame.minY, width: map.frame.width, height: map.frame.height),
            backingScale: map.scale)
        let geometry = try ExplanationCaptureGeometry(display: display, fullImageSize: full,
            crop: .init(x: 0, y: 0, width: full.width, height: full.height), imageSize: delivered)
        return (geometry, display)
    }

    private func expect(_ rect: ExplanationRect?, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        let r = try #require(rect, sourceLocation: sourceLocation)
        #expect(abs(r.x - x) < 1e-3 && abs(r.y - y) < 1e-3 && abs(r.width - w) < 1e-3 && abs(r.height - h) < 1e-3,
                "got \(r)", sourceLocation: sourceLocation)
    }

    @Test func retinaDisplayDownscaledToTheDeliveredImage() throws {
        let (geometry, display) = try capture(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900))
        // AX frame: 100 right of the left edge, 50 below the top.
        let rect = PointingGeometry.imageRect(fromAX: CGRect(x: 100, y: 50, width: 200, height: 40),
                                              mapper: mapper, geometry: geometry, display: display)
        try expect(rect, 100, 50, 200, 40)
    }

    @Test func eachAxisKeepsItsOwnDeliveredRatio() throws {
        let (geometry, display) = try capture(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 1280, height: 720))
        let rect = PointingGeometry.imageRect(fromAX: CGRect(x: 90, y: 50, width: 180, height: 40),
                                              mapper: mapper, geometry: geometry, display: display)
        try expect(rect, 90 * 1280 / 1440, 50 * 0.8, 180 * 1280 / 1440, 40 * 0.8)
    }

    @Test func displayLeftOfMainWithNegativeOriginAndOneXScale() throws {
        let (geometry, display) = try capture(Self.left, full: .init(width: 1920, height: 1080), delivered: .init(width: 1920, height: 1080))
        // AppKit rect x -1900..-1700, y 1000..1040 (top 1040): 40 px below the display's top.
        // Quartz y = main height (900) - 1040 = -140.
        let rect = PointingGeometry.imageRect(fromAX: CGRect(x: -1900, y: -140, width: 200, height: 40),
                                              mapper: mapper, geometry: geometry, display: display)
        try expect(rect, 20, 40, 200, 40)
    }

    @Test func displayAboveMain() throws {
        let (geometry, display) = try capture(Self.above, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900))
        // AppKit y 1700..1760 is 40 points below that display's top (1800). Quartz y = 900 - 1760.
        let rect = PointingGeometry.imageRect(fromAX: CGRect(x: 10, y: -860, width: 100, height: 60),
                                              mapper: mapper, geometry: geometry, display: display)
        try expect(rect, 10, 40, 100, 60)
    }

    @Test func aFrameOnAnotherDisplayIsNotClampedOntoThisOne() throws {
        let (geometry, display) = try capture(Self.left, full: .init(width: 1920, height: 1080), delivered: .init(width: 1920, height: 1080))
        #expect(PointingGeometry.imageRect(fromAX: CGRect(x: 100, y: 50, width: 200, height: 40),
                                           mapper: mapper, geometry: geometry, display: display) == nil)
    }

    @Test func aFramePartlyPastTheEdgeIsCutAtTheImageEdge() throws {
        let (geometry, display) = try capture(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900))
        let rect = PointingGeometry.imageRect(fromAX: CGRect(x: 1400, y: 100, width: 100, height: 50),
                                              mapper: mapper, geometry: geometry, display: display)
        try expect(rect, 1400, 100, 40, 50)
    }

    @Test func degenerateAndNonFiniteFramesAreRejected() throws {
        let (geometry, display) = try capture(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900))
        for frame in [CGRect(x: 10, y: 10, width: 0, height: 20), CGRect(x: .nan, y: 0, width: 5, height: 5)] {
            #expect(PointingGeometry.imageRect(fromAX: frame, mapper: mapper, geometry: geometry, display: display) == nil)
        }
    }

    @Test func imageToGlobalToImageRoundTripsOnEveryDisplayMix() throws {
        for (map, full) in [(Self.main, ExplanationSize2(width: 2880, height: 1800)),
                            (Self.left, ExplanationSize2(width: 1920, height: 1080)),
                            (Self.above, ExplanationSize2(width: 2880, height: 1800))] {
            let (geometry, display) = try capture(map, full: full, delivered: .init(width: 1280, height: 720))
            for point in [ExplanationVector3(x: 0, y: 0), .init(x: 640, y: 360), .init(x: 1279, y: 719), .init(x: 17.5, y: 701.25)] {
                let global = try #require(geometry.globalPoint(fromImage: point, current: display))
                let back = try #require(geometry.imagePoint(fromGlobal: global, current: display))
                #expect(abs(back.x - point.x) < 1e-6 && abs(back.y - point.y) < 1e-6)
            }
        }
    }

    @Test func contextDropsPointsOutsideTheImageInsteadOfClamping() throws {
        let (geometry, display) = try capture(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900))
        var trace = PointingTrace()
        trace.add(.init(time: 0, x: 100, y: 800, displayID: 1))     // inside
        trace.add(.init(time: 1, x: 5000, y: 800, displayID: 1))    // another display's area
        let context = PointingContext.make(trace: trace, candidates: [], geometry: geometry, display: display,
                                           frontmostBundleID: "com.example.app")
        #expect(context.pointerImagePath == [.init(x: 100, y: 100)])
        #expect(context.captureID == geometry.captureID)
        #expect(context.imageSize == .init(width: 1440, height: 900))
    }

    @Test func withoutCaptureTheContextHasNoImageGeometry() {
        let context = PointingContext.make(trace: PointingTrace(), candidates: [.init(id: "t0", role: "AXButton")],
                                           geometry: nil, display: nil, frontmostBundleID: nil)
        #expect(context.captureID == nil && context.imageSize == nil && context.candidates.count == 1)
    }

    @Test func secureFieldsNeverCarryALabel() {
        let candidate = PointingTargetCandidate(id: "t1", role: "AXTextField", subrole: "AXSecureTextField",
                                                label: "hunter2", isSecure: true)
        #expect(candidate.label == nil)
    }

    @Test func candidateLabelsAreTruncatedToOneHundredTwentyEightBytes() {
        let candidate = PointingTargetCandidate(id: "t2", role: "AXButton", label: String(repeating: "é", count: 200))
        #expect((candidate.label?.utf8.count ?? 0) <= 128)
    }
}
