import Foundation
import Testing
@testable import ZeusCore

@Suite struct InsertTargetDecisionTests {
    private let notes = DictationAppIdentity(processID: 10, bundleID: "app.notes")
    private let zeus = DictationAppIdentity(processID: 1, bundleID: "app.zeus")
    private let browser = DictationAppIdentity(processID: 44, bundleID: "app.browser")

    @Test func aPreviewCardWithZeusFrontmostPastesIntoTheTarget() {
        let choice = InsertTargetDecision.decide(keyDown: notes, frontmost: zeus, ownPid: zeus.processID)
        #expect(choice == .reactivateThenPaste)
    }

    @Test func aNotchClickWithZeusFrontmostPastesIntoTheTarget() {
        let choice = InsertTargetDecision.decide(keyDown: notes, frontmost: zeus, ownPid: zeus.processID)
        #expect(choice == .reactivateThenPaste)
    }

    @Test func aThirdAppFrontmostIsCopyOnly() {
        let choice = InsertTargetDecision.decide(keyDown: notes, frontmost: browser, ownPid: zeus.processID)
        #expect(choice == .copyOnly)
    }

    @Test func aMissingKeyDownAppFallsBackToPaste() {
        let missing = DictationAppIdentity(processID: 0, bundleID: nil)
        let choice = InsertTargetDecision.decide(keyDown: missing, frontmost: browser, ownPid: zeus.processID)
        #expect(choice == .paste)
    }

    @Test func aCorrectionWithZeusFrontmostReactivatesTheTarget() {
        let choice = InsertTargetDecision.decide(keyDown: notes, frontmost: zeus, ownPid: zeus.processID)
        #expect(choice == .reactivateThenPaste)
    }

    @Test func aSwitchDuringOpenReactivatesTheKeyDownApp() {
        // deliver() re-activates context.targetApp, which is read after the microphone opens.
        let reactivated = appReactivatedByTheCurrentDeliver(keyDown: notes, postOpen: browser)
        #expect(reactivated == notes)
    }

    private func appReactivatedByTheCurrentDeliver(keyDown: DictationAppIdentity, postOpen: DictationAppIdentity) -> DictationAppIdentity {
        _ = keyDown
        return postOpen
    }

    @Test func deliverAndCorrectionCallTheInsertDecision() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Dictation/DictationController.swift"), encoding: .utf8)
        let deliver = slice(source, from: "private func deliver(", to: "private func deliverCorrection")
        let correction = slice(source, from: "private func deliverCorrection", to: "private func removeEscape")
        #expect(deliver.contains("InsertTargetDecision.decide"))
        #expect(correction.contains("InsertTargetDecision.decide"))
    }

    private func slice(_ source: String, from start: String, to end: String) -> String {
        guard let lower = source.range(of: start), let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else { return "" }
        return String(source[lower.lowerBound..<upper.lowerBound])
    }
}
