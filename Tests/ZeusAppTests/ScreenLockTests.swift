import Testing
@testable import Zeus

/// The event-free lock call never touches the real login framework here: the lock function is injected.
@Suite struct ScreenLockTests {
    @Test func aMissingLockFunctionReportsFailureAndPostsNothing() {
        #expect(ScreenLock.lockWithoutEvents(using: nil) == false)
    }

    @Test func aLockFunctionThatSucceedsReportsSuccess() {
        #expect(ScreenLock.lockWithoutEvents(using: { 0 }) == true)
    }

    @Test func aLockFunctionThatFailsReportsFailure() {
        #expect(ScreenLock.lockWithoutEvents(using: { 1 }) == false)
    }

    @Test func aFailedImmediateLockDoesNotPretendTheShortcutSucceeded() {
        var posted = false
        let ok = ScreenLock.lock(using: { 1 }) {
            posted = true
            return true
        }
        #expect(ok == false)
        #expect(posted == false)
    }
}
