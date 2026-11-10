import CoreGraphics
import Testing
@testable import ZeusCore

/// L1: spring follow, Bezier flight, and the O8 ring snapped to an AX frame.
@Suite struct CompanionMotionTests {
    let hd = ScreenCoordinateMapper(displays: [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
    ])
    let desk = ScreenCoordinateMapper(displays: [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
        DisplayMap(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 2),
        DisplayMap(id: 4, frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160), scale: 1),
    ])

    @Test func companionNeverDrivesTheSystemPointer() {
        #expect(CompanionActuation.movesSystemPointer == false)
    }

    @Test func restSpotIsThirtyFiveRightAndTwentyFiveDown() {
        let rest = CompanionSpring.rest(near: CGPoint(x: 200, y: 400))
        #expect(abs(rest.x - 235) < 0.001)
        #expect(abs(rest.y - 375) < 0.001)
        #expect(CompanionSpring.tracksPointer(.always))
        #expect(CompanionSpring.tracksPointer(.onCall))
        #expect(!CompanionSpring.tracksPointer(.never))
    }

    @Test func springKeepsVelocityAndSettles() {
        let still = CompanionSpring(position: .zero, velocity: .zero)
            .stepped(toward: CGPoint(x: 100, y: 0), dt: 1.0 / 60)
        let moving = CompanionSpring(position: .zero, velocity: CGPoint(x: 400, y: 0))
            .stepped(toward: CGPoint(x: 100, y: 0), dt: 1.0 / 60)
        #expect(moving.position.x > still.position.x)
        #expect(still.position.x > 0)

        var spring = CompanionSpring(position: CGPoint(x: 0, y: 0), velocity: .zero)
        let target = CGPoint(x: 120, y: -40)
        var furthest = 0.0
        let start = hypot(target.x, target.y)
        for _ in 0..<180 {
            spring = spring.stepped(toward: target, dt: 1.0 / 60)
            furthest = max(furthest, hypot(spring.position.x - target.x, spring.position.y - target.y))
            #expect(spring.position.x.isFinite && spring.velocity.x.isFinite)
        }
        #expect(hypot(spring.position.x - target.x, spring.position.y - target.y) < 0.5)
        #expect(furthest < start)
        let jumped = CompanionSpring(position: .zero, velocity: CGPoint(x: 50, y: 50))
            .stepped(toward: target, dt: 1.0 / 60, reducedMotion: true)
        #expect(jumped.position == target)
        #expect(jumped.velocity == .zero)
    }

    @Test func sixHundredPointFlightIsSevenHundredFiftyMilliseconds() {
        let flight = CompanionFlight.plan(from: .zero, to: CGPoint(x: 600, y: 0))
        #expect(flight.duration == 0.75)
        #expect(abs(flight.control.y - 80) < 0.001)
        #expect(abs(flight.control.x - 300) < 0.001)

        let start = flight.sample(at: 0)
        let mid = flight.sample(at: 0.375)
        let end = flight.sample(at: 0.75)
        expectPoint(start.position, .zero)
        expectPoint(mid.position, CGPoint(x: 300, y: 40))
        expectPoint(end.position, CGPoint(x: 600, y: 0))
        #expect(abs(start.scale - 1) < 0.001)
        #expect(abs(mid.scale - 1.3) < 0.001)
        #expect(abs(end.scale - 1) < 0.001)
        #expect(abs(start.glow - 8) < 0.001)
        #expect(abs(mid.glow - 14) < 0.001)
        #expect(abs(end.glow - 8) < 0.001)
        #expect(abs(mid.scale - 1.3) < 0.001 && abs(mid.glow - 14) < 0.001)
    }

    @Test func flightStaysInsideTheControlHullAndTheAngleDoesNotJump() {
        let flight = CompanionFlight.plan(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 610, y: 20))
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
        let flight = CompanionFlight.plan(from: .zero, to: CGPoint(x: 600, y: 0))
        let at = flight.sample(at: 0.3)
        let next = flight.retarget(to: CGPoint(x: 100, y: 200), at: 0.3)
        expectPoint(next.sample(at: 0).position, at.position)
        #expect(next.to == CGPoint(x: 100, y: 200))

        let back = flight.returning(home: .zero)
        let landing = unit(flight.tangent(at: flight.duration))
        let depart = unit(back.tangent(at: 0))
        #expect(landing.x * depart.x + landing.y * depart.y > 0.999)
    }

    @Test func reducedMotionSkipsTheArc() {
        let flight = CompanionFlight.plan(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 80, y: 90), reducedMotion: true)
        #expect(flight.duration == 0)
        let sample = flight.sample(at: 0.2)
        expectPoint(sample.position, CGPoint(x: 80, y: 90))
        #expect(sample.scale == 1)
        #expect(sample.glow == 8)
    }

    @Test func displayMoveShiftsTheFlightAndUnplugDoesNot() {
        let before = [
            DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
            DisplayMap(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 2),
        ]
        let moved = [
            DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
            DisplayMap(id: 2, frame: CGRect(x: -1600, y: -100, width: 1920, height: 1080), scale: 2),
        ]
        let unplugged = [moved[0]]
        let shift = DisplayRebase.shift(of: 2, from: before, to: moved)
        #expect(shift == CGPoint(x: 320, y: -100))
        #expect(DisplayRebase.shift(of: 2, from: before, to: unplugged) == nil)
        let flight = CompanionFlight.plan(from: CGPoint(x: -100, y: 40), to: CGPoint(x: -400, y: 80))
        let shifted = flight.shifted(by: shift!)
        expectPoint(shifted.from, CGPoint(x: 220, y: -60))
        expectPoint(shifted.to, CGPoint(x: -80, y: -20))
    }

    @Test func ringSnapsToTheAXFrameNotThePixelGuess() {
        // Quartz frame on the main display. The ring center is the frame center.
        let frame = CGRect(x: 200, y: 100, width: 80, height: 40)
        let ring = TargetRing.snap(axFrame: frame, displayID: 1, mapper: hd, label: "Save")
        #expect(ring?.frame == frame)
        expectPoint(ring?.center, CGPoint(x: 240, y: 120))
        #expect(ring?.label == "Save")

        let show = ShowMeWhere.plan(from: CGPoint(x: 10, y: 10), axFrame: frame, displayID: 1, mapper: hd, label: "Save")
        expectPoint(show?.screenTarget, CGPoint(x: 240, y: 1080 - 120))
        #expect(show?.flight.to == show?.screenTarget)
        let landed = hd.withinRing(show!.screenTarget, of: show!.screenTarget, displayID: 1)
        #expect(landed == true)

        // 4K scale-1 panel: a landing 48 pt away still counts, 49 does not.
        let far = CGPoint(x: show!.screenTarget.x + 48, y: show!.screenTarget.y)
        #expect(desk.withinRing(far, of: show!.screenTarget, displayID: 4) == true)
    }

    @Test func ringOnANegativeDisplayUsesThatDisplaysOverlay() {
        // AX x is global quartz. The left display starts at x = -1920.
        let frame = CGRect(x: -1800, y: 100, width: 40, height: 20)
        let show = ShowMeWhere.plan(from: .zero, axFrame: frame, displayID: 2, mapper: desk)
        // Overlay center: x = -1800 - (-1920) + 20 = 140, y = 100 + 10 = 110.
        expectPoint(show?.ring.center, CGPoint(x: 140, y: 110))
        let screen = desk.convert(show!.ring.center, from: .overlay, to: .screen, context: MapContext(displayID: 2))
        expectPoint(show?.screenTarget, screen)
        #expect(desk.withinRing(show!.screenTarget, of: screen!, displayID: 2) == true)
    }

    @Test func snapPrefersTheSmallestFrameThatContainsThePoint() {
        let window = CGRect(x: 0, y: 0, width: 400, height: 300)
        let button = CGRect(x: 40, y: 50, width: 80, height: 24)
        // Screen point of the button's top-left area, inside both frames.
        let screen = hd.convert(CGPoint(x: 50, y: 60), from: .ax, to: .screen, context: MapContext())!
        let chosen = ElementSnap.best(axFrames: [window, button], around: screen, displayID: 1, mapper: hd)
        #expect(chosen == button)
        let outside = CGPoint(x: 900, y: 20)
        #expect(ElementSnap.best(axFrames: [button], around: outside, displayID: 1, mapper: hd) == nil)
    }

    @Test func presentProbeReportsTheFixture() {
        let report = PresentProbe.report()
        #expect(report.contains("movesSystemPointer=false"))
        #expect(report.contains("flight600.duration=0.750"))
        #expect(report.contains("flight600.mid=300.0,40.0"))
        #expect(report.contains("flight600.midScale=1.30"))
        #expect(report.contains("flight600.midGlow=14.0"))
        #expect(report.contains("ring1080.px=24"))
        #expect(report.contains("ring4k.px=48"))
    }

    @Test func nextClickClearsTheRing() {
        var session = RingSession()
        #expect(session.clearOnUserInput() == false)
        session.show(TargetRing(displayID: 1, center: CGPoint(x: 1, y: 2), frame: CGRect(x: 0, y: 0, width: 4, height: 4)))
        #expect(session.ring != nil)
        #expect(session.clearOnUserInput() == true)
        #expect(session.ring == nil)
    }

    private func unit(_ point: CGPoint) -> CGPoint {
        let length = hypot(point.x, point.y)
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    private func expectPoint(_ got: CGPoint?, _ want: CGPoint?) {
        #expect(got != nil && want != nil)
        guard let got, let want else { return }
        #expect(abs(got.x - want.x) < 0.001)
        #expect(abs(got.y - want.y) < 0.001)
    }
}
