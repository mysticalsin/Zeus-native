import Foundation
import Testing
@testable import ZeusCore

/// The hub experience contract. Focus order, the labels the list, transcript, and decision views match,
/// Reduce Motion, and the open and idle budgets.
@Suite("Hub experience")
struct HubExperienceTests {
    @Test func selectedSessionWithAnApprovalUsesTheNamedFocusOrder() {
        let order = HubExperience.focusOrder(sessionSelected: true, approvalShowing: true)
        #expect(order == [
            .groupHeader, .row, .deny, .approve, .transcript, .reply, .send, .open,
        ])
        #expect(order.reversed() == [
            .open, .send, .reply, .transcript, .approve, .deny, .row, .groupHeader,
        ])
        #expect(order.map { HubExperience.accessibilityLabel(for: $0) } == [
            nil, nil,
            HubAccessibilityLabel.deny,
            HubAccessibilityLabel.approve,
            HubAccessibilityLabel.transcript,
            HubAccessibilityLabel.reply,
            HubAccessibilityLabel.send,
            HubAccessibilityLabel.open,
        ])

        #expect(HubExperience.focusOrder(sessionSelected: true, approvalShowing: false) == [
            .groupHeader, .row, .transcript, .copy, .reply, .send, .open,
        ])
        #expect(HubExperience.focusOrder(sessionSelected: false, approvalShowing: true) == [
            .groupHeader, .row, .deny, .approve,
        ])
        #expect(HubExperience.focusOrder(sessionSelected: false, approvalShowing: false) == [
            .groupHeader, .row,
        ])
    }

    @Test func reduceMotionRequestsZeroOffsetAndScaleOne() {
        let reduced = HubExperience.motionRequest(reduceMotion: true)
        #expect(reduced.offset == 0)
        #expect(reduced.scale == 1)

        let moving = HubExperience.motionRequest(reduceMotion: false)
        #expect(HubExperience.pageRisePoints == 8)
        #expect(HubExperience.pageScale == 0.985)
        #expect(moving.offset == HubExperience.pageRisePoints)
        #expect(moving.scale == HubExperience.pageScale)

        #expect(HubExperience.pressScale(reduceMotion: true) == 1)
        #expect(HubExperience.pressScale(reduceMotion: false) == MotionTokens.pressScale)

        #expect(HubExperience.waveMoves(status: .running, reduceMotion: true) == false)
        #expect(HubExperience.waveMoves(status: .running, reduceMotion: false))
        for status in HubSessionStatus.allCases where status != .running {
            #expect(HubExperience.waveMoves(status: status, reduceMotion: false) == false)
            #expect(HubExperience.waveMoves(status: status, reduceMotion: true) == false)
        }
    }

    @Test func openAndIdleBudgetsHoldAtTheBudgetAndFailOnePastIt() {
        let open = HubExperience.openBudgetMilliseconds
        #expect(open == 100)
        #expect(HubExperience.meetsOpenBudget(milliseconds: open))
        #expect(HubExperience.meetsOpenBudget(milliseconds: open + 1) == false)
        #expect(HubExperience.meetsOpenBudget(milliseconds: -1) == false)

        let idle = HubExperience.idleBudgetPercentOfOneCore
        #expect(idle == 1)
        #expect(HubExperience.meetsIdleBudget(percentOfOneCore: idle))
        #expect(HubExperience.meetsIdleBudget(percentOfOneCore: idle + 1) == false)
        #expect(HubExperience.meetsIdleBudget(percentOfOneCore: idle + 0.1) == false)
        #expect(HubExperience.meetsIdleBudget(percentOfOneCore: -0.1) == false)
        #expect(HubExperience.meetsIdleBudget(percentOfOneCore: .nan) == false)
        #expect(HubExperience.meetsIdleBudget(percentOfOneCore: .infinity) == false)

        #expect(HubExperience.isIdle(closedPanel(percentOfOneCore: idle)))
        #expect(HubExperience.isIdle(closedPanel(percentOfOneCore: idle + 1)) == false)
    }

    @Test func theIdlePredicateIsFalseWhenAOneSecondTimerIsScheduledWhileThePanelIsClosed() {
        #expect(HubExperience.clockTickSeconds == 1)
        let scheduled = closedPanel(percentOfOneCore: 0, oneSecondTimerScheduled: true)
        #expect(scheduled.panelClosed)
        #expect(scheduled.oneSecondTimerScheduled)
        #expect(HubExperience.isIdle(scheduled) == false)
        #expect(HubExperience.isIdle(closedPanel(
            percentOfOneCore: HubExperience.idleBudgetPercentOfOneCore,
            oneSecondTimerScheduled: true
        )) == false)

        #expect(HubExperience.isIdle(closedPanel(percentOfOneCore: 0, approvalShowing: true)) == false)
        #expect(HubExperience.isIdle(closedPanel(percentOfOneCore: 0, socketReadInProgress: true)) == false)
        #expect(HubExperience.isIdle(closedPanel(percentOfOneCore: 0, waveDisplayLinkRunning: true)) == false)

        var openPanel = closedPanel(percentOfOneCore: 0)
        openPanel.panelClosed = false
        #expect(HubExperience.isIdle(openPanel) == false)
    }

    @Test func accessibilityLabelsAreTheWordsTheViewsMatch() {
        #expect(HubAccessibilityLabel.deny == "Deny")
        #expect(HubAccessibilityLabel.approve == "Approve")
        #expect(HubAccessibilityLabel.transcript == "Transcript")
        #expect(HubAccessibilityLabel.copy == "Copy code")
        #expect(HubAccessibilityLabel.reply == "Reply")
        #expect(HubAccessibilityLabel.send == "Send")
        #expect(HubAccessibilityLabel.open == "Open")
        #expect(HubAccessibilityLabel.dismiss == "Dismiss")
        let fixed = [
            HubAccessibilityLabel.deny, HubAccessibilityLabel.approve, HubAccessibilityLabel.transcript,
            HubAccessibilityLabel.copy, HubAccessibilityLabel.reply, HubAccessibilityLabel.send,
            HubAccessibilityLabel.open, HubAccessibilityLabel.dismiss,
        ]
        #expect(Set(fixed).count == fixed.count)

        #expect(HubExperience.accessibilityLabel(for: .deny) == HubAccessibilityLabel.deny)
        #expect(HubExperience.accessibilityLabel(for: .approve) == HubAccessibilityLabel.approve)
        #expect(HubExperience.accessibilityLabel(for: .transcript) == HubAccessibilityLabel.transcript)
        #expect(HubExperience.accessibilityLabel(for: .copy) == HubAccessibilityLabel.copy)
        #expect(HubExperience.accessibilityLabel(for: .reply) == HubAccessibilityLabel.reply)
        #expect(HubExperience.accessibilityLabel(for: .send) == HubAccessibilityLabel.send)
        #expect(HubExperience.accessibilityLabel(for: .open) == HubAccessibilityLabel.open)
        #expect(HubExperience.accessibilityLabel(for: .groupHeader) == nil)
        #expect(HubExperience.accessibilityLabel(for: .row) == nil)
        #expect(HubExperience.accessibilityLabel(for: .tabRow) == nil)
        #expect(HubExperience.accessibilityLabel(for: .picker) == nil)
        #expect(HubExperience.accessibilityLabel(for: .outside) == nil)

        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "project", status: .running, elapsedSeconds: 192
        ) == "Agent, project, Running, 3 minutes 12 seconds")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "project", status: .running, elapsedSeconds: 192, hidesProject: true
        ) == "Agent, Running, 3 minutes 12 seconds")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "payments-api", status: .loading, elapsedSeconds: nil
        ) == "Agent, payments-api, Announced")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "", status: .done, elapsedSeconds: 60
        ) == "Agent, Done, 1 minute")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "infra", status: .done, elapsedSeconds: 1
        ) == "Agent, infra, Done, 1 second")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "infra", status: .done, elapsedSeconds: 0
        ) == "Agent, infra, Done, 0 seconds")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent", project: "infra", status: .done, elapsedSeconds: 3661
        ) == "Agent, infra, Done, 1 hour 1 minute 1 second")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent B", project: "web-client", status: .error(.quiet), elapsedSeconds: 360
        ) == "Agent B, web-client, Error, 6 minutes")
        #expect(HubExperience.sessionRowLabel(
            agent: "Agent B", project: "web-client", status: .error(.failed), elapsedSeconds: 52
        ) == "Agent B, web-client, Error, 52 seconds")

        #expect(HubExperience.groupHeaderLabel(
            name: "Agent A", count: 2, urgentStatus: .needsApproval, elapsedSeconds: 192, expanded: true
        ) == "Agent A, Needs approval, 2 sessions, expanded")
        #expect(HubExperience.groupHeaderLabel(
            name: "Agent B", count: 1, urgentStatus: .error(.quiet), elapsedSeconds: 52, expanded: false
        ) == "Agent B, Error, 1 session, 52 seconds, collapsed")
        #expect(HubExperience.groupHeaderLabel(
            name: "Agent C", count: 1, urgentStatus: .loading, elapsedSeconds: nil, expanded: false
        ) == "Agent C, Announced, 1 session, collapsed")
    }

    /// Revision 3 decision contract. The row matches these labels, keys, windows, and identifiers.
    /// ZB-UIUX-A11Y-030, 032, 033, 034, ZB-UIUX-ESCAPE-001, and ZB-UIUX-DECISION-001.
    @Test func revision3NamesTheDecisionActionsKeysAndIdentifiers() {
        #expect(HubExperience.revision3DecisionOrder() == [
            "Allow once", "Allow for this session", "Deny", "Deny with note",
        ])
        #expect(HubExperience.revision3CountdownExpiresByApproving == false)
        #expect(HubExperience.revision3CountdownSeconds == 12)
        #expect(HubExperience.revision3UndoSeconds == 2)
        #expect(HubExperience.revision3DestructiveHoldSeconds == 1.2)
        #expect(HubExperience.revision3NoteCharacterLimit == 280)
        #expect(HubExperience.revision3CountdownAnimates(reduceMotion: true) == false)
        #expect(HubExperience.revision3CountdownAnimates(reduceMotion: false))
        #expect(HubExperience.revision3CountdownTextRemains(reduceMotion: true))
        let still = HubExperience.revision3Motion(reduceMotion: true)
        #expect(still.offset == 0)
        #expect(still.scale == 1)
        let moving = HubExperience.revision3Motion(reduceMotion: false)
        #expect(moving.offset == HubExperience.pageRisePoints)
        #expect(moving.scale == HubExperience.pageScale)
        #expect(HubExperience.revision3CommandKeyIsShortcut == false)
        #expect(HubExperience.revision3KeysActive(decisionShowing: false) == false)
        #expect(HubExperience.revision3KeysActive(decisionShowing: true))
        #expect(HubExperience.revision3Key("return", command: false, decisionShowing: true) == "Allow once")
        #expect(HubExperience.revision3Key("2", command: false, decisionShowing: true) == "Allow for this session")
        #expect(HubExperience.revision3Key("escape", command: false, decisionShowing: true) == "Deny")
        #expect(HubExperience.revision3Key("3", command: false, decisionShowing: true) == "Deny")
        #expect(HubExperience.revision3Key("4", command: false, decisionShowing: true) == "Deny with note")
        #expect(HubExperience.revision3Key("shiftEscape", command: false, decisionShowing: true) == "Deny all queued")
        #expect(HubExperience.revision3Key("u", command: false, decisionShowing: true) == nil)
        #expect(HubExperience.revision3Key("u", command: false, undoShowing: true) == "Undo")
        #expect(HubExperience.revision3Key("return", command: true, decisionShowing: true) == nil)
        #expect(HubExperience.revision3Key("escape", command: true, decisionShowing: true) == nil)
        #expect(HubExperience.revision3Key("escape", command: false, decisionShowing: false) == nil)
        #expect(HubExperience.revision3PauseReasons == ["hover", "focus", "VoiceOver focus"])
        #expect(HubExperience.revision3QueueCount(1) == "1 waiting")
        #expect(HubExperience.revision3QueueCount(2) == "2 waiting")
        #expect(HubExperience.revision3CountdownSentence(seconds: 12, paused: false) == "12 s left, then it's denied.")
        let paused = HubExperience.revision3CountdownSentence(seconds: 12, paused: true)
        #expect(paused.contains("paused"))
        #expect(paused.contains("denied."))
        #expect(paused.contains("approv") == false)
        #expect(HubExperience.revision3Identifier(forFinding: "ZB-UIUX-DECISION-001") == "hub.decision.row")
        #expect(HubExperience.revision3Identifier(forFinding: "ZB-UIUX-A11Y-030") == "hub.decision.allow-once")
        #expect(HubExperience.revision3Identifier(forFinding: "ZB-UIUX-A11Y-034") == "hub.decision.allow-once")
        #expect(HubExperience.revision3Identifier(forFinding: "ZB-UIUX-A11Y-032") == "hub.decision.deny.hidden")
        #expect(HubExperience.revision3Identifier(forFinding: "ZB-UIUX-A11Y-033") == "hub.decision.deny")
        #expect(HubExperience.revision3Identifier(forFinding: "ZB-UIUX-ESCAPE-001") == "hub.decision.deny")
        #expect(HubExperience.revision3VoiceOverLabel(forIdentifier: "hub.decision.allow-once") == "Allow once")
        #expect(HubExperience.revision3VoiceOverLabel(forIdentifier: "hub.decision.allow-session") == "Allow for this session")
        #expect(HubExperience.revision3VoiceOverLabel(forIdentifier: "hub.decision.deny") == "Deny")
        #expect(HubExperience.revision3VoiceOverLabel(forIdentifier: "hub.decision.deny.hidden") == "Deny")
        #expect(HubExperience.revision3VoiceOverLabel(forIdentifier: "hub.decision.deny-note") == "Deny with note")
        #expect(HubExperience.revision3VoiceOverLabel(forIdentifier: "hub.decision.row") == "Decision")
    }

    private func closedPanel(
        percentOfOneCore: Double,
        oneSecondTimerScheduled: Bool = false,
        approvalShowing: Bool = false,
        socketReadInProgress: Bool = false,
        waveDisplayLinkRunning: Bool = false
    ) -> HubIdleSample {
        HubIdleSample(
            panelClosed: true,
            approvalShowing: approvalShowing,
            socketReadInProgress: socketReadInProgress,
            oneSecondTimerScheduled: oneSecondTimerScheduled,
            waveDisplayLinkRunning: waveDisplayLinkRunning,
            percentOfOneCore: percentOfOneCore
        )
    }
}
