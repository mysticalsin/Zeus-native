import Foundation
import Testing
@testable import ZeusCore

@Suite struct PenRevealTests {
    private let elbow = [
        PenPoint(x: 0, y: 0),
        PenPoint(x: 16, y: 0),
        PenPoint(x: 16, y: 16),
    ]

    @Test func aStillPenDrawsNothingUntilAudioMoves() {
        #expect(show(0) == [])
    }

    @Test func theStrokeFollowsArcLength() {
        #expect(show(0.25) == [PenPoint(x: 0, y: 0), PenPoint(x: 8, y: 0)])
        #expect(show(0.5) == [PenPoint(x: 0, y: 0), PenPoint(x: 16, y: 0)])
        #expect(show(0.75) == [PenPoint(x: 0, y: 0), PenPoint(x: 16, y: 0), PenPoint(x: 16, y: 8)])
        let doubled = [PenPoint(x: 0, y: 0), PenPoint(x: 0, y: 0), PenPoint(x: 16, y: 0)]
        #expect(show(0.5, points: doubled) == [PenPoint(x: 0, y: 0), PenPoint(x: 8, y: 0)])
    }

    @Test func theEndAndPastItKeepEveryPoint() {
        #expect(show(1) == elbow)
        #expect(show(1.25) == elbow)
    }

    @Test func reduceMotionDrawsTheWholeStrokeAtOnce() {
        #expect(show(0, reduceMotion: true) == elbow)
        #expect(show(0.25, reduceMotion: true) == elbow)
    }

    @Test func aChangedScreenDropsTheStep() {
        #expect(show(1, screen: 2, currentScreen: 1) == nil)
        #expect(show(1, reduceMotion: true, screen: 1, currentScreen: 4) == nil)
        #expect(show(0, screen: 3, currentScreen: 3) == [])
    }

    @Test func thePointCapDropsTheStep() {
        let capped = (0..<PenReveal.maxPoints).map { PenPoint(x: Double($0), y: 0) }
        #expect(show(1, points: capped)?.count == PenReveal.maxPoints)
        let over = capped + [PenPoint(x: Double(PenReveal.maxPoints), y: 0)]
        #expect(show(1, points: over) == nil)
        #expect(show(1, reduceMotion: true, points: over) == nil)
    }

    @Test func aDotAZeroLengthStrokeAndANonFinitePointDrop() {
        #expect(show(1, points: [PenPoint(x: 1, y: 1)]) == nil)
        #expect(show(1, points: []) == nil)
        #expect(show(1, points: [PenPoint(x: 2, y: 2), PenPoint(x: 2, y: 2)]) == nil)
        #expect(show(1, points: [PenPoint(x: 0, y: 0), PenPoint(x: .nan, y: 1)]) == nil)
        #expect(show(1, points: [PenPoint(x: 0, y: 0), PenPoint(x: .infinity, y: 4)]) == nil)
    }

    @Test func aNegativeOrNonFiniteProgressDrops() {
        #expect(show(-0.01) == nil)
        #expect(show(.nan) == nil)
        #expect(show(.infinity) == nil)
        #expect(show(-1, reduceMotion: true) == nil)
    }

    private func show(
        _ progress: Double,
        reduceMotion: Bool = false,
        screen: Int = 1,
        currentScreen: Int = 1,
        points: [PenPoint]? = nil
    ) -> [PenPoint]? {
        PenReveal.stroke(
            points ?? elbow,
            progress: progress,
            reduceMotion: reduceMotion,
            screen: screen,
            currentScreen: currentScreen)
    }
}
