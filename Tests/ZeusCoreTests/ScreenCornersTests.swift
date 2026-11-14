import Foundation
import Testing
@testable import ZeusCore

/// S2: rounded bottom screen corners (pure rules; the panels live in Sources/Zeus/Notch/ScreenCornerOverlay.swift).
@Suite struct ScreenCornersTests {
    // MARK: Size

    @Test func sizeRadii() {
        #expect(ScreenCornerSize.small.radius == 8)
        #expect(ScreenCornerSize.medium.radius == 12)
        #expect(ScreenCornerSize.large.radius == 18)
    }

    @Test func sizeLabelsParse() {
        #expect(ScreenCornerSize(label: "Small") == .small)
        #expect(ScreenCornerSize(label: "Medium") == .medium)
        #expect(ScreenCornerSize(label: "Large") == .large)
        #expect(ScreenCornerSize(label: " large ") == .large)
        #expect(ScreenCornerSize(label: "SMALL") == .small)
    }

    @Test func unknownLabelFallsBackToMedium() {
        for label in ["", "Huge", "12", "Extra large"] {
            #expect(ScreenCornerSize(label: label) == .medium)
        }
    }

    @Test func labelsRoundTrip() {
        for size in ScreenCornerSize.allCases {
            #expect(ScreenCornerSize(label: size.label) == size)
        }
        #expect(ScreenCornerSize.allCases.map(\.label) == ["Small", "Medium", "Large"])
    }

    // MARK: Which screens

    @Test func drawsOnlyWithANotchAndTheSettingOn() {
        #expect(ScreenCorners.draws(hasNotch: true, enabled: true))
        #expect(!ScreenCorners.draws(hasNotch: true, enabled: false))
        #expect(!ScreenCorners.draws(hasNotch: false, enabled: true))
        #expect(!ScreenCorners.draws(hasNotch: false, enabled: false))
    }

    @Test func aNotchNeedsAnInsetAndBothSideAreas() {
        #expect(ScreenCorners.hasNotch(safeAreaTop: 32, leftAreaWidth: 660, rightAreaWidth: 660))
        #expect(!ScreenCorners.hasNotch(safeAreaTop: 0, leftAreaWidth: 660, rightAreaWidth: 660))
        // An empty or missing area (the app passes 0) is not a notch, even with a top inset.
        #expect(!ScreenCorners.hasNotch(safeAreaTop: 32, leftAreaWidth: 0, rightAreaWidth: 660))
        #expect(!ScreenCorners.hasNotch(safeAreaTop: 32, leftAreaWidth: 660, rightAreaWidth: 0))
        #expect(!ScreenCorners.hasNotch(safeAreaTop: .nan, leftAreaWidth: 660, rightAreaWidth: 660))
    }

    // MARK: Frames

