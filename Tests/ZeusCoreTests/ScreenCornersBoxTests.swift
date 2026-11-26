import Foundation
import Testing
@testable import ZeusCore

@Suite("Screen corners box")
struct ScreenCornersBoxTests {
    private func frames(
        x: Double, y: Double, width: Double, height: Double, radius: Double
    ) -> ScreenCornersBox.Frames {
        ScreenCornersBox.cornerFrames(x: x, y: y, width: width, height: height, radius: radius)
    }

    private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ScreenCornersBox.Rect {
        ScreenCornersBox.Rect(x: x, y: y, width: width, height: height)
    }

    private func probe(_ side: ScreenCornersBox.Side, radius r: Double, distance: Double) -> ScreenCornersBox.Point {
        let s = 1 / 2.0.squareRoot()
        switch side {
        case .bottomLeft:
            return ScreenCornersBox.Point(x: r - distance * s, y: distance * s)
        case .bottomRight:
            return ScreenCornersBox.Point(x: distance * s, y: distance * s)
        }
    }

    private func outerCorner(_ side: ScreenCornersBox.Side, radius r: Double) -> ScreenCornersBox.Point {
        side == .bottomLeft
            ? ScreenCornersBox.Point(x: 0, y: r)
            : ScreenCornersBox.Point(x: r, y: r)
    }

