import Foundation
import Testing
@testable import ZeusCore

/// P0 item G: screen-edge HUD glow math (pure, no AppKit -- the panels live in
/// Sources/Zeus/Notch/ScreenEdgeGlowController.swift).
@Suite struct ScreenEdgeGlowTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    private func state(from: Double = 0.4, to: Double = 0.6, muted: Bool = false, at: Date? = nil) -> ScreenEdgeGlowState {
        .init(kind: .volume, fromLevel: from, toLevel: to, muted: muted, changedAt: at ?? t0)
    }

    @Test func opacityFadesInThenHoldsThenFadesOut() {
        let s = state()
        let start = ScreenEdgeGlowMath.frame(s, now: t0, reduceMotion: false)
        #expect(start.opacity == 0)
        #expect(start.isActive)

        let mid = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.fadeIn / 2), reduceMotion: false)
        #expect(mid.opacity > 0 && mid.opacity < 1)

        let held = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.fadeIn + 0.5), reduceMotion: false)
        #expect(held.opacity == 1)
        #expect(held.isActive)

        let fading = ScreenEdgeGlowMath.frame(
            s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.fadeIn + ScreenEdgeGlowMath.hold + ScreenEdgeGlowMath.fadeOut / 2),
            reduceMotion: false)
        #expect(fading.opacity > 0 && fading.opacity < 1)

        let done = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.totalDuration + 1), reduceMotion: false)
        #expect(done.opacity == 0)
        #expect(!done.isActive)
    }

    @Test func levelSpringsFromFromLevelTowardToLevel() {
        let s = state(from: 0.2, to: 0.8)
        let start = ScreenEdgeGlowMath.frame(s, now: t0, reduceMotion: false)
        #expect(abs(start.level - 0.2) < 0.001)
        let settled = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.levelSpring + 0.01), reduceMotion: false)
        #expect(abs(settled.level - 0.8) < 0.01)
        let partway = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.levelSpring / 2), reduceMotion: false)
        #expect(partway.level > 0.2 && partway.level < 0.8)
    }

    @Test func reduceMotionShowsTargetLevelImmediatelyNoSpring() {
        let s = state(from: 0.2, to: 0.8)
        let start = ScreenEdgeGlowMath.frame(s, now: t0, reduceMotion: true)
        #expect(abs(start.level - 0.8) < 0.001, "Reduce Motion: no travelling spring, just the target level")
        // Opacity envelope (fade in/hold/out) is unaffected by Reduce Motion.
        #expect(start.opacity == 0)
    }

    @Test func mutedCollapsesLevelTowardZero() {
        let s = state(from: 0.6, to: 0, muted: true)
        let held = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(ScreenEdgeGlowMath.fadeIn + ScreenEdgeGlowMath.levelSpring + 0.01), reduceMotion: false)
        #expect(held.level < 0.02)
    }

    @Test func startLevelContinuesAStillActiveLightInsteadOfRestarting() {
        let first = state(from: 0, to: 0.5, at: t0)
        // A second change arrives mid-animation of the first.
        let secondChangeAt = t0.addingTimeInterval(ScreenEdgeGlowMath.fadeIn + 0.1)
        let start = ScreenEdgeGlowMath.startLevel(previous: first, now: secondChangeAt, reduceMotion: false, fallback: 0.9)
        // The first light had already sprung to ~0.5 by then; the new light should continue from
        // there, not restart from the fallback (which would be used only if nothing was active).
        #expect(abs(start - 0.5) < 0.01)
    }

    @Test func startLevelUsesFallbackWhenNothingWasActive() {
        let longDone = state(from: 0, to: 0.5, at: t0)
        let farLater = t0.addingTimeInterval(ScreenEdgeGlowMath.totalDuration + 5)
        let start = ScreenEdgeGlowMath.startLevel(previous: longDone, now: farLater, reduceMotion: false, fallback: 0.9)
        #expect(abs(start - 0.9) < 0.001)
    }

    @Test func startLevelWithNoPreviousStateUsesFallback() {
        let start = ScreenEdgeGlowMath.startLevel(previous: nil, now: t0, reduceMotion: false, fallback: 0.33)
        #expect(abs(start - 0.33) < 0.001)
    }

    @Test func levelAndOpacityAreAlwaysClamped() {
        let s = ScreenEdgeGlowState(kind: .brightness, fromLevel: -5, toLevel: 50, muted: false, changedAt: t0)
        let f = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(1000), reduceMotion: false)
        #expect(f.level >= 0 && f.level <= 1)
        #expect(f.opacity >= 0 && f.opacity <= 1)
    }

    @Test func clockSkewBeforeChangedAtNeverGoesNegative() {
        let s = state(at: t0)
        let f = ScreenEdgeGlowMath.frame(s, now: t0.addingTimeInterval(-1), reduceMotion: false)
        #expect(f.opacity == 0)
        #expect(f.isActive)
    }
}
