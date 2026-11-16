import Foundation
import Testing
@testable import ZeusCore

/// The one table of motion tokens (docs/SMOOTH-MOTION-PLAN.md section 2) and the numbers it must meet.
@Suite("Motion tokens")
struct MotionTokensTests {
    /// What the app draws on close: the body goes from the recorded start height to the real closed body height (the
    /// notch plus the strip that hangs below it), with no time offset and no hidden end point.
    static var closedBodyHeight: Double { Double(GlanceTopBar.closedSize.height + NotchClosedBodyLayout.belowNotch) }

    static func closeRMS(response: Double, damping: Double) -> Double {
        let start = GlanceTopBar.measuredClose[0].height, end = closedBodyHeight
        let squares = GlanceTopBar.measuredClose.reduce(0.0) { sum, sample in
            let model = end + (start - end) * GlanceTopBar.springRemaining(at: sample.ms / 1000, response: response, damping: damping)
            return sum + (model - sample.height) * (model - sample.height)
        }
        return (squares / Double(GlanceTopBar.measuredClose.count)).squareRoot()
    }

    /// The old close: linear over 0.1 s from the same start to the same end.
    static func linearCloseRMS(duration: Double = 0.1) -> Double {
        let start = GlanceTopBar.measuredClose[0].height, end = closedBodyHeight
        let squares = GlanceTopBar.measuredClose.reduce(0.0) { sum, sample in
            let model = end + (start - end) * max(0, 1 - sample.ms / 1000 / duration)
            return sum + (model - sample.height) * (model - sample.height)
        }
        return (squares / Double(GlanceTopBar.measuredClose.count)).squareRoot()
    }

    /// Measured on the recorded samples (231 down to 38 pt, no offset): the old linear 0.1 s close is 19.4 pt rms off,
    /// the critically damped spring at response 0.175 is 12.5 pt rms off. The recording ends on a strip that fades, so
    /// the spring cannot match its tail; the gate is that it is clearly closer than linear, is the best response of
    /// a sweep (within a tenth of a point), never overshoots, only falls, and is done within a quarter second.
    @Test func theCloseSpringFitsTheMeasuredCloseBetterThanTheOldLinearClose() {
        let spring = MotionTokens.panelClose
        let rms = Self.closeRMS(response: spring.response, damping: spring.damping)
        let linear = Self.linearCloseRMS()
        #expect(rms < 0.75 * linear, "spring \(rms) pt rms, linear \(linear) pt rms")
        let best = stride(from: 0.06, through: 0.4, by: 0.005).map { Self.closeRMS(response: $0, damping: 1) }.min()!
        #expect(rms <= best + 0.1, "spring \(rms), best of the sweep \(best)")
        #expect(spring.damping >= 1)
        var previous = 1.0
        for frame in 0...600 {
            let remaining = GlanceTopBar.springRemaining(at: Double(frame) / 600, response: spring.response, damping: spring.damping)
            #expect(remaining >= -0.0001, "the close must not bounce")
            #expect(remaining <= previous + 1e-9, "the close only falls")
            previous = remaining
        }
        let distance = GlanceTopBar.measuredClose[0].height - Self.closedBodyHeight
        #expect(GlanceTopBar.settleTime(response: spring.response, damping: spring.damping, distance: distance, tolerance: 1) <= 0.25)
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
