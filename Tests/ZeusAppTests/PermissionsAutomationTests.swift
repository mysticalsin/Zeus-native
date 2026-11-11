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

    @Test func checkStartedBeforeAllowCannotOverwriteTheGrantOrDeleteTheSavedOne() {
        // A background check is mid-flight (it will report "would require consent"), the person clicks
        // Allow and the grant is stored, then the older check finishes. The grant must survive.
        Automation.resetCacheForTesting()
        let target = "com.spotify.client"
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        Automation.testStatusProvider = { id, ask in
            guard id == target, !ask else { return noErr }
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
            return OSStatus(errAEEventWouldRequireUserConsent)
        }
        _ = Automation.allowed(target)
        #expect(entered.wait(timeout: .now() + 2) == .success)
        Automation.promptAnswered(target, noErr)
        #expect(Automation.allowed(target))
        release.signal()
        Automation.waitForChecksToEndForTesting()
        #expect(Automation.allowed(target), "the older check must not replace the newer grant")
        #expect(Automation.grantIsRemembered(target), "the older check must not delete the saved grant")
        Automation.resetCacheForTesting()
    }
}
