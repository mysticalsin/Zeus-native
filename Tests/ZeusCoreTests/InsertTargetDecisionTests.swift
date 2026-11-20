import Foundation
import Testing

/// What 2d6760c2 does: any frontmost app other than the key-down app is copy-only.
/// Zeus in front is treated as that other app. These expectations are the insert rule we want.
private struct InsertApp: Equatable {
    var processID: Int32
    var bundleID: String?
    func sameApp(as other: InsertApp) -> Bool {
        if processID != 0, processID == other.processID { return true }
        if let bundleID, let otherID = other.bundleID, bundleID == otherID { return true }
        return false
    }
}

private enum InsertChoice: Equatable {
    case paste
    case reactivateThenPaste
    case copyOnly
}

private enum InsertTargetDecision {
    static func decide(keyDown: InsertApp, frontmost: InsertApp, ownPid: Int32) -> InsertChoice {
        _ = ownPid
        return keyDown.sameApp(as: frontmost) ? .paste : .copyOnly
    }
}

@Suite struct InsertTargetDecisionTests {
    private let notes = InsertApp(processID: 10, bundleID: "app.notes")
    private let zeus = InsertApp(processID: 1, bundleID: "app.zeus")
    private let browser = InsertApp(processID: 44, bundleID: "app.browser")

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
        let missing = InsertApp(processID: 0, bundleID: nil)
        let choice = InsertTargetDecision.decide(keyDown: missing, frontmost: browser, ownPid: zeus.processID)
        #expect(choice == .paste)
    }

    @Test func aCorrectionWithZeusFrontmostReactivatesTheTarget() {
        let choice = InsertTargetDecision.decide(keyDown: notes, frontmost: zeus, ownPid: zeus.processID)
        #expect(choice == .reactivateThenPaste)
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
