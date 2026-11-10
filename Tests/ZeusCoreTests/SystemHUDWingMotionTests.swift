import Testing
import ZeusCore

@Suite struct SystemHUDWingMotionTests {
    @Test func everyHudAnimateKindPassesFrameTiming() {
        for kind in SystemHUDWingMotion.AnimateKind.allCases {
            let issues = SystemHUDWingMotion.validateKind(kind)
            #expect(issues.isEmpty, "\(kind.rawValue): \(issues.map(\.message).joined(separator: "; "))")
        }
    }

    @Test func openFirstFrameStaysSmall() {
        let final = SystemHUDWingMotion.finalWidth(extraWidth: 58)
        let open = SystemHUDWingMotion.timeline(opening: true, extraWidth: 58)
        let issues = SystemHUDWingMotion.validateOpen(open, finalSize: final)
        #expect(issues.isEmpty)
    }

    @Test func closeDoesNotJumpToZero() {
        let final = SystemHUDWingMotion.finalWidth(extraWidth: 58)
        let close = SystemHUDWingMotion.timeline(opening: false, extraWidth: 58)
        let issues = SystemHUDWingMotion.validateClose(close, finalSize: final)
        #expect(issues.isEmpty)
    }
}
