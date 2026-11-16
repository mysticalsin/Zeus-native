import Foundation
import Testing
@testable import ZeusCore

/// The one table of motion tokens (docs/SMOOTH-MOTION-PLAN.md section 2) and the numbers it must meet.
@Suite("Motion tokens")
struct MotionTokensTests {
    private static func fitRMS(_ spring: SpringToken) -> Double {
        let start = GlanceTopBar.measuredClose[0].height
        let end = GlanceTopBar.measuredCloseEnd
        var squares = 0.0
        for sample in GlanceTopBar.measuredClose {
            let t = max(0, sample.ms / 1000 + GlanceTopBar.measuredCloseOffset)
            let model = end + (start - end) * GlanceTopBar.springRemaining(at: t, response: spring.response, damping: spring.damping)
            squares += (model - sample.height) * (model - sample.height)
        }
        return (squares / Double(GlanceTopBar.measuredClose.count)).squareRoot()
    }

    @Test func theCloseSpringFitsTheMeasuredCloseWithNoOvershoot() {
        let spring = MotionTokens.panelClose
        #expect(Self.fitRMS(spring) < 8, "rms \(Self.fitRMS(spring)) pt")
        let lowest = (0...600).map { GlanceTopBar.springRemaining(at: Double($0) / 600, response: spring.response, damping: spring.damping) }.min()!
        #expect(lowest > -0.0001, "the close must not bounce")
        #expect(spring.damping >= 1)
    }

    @Test func theCueSpringSettlesUnder120msOver120pt() {
        let spring = MotionTokens.cueGrow
        #expect(GlanceTopBar.settleTime(response: spring.response, damping: spring.damping, distance: 120) < 0.12)
        #expect(SystemHUDWingMotion.allKindsPass())
        #expect(NotchClosedBodyLayout.wingsSpringResponse == spring.response)
        #expect(NotchClosedBodyLayout.wingsSpringDamping == spring.damping)
    }

    @Test func theFirstFrameOfACueAt120HzIsUnderTenPercent() {
        let spring = MotionTokens.cueGrow
        let first = 1 - GlanceTopBar.springRemaining(at: 1.0 / 120, response: spring.response, damping: spring.damping)
        #expect(first < 0.10, "first frame \(first)")
    }

    @Test func everyDampingIsBetween075And1() {
        #expect(!MotionTokens.allSprings.isEmpty)
        for spring in MotionTokens.allSprings {
            #expect((0.75...1.0).contains(spring.damping), "damping \(spring.damping)")
            #expect(spring.response > 0)
        }
    }

    @Test func theExistingSpringsKeepTheirValues() {
        #expect(MotionTokens.panelOpen == SpringToken(response: 0.30, damping: 0.87))
        #expect(MotionTokens.panelOpenHeight == SpringToken(response: 0.105, damping: 1.0))
        #expect(MotionTokens.panelResize == SpringToken(response: 0.34, damping: 0.84))
        #expect(MotionTokens.peekContent == SpringToken(response: 0.34, damping: 0.82))
        #expect(MotionTokens.panelOpen.response == GlanceTopBar.openSpring.response)
        #expect(MotionTokens.panelOpenHeight.response == GlanceTopBar.openHeightSpring.response)
    }

    @Test func ambientLoopsRunAtADivisorOf120() {
        #expect(120 % MotionRules.ambientFPS == 0)
        #expect(MotionRules.ambientFPS == 60)
        #expect(MotionRules.spinnerFPS == 120)
        #expect(MotionRules.displayMaxFPS == 120)
    }

    @Test func theMascotRunsAtItsClipRateAndSixtyWhileTravelling() {
        for clip in [12.0, 20.0, 24.0] {
            #expect(MotionRules.fps(clipFPS: clip, travelling: false) == clip)
            #expect(MotionRules.fps(clipFPS: clip, travelling: true) == 60)
        }
    }

    @Test func theWindowFadesAndPageOutAreExplicit() {
        #expect(MotionTokens.windowFadeInDuration == 0.2)
        #expect(MotionTokens.windowFadeOutDuration == 0.25)
        #expect(MotionTokens.pageOutDuration == 0.08)
        #expect(MotionTokens.crossfadeDuration == 0.12)
        #expect(MotionTokens.peekContentDelay == 0.1)
    }
}
