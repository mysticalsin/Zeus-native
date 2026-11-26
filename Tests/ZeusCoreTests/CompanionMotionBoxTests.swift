import Foundation
import Testing
@testable import ZeusCore

@Suite struct CompanionMotionBoxTests {
    @Test func companionStaysDecorativeAndTracksUnlessHidden() {
        #expect(CompanionMotionBox.movesSystemPointer == false)
        #expect(CompanionMotionBox.Spring.tracksPointer(showIsNever: false))
        #expect(!CompanionMotionBox.Spring.tracksPointer(showIsNever: true))
    }

    @Test func restSpotIsThirtyFiveRightAndTwentyFiveDown() {
        let rest = CompanionMotionBox.Spring.rest(near: Point(x: 200, y: 400))
        #expect(abs(rest.x - 235) < 0.001)
        #expect(abs(rest.y - 375) < 0.001)
        #expect(CompanionMotionBox.Spring.response == 0.2)
        #expect(CompanionMotionBox.Spring.damping == 0.6)
        #expect(CompanionMotionBox.Spring.offsetX == 35)
        #expect(CompanionMotionBox.Spring.offsetY == 25)
    }

    @Test func springKeepsVelocityAndRejectsABadStep() {
        let still = CompanionMotionBox.Spring(position: .zero, velocity: .zero)
            .stepped(toward: Point(x: 100, y: 0), dt: 1.0 / 60)
        let moving = CompanionMotionBox.Spring(position: .zero, velocity: Point(x: 400, y: 0))
            .stepped(toward: Point(x: 100, y: 0), dt: 1.0 / 60)
        #expect(moving.position.x > still.position.x)
        #expect(still.position.x > 0)

        let held = CompanionMotionBox.Spring(position: Point(x: 4, y: -3), velocity: Point(x: 8, y: 9))
        for bad in [0.0, -0.01, Double.nan, Double.infinity] {
            let stayed = held.stepped(toward: Point(x: 100, y: 100), dt: bad)
            #expect(stayed.position.x == 4)
            #expect(stayed.position.y == -3)
            #expect(stayed.velocity.x == 8)
            #expect(stayed.velocity.y == 9)
        }

        let snapped = CompanionMotionBox.Spring(position: Point(x: .nan, y: 2), velocity: Point(x: 1, y: 1))
            .stepped(toward: Point(x: 5, y: -7), dt: 1.0 / 60)
        let finiteY = CompanionMotionBox.Spring(position: Point(x: 0, y: 2), velocity: Point(x: 0, y: 1))
            .stepped(toward: Point(x: 5, y: -7), dt: 1.0 / 60)
        #expect(snapped.position.x == 5)
        #expect(snapped.velocity.x == 0)
        #expect(snapped.position.y == finiteY.position.y)
        #expect(snapped.velocity.y == finiteY.velocity.y)

        let wild = CompanionMotionBox.Spring(position: Point(x: 1, y: 1), velocity: Point(x: .infinity, y: 0))
            .stepped(toward: Point(x: 9, y: 3), dt: 1.0 / 60)
        let finiteWild = CompanionMotionBox.Spring(position: Point(x: 1, y: 1), velocity: .zero)
            .stepped(toward: Point(x: 9, y: 3), dt: 1.0 / 60)
        #expect(wild.position.x == 9)
        #expect(wild.velocity.x == 0)
        #expect(wild.position.y == finiteWild.position.y)
        #expect(wild.velocity.y == finiteWild.velocity.y)
    }

    @Test func springSettlesAndReducedMotionJumps() {
        var spring = CompanionMotionBox.Spring(position: .zero, velocity: .zero)
        let target = Point(x: 120, y: -40)
        var furthest = 0.0
        let start = hypot(target.x, target.y)
        for _ in 0..<180 {
            spring = spring.stepped(toward: target, dt: 1.0 / 60)
            furthest = max(furthest, hypot(spring.position.x - target.x, spring.position.y - target.y))
            #expect(spring.position.x.isFinite && spring.velocity.x.isFinite)
        }
        #expect(hypot(spring.position.x - target.x, spring.position.y - target.y) < 0.5)
        #expect(furthest < start)

        let jumped = CompanionMotionBox.Spring(position: .zero, velocity: Point(x: 50, y: 50))
            .stepped(toward: target, dt: 1.0 / 60, reducedMotion: true)
        #expect(jumped.position == target)
        #expect(jumped.velocity == .zero)
    }

    @Test func sixHundredPointFlightIsSevenHundredFiftyMilliseconds() {
        let flight = CompanionMotionBox.Flight.plan(from: .zero, to: Point(x: 600, y: 0))
        #expect(flight.duration == 0.75)
        #expect(abs(flight.control.y - 80) < 0.001)
        #expect(abs(flight.control.x - 300) < 0.001)
        #expect(CompanionMotionBox.Flight.scaleRest == 1)
        #expect(CompanionMotionBox.Flight.scalePeak == 1.3)
        #expect(CompanionMotionBox.Flight.glowRest == 8)
        #expect(CompanionMotionBox.Flight.glowPeak == 14)

        let start = flight.sample(at: 0)
        let mid = flight.sample(at: 0.375)
        let end = flight.sample(at: 0.75)
        expectPoint(start.position, .zero)
        expectPoint(mid.position, Point(x: 300, y: 40))
        expectPoint(end.position, Point(x: 600, y: 0))
        #expect(abs(start.scale - 1) < 0.001)
        #expect(abs(mid.scale - 1.3) < 0.001)
        #expect(abs(end.scale - 1) < 0.001)
        #expect(abs(start.glow - 8) < 0.001)
        #expect(abs(mid.glow - 14) < 0.001)
        #expect(abs(end.glow - 8) < 0.001)
        #expect(abs(start.progress) < 0.001)
        #expect(abs(mid.progress - 0.5) < 0.001)
        #expect(abs(end.progress - 1) < 0.001)
    }