    @Test func framesForAnOrdinaryScreen() {
        let frames = ScreenCorners.cornerFrames(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), radius: 12)
        #expect(frames.radius == 12)
        #expect(frames.bottomLeft == CGRect(x: 0, y: 0, width: 12, height: 12))
        #expect(frames.bottomRight == CGRect(x: 1500, y: 0, width: 12, height: 12))
    }

    @Test func framesForAScreenAtANegativeOrigin() {
        let screen = CGRect(x: -1728, y: -300, width: 1728, height: 1117)
        let frames = ScreenCorners.cornerFrames(screenFrame: screen, radius: 18)
        #expect(frames.bottomLeft == CGRect(x: -1728, y: -300, width: 18, height: 18))
        #expect(frames.bottomRight == CGRect(x: -18, y: -300, width: 18, height: 18))
    }

    @Test func framesForASecondDisplayToTheRight() {
        let screen = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let frames = ScreenCorners.cornerFrames(screenFrame: screen, radius: 8)
        #expect(frames.bottomLeft == CGRect(x: 1512, y: 0, width: 8, height: 8))
        #expect(frames.bottomRight == CGRect(x: 3424, y: 0, width: 8, height: 8))
    }

    @Test func eachCornerStaysInsideItsScreen() {
        let screen = CGRect(x: -400, y: 250, width: 1440, height: 900)
        let frames = ScreenCorners.cornerFrames(screenFrame: screen, radius: 12)
        #expect(screen.contains(frames.bottomLeft))
        #expect(screen.contains(frames.bottomRight))
        #expect(!frames.bottomLeft.intersects(frames.bottomRight))
        #expect(frames.frame(for: .bottomLeft) == frames.bottomLeft)
        #expect(frames.frame(for: .bottomRight) == frames.bottomRight)
    }

    @Test func radiusIsClampedToAQuarterOfTheShorterSide() {
        let tiny = ScreenCorners.cornerFrames(screenFrame: CGRect(x: 0, y: 0, width: 40, height: 40), radius: 18)
        #expect(tiny.radius == 10)
        #expect(tiny.bottomLeft.size == CGSize(width: 10, height: 10))
        #expect(tiny.bottomRight == CGRect(x: 30, y: 0, width: 10, height: 10))

        let narrow = ScreenCorners.cornerFrames(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 30), radius: 18)
        #expect(narrow.radius == 7.5)

        #expect(ScreenCorners.clampedRadius(12, in: CGRect(x: 0, y: 0, width: 1512, height: 982)) == 12)
    }

    @Test func oddInputsGiveNoCorner() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for radius in [0, -4, Double.nan, Double.infinity] {
            let frames = ScreenCorners.cornerFrames(screenFrame: screen, radius: radius)
            #expect(frames.radius == 0)
            #expect(frames.bottomLeft.isEmpty)
            #expect(frames.bottomRight.isEmpty)
        }
        let empty = ScreenCorners.cornerFrames(screenFrame: .zero, radius: 12)
        #expect(empty.radius == 0)
        let broken = ScreenCorners.cornerFrames(screenFrame: CGRect(x: 0, y: 0, width: Double.nan, height: 900), radius: 12)
        #expect(broken.radius == 0)
    }

    // MARK: The filled region

    /// The point `distance` from the disc centre along the line to the outer corner, in the corner square's
    /// own coordinates (origin top-left, y down). The disc centre is the square's inner corner.
    private func probe(_ side: ScreenCornerSide, radius r: Double, distance: Double) -> CGPoint {
        let s = 1 / 2.0.squareRoot()
        switch side {
        case .bottomLeft: return CGPoint(x: r - distance * s, y: distance * s)      // centre (r, 0), corner (0, r)
        case .bottomRight: return CGPoint(x: distance * s, y: distance * s)         // centre (0, 0), corner (r, r)
        }
    }

    private func outerCorner(_ side: ScreenCornerSide, radius r: Double) -> CGPoint {
        side == .bottomLeft ? CGPoint(x: 0, y: r) : CGPoint(x: r, y: r)
    }

    @Test func filledRegionHoldsTheOuterCornerAndLeavesTheArcInsideEmpty() {
        for side in ScreenCornerSide.allCases {
            for r in [8.0, 12, 18] {
                #expect(ScreenCorners.fills(outerCorner(side, radius: r), side: side, radius: r))
                // Just outside the arc: black. Just inside it: left clear.
                #expect(ScreenCorners.fills(probe(side, radius: r, distance: r + 0.5), side: side, radius: r))
                #expect(!ScreenCorners.fills(probe(side, radius: r, distance: r - 0.5), side: side, radius: r))
                #expect(!ScreenCorners.fills(probe(side, radius: r, distance: 0), side: side, radius: r))
            }
        }
    }

    @Test func filledRegionStaysInsideTheSquare() {
        let r = 12.0
        for side in ScreenCornerSide.allCases {
            #expect(!ScreenCorners.fills(CGPoint(x: -1, y: r), side: side, radius: r))
            #expect(!ScreenCorners.fills(CGPoint(x: r + 1, y: r), side: side, radius: r))
            #expect(!ScreenCorners.fills(CGPoint(x: r / 2, y: r + 1), side: side, radius: r))
            #expect(!ScreenCorners.fills(CGPoint(x: r / 2, y: -1), side: side, radius: r))
        }
    }

    @Test func bottomRightMirrorsBottomLeft() {
        let r = 18.0
        for step in 0...18 {
            for other in 0...18 {
                let p = CGPoint(x: Double(step), y: Double(other))
                let mirrored = CGPoint(x: r - p.x, y: p.y)
                #expect(ScreenCorners.fills(p, side: .bottomLeft, radius: r) == ScreenCorners.fills(mirrored, side: .bottomRight, radius: r))
            }
        }
    }

    @Test func maskPointsTraceTheFilledRegion() {
        for side in ScreenCornerSide.allCases {
            let r = 12.0
            let points = ScreenCorners.maskPoints(side: side, radius: r)
            #expect(points.count >= 4)
            // Starts at the outer corner of the screen; every other point is on the arc.
            #expect(points.first == outerCorner(side, radius: r))
            let centre = side == .bottomLeft ? CGPoint(x: r, y: 0) : CGPoint(x: 0, y: 0)
            for point in points.dropFirst() {
                #expect(abs(hypot(point.x - centre.x, point.y - centre.y) - r) < 1e-9)
            }
            for point in points {
                #expect(point.x >= -1e-9 && point.x <= r + 1e-9 && point.y >= -1e-9 && point.y <= r + 1e-9)
            }
            // The corner itself is a vertex, so test a point a hair inside it.
            let nudge = side == .bottomLeft ? 0.05 : -0.05
            #expect(Self.polygon(points, contains: CGPoint(x: outerCorner(side, radius: r).x + nudge, y: r - 0.05)))
            #expect(!Self.polygon(points, contains: probe(side, radius: r, distance: r - 0.5)))
            #expect(Self.polygon(points, contains: probe(side, radius: r, distance: r + 0.5)))
        }
    }

    @Test func maskPointsMirrorAndScale() {
        let left = ScreenCorners.maskPoints(side: .bottomLeft, radius: 12)
        let right = ScreenCorners.maskPoints(side: .bottomRight, radius: 12)
        #expect(left.count == right.count)
        for (l, r) in zip(left, right) {
            #expect(abs((12 - l.x) - r.x) < 1e-9)
            #expect(abs(l.y - r.y) < 1e-9)
        }
        let big = ScreenCorners.maskPoints(side: .bottomLeft, radius: 18)
        #expect(big.count == left.count)
        #expect(ScreenCorners.maskPoints(side: .bottomLeft, radius: 0).isEmpty)
        #expect(ScreenCorners.maskPoints(side: .bottomRight, radius: .nan).isEmpty)
    }

    /// Even-odd ray cast.
    private static func polygon(_ points: [CGPoint], contains p: CGPoint) -> Bool {
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
