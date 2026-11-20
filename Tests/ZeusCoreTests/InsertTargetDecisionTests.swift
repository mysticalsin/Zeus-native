import Foundation
import Testing
@testable import ZeusCore

@Suite struct InsertTargetDecisionTests {
    private let notes = DictationAppIdentity(processID: 10, bundleID: "app.notes")
    private let zeus = DictationAppIdentity(processID: 1, bundleID: "app.zeus")
    private let browser = DictationAppIdentity(processID: 44, bundleID: "app.browser")

    @Test func aSwitchDuringOpenReactivatesTheKeyDownApp() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: zeus.processID)
        #expect(route == .reactivate(notes))
    }

    @Test func aNotchClickReactivatesTheKeyDownAppWhileTheFieldStayed() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: notes, frontmost: zeus, ownPid: zeus.processID)
        #expect(route == .reactivate(notes))
    }

    @Test func aThirdAppFrontmostIsCopyOnly() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: notes, frontmost: browser, ownPid: zeus.processID)
        #expect(InsertTargetDecision.deliverEffect(route) == .copyOnly)
    }

    @Test func aMissingKeyDownAppFallsBackToPaste() {
        let missing = DictationAppIdentity(processID: 0, bundleID: nil)
        let route = InsertTargetDecision.route(keyDown: missing, postOpen: browser, frontmost: browser, ownPid: zeus.processID)
        #expect(route == .paste)
    }

    @Test func aMissingKeyDownAppReactivatesTheAppReadAfterOpen() {
        let missing = DictationAppIdentity(processID: 0, bundleID: nil)
        let route = InsertTargetDecision.route(keyDown: missing, postOpen: browser, frontmost: zeus, ownPid: zeus.processID)
        #expect(route == .reactivate(browser))
    }

    @Test func aCorrectionKeepsTheKeyDownApp() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: zeus.processID)
        #expect(InsertTargetDecision.correctionEffect(route) == .reactivate(notes))
    }

    @Test func aZeroOwnPidDoesNotTreatTheFrontmostAppAsZeus() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: 0)
        #expect(route == .copyOnly)
    }

    @Test func passingTheFrontmostPidTreatsThatAppAsZeus() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: notes, frontmost: browser, ownPid: browser.processID)
        #expect(route == .reactivate(notes))
    }
}
