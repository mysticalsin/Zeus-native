import Foundation
import Testing
@testable import ZeusCore

@Suite("Screen edge glow box")
struct ScreenEdgeGlowBoxTests {
    @Test func theEnvelopeIsFadeHoldAndFade() {
        #expect(ScreenEdgeGlowBox.fadeIn == 0.12)
        #expect(ScreenEdgeGlowBox.hold == 1.2)
        #expect(ScreenEdgeGlowBox.fadeOut == 0.25)
        #expect(ScreenEdgeGlowBox.levelSpring == 0.18)
        #expect(abs(ScreenEdgeGlowBox.totalDuration - 1.57) < 0.001)
    }

    @Test func aLevelOutsideZeroToOneIsClamped() {
        #expect(ScreenEdgeGlowBox.clampedLevel(-5) == 0)
        #expect(ScreenEdgeGlowBox.clampedLevel(0) == 0)
        #expect(ScreenEdgeGlowBox.clampedLevel(0.4) == 0.4)
        #expect(ScreenEdgeGlowBox.clampedLevel(1) == 1)
        #expect(ScreenEdgeGlowBox.clampedLevel(50) == 1)
    }

    @Test func aLevelThatIsNotFiniteUsesTheSameClamp() {
        #expect(ScreenEdgeGlowBox.clampedLevel(.nan) == 1)
        #expect(ScreenEdgeGlowBox.clampedLevel(.infinity) == 1)
        #expect(ScreenEdgeGlowBox.clampedLevel(-.infinity) == 0)
    }

    @Test func theEaseStartsFlatAndFinishesAtOne() {
        #expect(ScreenEdgeGlowBox.easeOutCubic(0) == 0)
        #expect(ScreenEdgeGlowBox.easeOutCubic(0.5) == 0.875)
        #expect(ScreenEdgeGlowBox.easeOutCubic(1) == 1)
        #expect(ScreenEdgeGlowBox.easeOutCubic(-2) == 0)
        #expect(ScreenEdgeGlowBox.easeOutCubic(3) == 1)
        #expect(ScreenEdgeGlowBox.easeOutCubic(.nan) == 1)
    }

    @Test func opacityFadesInHoldsThenFadesOut() {
        let start = frame(0)
        #expect(start.opacity == 0)
        #expect(start.isActive)

        let rising = frame(ScreenEdgeGlowBox.fadeIn / 2)
        #expect(abs(rising.opacity - 0.5) < 0.001)
        #expect(rising.isActive)

        let held = frame(ScreenEdgeGlowBox.fadeIn)
        #expect(held.opacity == 1)
        #expect(held.isActive)

        let stillHeld = frame(ScreenEdgeGlowBox.fadeIn + ScreenEdgeGlowBox.hold)
        #expect(stillHeld.opacity == 1)
        #expect(stillHeld.isActive)

        let fading = frame(ScreenEdgeGlowBox.fadeIn + ScreenEdgeGlowBox.hold + ScreenEdgeGlowBox.fadeOut / 2)
        #expect(abs(fading.opacity - 0.5) < 0.001)
        #expect(fading.isActive)

        let done = frame(ScreenEdgeGlowBox.totalDuration)
        #expect(done.opacity == 0)
        #expect(!done.isActive)

        let later = frame(ScreenEdgeGlowBox.totalDuration + 1)
        #expect(later.opacity == 0)
        #expect(!later.isActive)
    }

    @Test func theLevelSpringsTowardTheTarget() {
        let start = frame(0, from: 0.2, to: 0.8)
        #expect(abs(start.level - 0.2) < 0.001)

        let halfway = frame(ScreenEdgeGlowBox.levelSpring / 2, from: 0.2, to: 0.8)
        #expect(abs(halfway.level - 0.725) < 0.001)
        #expect(halfway.level > 0.2 && halfway.level < 0.8)

        let settled = frame(ScreenEdgeGlowBox.levelSpring, from: 0.2, to: 0.8)
        #expect(abs(settled.level - 0.8) < 0.001)
    }

    @Test func reduceMotionShowsTheTargetAtOnce() {
        let start = frame(0, from: 0.2, to: 0.8, reduceMotion: true)
        #expect(abs(start.level - 0.8) < 0.001)
        #expect(start.opacity == 0)
        #expect(start.isActive)

        let rising = frame(ScreenEdgeGlowBox.fadeIn / 2, from: 0.2, to: 0.8, reduceMotion: true)
        #expect(abs(rising.level - 0.8) < 0.001)
        #expect(abs(rising.opacity - 0.5) < 0.001)
    }

    @Test func aClockBeforeTheChangeReadsAsTheStart() {
        let early = frame(-1, from: 0.2, to: 0.8)
        #expect(early.opacity == 0)
        #expect(early.isActive)
        #expect(abs(early.level - 0.2) < 0.001)
    }

    @Test func anElapsedTimeThatIsNotFiniteReadsAsTheStart() {
        let missing = frame(.nan, from: 0.2, to: 0.8)
        #expect(missing.opacity == 0)
        #expect(missing.isActive)
        #expect(abs(missing.level - 0.2) < 0.001)
    }

    @Test func aFinishedGlowIsDarkAndStillAtTheTarget() {
        let finished = frame(.infinity, from: 0.2, to: 0.8)
        #expect(finished.opacity == 0)
        #expect(!finished.isActive)
        #expect(abs(finished.level - 0.8) < 0.001)
    }

    @Test func anActiveGlowContinuesFromTheLevelOnScreen() {
        #expect(ScreenEdgeGlowBox.continuedLevel(
            previousElapsed: nil, previousFrom: 0, previousTo: 0.5, reduceMotion: false, fallback: 0.33
        ) == 0.33)

        let continued = ScreenEdgeGlowBox.continuedLevel(
            previousElapsed: ScreenEdgeGlowBox.fadeIn + 0.1,
            previousFrom: 0, previousTo: 0.5, reduceMotion: false, fallback: 0.9
        )
        #expect(abs(continued - 0.5) < 0.01)

        let reduced = ScreenEdgeGlowBox.continuedLevel(
            previousElapsed: 0, previousFrom: 0.2, previousTo: 0.8, reduceMotion: true, fallback: 0.1
        )
        #expect(abs(reduced - 0.8) < 0.001)
    }

    @Test func nothingActiveUsesTheFallback() {
        let done = ScreenEdgeGlowBox.continuedLevel(
            previousElapsed: ScreenEdgeGlowBox.totalDuration + 5,
            previousFrom: 0, previousTo: 0.5, reduceMotion: false, fallback: 0.9
        )
        #expect(abs(done - 0.9) < 0.001)

        let runaway = ScreenEdgeGlowBox.continuedLevel(
            previousElapsed: .infinity, previousFrom: 0.2, previousTo: 0.8, reduceMotion: false, fallback: 1.4
        )
        #expect(runaway == 1.4)
    }

    private func frame(
        _ elapsed: Double, from: Double = 0.4, to: Double = 0.6, reduceMotion: Bool = false
    ) -> ScreenEdgeGlowBox.Frame {
        ScreenEdgeGlowBox.frame(elapsed: elapsed, fromLevel: from, toLevel: to, reduceMotion: reduceMotion)
    }
}
