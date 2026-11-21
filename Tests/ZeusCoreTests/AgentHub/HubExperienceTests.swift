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
