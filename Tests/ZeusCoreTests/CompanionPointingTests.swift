import Foundation
import Testing
@testable import ZeusCore

@Suite("Companion display changes and accessible labels")
struct CompanionPointingTests {
    private let before = [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
        DisplayMap(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 2),
    ]
    private let moved = [
        DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1),
        DisplayMap(id: 2, frame: CGRect(x: -1600, y: -100, width: 1920, height: 1080), scale: 2),
    ]

    @Test func movingDisplayDuringFlightKeepsLandingAndPointingAtTheSameTarget() throws {
        let flight = CompanionFlight.plan(from: CGPoint(x: 100, y: 300), to: CGPoint(x: -500, y: 400))
        let original = CompanionPointingGeometry(flight: flight, target: flight.to,
            position: flight.sample(at: 0.3).position,
            ringFrame: CGRect(x: -520, y: 380, width: 40, height: 40), strikeCenter: flight.to)
        let rebased = try #require(original.rebased(from: before, to: moved))
        let shiftedFlight = try #require(rebased.flight)
        let nextPointingTarget = try #require(rebased.target)
        // Arrival and the next pointing tick must agree, not snap back to the old display coordinates.
        #expect(shiftedFlight.sample(at: shiftedFlight.duration).position == nextPointingTarget)
        #expect(nextPointingTarget == CGPoint(x: -180, y: 300))
        #expect(rebased.ringFrame == CGRect(x: -200, y: 280, width: 40, height: 40))
        #expect(rebased.strikeCenter == nextPointingTarget)
        #expect(shiftedFlight.duration == flight.duration)
        #expect(rebased.position == CGPoint(x: original.position.x + 320, y: original.position.y - 100))
    }

    @Test func movingDisplayAfterArrivalMovesTheLabelTargetAndRingTogether() throws {
        let original = CompanionPointingGeometry(flight: nil, target: CGPoint(x: -500, y: 400),
            position: CGPoint(x: -500, y: 400),
            ringFrame: CGRect(x: -520, y: 380, width: 40, height: 40), strikeCenter: CGPoint(x: -500, y: 400))
        let rebased = try #require(original.rebased(from: before, to: moved))
        #expect(rebased.flight == nil)
        #expect(rebased.position == rebased.target)
        #expect(rebased.position == CGPoint(x: -180, y: 300))
        #expect(rebased.ringFrame?.midX == rebased.position.x)
        #expect(rebased.ringFrame?.midY == rebased.position.y)
    }

    @Test func unpluggingTheTargetDoesNotAdoptAReplacementDisplayAtTheSameCoordinates() {
        let flight = CompanionFlight.plan(from: .zero, to: CGPoint(x: -500, y: 400))
        let original = CompanionPointingGeometry(flight: flight, target: flight.to, position: .zero,
            ringFrame: nil, strikeCenter: .zero)
        let replacement = [before[0], DisplayMap(id: 99, frame: before[1].frame, scale: 2)]
        #expect(original.rebased(from: before, to: [before[0]]) == nil)
        #expect(original.rebased(from: before, to: replacement) == nil)
    }

    @Test func changingAnotherDisplayDoesNotShiftThisTarget() {
        let target = CGPoint(x: 500, y: 400)
        let original = CompanionPointingGeometry(flight: nil, target: target, position: target,
            ringFrame: nil, strikeCenter: target)
        #expect(original.rebased(from: before, to: moved) == original)
    }

    @Test func reducedMotionShowsTheWholeUnicodeLabelAtArrival() {
        let text = "Choose 👩🏽‍💻 Café"
        let label = CompanionPointingLabel(text: text, beganAt: 50, reduceMotion: true)
        #expect(label.visibleText == text)
        #expect(label.isComplete)
    }

    @Test func enablingReducedMotionMidLabelDoesNotWaitForTheNextCharacterDeadline() {
        var label = CompanionPointingLabel(text: "Save changes", beganAt: 10, reduceMotion: false)
        label.advance(at: 10.2, reduceMotion: false, characterDelay: 0.06)
        #expect(label.visibleText == "S")
        label.advance(at: 10.21, reduceMotion: true, characterDelay: 0.06)
        #expect(label.visibleText == "Save changes")
        #expect(label.isComplete)
        label.advance(at: 11, reduceMotion: false, characterDelay: 0.06)
        #expect(label.visibleText == "Save changes")
    }

    @Test func normalLabelKeepsItsDelayAndEmptyLabelsAreAlreadyComplete() {
        var label = CompanionPointingLabel(text: "Go", beganAt: 10, reduceMotion: false)
        label.advance(at: 10.1, reduceMotion: false, characterDelay: 0.04)
        #expect(label.visibleText.isEmpty)
        label.advance(at: 10.2, reduceMotion: false, characterDelay: 0.04)
        #expect(label.visibleText == "G")
        label.advance(at: 10.21, reduceMotion: false, characterDelay: 0.04)
        #expect(label.visibleText == "G")
        label.advance(at: 10.3, reduceMotion: false, characterDelay: 0.04)
        #expect(label.visibleText == "Go")
        #expect(CompanionPointingLabel(text: "", beganAt: 0, reduceMotion: false).isComplete)
    }
}
