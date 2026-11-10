import CoreGraphics
import Testing
import ZeusCore

@Suite("Onboarding chrome layout")
struct OnboardingChromeLayoutTests {
    @Test func brandAndHeadingShareLeadingEdge() {
        #expect(OnboardingChromeLayout.leadingEdge == 48)
        #expect(OnboardingChromeLayout.headingTopY == 168)
    }

    @Test func welcomePreviewCenterKeepsCardInsideWindow() {
        let frame = OnboardingChromeLayout.welcomePreviewFrame()
        #expect(frame.maxX <= OnboardingChromeLayout.windowWidth - OnboardingChromeLayout.trailingMargin)
        #expect(OnboardingChromeLayout.previewFitsWindow(at: 1))
    }
}

@Suite("Persona compliance")
struct PersonaComplianceTests {
    private let forbidden = [
        "something like wear",
        "I feel tired",
        "there is something like fatigue",
        "I am frustrated",
        "I need rest",
    ]

    @Test func cannedRepliesAvoidFeelingLanguage() {
        for sample in forbidden {
            #expect(PersonaCompliance.violatesFeelingClaim(sample), "expected violation in: \(sample)")
        }
        #expect(!PersonaCompliance.violatesFeelingClaim("Two meetings and one reminder."))
    }
}

@Suite("Onboarding row grid (R24)")
struct OnboardingRowGridTests {
    private typealias L = OnboardingChromeLayout

    @Test func rowsStartAHeadingGapBelowTheHeading() {
        #expect(L.rowsTopY == L.headingTopY + L.headingHeight + L.headingToRows)
        #expect(L.rowsTopY == 236)
    }

    @Test func rowCentresFollowThePitch() {
        let first = L.rowCenterY(0, pitch: 88)
        let third = L.rowCenterY(2, pitch: 88)
        #expect(first == 280, "first row centre \(first)")
        #expect(third == 456, "third row centre \(third)")
        #expect(L.rowsMidY(count: 3, pitch: 88) == L.rowCenterY(1, pitch: 88))
    }

    @Test func rowBlocksOfTheRowStepsFillTheWindow() {
        // day (3 x 88), halo (4 x 66), sounds (5 x 62), control (3 x 84), reach (4 x 66)
        for (count, pitch) in [(3, CGFloat(88)), (4, 66), (5, 62), (3, 84), (4, 66)] {
            let block = L.rowsBlock(count: count, pitch: pitch)
            #expect(L.fillFraction(rowsBottom: block.top + block.height) >= L.minimumFillFraction)
            #expect(block.top + block.height < L.footerTopY)
        }
    }

    @Test func welcomeHeroSitsInTheRightColumn() {
        let frame = L.welcomePreviewFrame()
        #expect(frame.minY == L.headingTopY)
        #expect(frame.maxY < L.footerTopY)
        #expect(frame.minX >= L.columnTrailingX)
    }
}
