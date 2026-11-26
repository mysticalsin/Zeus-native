import Foundation
import Testing
@testable import ZeusCore

/// Phase 4 flow geometry (docs/POINTING-ASSISTANT-PLAN.md).
/// Dash-phase motion runs along a tube or a path and is a pure function of
/// presentation time. Reduce Motion replaces that motion with static arrowheads.
/// The dash lengths and the arrow angle are the ones `ExplanationCanvasPainter` already uses.
@Suite("Explanation flow geometry")
struct ExplanationFlowGeometryTests {
    private func vec(_ x: Double, _ y: Double, _ z: Double = 0) -> ExplanationVector3 {
        .init(x: x, y: y, z: z)
    }

    private let line = [ExplanationVector3.zero, ExplanationVector3(x: 100, y: 0, z: 0)]

    private func sample(
        _ points: [ExplanationVector3],
        at time: Double,
        reduceMotion: Bool,
        direction: ExplanationFlow.Direction = .forward,
        centerline: ExplanationFlowGeometry.Centerline = .path,
        lineWidth: Double = 2,
        arrowCount: Int = 4
    ) -> ExplanationFlowGeometry.Sample {
        ExplanationFlowGeometry.sample(
            points: points, at: time, reduceMotion: reduceMotion, direction: direction,
            centerline: centerline, lineWidth: lineWidth, arrowCount: arrowCount)
    }

    private func distance(_ a: ExplanationVector3, _ b: ExplanationVector3) -> Double {
        let d = ExplanationVector3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
        return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }

    @Test func thePatternMatchesTheCanvasDashAndArrow() {
        #expect(ExplanationFlowGeometry.dashOn == 6)
        #expect(ExplanationFlowGeometry.dashOff == 5)
        #expect(ExplanationFlowGeometry.dashPeriod == 11)
        #expect(ExplanationFlowGeometry.arrowAngle == 0.45)
        #expect(ExplanationFlowGeometry.minimumArrowLength == 8)
        #expect(ExplanationFlowGeometry.maximumArrowLength == 18)
    }

    @Test func dashPhaseIsPresentationTimeAndWrapsOncePerSecond() {
        let start = sample(line, at: 0, reduceMotion: false)
        let quarter = sample(line, at: 0.25, reduceMotion: false)
        let half = sample(line, at: 0.5, reduceMotion: false)
        let wrapped = sample(line, at: 1.25, reduceMotion: false)
        #expect(start.dashPhase == 0)
        #expect(abs(quarter.dashPhase - 2.75) < 1e-9)
        #expect(abs(half.dashPhase - 5.5) < 1e-9)
        #expect(abs(wrapped.dashPhase - quarter.dashPhase) < 1e-9)
        #expect(quarter.arrowheads.isEmpty)
        #expect(quarter.reduced == false)
        #expect(quarter.tubeRadius == nil)
        #expect(quarter == sample(line, at: 0.25, reduceMotion: false))
    }

    @Test func reverseTravelShiftsThePhaseTheOtherWay() {
        let forward = sample(line, at: 0.25, reduceMotion: false, direction: .forward)
        let reverse = sample(line, at: 0.25, reduceMotion: false, direction: .reverse)
        #expect(abs(forward.dashPhase - 2.75) < 1e-9)
        #expect(abs(reverse.dashPhase - 8.25) < 1e-9)
        #expect(forward.dashPhase != reverse.dashPhase)
        #expect(sample(line, at: 1, reduceMotion: false, direction: .reverse).dashPhase == 0)
    }

    @Test func aTubeUsesTheSameCenterlinePhaseAsAPath() {
        let path = sample(line, at: 0.5, reduceMotion: false, centerline: .path)
        let tube = sample(line, at: 0.5, reduceMotion: false, centerline: .tube(radius: 0.2))
        #expect(path.dashPhase == tube.dashPhase)
        #expect(path.arrowheads == tube.arrowheads)
        #expect(path.tubeRadius == nil)
        #expect(tube.tubeRadius == 0.2)
        let invalid = [0.0, -1, Double.nan, Double.infinity].map {
            sample(line, at: 0.5, reduceMotion: false, centerline: .tube(radius: $0))
        }
        #expect(invalid.allSatisfy { $0.tubeRadius == nil && abs($0.dashPhase - 5.5) < 1e-9 })
    }

    @Test func reduceMotionHoldsStaticArrowheadsAndDropsTheDash() {
        let still = sample(line, at: 0, reduceMotion: true)
        let later = sample(line, at: 4.5, reduceMotion: true)
        #expect(still == later)
        #expect(still.reduced)
        #expect(still.dashPhase == 0)
        #expect(still.arrowheads.count == 4)
        let moving = sample(line, at: 4.5, reduceMotion: false)
        #expect(moving.arrowheads.isEmpty)
        #expect(moving.dashPhase != 0)
        let path = ExplanationFlowPath(id: "route", points: line)
        let flow = ExplanationFlow(id: "energy", pathID: "route", speed: 1, direction: .forward, count: 4)
        let markers = ExplanationFlowMath.markers(for: flow, path: path, progress: 0)
        #expect(still.arrowheads.map(\.tip) == markers.map(\.position))
        #expect(still.arrowheads.map(\.tangent) == markers.map(\.tangent))
    }

