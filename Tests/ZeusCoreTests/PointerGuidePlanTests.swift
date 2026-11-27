import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointer guide steps")
struct PointerGuidePlanTests {
    private func plan(named name: String) throws -> PointerGuidePlan {
        let file = PointerGuideStep(
            id: "file",
            bolt: PointerGuidePoint(x: 80, y: 740),
            ring: PointerGuideRect(x: 40, y: 720, width: 80, height: 28),
            caption: "Click File")
        let export = PointerGuideStep(
            id: "export",
            bolt: PointerGuidePoint(x: 180, y: 640),
            ring: PointerGuideRect(x: 140, y: 620, width: 120, height: 32),
            caption: "Export as PDF")
        let reduced = name == "file-then-export-reduced"
        guard name == "file-then-export" || reduced,
              let plan = PointerGuidePlan(steps: [file, export], reduceMotion: reduced) else {
            throw PlanError.invalid
        }
        return plan
    }

    private enum PlanError: Error { case invalid }

    private func speaking() -> PointingSession {
        var session = PointingSession()
        session.send(.keyDown)
        session.send(.keyUp)
        session.send(.firstPlaybackStart)
        return session
    }

    @Test func oneModelPlanAdvancesOnAClickInsideTheRing() throws {
        var guide = try plan(named: "file-then-export")
        let first = try #require(guide.current)
        #expect(guide.modelTurns == 1)
        let advanced = guide.click(at: first.ring.center)
        guard case .step(let next) = advanced else {
            Issue.record("a guiding click did not advance the local step")
            return
        }
        #expect(next.id == "export")
        #expect(next.caption == "Export as PDF")
        #expect(guide.modelTurns == 1)
        #expect(guide.current?.id == "export")
    }

    @Test func aClickOutsideTheRingStaysOnTheCurrentStep() throws {
        var guide = try plan(named: "file-then-export")
        let missed = guide.click(at: PointerGuidePoint(x: 0, y: 0))
        guard case .waiting = missed else {
            Issue.record("a click outside the ring left the current step")
            return
        }
        #expect(guide.index == 0)
        #expect(guide.current?.id == "file")
        #expect(guide.modelTurns == 1)
    }

    @Test func aSecondClickOnTheSamePointAdvancesOnce() throws {
        var guide = try plan(named: "file-then-export")
        let first = try #require(guide.current)
        _ = guide.click(at: first.ring.center)
        _ = guide.click(at: first.ring.center)
        #expect(guide.index == 1)
        #expect(guide.current?.id == "export")
        #expect(guide.modelTurns == 1)
    }

    @Test func theLastStepFinishesWithoutAnotherModelTurn() throws {
        var guide = try plan(named: "file-then-export")
        let first = try #require(guide.steps.first)
        let last = try #require(guide.steps.last)
        _ = guide.click(at: first.ring.center)
        let done = guide.click(at: last.ring.center)
        guard case .finished = done else {
            Issue.record("the last guiding click did not finish the plan")
            return
        }
        #expect(guide.current == nil)
        #expect(guide.modelTurns == 1)
    }

    @Test func theSessionKeepsTheNextStepLocal() throws {
        let guide = try plan(named: "file-then-export")
        let first = try #require(guide.steps.first)
        let second = try #require(guide.steps.last)
        var session = speaking()
        #expect(session.state == .speaking)
        let admitted = session.admitGuide(guide)
        #expect(admitted.to == .guiding)
        #expect(session.guide?.modelTurns == 1)
        let generation = session.generation
        let click = session.guideClick(at: first.ring.center)
        #expect(click.to == .guiding)
        #expect(click.effects == [.showGuideStep])
        #expect(session.state == .guiding)
        #expect(session.generation == generation)
        #expect(session.guide?.current?.caption == "Export as PDF")
        #expect(session.guide?.modelTurns == 1)
        let done = session.guideClick(at: second.ring.center)
        #expect(done.to == .idle)
        #expect(done.effects.isEmpty)
        #expect(session.guide == nil)
        #expect(session.generation == generation)
        #expect(session.state == .idle)
    }

    @Test func aMissedSessionClickDoesNotLeaveGuiding() throws {
        let guide = try plan(named: "file-then-export")
        var session = speaking()
        session.admitGuide(guide)
        let generation = session.generation
        let missed = session.guideClick(at: PointerGuidePoint(x: 0, y: 0))
        #expect(missed.to == .guiding)
        #expect(missed.effects.isEmpty)
        #expect(session.generation == generation)
        #expect(session.guide?.current?.id == "file")
        #expect(session.guide?.modelTurns == 1)
    }

    @Test func reducedMotionSettlesTheBoltRingAndCaption() throws {
        let guide = try plan(named: "file-then-export-reduced")
        let step = try #require(guide.current)
        let origin = CGPoint(x: 10, y: 10)
        let pose = try #require(guide.pose(from: origin, at: 0, beganAt: 0, reduceMotion: true))
        let flight = CompanionFlight.plan(from: origin, to: step.boltPoint, reducedMotion: true)
        #expect(pose.flight == flight)
        #expect(pose.flight.duration == 0)
        #expect(pose.bolt == step.boltPoint)
        #expect(pose.ring == step.ringRect)
        #expect(pose.caption == "Click File")
        #expect(pose.visibleCaption == "Click File")
    }

