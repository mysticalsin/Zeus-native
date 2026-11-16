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

/// REG-698: floating papers cascade down and left from the top right corner, wrap before they leave the screen,
    /// and always stay inside the area.
    @Test func papersCascadeFromTheCornerAndStayOnScreen() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let paper = CGSize(width: 180, height: 120)
        let first = FlingGeometry.paperOrigin(index: 0, paper: paper, in: area)
        let second = FlingGeometry.paperOrigin(index: 1, paper: paper, in: area)
        #expect(first.x + paper.width <= area.maxX && first.y + paper.height <= area.maxY)
        #expect(second.x < first.x && second.y < first.y, "each paper steps down and to the left (y grows upward)")
        for index in 0..<200 {
            let origin = FlingGeometry.paperOrigin(index: index, paper: paper, in: area)
            #expect(area.contains(CGRect(origin: origin, size: paper)), "paper \(index) at \(origin)")
        }
        // A paper bigger than the area is pinned to its corner instead of leaving it.
        let huge = FlingGeometry.paperOrigin(index: 3, paper: CGSize(width: 2000, height: 2000), in: area)
        #expect(huge == CGPoint(x: area.minX, y: area.minY))
    }

    /// REG-698: pinching papers together fans them into one stack, at most five offsets, and one paper is not a stack.
    @Test func aPinchFansPapersIntoOneStack() {
        #expect(FlingGeometry.stackFan(count: 0).isEmpty && FlingGeometry.stackFan(count: 1).isEmpty)
        let three = FlingGeometry.stackFan(count: 3)
        #expect(three.count == 3 && three[0] == .zero && three[1].x > three[0].x)
        #expect(FlingGeometry.stackFan(count: 40).count == 5)
    }
}
