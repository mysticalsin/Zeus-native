import Foundation
import Testing
@testable import Zeus

/// Revision 3 of the inline decision row. The labels, the keys, and Reduce Motion
/// are the contract. The row does not approve when the countdown ends.
@Suite("Hub decision row revision 3")
struct HubDecisionRowAccessibilityTests {
    @Test func theRowNamesAllowOnceAllowForThisSessionDenyAndDenyWithNote() {
        #expect(HubDecisionRow.ownedAccessibilityLabels(showingApproval: true) == [
            "Allow once",
            "Allow for this session",
            "Deny",
            "Deny with note",
            "Reply",
            "Send",
        ])
        #expect(HubDecisionRow.ownedAccessibilityLabels(showingApproval: false) == ["Reply", "Send"])
        let contract = HubDecisionRow.accessibilityContractLabel
        #expect(contract.contains("Allow once"))
        #expect(contract.contains("Allow for this session"))
        #expect(contract.contains("Deny with note"))
        #expect(contract.contains("Approve") == false)
        #expect(contract.hasPrefix("group header, row, "))
    }

    @Test func keysAreReturnTwoEscapeAndUndoAndCommandIsNotAShortcut() {
        let deny = HubDecisionContract.denyHint(answerKeysOn: true)
        let allow = HubDecisionContract.approveHint(answerKeysOn: true, allowsAsk: true)
        #expect(deny.contains("Escape"))
        #expect(deny.contains("3"))
        #expect(allow.contains("Return"))
        #expect(deny.contains("Control-Option") == false)
        #expect(allow.contains("Control-Option") == false)
        #expect(deny.contains("Command") == false)
        #expect(allow.contains("Command") == false)
        #expect(HubDecisionContract.approveHint(answerKeysOn: false, allowsAsk: false).contains("Command") == false)
    }

    @Test func reduceMotionKeepsZeroOffsetScaleOneAndTheDenialSentence() {
        let still = HubDecisionRow.motion(reduceMotion: true)
        #expect(still.offset == 0)
        #expect(still.scale == 1)
        #expect(HubDecisionRow.motion(reduceMotion: false).offset == 8)
        #expect(HubDecisionRow.motion(reduceMotion: false).scale == 0.985)
        #expect(HubDecisionRow.animates(reduceMotion: true) == false)
        #expect(HubDecisionRow.animates(reduceMotion: false))
        #expect(HubDecisionRow.countdown(12) == "12 s left, then it's denied.")
        #expect(HubDecisionRow.countdown(12).contains("approv") == false)
        #expect(HubDecisionRow.countdown(0) == "0 s left, then it's denied.")
        #expect(HubDecisionRow.denyIsDefaultAction == false)
        #expect(HubDecisionRow.approveIsDefaultAction == false)
        #expect(HubDecisionRow.sendIsDefaultAction == false)
        #expect(HubDecisionRow.askIsButton == false)
        #expect(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 1) == "1 waiting")
        #expect(HubDecisionRow.queuedHint(thisRowIsQueued: false, count: 2) == "2 waiting")
    }

    /// ZB-UIUX-A11Y-030, 032, 033, 034: the approval controls had no accessibility identifier.
    /// ZB-UIUX-DECISION-001: a decision row had none either.
    /// ZB-UIUX-ESCAPE-001: Escape was not bound. Revision 3 binds Escape and 3 to Deny.
    @Test func eachControlHasAStableIdentifierAndEscapeDenies() throws {
        let source = try rowSource()
        let identifiers = [
            ("hub.decision.row", "ZB-UIUX-DECISION-001"),
            ("hub.decision.allow-once", "ZB-UIUX-A11Y-030"),
            ("hub.decision.allow-once", "ZB-UIUX-A11Y-034"),
            ("hub.decision.deny.hidden", "ZB-UIUX-A11Y-032"),
            ("hub.decision.deny", "ZB-UIUX-A11Y-033"),
            ("hub.decision.allow-session", "ZB-UIUX-A11Y-034"),
            ("hub.decision.deny-note", "ZB-UIUX-A11Y-033"),
        ]
        for (identifier, finding) in identifiers {
            #expect(source.contains(identifier), "missing \(identifier) for \(finding)")
            #expect(source.contains(finding), "missing finding \(finding)")
            #expect(source.contains(".accessibilityIdentifier(\(identifierLiteral(identifier)))"))
        }
        #expect(source.contains("ZB-UIUX-ESCAPE-001"))
        #expect(source.contains("kVK_Escape"))
        #expect(source.contains("kVK_ANSI_3"))
        #expect(HubDecisionContract.denyHint(answerKeysOn: true).contains("Escape"))
        #expect(HubDecisionContract.denyHint(answerKeysOn: true).contains("3"))
    }

    private func identifierLiteral(_ identifier: String) -> String {
        "\"\(identifier)\""
    }

    private func rowSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Zeus/Agents/Hub/HubDecisionRow.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
