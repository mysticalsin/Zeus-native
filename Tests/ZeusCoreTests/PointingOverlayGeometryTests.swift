import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing overlay geometry: the ring lands on the candidate")
struct PointingOverlayGeometryTests {
    private static let main = DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private static let left = DisplayMap(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
    private static let above = DisplayMap(id: 3, frame: CGRect(x: 0, y: 900, width: 1440, height: 900), scale: 2)
    private let mapper = ScreenCoordinateMapper(displays: [main, left, above], mainDisplayID: 1)

    private func geometry(_ map: DisplayMap, full: ExplanationSize2, delivered: ExplanationSize2) throws
        -> (ExplanationCaptureGeometry, ExplanationDisplayContext) {
        let display = try ExplanationDisplayContext(displayID: UInt32(map.id),
            frame: .init(x: map.frame.minX, y: map.frame.minY, width: map.frame.width, height: map.frame.height),
            backingScale: map.scale)
        let value = try ExplanationCaptureGeometry(display: display, fullImageSize: full,
            crop: .init(x: 0, y: 0, width: full.width, height: full.height), imageSize: delivered)
        return (value, display)
    }

    /// AX frame to candidate rect, then the ring centre back to AppKit points. The ring centre must be
    /// the candidate centre, and the ring must reach the candidate's edges.
    private func check(_ map: DisplayMap, full: ExplanationSize2, delivered: ExplanationSize2, ax: CGRect,
                       expectedCenter: CGPoint, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (capture, display) = try geometry(map, full: full, delivered: delivered)
        let rect = try #require(PointingGeometry.imageRect(fromAX: ax, mapper: mapper, geometry: capture, display: display),
                                sourceLocation: sourceLocation)
        let ringCenter = ExplanationVector3(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
        let global = try #require(capture.globalPoint(fromImage: ringCenter, current: display), sourceLocation: sourceLocation)
        #expect(abs(global.x - expectedCenter.x) < 1e-3 && abs(global.y - expectedCenter.y) < 1e-3,
                "ring centre \(global) expected \(expectedCenter)", sourceLocation: sourceLocation)
        #expect(PointingSceneResolver.ringRadius(for: rect) >= max(rect.width, rect.height) / 2,
                sourceLocation: sourceLocation)
    }

    @Test func twoXDisplayDeliveredAtHalfTheBackingPixels() throws {
        try check(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900),
                  ax: CGRect(x: 100, y: 50, width: 200, height: 40), expectedCenter: CGPoint(x: 200, y: 830))
    }

    @Test func twoXDisplayDeliveredAtFullBackingPixels() throws {
        try check(Self.main, full: .init(width: 2880, height: 1800), delivered: .init(width: 2880, height: 1800),
                  ax: CGRect(x: 100, y: 50, width: 200, height: 40), expectedCenter: CGPoint(x: 200, y: 830))
    }

    @Test func oneXDisplayWithANegativeOrigin() throws {
        try check(Self.left, full: .init(width: 1920, height: 1080), delivered: .init(width: 1920, height: 1080),
                  ax: CGRect(x: -1900, y: -140, width: 200, height: 40), expectedCenter: CGPoint(x: -1800, y: 1020))
    }

    @Test func displayAboveTheMainOne() throws {
        try check(Self.above, full: .init(width: 2880, height: 1800), delivered: .init(width: 1440, height: 900),
                  ax: CGRect(x: 10, y: -860, width: 100, height: 60), expectedCenter: CGPoint(x: 60, y: 1730))
    }
}
