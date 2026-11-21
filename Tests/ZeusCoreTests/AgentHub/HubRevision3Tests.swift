import Foundation
import Testing
@testable import ZeusCore

/// Revision 3 names for a hub decision: risk tier, action, key, and the countdown and undo windows.
/// The machine that applies them is not in this file.
@Suite("Hub revision 3 types")
struct HubRevision3Tests {
    @Test func tiersActionsKeysAndPausesRoundTrip() throws {
        try roundTrip(HubRiskTier.self, ["low", "high", "destructive"])
        #expect(HubRiskTier.allCases.map(\.title) == ["Low", "High", "Destructive"])

        try roundTrip(HubDecisionAction.self, ["allowOnce", "allowForThisSession", "deny", "denyWithNote"])
        #expect(HubDecisionAction.allCases.map(\.title) == [
            "Allow once", "Allow for this session", "Deny", "Deny with note",
        ])
        #expect(HubDecisionAction.allowOnce.isApproval)
        #expect(HubDecisionAction.allowForThisSession.isApproval)
        #expect(HubDecisionAction.deny.isApproval == false)
        #expect(HubDecisionAction.denyWithNote.isApproval == false)

        try roundTrip(HubDecisionKey.self, ["return", "two", "escape", "three", "four", "shiftEscape", "undo"])
        #expect(HubDecisionKey.return.action == .allowOnce)
        #expect(HubDecisionKey.two.action == .allowForThisSession)
        #expect(HubDecisionKey.escape.action == .deny)
        #expect(HubDecisionKey.three.action == .deny)
        #expect(HubDecisionKey.four.action == .denyWithNote)
        #expect(HubDecisionKey.shiftEscape.action == nil)
        #expect(HubDecisionKey.undo.action == nil)

        try roundTrip(HubCountdownPause.self, ["hover", "focus", "voiceOverFocus"])
        #expect(HubCountdownPause.allCases.map(\.title) == ["hover", "focus", "VoiceOver focus"])
    }

    @Test func countdownEndsInDenyAndTheWindowsAreFixed() {
        #expect(HubRevision3Timing.destructiveHoldMilliseconds == 1_200)
        #expect(HubRevision3Timing.countdownMilliseconds == 12_000)
        #expect(HubRevision3Timing.undoMilliseconds == 2_000)
        #expect(HubRevision3Timing.noteCharacterLimit == 280)
        #expect(HubRevision3Timing.countdownExpiry == .deny)
        #expect(HubRevision3Timing.countdownExpiry.isApproval == false)
        for action in HubDecisionAction.allCases where action.isApproval {
            #expect(action != HubRevision3Timing.countdownExpiry)
        }
    }

    @Test func keysMapOnlyWhileADecisionIsShowingAndNeverWithCommand() {
        #expect(HubDecisionKeys.decision(.return, command: false, decisionShowing: true) == .allowOnce)
        #expect(HubDecisionKeys.decision(.two, command: false, decisionShowing: true) == .allowForThisSession)
        #expect(HubDecisionKeys.decision(.escape, command: false, decisionShowing: true) == .deny)
        #expect(HubDecisionKeys.decision(.three, command: false, decisionShowing: true) == .deny)
        #expect(HubDecisionKeys.decision(.four, command: false, decisionShowing: true) == .denyWithNote)
        #expect(HubDecisionKeys.decision(.shiftEscape, command: false, decisionShowing: true) == nil)
        #expect(HubDecisionKeys.decision(.undo, command: false, decisionShowing: true) == nil)

        #expect(HubDecisionKeys.deniesAllQueued(key: .shiftEscape, command: false, decisionShowing: true))
        #expect(HubDecisionKeys.deniesAllQueued(key: .escape, command: false, decisionShowing: true) == false)
        #expect(HubDecisionKeys.undoes(key: .undo, command: false, undoShowing: true))
        #expect(HubDecisionKeys.undoes(key: .undo, command: false, undoShowing: false) == false)
        #expect(HubDecisionKeys.undoes(key: .return, command: false, undoShowing: true) == false)

        for key in HubDecisionKey.allCases {
            #expect(HubDecisionKeys.decision(key, command: false, decisionShowing: false) == nil)
            #expect(HubDecisionKeys.decision(key, command: true, decisionShowing: true) == nil)
            #expect(HubDecisionKeys.decision(key, command: true, decisionShowing: false) == nil)
            #expect(HubDecisionKeys.deniesAllQueued(key: key, command: true, decisionShowing: true) == false)
            #expect(HubDecisionKeys.deniesAllQueued(key: key, command: false, decisionShowing: false) == false)
            #expect(HubDecisionKeys.undoes(key: key, command: true, undoShowing: true) == false)
        }
    }

    private func roundTrip<T: HubStoredLabel>(_ type: T.Type, _ labels: [String]) throws {
        #expect(type.allCases.map(\.storedLabel) == labels)
        #expect(Set(labels).count == labels.count)
        for value in type.allCases {
            #expect(T(storedLabel: value.storedLabel) == value)
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(T.self, from: data) == value)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(value.storedLabel)\"")
        }
        #expect(type.init(storedLabel: "not-a-label") == nil)
        #expect(type.init(storedLabel: "") == nil)
    }
}
