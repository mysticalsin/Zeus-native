import Testing
@testable import ZeusCore

@Suite("Accessibility revoked at runtime")
struct AccessWatchTests {
    @Test func aGrantThenARevokeIsReportedOnce() {
        var watch = AccessWatch()
        #expect(watch.sample(false) == nil)
        #expect(watch.sample(true) == .granted)
        #expect(watch.sample(true) == nil)
        #expect(watch.sample(false) == .revoked)
        #expect(watch.sample(false) == nil)
        #expect(watch.phase == .denied)
    }

    @Test func grantingAgainAfterARevokeStartsFeaturesAgain() {
        var watch = AccessWatch()
        #expect(watch.sample(true) == .granted)
        #expect(watch.sample(false) == .revoked)
        #expect(watch.sample(true) == .granted)
    }
}
