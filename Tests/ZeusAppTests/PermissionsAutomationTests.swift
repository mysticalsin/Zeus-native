import Foundation
import Testing
@testable import Zeus

@Suite("Automation permission checks", .serialized)
@MainActor
struct PermissionsAutomationTests {
    @Test func refreshReturnsPromptlyWhenStatusCheckHangs() async {
        Automation.resetCacheForTesting()
        var calls = 0
        let target = "com.spotify.client"
        Automation.testStatusProvider = { id, _ in
            guard id == target else { return noErr }
            calls += 1
            Thread.sleep(forTimeInterval: 3)
            return noErr
        }
        let model = PermissionsModel()
        let start = ContinuousClock.now
        _ = Automation.allowed(target)
        let elapsed = start.duration(to: ContinuousClock.now)
        #expect(elapsed < .milliseconds(400))
        model.refresh()
        #expect(model.automationPending || model.granted[.automation] != true)
        let firstCalls = calls
        _ = Automation.allowed(target)
        model.refresh()
        #expect(calls == firstCalls)
        Automation.resetCacheForTesting()
    }

    @Test func pendingStateDoesNotStartParallelChecks() async {
        Automation.resetCacheForTesting()
        var calls = 0
        let target = "com.spotify.client"
        Automation.testStatusProvider = { id, _ in
            guard id == target else { return noErr }
            calls += 1
            Thread.sleep(forTimeInterval: 3)
            return noErr
        }
        _ = Automation.allowed(target)
        var started = 0
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(25))
            started = calls
            if started >= 1 { break }
        }
        #expect(started == 1)
        _ = Automation.allowed(target)
        #expect(calls == started)
        try? await Task.sleep(for: .milliseconds(1050))
        #expect(Automation.anyPending)
        let afterTimeout = calls
        for _ in 0..<4 { _ = Automation.allowed(target) }
        #expect(calls == afterTimeout)
        Automation.resetCacheForTesting()
    }
}
