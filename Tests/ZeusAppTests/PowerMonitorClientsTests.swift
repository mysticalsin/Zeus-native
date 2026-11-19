import Foundation
import Testing
@testable import Zeus

/// The keep-awake session and the music hold share one PowerMonitor. Either one stopping must not
/// switch the readings off for the other.
@Suite @MainActor struct PowerMonitorClientsTests {
    @Test func stopsOnlyWhenTheLastClientLeaves() {
        let monitor = PowerMonitor()
        monitor.start(for: .keepAwake)
        monitor.start(for: .music)
        #expect(monitor.isRunning)
        monitor.stop(for: .keepAwake)
        #expect(monitor.isRunning)
        monitor.stop(for: .music)
        #expect(!monitor.isRunning)
    }

    @Test func theMusicClientAloneKeepsItRunning() {
        let monitor = PowerMonitor()
        monitor.start(for: .music)
        monitor.start(for: .keepAwake)
        monitor.stop(for: .music)
        #expect(monitor.isRunning)
        monitor.stop(for: .keepAwake)
        #expect(!monitor.isRunning)
    }

    @Test func startingTwiceAndStoppingOnceStopsThatClient() {
        let monitor = PowerMonitor()
        monitor.start(for: .keepAwake)
        monitor.start(for: .keepAwake)
        monitor.stop(for: .keepAwake)
        #expect(!monitor.isRunning)
    }

    @Test func theDefaultClientIsTheKeepAwakeSession() {
        let monitor = PowerMonitor()
        monitor.start()
        monitor.start(for: .music)
        monitor.stop()
        #expect(monitor.isRunning)
        monitor.stop(for: .music)
        #expect(!monitor.isRunning)
    }
}
