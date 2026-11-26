import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing ink trail box")
struct PointingInkTrailBoxTests {
    private func p(_ x: Double, _ y: Double) -> PointingInkTrailBox.Point {
        PointingInkTrailBox.Point(x: x, y: y)
    }

    @Test func hoveringBeginsAStrokeAndExtendsIt() {
        var trail = PointingInkTrailBox()
        #expect(trail.add(p(0, 0), at: 0) == .began)
        #expect(trail.add(p(10, 0), at: 0.03) == .extended)
        #expect(trail.add(p(20, 5), at: 0.06) == .extended)
        #expect(trail.strokes.count == 1 && trail.strokes[0].count == 3)
        #expect(trail.isDrawing)
        #expect(trail.strokes[0] == [p(0, 0), p(10, 0), p(20, 5)])
    }

    @Test func nearDuplicateSamplesAreDropped() {
        var trail = PointingInkTrailBox()
        trail.add(p(0, 0), at: 0)
        #expect(trail.add(p(1, 1), at: 0.03) == .dropped)
        #expect(trail.add(p(0.5, 0), at: 0.06) == .dropped)
        #expect(trail.strokes[0].count == 1)
        #expect(trail.droppedPoints == 2)
        #expect(PointingInkTrailBox.minSpacing == 2.5)
    }

    @Test func aPauseThenMovementStartsANewStroke() {
        var trail = PointingInkTrailBox()
        trail.add(p(0, 0), at: 0)
        trail.add(p(30, 0), at: 0.1)
        #expect(trail.add(p(30.5, 0), at: 0.9) == .dropped)
        #expect(trail.add(p(80, 40), at: 1.0) == .began)
        #expect(trail.strokes.count == 2)
        #expect(trail.strokes[1] == [p(80, 40)])
        #expect(PointingInkTrailBox.pauseSplit == 0.6)
    }

    @Test func endStrokeMakesTheNextPointBeginANewOne() {
        var trail = PointingInkTrailBox()
        trail.add(p(0, 0), at: 0)
        trail.endStroke()
        #expect(!trail.isDrawing)
        #expect(trail.add(p(5, 5), at: 0.05) == .began)
        #expect(trail.strokes.count == 2)
    }

    @Test func memoryIsBounded() {
        var trail = PointingInkTrailBox()
        for index in 0..<(PointingInkTrailBox.maxPointsPerStroke + 50) {
            trail.add(p(Double(index) * 5, 0), at: Double(index) * 0.01)
        }
        #expect(trail.strokes.count == 1)
        #expect(trail.strokes[0].count == PointingInkTrailBox.maxPointsPerStroke)
        #expect(trail.droppedPoints == 50)
        var many = PointingInkTrailBox()
        for index in 0..<(PointingInkTrailBox.maxStrokes + 5) {
            many.add(p(Double(index) * 100, 0), at: Double(index) * 2)
        }
        #expect(many.strokes.count == PointingInkTrailBox.maxStrokes)
        #expect(many.droppedPoints == 5)
        #expect(PointingInkTrailBox.maxStrokes == 16)
        #expect(PointingInkTrailBox.maxPointsPerStroke == 512)
    }

    @Test func nonFinitePointsAreRejected() {
        var trail = PointingInkTrailBox()
        #expect(trail.add(p(.nan, 0), at: 0) == .dropped)
        #expect(trail.add(p(0, 0), at: .infinity) == .dropped)
        #expect(trail.add(p(.infinity, 1), at: 1) == .dropped)
        #expect(trail.strokes.isEmpty)
        #expect(trail.droppedPoints == 3)
    }

    @Test func smoothingKeepsEndpointsAndSharpCorners() {
        let corner = p(100, 0)
        let path = [p(0, 0), p(50, 0), corner, p(100, 50), p(100, 100)]
        let smooth = PointingInkTrailBox.smooth(path)
        #expect(smooth.first == path.first)
        #expect(smooth.last == path.last)
        #expect(smooth.contains(corner))
        #expect(PointingInkTrailBox.cornerDegrees == 55)
    }

    @Test func smoothingRoundsAGentleBend() {
        let path = [p(0, 0), p(40, 0), p(80, 10), p(120, 30), p(150, 60)]
        let smooth = PointingInkTrailBox.smooth(path)
        #expect(smooth.count > path.count)
        #expect(smooth.first == path.first && smooth.last == path.last)
        #expect(!smooth.contains(path[2]))
    }

    @Test func shortPathsAreReturnedAsIs() {
        #expect(PointingInkTrailBox.smooth([]) == [])
        #expect(PointingInkTrailBox.smooth([p(1, 1), p(5, 5)]) == [p(1, 1), p(5, 5)])
    }

    @Test func turnAngleMeasuresDeviation() {
        #expect(abs(PointingInkTrailBox.turn(p(0, 0), p(10, 0), p(20, 0))) < 1e-9)
        #expect(abs(PointingInkTrailBox.turn(p(0, 0), p(10, 0), p(10, 10)) - 90) < 1e-6)
        #expect(abs(PointingInkTrailBox.turn(p(0, 0), p(10, 0), p(0, 0)) - 180) < 1e-6)
        #expect(PointingInkTrailBox.turn(p(0, 0), p(0, 0), p(1, 0)) == 0)
    }
}
