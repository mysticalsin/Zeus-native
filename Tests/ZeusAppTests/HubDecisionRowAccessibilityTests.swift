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
}
