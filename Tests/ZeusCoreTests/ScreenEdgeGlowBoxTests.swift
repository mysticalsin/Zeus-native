import Foundation
import Testing
@testable import ZeusCore

@Suite("Screen edge glow box")
struct ScreenEdgeGlowBoxTests {
    @Test func theEnvelopeUsesTheHudTimings() {
        #expect(ScreenEdgeGlowBox.fadeIn == 0.12)
        #expect(ScreenEdgeGlowBox.hold == 1.2)
        #expect(ScreenEdgeGlowBox.fadeOut == 0.25)
        #expect(ScreenEdgeGlowBox.levelSpring == 0.18)
        #expect(ScreenEdgeGlowBox.totalDuration == ScreenEdgeGlowBox.fadeIn + ScreenEdgeGlowBox.hold + ScreenEdgeGlowBox.fadeOut)
    }

    @Test func theLightIsOffAtTheInstantOfTheChange() {
        let sample = ScreenEdgeGlowBox.sample(fromLevel: 0.2, toLevel: 0.8, elapsed: 0, reduceMotion: false)
        #expect(sample.level == 0.2)
        #expect(sample.opacity == 0)
        #expect(sample.isActive)
    }

    @Test func opacityClimbsThroughTheFadeIn() {
        let sample = ScreenEdgeGlowBox.sample(
            fromLevel: 0.4, toLevel: 0.6, elapsed: ScreenEdgeGlowBox.fadeIn / 2, reduceMotion: false
        )
        #expect(sample.opacity == 0.5)
        #expect(sample.isActive)
    }

    @Test func theHoldStaysFullyLit() {
        let sample = ScreenEdgeGlowBox.sample(
            fromLevel: 0.4, toLevel: 0.6, elapsed: ScreenEdgeGlowBox.fadeIn + ScreenEdgeGlowBox.hold / 2, reduceMotion: false
        )
        #expect(sample.opacity == 1)
        #expect(sample.isActive)
    }

    @Test func opacityFallsThroughTheFadeOut() {
        let elapsed = ScreenEdgeGlowBox.fadeIn + ScreenEdgeGlowBox.hold + ScreenEdgeGlowBox.fadeOut / 2
        let sample = ScreenEdgeGlowBox.sample(fromLevel: 0.4, toLevel: 0.6, elapsed: elapsed, reduceMotion: false)
        #expect(abs(sample.opacity - 0.5) < 0.000_001)
        #expect(sample.isActive)
    }

    @Test func theLightIsGoneWhenTheEnvelopeEnds() {
        let done = ScreenEdgeGlowBox.sample(
            fromLevel: 0.4, toLevel: 0.6, elapsed: ScreenEdgeGlowBox.totalDuration, reduceMotion: false
        )
        #expect(done.opacity == 0)
        #expect(abs(done.level - 0.6) < 0.000_001)
        #expect(!done.isActive)
        let later = ScreenEdgeGlowBox.sample(fromLevel: 0.4, toLevel: 0.6, elapsed: 4, reduceMotion: false)
        #expect(later.opacity == 0)
        #expect(!later.isActive)
    }

    @Test func theLevelEasesOutTowardTheTarget() {
        let half = ScreenEdgeGlowBox.sample(
            fromLevel: 0.2, toLevel: 0.8, elapsed: ScreenEdgeGlowBox.levelSpring / 2, reduceMotion: false
        )
        #expect(abs(half.level - 0.725) < 0.000_001)
        let arrived = ScreenEdgeGlowBox.sample(
            fromLevel: 0.2, toLevel: 0.8, elapsed: ScreenEdgeGlowBox.levelSpring, reduceMotion: false
        )
        #expect(arrived.level == 0.8)
    }

    @Test func reduceMotionJumpsToTheTargetAndStillFades() {
        let start = ScreenEdgeGlowBox.sample(fromLevel: 0.2, toLevel: 0.8, elapsed: 0, reduceMotion: true)
        #expect(start.level == 0.8)
        #expect(start.opacity == 0)
        #expect(start.isActive)
        let held = ScreenEdgeGlowBox.sample(fromLevel: 0.2, toLevel: 0.8, elapsed: 0.62, reduceMotion: true)
        #expect(held.level == 0.8)
        #expect(held.opacity == 1)
    }

    @Test func aLevelOutsideZeroToOneIsClamped() {
        let start = ScreenEdgeGlowBox.sample(fromLevel: -5, toLevel: 50, elapsed: 0, reduceMotion: false)
        #expect(start.level == 0)
        let target = ScreenEdgeGlowBox.sample(fromLevel: -5, toLevel: 50, elapsed: 0, reduceMotion: true)
        #expect(target.level == 1)
        let settled = ScreenEdgeGlowBox.sample(fromLevel: -5, toLevel: 50, elapsed: 2, reduceMotion: false)
        #expect(settled.level == 1)
        #expect(settled.opacity == 0)
    }

    @Test func aNegativeElapsedReadsAsTheStart() {
        let sample = ScreenEdgeGlowBox.sample(fromLevel: 0.25, toLevel: 0.75, elapsed: -1, reduceMotion: false)
        #expect(sample.level == 0.25)
        #expect(sample.opacity == 0)
        #expect(sample.isActive)
    }

    @Test func anActiveLightContinuesFromTheLevelAlreadyOnScreen() {
        let continued = ScreenEdgeGlowBox.startLevel(
            fromLevel: 0, toLevel: 0.5, elapsed: ScreenEdgeGlowBox.fadeIn + 0.1, reduceMotion: false, fallback: 0.9
        )
        #expect(continued == 0.5)
    }

    @Test func aFinishedLightUsesTheFallback() {
        let restart = ScreenEdgeGlowBox.startLevel(
            fromLevel: 0, toLevel: 0.5, elapsed: ScreenEdgeGlowBox.totalDuration + 5, reduceMotion: false, fallback: 0.9
        )
        #expect(restart == 0.9)
        let untouched = ScreenEdgeGlowBox.startLevel(
            fromLevel: 0.2, toLevel: 0.8, elapsed: ScreenEdgeGlowBox.totalDuration, reduceMotion: true, fallback: 0.33
        )
        #expect(untouched == 0.33)
    }
}
