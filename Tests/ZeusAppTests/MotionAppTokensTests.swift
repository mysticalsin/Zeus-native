import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// The app side of the motion token table: views read `Motion`, and `Motion` reads `MotionTokens`.
@Suite("Motion app tokens")
@MainActor
struct MotionAppTokensTests {
    @Test func theCloseIsTheCriticallyDampedPanelSpring() {
        #expect(TopBarStyle.closeMotion == .spring(response: 0.165, dampingFraction: 1.0))
        #expect(Motion.panelClose == TopBarStyle.closeMotion)
    }

    @Test func theCueWingsUseTheCueGrowToken() {
        #expect(NotchView.wingsSpring == .spring(response: 0.12, dampingFraction: 0.90))
        #expect(Motion.cueGrow == NotchView.wingsSpring)
    }

    @Test func aTokenSpringIsInstantUnderReduceMotion() {
        #expect(Motion.spring(MotionTokens.panelClose, reduceMotion: true) == nil)
        #expect(Motion.spring(MotionTokens.panelClose, reduceMotion: false) != nil)
        #expect(Motion.page(reduceMotion: true) == nil)
    }

    @Test func thePageSpringIsThePanelResizeToken() {
        #expect(Motion.pageResponse == MotionTokens.panelResize.response)
        #expect(Motion.pageDamping == MotionTokens.panelResize.damping)
        #expect(Motion.page(reduceMotion: false) == .spring(response: 0.34, dampingFraction: 0.84))
    }

    @Test func peekContentIsOneSpringWithATenthOfASecondDelay() {
        #expect(Motion.peekContent == .spring(response: 0.34, dampingFraction: 0.82).delay(0.1))
    }

    @Test func pageOutAndTheWindowFadesComeFromTheTable() {
        #expect(Motion.pageOut == .easeOut(duration: 0.08))
        #expect(Motion.crossfadeDuration == MotionTokens.crossfadeDuration)
        #expect(Motion.feedbackDuration == MotionTokens.pressDuration)
        #expect(Motion.pressedScale == CGFloat(MotionTokens.pressScale))
        #expect(Motion.windowFadeIn == MotionTokens.windowFadeInDuration)
        #expect(Motion.windowFadeOut == MotionTokens.windowFadeOutDuration)
    }

    @Test func ambientLoopsUseTheTableRates() {
        #expect(Motion.ambientFPS == MotionRules.ambientFPS)
        #expect(Motion.spinnerFPS == MotionRules.spinnerFPS)
    }
}
