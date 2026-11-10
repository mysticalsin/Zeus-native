import CoreGraphics
import Testing
@testable import ZeusCore

@Suite struct SpatialTrailTests {
    @Test func aStillHoldDrawsNothing() {
        var trail = SpatialTrail()
        for step in 0..<10 {
            trail.add(point: CGPoint(x: 3, y: Double(step) * 0.2), at: Double(step) * 0.05)
        }
        #expect(trail.kept.isEmpty)
        #expect(trail.raw.count == 10)
        #expect(trail.dwell == nil)
    }

    @Test func motionPastTheThresholdKeepsSpacedPointsAndADwell() {
        var trail = SpatialTrail()
        trail.add(point: .zero, at: 0)
        trail.add(point: CGPoint(x: 10, y: 0), at: 0.05)
        trail.add(point: CGPoint(x: 11, y: 0), at: 0.08)
        trail.add(point: CGPoint(x: 20, y: 0), at: 0.12)
        trail.add(point: CGPoint(x: 20.4, y: 0), at: 0.5)
        #expect(trail.kept.count == 2)
        #expect(trail.dwell != nil)
        let fresh = trail.alpha(of: trail.kept[1], at: 0.12)
        #expect(abs(fresh - SpatialTrail.parentOpacity) < 0.001)
        let gone = trail.alpha(of: trail.kept[0], at: 1.05)
        #expect(gone == 0)
        trail.hideInk()
        #expect(trail.alpha(of: trail.kept[1], at: 0.5) == 0)
        #expect(trail.raw.count == 5)
        #expect(trail.smooth().count <= SpatialTrail.maxSubdivisions)
        #expect(trail.smooth().count >= 2)
    }
}
