import Testing
@testable import ZeusCore

@Suite struct DictationFocusRuleTests {
    @Test func aFocusChangeWithinTheSameAppTargetsThePostOpenField() {
        let keyDown = DictationAppIdentity(processID: 10, bundleID: "app.notes")
        let stillThatApp = DictationAppIdentity(processID: 10, bundleID: "app.notes")
        #expect(DictationFocusRule.choose(keyDown: keyDown, frontmost: stillThatApp) == .postOpenField)
    }

    @Test func theSameBundleWithAnotherPidIsTheSameApp() {
        let keyDown = DictationAppIdentity(processID: 10, bundleID: "app.notes")
        let relaunched = DictationAppIdentity(processID: 77, bundleID: "app.notes")
        #expect(keyDown.sameApp(as: relaunched))
        #expect(DictationFocusRule.choose(keyDown: keyDown, frontmost: relaunched) == .postOpenField)
    }

    @Test func anAppSwitchDuringOpenRefusesTheInsert() {
        let keyDown = DictationAppIdentity(processID: 10, bundleID: "app.notes")
        let other = DictationAppIdentity(processID: 44, bundleID: "app.browser")
        #expect(DictationFocusRule.choose(keyDown: keyDown, frontmost: other) == .copyInstead)
    }
}
