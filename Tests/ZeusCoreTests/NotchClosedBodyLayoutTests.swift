import CoreGraphics
import Testing
import ZeusCore

@Suite struct NotchClosedBodyLayoutTests {
    @Test func hudCueExpandsClosedBodyWidth() {
        let narrow = NotchClosedBodyLayout.bodyWidth(
            notchWidth: 185, shoulder: 0, showWings: false, extraWidth: 0, hasNotch: true, slimPill: false)
        let wide = NotchClosedBodyLayout.bodyWidth(
            notchWidth: 185, shoulder: 0, showWings: true, extraWidth: 58, hasNotch: true, slimPill: false)
        #expect(narrow == 185)
        #expect(wide > narrow)
        #expect(wide - narrow > 100)
    }

    @Test func wingsSpringTargetsUnder120ms() {
        #expect(NotchClosedBodyLayout.wingsSpringResponse <= 0.12)
    }

    @Test func showWingsWhenHudLightsAppear() {
        #expect(NotchClosedBodyLayout.showWings(closedWingKindIsNone: true, hasLights: true, hasLiveActivity: false))
        #expect(!NotchClosedBodyLayout.showWings(closedWingKindIsNone: true, hasLights: false, hasLiveActivity: false))
    }
}