    @Test func arrowheadsPointAlongTravelAndUseTheCanvasHead() {
        let heads = sample(line, at: 9, reduceMotion: true, arrowCount: 1).arrowheads
        #expect(heads.count == 1)
        let head = heads[0]
        #expect(head.tip == .zero)
        #expect(head.tangent == vec(1, 0, 0))
        #expect(abs(distance(head.tip, head.left) - 8) < 1e-9)
        #expect(abs(distance(head.tip, head.right) - 8) < 1e-9)
        let left = vec(head.left.x - head.tip.x, head.left.y - head.tip.y, head.left.z - head.tip.z)
        let right = vec(head.right.x - head.tip.x, head.right.y - head.tip.y, head.right.z - head.tip.z)
        let unitLeft = vec(left.x / 8, left.y / 8, left.z / 8)
        let reverse = vec(-1, 0, 0)
        let alignment = unitLeft.x * reverse.x + unitLeft.y * reverse.y + unitLeft.z * reverse.z
        #expect(abs(alignment - cos(0.45)) < 1e-9)
        #expect(abs(left.y) < 1e-9 && abs(right.y) < 1e-9)
        #expect(left.z > 0 && right.z < 0)
        #expect(abs(left.x - right.x) < 1e-9)
    }

    @Test func aShortSegmentClampsTheHeadAndAWideStrokeUsesTheCeiling() {
        let short = sample([.zero, vec(3, 0, 0)], at: 0, reduceMotion: true, arrowCount: 1)
        #expect(abs(distance(short.arrowheads[0].tip, short.arrowheads[0].left) - 3) < 1e-9)
        let wide = sample(line, at: 0, reduceMotion: true, lineWidth: 10, arrowCount: 1)
        #expect(abs(distance(wide.arrowheads[0].tip, wide.arrowheads[0].left) - 18) < 1e-9)
        let fallback = sample(line, at: 0, reduceMotion: true, lineWidth: .nan, arrowCount: 1)
        #expect(abs(distance(fallback.arrowheads[0].tip, fallback.arrowheads[0].left) - 8) < 1e-9)
    }

    @Test func aBentPathAndAVerticalPathKeepAFiniteHead() {
        let bentPoints = [vec(0, 0, 0), vec(10, 0, 0), vec(10, 10, 0)]
        let bent = sample(bentPoints, at: 2, reduceMotion: true, arrowCount: 4)
        #expect(bent.arrowheads.count == 4)
        #expect(bent.arrowheads[0].tangent == vec(1, 0, 0))
        // A station that lands on the corner stays on the segment that ends there.
        #expect(bent.arrowheads[2].tangent == vec(1, 0, 0))
        #expect(abs(bent.arrowheads[2].tip.x - 10) < 1e-9 && abs(bent.arrowheads[2].tip.y) < 1e-9)
        #expect(bent.arrowheads[3].tangent == vec(0, 1, 0))
        #expect(abs(bent.arrowheads[3].tip.x - 10) < 1e-9)
        #expect(abs(bent.arrowheads[3].tip.y - 5) < 1e-9)
        let rising = sample([.zero, vec(0, 40, 0)], at: 1, reduceMotion: true, arrowCount: 1)
        let head = rising.arrowheads[0]
        #expect(head.tangent == vec(0, 1, 0))
        #expect(head.left.z < 0 && head.right.z > 0)
        #expect(abs(distance(head.tip, head.left) - 8) < 1e-9)
        #expect(head.left.x.isFinite && head.right.y.isFinite)
    }

    @Test func reverseArrowheadsPointBackAlongThePath() {
        let heads = sample(line, at: 3, reduceMotion: true, direction: .reverse, arrowCount: 4).arrowheads
        #expect(heads.allSatisfy { $0.tangent == vec(-1, 0, 0) })
        let path = ExplanationFlowPath(id: "route", points: line)
        var flow = ExplanationFlow(id: "energy", pathID: "route", speed: 1, direction: .forward, count: 4)
        flow.direction = .reverse
        let markers = ExplanationFlowMath.markers(for: flow, path: path, progress: 0)
        #expect(heads.map(\.tip) == markers.map(\.position))
        #expect(heads.map(\.tangent) == markers.map(\.tangent))
        let later = sample(line, at: 0, reduceMotion: true, direction: .reverse, arrowCount: 4)
        #expect(heads == later.arrowheads)
    }

    @Test func arrowCountStaysInsideTheFlowMarkerLimit() {
        #expect(sample(line, at: 0, reduceMotion: true, arrowCount: 0).arrowheads.count == 1)
        #expect(sample(line, at: 0, reduceMotion: true, arrowCount: -5).arrowheads.count == 1)
        #expect(sample(line, at: 0, reduceMotion: true, arrowCount: 100).arrowheads.count == ExplanationModelLimits.markersPerFlow)
        let moving = sample(line, at: 0.25, reduceMotion: false, arrowCount: 100)
        #expect(moving.arrowheads.isEmpty)
        #expect(abs(moving.dashPhase - 2.75) < 1e-9)
    }

    @Test func aPathThatCannotBeDrawnStaysEmpty() {
        let empties: [[ExplanationVector3]] = [[], [.zero], [.zero, .zero], [vec(.nan, 0, 0), vec(1, 0, 0)]]
        for points in empties {
            let moving = sample(points, at: 0.5, reduceMotion: false)
            let still = sample(points, at: 0.5, reduceMotion: true)
            #expect(moving.dashPhase == 0 && moving.arrowheads.isEmpty)
            #expect(still.dashPhase == 0 && still.arrowheads.isEmpty)
            #expect(still.reduced)
        }
    }

    @Test func aNonFiniteOrNegativeTimeDoesNotMoveThePattern() {
        for time in [Double.nan, Double.infinity, -Double.infinity, -0.25] {
            let moving = sample(line, at: time, reduceMotion: false)
            #expect(moving.dashPhase == 0)
            #expect(moving.arrowheads.isEmpty)
            #expect(moving.dashPhase.isFinite)
            let still = sample(line, at: time, reduceMotion: true)
            let atZero = sample(line, at: 0, reduceMotion: true)
            #expect(still == atZero)
        }
    }
}