    @Test func theBoltUsesTheCompanionFlightAndTheCaptionUsesThePointingLabel() throws {
        let guide = try plan(named: "file-then-export")
        let step = try #require(guide.current)
        let origin = CGPoint(x: 12, y: 40)
        let began: TimeInterval = 5
        let pose = try #require(guide.pose(from: origin, at: began, beganAt: began, reduceMotion: false))
        let flight = CompanionFlight.plan(from: origin, to: step.boltPoint, reducedMotion: false)
        #expect(pose.flight == flight)
        #expect(pose.bolt == flight.sample(at: 0).position)
        #expect(pose.ring == step.ringRect)
        #expect(pose.visibleCaption.isEmpty)
        #expect(pose.flight.duration > 0)
        let first = try #require(guide.pose(from: origin, at: began + 0.12, beganAt: began, reduceMotion: false))
        #expect(first.visibleCaption == "C")
        #expect(first.bolt == flight.sample(at: (began + 0.12) - began).position)
        let second = try #require(guide.pose(from: origin, at: began + 0.16, beganAt: began, reduceMotion: false))
        #expect(second.visibleCaption == "Cl")
    }

    @Test func reducedMotionMidStepShowsTheWholeCaption() throws {
        let guide = try plan(named: "file-then-export")
        let step = try #require(guide.current)
        let origin = CGPoint(x: 12, y: 40)
        let snapped = try #require(guide.pose(from: origin, at: 0.2, beganAt: 0, reduceMotion: true))
        #expect(snapped.visibleCaption == step.caption)
        #expect(snapped.bolt == step.boltPoint)
        #expect(snapped.ring == step.ringRect)
        #expect(snapped.flight.duration == 0)
    }

    @Test func anEmptyDuplicateOrOversizedPlanIsRejected() {
        #expect(PointerGuidePlan(steps: [], reduceMotion: false) == nil)
        let step = PointerGuideStep(id: "file", bolt: PointerGuidePoint(x: 1, y: 2),
                                     ring: PointerGuideRect(x: 0, y: 0, width: 10, height: 10), caption: "Click File")
        #expect(PointerGuidePlan(steps: [step, step], reduceMotion: false) == nil)
        var blank = step
        blank.caption = ""
        #expect(PointerGuidePlan(steps: [blank], reduceMotion: false) == nil)
        var long = step
        long.caption = String(repeating: "a", count: 41)
        #expect(PointerGuidePlan(steps: [long], reduceMotion: false) == nil)
        var flat = step
        flat.ring = PointerGuideRect(x: 0, y: 0, width: 0, height: 10)
        #expect(PointerGuidePlan(steps: [flat], reduceMotion: false) == nil)
        var broken = step
        broken.bolt = PointerGuidePoint(x: .infinity, y: 1)
        #expect(PointerGuidePlan(steps: [broken], reduceMotion: false) == nil)
        var many: [PointerGuideStep] = []
        for index in 0..<(PointerGuidePlan.maxSteps + 1) {
            var extra = step
            extra.id = "s\(index)"
            many.append(extra)
        }
        #expect(PointerGuidePlan(steps: many, reduceMotion: true) == nil)
    }

    @Test func aLiveRingBecomesOneLocalStep() {
        let bolt = CGPoint(x: 80, y: 740)
        let ring = CGRect(x: 40, y: 720, width: 80, height: 28)
        let plan = PointerGuideAdmission.step(id: "ring-1", bolt: bolt, ring: ring, caption: "Click File\nThe menu opens", reduceMotion: false)
        #expect(plan?.current?.caption == "Click File")
        #expect(plan?.current?.ring.contains(PointerGuidePoint(x: 50, y: 730)) == true)
        #expect(PointerGuideAdmission.step(id: "ring-1", bolt: bolt, ring: ring, caption: String(repeating: "a", count: 41), reduceMotion: false) == nil)
        #expect(PointerGuideAdmission.step(id: "ring-1", bolt: bolt, ring: .zero, caption: "Click File", reduceMotion: false) == nil)
    }

    @Test func admitGuideWhileSpeakingIsTheOnlyModelTurn() throws {
        var idle = PointingSession()
        let guide = try plan(named: "file-then-export")
        let ignored = idle.admitGuide(guide)
        #expect(ignored.to == .idle)
        #expect(idle.guide == nil)
        var session = speaking()
        let generation = session.generation
        session.admitGuide(guide)
        #expect(session.generation == generation)
        #expect(session.guide?.modelTurns == 1)
        session.admitGuide(guide)
        #expect(session.state == .guiding)
        #expect(session.guide?.index == 0)
        #expect(session.guide?.modelTurns == 1)
    }
}
