import Foundation
import Testing
@testable import ZeusCore

/// The hub vocabulary. Names only: a stored label round-trips, and the words on screen are the ones the target names.
@Suite("Hub types")
struct HubTypesTests {
    @Test func sessionStatusRoundTripsThroughItsStoredLabel() throws {
        let labels = [
            "absent", "loading", "running", "waitingForInput", "needsApproval", "done", "error.failed", "error.quiet",
        ]
        #expect(HubSessionStatus.allCases.map(\.storedLabel) == labels)
        for status in HubSessionStatus.allCases {
            #expect(HubSessionStatus(storedLabel: status.storedLabel) == status)
            let data = try JSONEncoder().encode(status)
            #expect(try JSONDecoder().decode(HubSessionStatus.self, from: data) == status)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(status.storedLabel)\"")
        }
        #expect(HubSessionStatus(storedLabel: "not-a-status") == nil)
        #expect(HubSessionStatus(storedLabel: "error") == nil)
        #expect(HubSessionStatus(storedLabel: "") == nil)

        #expect(HubSessionStatus.running.visibleWord == "Running")
        #expect(HubSessionStatus.waitingForInput.visibleWord == "Question")
        #expect(HubSessionStatus.needsApproval.visibleWord == "Needs you")
        #expect(HubSessionStatus.done.visibleWord == "Done")
        #expect(HubSessionStatus.error(.failed).visibleWord == "Failed")
        #expect(HubSessionStatus.error(.quiet).visibleWord == "Failed")
        #expect(HubSessionStatus.visibleWords == ["Running", "Question", "Needs you", "Done", "Failed"])
        #expect(HubSessionStatus.loading.visibleWord == "Starting")
        #expect(HubSessionStatus.absent.visibleWord == nil)
        let drawn = Set(HubSessionStatus.allCases.compactMap(\.visibleWord))
        #expect(drawn == Set(HubSessionStatus.visibleWords + ["Starting"]))
        #expect(!drawn.contains("Quiet"))

        #expect(HubSessionStatus.absent.clockPhase == nil)
        #expect(HubSessionStatus.loading.clockPhase == .notStarted)
        #expect(HubSessionStatus.running.clockPhase == .ticking)
        #expect(HubSessionStatus.waitingForInput.clockPhase == .ticking)
        #expect(HubSessionStatus.needsApproval.clockPhase == .ticking)
        #expect(HubSessionStatus.done.clockPhase == .frozen)
        #expect(HubSessionStatus.error(.failed).clockPhase == .frozen)
        #expect(HubSessionStatus.error(.quiet).clockPhase == .frozen)
        #expect(HubSessionStatus.urgencyLabels == [
            "needsApproval", "error", "waitingForInput", "running", "done", "loading",
        ])
    }

    @Test func screenWordsStayDistinct() {
        #expect(HubScreen.empty.sentence == "Nothing running")
        #expect(HubScreen.empty.detail == "Start a session and it shows up here.")
        #expect(HubScreen.empty.actionTitle == "New session")
        #expect(HubScreen.loading.sentence == "Connecting…")
        #expect(HubScreen.loading.detail == nil)
        #expect(HubScreen.loading.actionTitle == nil)
        #expect(HubScreen.connectionError.sentence == "Agents aren't connected.")
        #expect(HubScreen.connectionError.detail == nil)
        #expect(HubScreen.connectionError.actionTitle == "Try again")
        #expect(HubScreen.ready.sentence == nil)
        #expect(HubScreen.ready.detail == nil)
        #expect(HubScreen.ready.actionTitle == nil)
        #expect(HubScreen.empty.sentence != HubScreen.connectionError.sentence)
        #expect(HubScreen.empty.actionTitle != HubScreen.connectionError.actionTitle)
    }

    @Test func causesScreensAndEventsRoundTripThroughStoredLabels() throws {
        try roundTrip(HubErrorCause.self, ["failed", "quiet"])
        try roundTrip(HubClockPhase.self, ["notStarted", "ticking", "frozen"])
        try roundTrip(HubSessionEvent.self, [
            "announced", "promptStarted", "ended", "toolActivity", "questionAsked", "approvalRequested",
            "finished", "failed", "quietForTheStallLimit", "answerAccepted", "approved", "denied", "timedOut",
            "dismissed", "activity",
        ])
        try roundTrip(HubScreen.self, ["empty", "loading", "ready", "connectionError"])
        try roundTrip(HubScreenEvent.self, [
            "socketOpenedNoSessions", "socketOpening", "atLeastOneSession", "sessionArrived", "lastSessionEnded",
            "socketFailed", "tryAgain", "socketOpened", "newChat",
        ])
        try roundTrip(HubScreenGuard.self, [
            "noSessions", "atLeastOneSession", "sessionsMayRemain", "chatTab", "sessionCount",
        ])
        try roundTrip(HubApprovalStatus.self, ["idle", "showing", "queued"])
        try roundTrip(HubApprovalEvent.self, ["request", "approve", "deny", "timeout", "ask", "showingClosed"])
        try roundTrip(HubApprovalVerdict.self, ["allow", "deny", "ask"])
        try roundTrip(HubTranscriptStatus.self, ["idle", "streaming", "settled", "failed"])
        try roundTrip(HubTranscriptEvent.self, ["send", "sendBlank", "delta", "finish", "finishEmpty", "stop", "failure"])
        try roundTrip(HubLineRole.self, ["person", "agent", "failed", "stopped"])
        try roundTrip(HubTranscriptNotice.self, ["No answer came back.", "Stopped"])
        try roundTrip(HubReplyStatus.self, ["idle", "drafting", "unsupported", "awaitingDecision", "sending", "failed"])
        try roundTrip(HubReplyEvent.self, [
            "textChanged", "send", "denied", "timedOut", "approved", "scriptTyped", "scriptFailed",
        ])
        try roundTrip(HubReplyGuard.self, ["emptyAfterCleaning", "destinationCannotTakeText", "destinationCanTakeText"])
        try roundTrip(HubReplyReceipt.self, [
            "Type something first.",
            "Not sent.",
            "Sent.",
            "This terminal can't take typed replies. Open it and reply there.",
            "I couldn't find that terminal tab. Open it and reply there.",
        ])
        try roundTrip(HubGroupStatus.self, ["collapsed", "expanded"])
        try roundTrip(HubGroupEvent.self, ["activateHeader", "sessionsChanged", "lostLastSession", "firstLoad"])
        try roundTrip(HubSoundStatus.self, ["silent", "armed", "playing"])
        try roundTrip(HubSoundEvent.self, ["optIn", "optOut", "cueAllowed", "cueSuppressed", "soundEnded"])
        try roundTrip(HubSoundCue.self, ["start", "done", "approval", "answer"])
        try roundTrip(HubSoundGuard.self, ["insideThreeSecondWindow", "finishUnderTwentySeconds", "startChimesOff"])
        try roundTrip(HubBannerEvent.self, ["failed", "quietError", "done", "needsApproval", "waitingForInput"])
        try roundTrip(HubFocusTarget.self, [
            "outside", "tabRow", "groupHeader", "row", "picker", "deny", "approve", "transcript", "copy", "reply", "send", "open",
        ])
        try roundTrip(HubFocusEvent.self, [
            "pageOpened", "activate", "up", "down", "return", "escape", "approveKey", "denyKey", "askKey",
        ])
        try roundTrip(HubFocusGuard.self, [
            "pickerClosed", "replyUnfocused", "listFocused", "fieldNonEmpty", "answerKeysOn", "pickerOpen", "rowSelected", "nothingSelected",
        ])
        #expect(HubFocusTarget.selectedApprovalOrder.map(\.storedLabel) == [
            "groupHeader", "row", "deny", "approve", "transcript", "reply", "send", "open",
        ])
        #expect(HubFocusTarget.screenOrder.map(\.storedLabel) == [
            "tabRow", "groupHeader", "row", "transcript", "copy", "reply", "send", "open",
        ])
    }

    private func roundTrip<T: HubStoredLabel>(_ type: T.Type, _ labels: [String]) throws {
        #expect(type.allCases.map(\.storedLabel) == labels)
        #expect(Set(labels).count == labels.count)
        for value in type.allCases {
            #expect(T(storedLabel: value.storedLabel) == value)
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(T.self, from: data) == value)
        }
        #expect(type.init(storedLabel: "not-a-label") == nil)
    }
}
