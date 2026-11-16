import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling geometry")
struct FlingGeometryTests {
    /// REG-677: a flick flies off along its own direction, never further than 240 points, and Reduce Motion only fades.
    @Test func aFlickFliesOffAlongItsDirectionAndReduceMotionOnlyFades() {
        let far = FlingGeometry.flyOff(translation: CGSize(width: 600, height: -80), reduceMotion: false)
        #expect(!far.fadeOnly)
        #expect(abs(hypot(far.offset.width, far.offset.height) - 240) < 0.001)
        #expect(far.offset.width > 0 && far.offset.height < 0)
        #expect(abs(far.offset.height / far.offset.width - (-80.0 / 600.0)) < 0.001)

        let near = FlingGeometry.flyOff(translation: CGSize(width: 30, height: 40), reduceMotion: false)
        #expect(near.offset == CGSize(width: 30, height: 40))

        let still = FlingGeometry.flyOff(translation: .zero, reduceMotion: false)
        #expect(still.offset == .zero)

        let reduced = FlingGeometry.flyOff(translation: CGSize(width: 600, height: -80), reduceMotion: true)
        #expect(reduced.fadeOnly && reduced.offset == .zero)
    }
}