    @Test func flightStaysInsideTheControlHullAndTheAngleDoesNotJump() {
        let flight = CompanionMotionBox.Flight.plan(from: Point(x: 10, y: 20), to: Point(x: 610, y: 20))
        var previous = flight.sample(at: 0).rotation
        let minX = min(flight.from.x, flight.control.x, flight.to.x) - 0.01
        let maxX = max(flight.from.x, flight.control.x, flight.to.x) + 0.01
        let minY = min(flight.from.y, flight.control.y, flight.to.y) - 0.01
        let maxY = max(flight.from.y, flight.control.y, flight.to.y) + 0.01
        for step in 0...45 {
            let sample = flight.sample(at: Double(step) / 60)
            #expect(sample.position.x >= minX && sample.position.x <= maxX)
            #expect(sample.position.y >= minY && sample.position.y <= maxY)
            #expect(sample.scale >= 1 && sample.scale <= 1.3 + 0.001)
            #expect(sample.glow >= 8 && sample.glow <= 14 + 0.001)
            let turn = abs(sample.rotation - previous)
            #expect(turn < 20)
            previous = sample.rotation
        }
    }

    @Test func retargetKeepsTheCurrentPointAndReturnKeepsTheLandingTangent() {
        let flight = CompanionMotionBox.Flight.plan(from: .zero, to: Point(x: 600, y: 0))
        let at = flight.sample(at: 0.3)
        let next = flight.retarget(to: Point(x: 100, y: 200), at: 0.3)
        expectPoint(next.sample(at: 0).position, at.position)
        #expect(next.to == Point(x: 100, y: 200))

        let back = flight.returning(home: .zero)
        let landing = unit(flight.tangent(at: flight.duration))
        let depart = unit(back.tangent(at: 0))
        #expect(landing.x * depart.x + landing.y * depart.y > 0.999)
    }

    @Test func reducedMotionSkipsTheArc() {
        let flight = CompanionMotionBox.Flight.plan(from: Point(x: 5, y: 5), to: Point(x: 80, y: 90),
                                                     reducedMotion: true)
        #expect(flight.duration == 0)
        let sample = flight.sample(at: 0.2)
        expectPoint(sample.position, Point(x: 80, y: 90))
        #expect(sample.scale == 1)
        #expect(sample.glow == 8)
        #expect(sample.progress == 1)
    }

    @Test func displayMoveShiftsTheFlight() {
        let delta = CompanionMotionBox.displayShift(oldMinX: -1920, oldMinY: 0, newMinX: -1600, newMinY: -100)
        #expect(delta == Point(x: 320, y: -100))
        let flight = CompanionMotionBox.Flight.plan(from: Point(x: -100, y: 40), to: Point(x: -400, y: 80))
        let shifted = flight.shifted(by: delta)
        expectPoint(shifted.from, Point(x: 220, y: -60))
        expectPoint(shifted.to, Point(x: -80, y: -20))
        expectPoint(shifted.control, Point(x: flight.control.x + 320, y: flight.control.y - 100))
        #expect(shifted.duration == flight.duration)
        #expect(shifted.reducedMotion == flight.reducedMotion)
    }

    @Test func durationClampsAndATangentLiftsAlongTheHeading() {
        #expect(CompanionMotionBox.Flight.duration(distance: 100, reducedMotion: false) == 0.6)
        #expect(CompanionMotionBox.Flight.duration(distance: 2000, reducedMotion: false) == 1.4)
        #expect(CompanionMotionBox.Flight.duration(distance: 2000, reducedMotion: true) == 0)

        let lifted = CompanionMotionBox.Flight.plan(from: .zero, to: Point(x: 100, y: 0),
                                                     departureTangent: Point(x: 0, y: 1))
        expectPoint(lifted.control, Point(x: 0, y: 20))

        let straight = CompanionMotionBox.Flight.plan(from: .zero, to: Point(x: 100, y: 0),
                                                       departureTangent: Point(x: 0, y: 0))
        expectPoint(straight.control, Point(x: 50, y: 20))
    }

    private func unit(_ point: CompanionMotionBox.Point) -> CompanionMotionBox.Point {
        let length = hypot(point.x, point.y)
        return CompanionMotionBox.Point(x: point.x / length, y: point.y / length)
    }

    private func expectPoint(_ got: CompanionMotionBox.Point, _ want: CompanionMotionBox.Point) {
        #expect(abs(got.x - want.x) < 0.001)
        #expect(abs(got.y - want.y) < 0.001)
    }
}

private typealias Point = CompanionMotionBox.Point
