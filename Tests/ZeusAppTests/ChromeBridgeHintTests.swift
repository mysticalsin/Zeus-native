import Testing
@testable import Zeus

/// The bridge Chrome keeps alive only accepts the kind of Zeus build that shipped it, so the not-connected
/// message has to say what to do after a change of build kind.
@Suite("Chrome bridge not-connected hint")
struct ChromeBridgeHintTests {
    @Test func theNotConnectedMessageSaysToRestartChromeAfterChangingBuildKind() {
        let text = ChromeBridge.BridgeFailure.notConnected.errorDescription ?? ""
        #expect(text.contains("quit Chrome and open it again"))
        #expect(text.contains("preview and a release build"))
    }
}
