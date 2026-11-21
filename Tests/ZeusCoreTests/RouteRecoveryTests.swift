import Testing
@testable import ZeusCore

@Suite struct RouteRecoveryTests {
    @Test func aPlaybackConfigurationChangeRewiresAndDoesNotCountTheLineFinished() {
        let decision = PlaybackGraphRecovery.afterConfigurationChange()
        #expect(decision.rewire)
        #expect(!decision.reportLineFinished)
    }

    @Test func aScribeOutputChangeRebuildsTheSystemTap() {
        #expect(ScribeOutputRoute.shouldRebuild(capturedUID: "speakers", currentUID: "headset"))
        #expect(!ScribeOutputRoute.shouldRebuild(capturedUID: "speakers", currentUID: "speakers"))
        #expect(ScribeOutputRoute.rejectsZeroSampleRate(0))
        #expect(!ScribeOutputRoute.rejectsZeroSampleRate(48_000))
    }
}
