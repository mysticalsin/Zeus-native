import Testing
@testable import Zeus

/// Allow all must open the sweep from the access it already has. Waiting on a fresh TCC read
/// leaves the button looking dead and the line stuck at "0 of 12 allowed".
@MainActor
@Suite("Allow all starts from the access it already has")
struct PermissionSweepStartTests {
    @Test func theLineDoesNotClaimZeroBeforeTheFirstRead() {
        let runner = PermissionSweepRunner(services: OnboardingServices(permissions: PermissionsModel()))
        #expect(runner.progressLine == "Checking permissions…")
    }

    @Test func allowAllStartsTheFirstPromptWithoutReadingAgain() async {
        let runner = PermissionSweepRunner(services: OnboardingServices(permissions: PermissionsModel()))
        let asked = AskedItems()
        runner.testingAsk = { asked.items.append($0) }
        runner.start()
        #expect(runner.isRunning)
        for _ in 0..<8 {
            if !asked.items.isEmpty { break }
            await Task.yield()
        }
        #expect(asked.items == [.microphone])
    }
}

@MainActor
private final class AskedItems {
    var items: [PermissionSweep.Item] = []
}