    @Test func ordinaryScreenPlacesBothSquares() {
        #expect(frames(x: 0, y: 0, width: 1512, height: 982, radius: 12) == ScreenCornersBox.Frames(
            radius: 12,
            bottomLeft: rect(0, 0, 12, 12),
            bottomRight: rect(1500, 0, 12, 12)
        ))
    }

    @Test func negativeOriginKeepsTheStoredEdges() {
        #expect(frames(x: -1728, y: -300, width: 1728, height: 1117, radius: 18) == ScreenCornersBox.Frames(
            radius: 18,
            bottomLeft: rect(-1728, -300, 18, 18),
            bottomRight: rect(-18, -300, 18, 18)
        ))
    }

    @Test func secondDisplaySitsToTheRight() {
        let placed = frames(x: 1512, y: 0, width: 1920, height: 1080, radius: 8)
        #expect(placed.bottomLeft == rect(1512, 0, 8, 8))
        #expect(placed.bottomRight == rect(3424, 0, 8, 8))
        #expect(placed.rect(for: .bottomLeft) == placed.bottomLeft)
        #expect(placed.rect(for: .bottomRight) == placed.bottomRight)
    }

    @Test func squaresStayInsideAndApart() {
        let placed = frames(x: -400, y: 250, width: 1440, height: 900, radius: 12)
        #expect(placed.radius == 12)
        #expect(placed.bottomLeft == rect(-400, 250, 12, 12))
        #expect(placed.bottomRight == rect(1028, 250, 12, 12))
        #expect(placed.bottomLeft.x + placed.bottomLeft.width < placed.bottomRight.x)
    }

    @Test func radiusIsClampedToAQuarterOfTheShorterSide() {
        #expect(ScreenCornersBox.clampedRadius(18, width: 40, height: 40) == 10)
        #expect(frames(x: 0, y: 0, width: 40, height: 40, radius: 18) == ScreenCornersBox.Frames(
            radius: 10,
            bottomLeft: rect(0, 0, 10, 10),
            bottomRight: rect(30, 0, 10, 10)
        ))
        #expect(ScreenCornersBox.clampedRadius(18, width: 1000, height: 30) == 7.5)
        #expect(frames(x: 0, y: 0, width: 1000, height: 30, radius: 18).radius == 7.5)
        #expect(ScreenCornersBox.clampedRadius(12, width: 1512, height: 982) == 12)
    }

    @Test func oddInputsGiveNoCorner() {
        let screen = (x: 0.0, y: 0.0, width: 1512.0, height: 982.0)
        for radius in [0.0, -4, Double.nan, Double.infinity] {
            #expect(ScreenCornersBox.clampedRadius(radius, width: screen.width, height: screen.height) == 0)
            let placed = frames(x: screen.x, y: screen.y, width: screen.width, height: screen.height, radius: radius)
            #expect(placed.radius == 0)
            #expect(placed.bottomLeft == .zero)
            #expect(placed.bottomRight == .zero)
        }
        #expect(frames(x: 0, y: 0, width: 0, height: 0, radius: 12).radius == 0)
        #expect(frames(x: 0, y: 0, width: .nan, height: 900, radius: 12).radius == 0)
        #expect(frames(x: 0, y: 0, width: -20, height: 900, radius: 12).radius == 0)
        #expect(ScreenCornersBox.clampedRadius(.infinity, width: 100, height: 100) == 0)
    }

    @Test func outerCornerIsFilledAndTheInsideOfTheArcIsClear() {
        for side in ScreenCornersBox.Side.allCases {
            for r in [8.0, 12, 18] {
                let corner = outerCorner(side, radius: r)
                #expect(ScreenCornersBox.fills(x: corner.x, y: corner.y, side: side, radius: r))
                let outside = probe(side, radius: r, distance: r + 0.5)
                let inside = probe(side, radius: r, distance: r - 0.5)
                let centre = probe(side, radius: r, distance: 0)
                #expect(ScreenCornersBox.fills(x: outside.x, y: outside.y, side: side, radius: r))
                #expect(!ScreenCornersBox.fills(x: inside.x, y: inside.y, side: side, radius: r))
                #expect(!ScreenCornersBox.fills(x: centre.x, y: centre.y, side: side, radius: r))
            }
        }
    }

    @Test func theArcItselfIsFilled() {
        let r = 12.0
        // These four points sit on the arc: each is exactly one radius from its disc centre.
        #expect(ScreenCornersBox.fills(x: 0, y: 0, side: .bottomLeft, radius: r))
        #expect(ScreenCornersBox.fills(x: r, y: r, side: .bottomLeft, radius: r))
        #expect(ScreenCornersBox.fills(x: r, y: 0, side: .bottomRight, radius: r))
        #expect(ScreenCornersBox.fills(x: 0, y: r, side: .bottomRight, radius: r))
    }

    @Test func aPointOutsideTheSquareIsClear() {
        let r = 12.0
        for side in ScreenCornersBox.Side.allCases {
            let corner = outerCorner(side, radius: r)
            #expect(ScreenCornersBox.fills(x: corner.x, y: corner.y, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: -1, y: r, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: r + 1, y: r, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: r / 2, y: r + 1, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: r / 2, y: -1, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: .nan, y: r / 2, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: r / 2, y: .infinity, side: side, radius: r))
            #expect(!ScreenCornersBox.fills(x: 0, y: r, side: side, radius: 0))
            #expect(!ScreenCornersBox.fills(x: 0, y: r, side: side, radius: .nan))
        }
    }

    @Test func bottomRightMirrorsBottomLeft() {
        let r = 18.0
        let corner = outerCorner(.bottomLeft, radius: r)
        #expect(ScreenCornersBox.fills(x: corner.x, y: corner.y, side: .bottomLeft, radius: r))
        for step in 0...18 {
            for other in 0...18 {
                let x = Double(step)
                let y = Double(other)
                #expect(
                    ScreenCornersBox.fills(x: x, y: y, side: .bottomLeft, radius: r)
                        == ScreenCornersBox.fills(x: r - x, y: y, side: .bottomRight, radius: r)
                )
            }
        }
    }

    @Test func maskStartsAtTheOuterCornerAndStaysOnTheArc() {
        for side in ScreenCornersBox.Side.allCases {
            let r = 12.0
            let points = ScreenCornersBox.maskPoints(side: side, radius: r)
            #expect(points.count == 18)
            #expect(points.first == outerCorner(side, radius: r))
            let centre = side == .bottomLeft
                ? ScreenCornersBox.Point(x: r, y: 0)
                : ScreenCornersBox.Point(x: 0, y: 0)
            for point in points.dropFirst() {
                #expect(abs(hypot(point.x - centre.x, point.y - centre.y) - r) < 1e-9)
                #expect(point.x >= -1e-9 && point.x <= r + 1e-9)
                #expect(point.y >= -1e-9 && point.y <= r + 1e-9)
            }
        }
    }

    @Test func maskMirrorsScalesAndDropsABadRadius() {
        let left = ScreenCornersBox.maskPoints(side: .bottomLeft, radius: 12)
        let right = ScreenCornersBox.maskPoints(side: .bottomRight, radius: 12)
        #expect(left.count == 18)
        #expect(left.count == right.count)
        for (l, r) in zip(left, right) {
            #expect(abs((12 - l.x) - r.x) < 1e-9)
            #expect(abs(l.y - r.y) < 1e-9)
        }
        let big = ScreenCornersBox.maskPoints(side: .bottomLeft, radius: 18)
        #expect(big.count == left.count)
        #expect(big.first == outerCorner(.bottomLeft, radius: 18))
        #expect(ScreenCornersBox.maskPoints(side: .bottomLeft, radius: 0).isEmpty)
        #expect(ScreenCornersBox.maskPoints(side: .bottomRight, radius: .nan).isEmpty)
        #expect(ScreenCornersBox.maskPoints(side: .bottomLeft, radius: -2).isEmpty)
        let coarse = ScreenCornersBox.maskPoints(side: .bottomRight, radius: 8, segments: 0)
        #expect(coarse.count == 4)
        #expect(coarse.first == outerCorner(.bottomRight, radius: 8))
    }
}
