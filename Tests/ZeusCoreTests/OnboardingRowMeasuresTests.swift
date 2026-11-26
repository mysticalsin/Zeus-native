import Testing
@testable import ZeusCore

@Suite("Onboarding row measures")
struct OnboardingRowMeasuresTests {
    @Test func rowsStartAHeadingGapBelowTheHeading() {
        #expect(OnboardingRowMeasures.rowsTopY == 236)
        #expect(OnboardingRowMeasures.rowPitch == 62)
    }

    @Test func rowCentresFollowThePitch() {
        #expect(OnboardingRowMeasures.rowCenterY(0, pitch: 88) == 280)
        #expect(OnboardingRowMeasures.rowCenterY(2, pitch: 88) == 456)
        #expect(OnboardingRowMeasures.rowsMidY(count: 3, pitch: 88) == OnboardingRowMeasures.rowCenterY(1, pitch: 88))
    }

    @Test func anEmptyBlockHasNoHeight() {
        let block = OnboardingRowMeasures.rowsBlock(count: 0)
        #expect(block.top == 236)
        #expect(block.height == 0)
        #expect(OnboardingRowMeasures.rowsBlock(count: -2).height == 0)
    }
}
