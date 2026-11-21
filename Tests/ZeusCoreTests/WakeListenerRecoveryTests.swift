import Testing
@testable import ZeusCore

@Suite struct WakeListenerRecoveryTests {
    @Test func stopRemovesTheTapEvenWhenTheEngineAlreadyStopped() {
        #expect(WakeListenerRecovery.stopRemovesTap(engineRunning: false))
        #expect(WakeListenerRecovery.stopRemovesTap(engineRunning: true))
    }

    @Test func aConfigurationChangeDropsTheListenerSoItCanStartAgain() {
        let decision = WakeListenerRecovery.afterConfigurationChange()
        #expect(decision.removeTap)
        #expect(decision.dropListener)
    }
}
