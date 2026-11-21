import Foundation
import Testing
@testable import ZeusCore

@Suite struct InsertTargetDecisionTests {
    private let notes = DictationAppIdentity(processID: 10, bundleID: "app.notes")
    private let zeus = DictationAppIdentity(processID: 1, bundleID: "app.zeus")
    private let browser = DictationAppIdentity(processID: 44, bundleID: "app.browser")

    @Test func aPasteUsesTheKeyDownAppNotTheAppAfterOpen() {
        let planned = InsertTargetDecision.plan(keyDown: notes, postOpen: browser, frontmost: notes, ownPid: zeus.processID)
        #expect(planned.action == .paste)
        #expect(planned.app == notes)
    }

    @Test func aSwitchDuringOpenReactivatesTheKeyDownApp() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: zeus.processID)
        #expect(route == .reactivate(notes))
    }

    @Test func aNotchClickReactivatesTheKeyDownAppWhileTheFieldStayed() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: notes, frontmost: zeus, ownPid: zeus.processID)
        #expect(route == .reactivate(notes))
    }

    @Test func aKeyDownAppWithoutABundleIdDoesNotPasteIntoTheNextApp() {
        let unnamed = DictationAppIdentity(processID: 10, bundleID: nil)
        let route = InsertTargetDecision.route(keyDown: unnamed, postOpen: nil, frontmost: browser, ownPid: zeus.processID)
        #expect(route == .copyOnly)
    }

    @Test func aThirdAppFrontmostIsCopyOnly() {
        let planned = InsertTargetDecision.plan(keyDown: notes, postOpen: notes, frontmost: browser, ownPid: zeus.processID)
        #expect(planned.action == .copyOnly)
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
        let planned = InsertTargetDecision.correctionPlan(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: zeus.processID)
        #expect(planned.action == .reactivate)
        #expect(planned.app == notes)
    }

    @Test func aZeroOwnPidDoesNotTreatTheFrontmostAppAsZeus() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: 0)
        #expect(route == .copyOnly)
    }

    @Test func aFrontmostPidOfZeroIsNotThisProcess() {
        let unnamed = DictationAppIdentity(processID: 0, bundleID: "app.unknown")
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: notes, frontmost: unnamed, ownPid: 0)
        #expect(route == .copyOnly)
    }

    @Test func deliverKeepsAReactivate() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: browser, frontmost: zeus, ownPid: zeus.processID)
        #expect(InsertTargetDecision.deliverEffect(route) == .reactivate(notes))
    }

    @Test func correctionKeepsPasteAndCopyOnly() {
        #expect(InsertTargetDecision.correctionEffect(.paste) == .paste)
        #expect(InsertTargetDecision.correctionEffect(.copyOnly) == .copyOnly)
        #expect(InsertTargetDecision.correctionEffect(.reactivate(notes)) == .reactivate(notes))
    }

    @Test func passingTheFrontmostPidTreatsThatAppAsZeus() {
        let route = InsertTargetDecision.route(keyDown: notes, postOpen: notes, frontmost: browser, ownPid: browser.processID)
        #expect(route == .reactivate(notes))
    }

    @Test func deliverCopyOnlyReturnsBeforeItActivates() throws {
        let deliver = try functionSource("private func deliver(", "private func deliverCorrection")
        let copyOnly = slice(deliver, from: "case .copyOnly:", to: "case .paste:")
        #expect(copyOnly.contains("return .copiedOnly"))
        #expect(!copyOnly.contains("activate()"))
        #expect(deliver.contains("ownPid: ownProcessID()"))
        #expect(!deliver.contains("ownPid: 0"))
        #expect(!deliver.contains("ownPid: frontmost"))
        #expect(!deliver.contains("ownPid: live.processID"))
    }

    @Test func beginKeepsPasteBackOnTheKeyDownApp() throws {
        let begin = try functionSource("func begin() {", "func injectDictationFile")
        let keyDown = try #require(begin.range(of: "let keyDownApp"))
        let laterRead = try #require(begin.range(of: "seams.contextRead"))
        #expect(keyDown.lowerBound < laterRead.lowerBound)
        #expect(begin.contains("pasteBackApp: frontmost"))
        #expect(!begin.contains("pasteBackApp: readApp"))
        #expect(!begin.contains("pasteBackApp: read.targetApp"))
    }

    @Test func correctionStillActivatesWhenThePlanSaysReactivate() throws {
        let correction = try functionSource("private func deliverCorrection", "private func removeEscape")
        #expect(correction.contains("InsertTargetDecision.correctionPlan"))
        #expect(correction.contains("planned.action == .reactivate"))
        #expect(correction.contains("app.activate()"))
    }

    private func functionSource(_ start: String, _ end: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Dictation/DictationController.swift"), encoding: .utf8)
        return slice(source, from: start, to: end)
    }

    private func slice(_ source: String, from start: String, to end: String) -> String {
        guard let lower = source.range(of: start), let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else { return "" }
        return String(source[lower.lowerBound..<upper.lowerBound])
    }
}
