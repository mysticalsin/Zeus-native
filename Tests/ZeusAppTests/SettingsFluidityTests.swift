import Foundation
import Testing
@testable import Zeus
import ZeusCore

/// Settings must open instantly and stay fluid: whatever a page asks while it draws (and whatever
/// runs when the window opens) answers from memory and never waits on the disk, a daemon or the OS.
/// Budgets are generous so a busy CI machine passes; a blocking call per row misses them by far.
@Suite @MainActor struct SettingsFluidityTests {
    private func elapsed(_ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        return clock.measure(work)
    }

    @Test func integrationRowsAnswerFromMemory() {
        let services = OnboardingServices(permissions: PermissionsModel())
        let connections = AIConnections.shared
        let time = elapsed {
            for _ in 0..<200 {
                for provider in AIProvider.allCases {
                    _ = connections.status(provider, services: services)
                    _ = connections.detail(provider, services: services)
                }
            }
        }
        #expect(time < .milliseconds(500), "AI rows must not read hook files while drawing (took \(time))")
    }

    @Test func launchAtLoginSwitchDrawsFromTheCacheNotTheService() {
        let defaults = UserDefaults(suiteName: "zeus.fluidity.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        let binding = store.boolBinding(SettingsStore.launchAtLoginID)
        let time = elapsed { for _ in 0..<5_000 { _ = binding.wrappedValue } }
        #expect(time < .milliseconds(250), "reading the switch must not query SMAppService (took \(time))")
        #expect(binding.wrappedValue == store.bool(SettingsStore.launchAtLoginID))
    }

    @Test func openingSettingsDoesNotWaitOnDiskProbes() {
        let services = OnboardingServices(permissions: PermissionsModel())
        let time = elapsed { for _ in 0..<20 { services.refresh() } }
        #expect(time < .milliseconds(750), "refresh runs on window open and must hand disk reads to a background task (took \(time))")
    }
}
