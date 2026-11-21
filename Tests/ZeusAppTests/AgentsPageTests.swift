import Foundation
import Testing
#if canImport(ZeusCore)
import ZeusCore
#endif
#if canImport(Zeus)
@testable import Zeus
#else
@testable import HubPage
#endif

/// The Agents page from the tab and from Home: empty, connecting, connection error,
/// groups, a selected row, an approval that grows, and an error whose Dismiss becomes Done.
@Suite("Agents page")
struct AgentsPageTests {
    @Test func emptyCopyIsTheHubSentence() {
        let copy = AgentsPage.fresh().copy
        #expect(copy.sentence == "Nothing running")
        #expect(copy.detail == "Start a chat and it shows up here.")
        #expect(copy.actionTitle == "New chat")
    }

    @Test func connectingAndConnectionErrorAreNotEmpty() {
        let connecting = page(.connecting)
        #expect(connecting.copy.sentence == "Connecting…")
        #expect(connecting.copy.actionTitle == nil)
        #expect(connecting.phase == .connecting)

        let error = page(.connectionError)
        #expect(error.copy.sentence == "Agents aren't connected.")
        #expect(error.copy.actionTitle == "Try again")
        #expect(error.showsTryAgain)
        #expect(error.copy.sentence != "Nothing running")
        #expect(error.phase == .connectionError)
    }

    @Test func openingTheSocketMovesEmptyToConnecting() {
        let next = page(.empty).applying(.socketOpening)
        #expect(next.phase == .connecting)
        #expect(next.screen.screen == .loading)
        #expect(next.copy.sentence == "Connecting…")
        #expect(!next.openedWindow)
    }

    @Test func aFailedSocketIsConnectionErrorWithTryAgain() {
        let next = page(.connecting).applying(.socketFailed("The socket closed."))
        #expect(next.phase == .connectionError)
        #expect(next.screen.reason == "The socket closed.")
        #expect(next.showsTryAgain)
        #expect(next.copy.sentence == "Agents aren't connected.")
        #expect(!next.openedWindow)
    }

    @Test func noSessionsAndAFailedSocketIsNotEmpty() {
        let next = page(.connecting).applying(.socketFailed("The socket closed."))
        #expect(next.screen.screen == .connectionError)
        #expect(next.screen.screen != .empty)
    }

    @Test func tryAgainReturnsToConnecting() {
        let next = page(.connectionError).applying(.tryAgain)
        #expect(next.phase == .connecting)
        #expect(next.screen.reason == nil)
        #expect(!next.showsTryAgain)
    }

    @Test func homeAndTheTabShowTheSamePage() {
        let start = page(.groups)
        let home = start.applying(.show(.home))
        let tab = start.applying(.show(.tab))
        #expect(home.phase == tab.phase)
        #expect(home.screen == tab.screen)
        #expect(home.roster == tab.roster)
        #expect(home.groups == tab.groups)
        #expect(home.entry == .home)
        #expect(tab.entry == .tab)
    }

    @Test func openJumpsAndDoesNotOpenAWindow() {
        let next = page(.groups).applying(.open("s1"))
        #expect(next.jumpSessionID == "s1")
        #expect(!next.openedWindow)
        #expect(!AgentsPage.opensNewWindow)
        #expect(next.phase == .groups)
    }

    @Test func anApprovalGrowsTheRowAndDoesNotPaintACardAbove() {
        let next = page(.groups).applying(.approvalRequested(request("s1", highRisk: false, command: "list files")))
        #expect(next.approvalGrown)
        #expect(next.phase == .approval)
        #expect(!next.cardAbovePage)
        #expect(next.secondsLeft == AgentsPage.countdownStart)
        #expect(next.showingRequest?.sessionID == "s1")
        #expect(next.sessions["s1"]?.status == .needsApproval)
        #expect(next.focusOrder == HubFocusTarget.selectedApprovalOrder || next.selectedID == nil)
    }

    @Test func aSecondRequestWaitsAndApproveRevealsIt() {
        var waiting = page(.approval)
        waiting.roster.append(HubGroupSession(id: "s2", agent: "Agent A", project: "Fixture", status: .running, elapsedSeconds: 1))
        waiting.sessions["s2"] = HubSessionState(status: .running, clockGeneration: 1)
        waiting = waiting.applying(.approvalRequested(request("s2", highRisk: true, command: "show the diff")))
        #expect(waiting.queuedRequests.map(\.sessionID) == ["s2"])
        #expect(waiting.showingRequest?.sessionID == "s1")
        #expect(waiting.sessions["s2"]?.status == .running)
        #expect(waiting.approvalGrown)

        let pending = waiting.applying(.approve)
        #expect(pending.revision.pending?.action == .allowOnce)
        #expect(pending.sessions["s1"]?.status == .needsApproval)
        #expect(pending.sessions["s2"]?.status == .running)
        #expect(pending.revision.waiting.map(\.sessionID) == ["s2"])
        let revealed = pending.applying(.tick).applying(.tick)
        #expect(revealed.showingRequest?.sessionID == "s2")
        #expect(revealed.showingRequest?.tier == .high)
        #expect(revealed.sessions["s2"]?.status == .needsApproval)
        #expect(revealed.sessions["s1"]?.status == .running)
        #expect(revealed.queuedRequests.isEmpty)
        #expect(revealed.approvalGrown)
        #expect(revealed.secondsLeft == AgentsPage.countdownStart)
        #expect(revealed.revision.executed.last?.action == .allowOnce)
        #expect(!revealed.cardAbovePage)
        #expect(!revealed.openedWindow)
    }

    @Test func dismissOnAFailedErrorBecomesDoneAndKeepsTheReason() {
        let start = page(.failed)
        let clock = start.sessions["s1"]?.clockGeneration
        let next = start.applying(.dismiss)
        #expect(next.sessions["s1"]?.status == .done)
        #expect(next.sessions["s1"]?.clockGeneration == clock)
        #expect(next.reasons["s1"] == "The service had an error")
        #expect(next.dismissTitle == nil)
        #expect(next.sessions["s1"]?.status.visibleWord == "Done")
        #expect(!next.openedWindow)
    }

    @Test func aQuietErrorHasNoDismissAndActivityReturnsToRunning() {
        let start = page(.quiet)
        #expect(start.dismissTitle == nil)
        #expect(start.applying(.dismiss) == start)
        let next = start.applying(.activity("s1"))
        #expect(next.sessions["s1"]?.status == .running)
        #expect(next.reasons["s1"] == nil)
        #expect(next.sessions["s1"]?.clockGeneration == start.sessions["s1"]?.clockGeneration)
    }

    @Test func theCountdownPausesAndEndsInDeny() {
        var paused = page(.approval).applying(.hover(true)).applying(.tick)
        #expect(paused.countdownPaused)
        #expect(paused.secondsLeft == AgentsPage.countdownStart)
        paused = paused.applying(.hover(false)).applying(.focus(true)).applying(.tick)
        #expect(paused.countdownPaused)
        #expect(paused.secondsLeft == AgentsPage.countdownStart)
        paused = paused.applying(.focus(false))
        for _ in 0..<11 { paused = paused.applying(.tick) }
        #expect(paused.secondsLeft == 1)
        #expect(paused.showingRequest != nil)
        #expect(paused.lastVerdict == nil)
        let denied = paused.applying(.tick)
        #expect(denied.revision.pending?.action == HubRevision3Timing.countdownExpiry)
        #expect(denied.revision.pending?.fromCountdown == true)
        #expect(denied.revision.pending?.action.isApproval == false)
        #expect(denied.sessions["s1"]?.status == .needsApproval)
        let finished = denied.applying(.tick).applying(.tick)
        #expect(finished.revision.executed.last?.action == .deny)
        #expect(finished.revision.showing == nil)
        #expect(finished.sessions["s1"]?.status == .running)
        #expect(!finished.openedWindow)
    }

    @Test func undoLastsTwoSeconds() {
        let decided = page(.approval).applying(.approve)
        #expect(decided.undoTicksLeft == AgentsPage.undoSeconds)
        #expect(decided.revision.pending?.action == .allowOnce)
        #expect(decided.sessions["s1"]?.status == .needsApproval)
        let restored = decided.applying(.undo)
        #expect(restored.showingRequest?.sessionID == "s1")
        #expect(restored.sessions["s1"]?.status == .needsApproval)
        #expect(restored.revision.pending == nil)
        #expect(restored.approvalGrown)
        #expect(restored.undoTicksLeft == 0)

        var expired = page(.approval).applying(.deny)
        expired = expired.applying(.tick).applying(.tick)
        #expect(expired.undoTicksLeft == 0)
        #expect(expired.revision.executed.last?.action == .deny)
        #expect(expired.sessions["s1"]?.status == .running)
        let stayed = expired.applying(.undo)
        #expect(stayed.sessions["s1"]?.status == .running)
        #expect(stayed.revision.pending == nil)
    }

    @Test func reduceMotionUsesNoOffsetAndScaleOne() {
        #expect(AgentsPage.approvalOffset(reduceMotion: true) == 0)
        #expect(AgentsPage.approvalScale(reduceMotion: true) == 1)
        #expect(AgentsPage.approvalOffset(reduceMotion: false) == SessionListAccessibility.rise)
        #expect(AgentsPage.approvalScale(reduceMotion: false) == SessionListAccessibility.arrivingScale)
    }

    @Test func openAndIdleBudgets() {
        let page = AgentsPage.fresh()
        #expect(page.meetsOpenBudget(0))
        #expect(page.meetsOpenBudget(AgentsPage.openBudgetMilliseconds))
        #expect(!page.meetsOpenBudget(AgentsPage.openBudgetMilliseconds + 1))
        #expect(!page.meetsOpenBudget(-1))

        var idle = AgentsPage.fresh()
        idle.panelClosed = true
        #expect(!idle.schedulesOneSecondTimer)
        #expect(idle.isIdle(percentOfOneCore: 0))
        #expect(idle.isIdle(percentOfOneCore: AgentsPage.idleBudgetPercentOfOneCore))
        #expect(!idle.isIdle(percentOfOneCore: AgentsPage.idleBudgetPercentOfOneCore + 0.01))
        #expect(!idle.isIdle(percentOfOneCore: .nan))
        #expect(!idle.isIdle(percentOfOneCore: -0.1))
        idle.oneSecondTimerScheduled = true
        #expect(!idle.isIdle(percentOfOneCore: 0))
        idle.oneSecondTimerScheduled = false
        idle.socketReadInProgress = true
        #expect(!idle.isIdle(percentOfOneCore: 0))
        idle.socketReadInProgress = false
        idle.waveDisplayLinkRunning = true
        #expect(!idle.isIdle(percentOfOneCore: 0))
        idle.waveDisplayLinkRunning = false
        idle.showingRequest = request("s1", highRisk: false, command: "list files")
        #expect(!idle.isIdle(percentOfOneCore: 0))
        idle.showingRequest = nil
        idle.panelClosed = false
        #expect(!idle.isIdle(percentOfOneCore: 0))
    }

    @Test func thePageUsesExistingKeysAndDoesNotInventTheMissingOnes() {
        #expect(AgentsPage.verdict(forKey: .approveKey) == .allow)
        #expect(AgentsPage.verdict(forKey: .denyKey) == .deny)
        #expect(AgentsPage.verdict(forKey: .askKey) == .ask)
        #expect(AgentsPage.verdict(forKey: .return) == nil)
        #expect(AgentsPage.verdict(forKey: .escape) == nil)
        #expect(!AgentsPage.usesCommandShortcut)
        #expect(AgentsPage.holdSeconds(highRisk: true) == nil)
        #expect(AgentsPage.holdSeconds(highRisk: false) == nil)
        #expect(AgentsPage.holdMilliseconds(tier: .destructive) == HubRevision3Timing.destructiveHoldMilliseconds)
        #expect(AgentsPage.holdMilliseconds(tier: .high) == 0)
        #expect(AgentsPage.holdMilliseconds(tier: .low) == 0)
        #expect(AgentsPage.denyNoteLimit == HubRevision3Timing.noteCharacterLimit)
        #expect(HubDecisionKey.return.action == .allowOnce)
        #expect(HubDecisionKey.two.action == .allowForThisSession)
        #expect(HubDecisionKey.escape.action == .deny)
        #expect(HubDecisionKey.three.action == .deny)
        #expect(HubDecisionKey.four.action == .denyWithNote)
        #expect(HubDecisionKeys.decision(.return, command: true, decisionShowing: true) == nil)
        #expect(HubDecisionKeys.deniesAllQueued(key: .shiftEscape, command: false, decisionShowing: true))
        #expect(HubDecisionKeys.undoes(key: .undo, command: false, undoShowing: true))
        #expect(HubRevision3Timing.countdownExpiry == .deny)
        #expect(HubRevision3Timing.countdownExpiry.isApproval == false)
        #expect(AgentsPage.countdownStart == 12)
        #expect(AgentsPage.undoSeconds == 2)
    }

    @Test func failureSentencesKeepASlashAndDropABlank() {
        let slash = page(.connecting).applying(.socketFailed("closed /var/run/hub.sock"))
        #expect(slash.screen.reason == "closed /var/run/hub.sock")
        let url = page(.connecting).applying(.socketFailed("https://example.test/hub"))
        #expect(url.screen.reason == "https://example.test/hub")
        let marked = page(.connecting).applying(.socketFailed("**retry**"))
        #expect(marked.screen.reason == "**retry**")
        let spoken = page(.connecting).applying(.socketFailed("café — retry"))
        #expect(spoken.screen.reason == "café — retry")
        let long = String(repeating: "n", count: 500)
        #expect(page(.connecting).applying(.socketFailed(long)).screen.reason == long)
        #expect(page(.connecting).applying(.socketFailed("")).screen.reason == nil)
        #expect(page(.connecting).applying(.socketFailed("   ")).screen.reason == nil)
        #expect(page(.connecting).applying(.socketFailed("line\nstill")).screen.reason == nil)
    }

    @Test func theFirstLoadExpandsOnlyTheUrgentGroup() {
        let running = HubGroupSession(id: "a", agent: "Agent A", project: "One", status: .running, elapsedSeconds: 4)
        let waiting = HubGroupSession(id: "b", agent: "Agent B", project: "Two", status: .needsApproval, elapsedSeconds: 9)
        let loaded = AgentsPage.fresh().applying(.panel(closed: false)).applying(.sessionsReplaced([running, waiting]))
        #expect(loaded.screen.screen == .ready)
        #expect(loaded.groups.expanded == ["Agent B"])
        #expect(loaded.groups.groups.map(\.agent) == ["Agent B", "Agent A"])

        let tie = AgentsPage.fresh().applying(.panel(closed: false)).applying(.sessionsReplaced([
            HubGroupSession(id: "b", agent: "Agent B", project: "Two", status: .running, elapsedSeconds: 9),
            HubGroupSession(id: "a", agent: "Agent A", project: "One", status: .running, elapsedSeconds: 4),
        ]))
        #expect(tie.groups.expanded == ["Agent A"])
    }

    @Test func removingAGroupsLastSessionDropsItsHeader() {
        var loaded = AgentsPage.fresh().applying(.panel(closed: false)).applying(.sessionsReplaced([
            HubGroupSession(id: "a", agent: "Agent A", project: "One", status: .running, elapsedSeconds: 4),
            HubGroupSession(id: "b", agent: "Agent B", project: "Two", status: .running, elapsedSeconds: 9),
        ]))
        loaded = loaded.applying(.toggleGroup("Agent B"))
        #expect(loaded.groups.expanded == ["Agent A", "Agent B"])
        let left = loaded.applying(.sessionsReplaced([
            HubGroupSession(id: "a", agent: "Agent A", project: "One", status: .running, elapsedSeconds: 4),
        ]))
        #expect(left.groups.groups.map(\.agent) == ["Agent A"])
        #expect(left.groups.expanded == ["Agent A"])
    }

    @Test func aNoteStopsAt280AndACommandKeyDoesNothing() {
        let kept = page(.approval).applying(.note(String(repeating: "n", count: HubRevision3Timing.noteCharacterLimit)))
        #expect(kept.revision.note.count == HubRevision3Timing.noteCharacterLimit)
        let rejected = page(.approval).applying(.note(String(repeating: "n", count: HubRevision3Timing.noteCharacterLimit + 1)))
        #expect(rejected.revision.note.isEmpty)
        let armed = page(.approval)
        let ignored = armed.applying(.key(.return, command: true))
        #expect(ignored.revision == armed.revision)
        #expect(ignored.sessions["s1"]?.status == .needsApproval)
    }

    @Test func destructiveApprovalNeedsAHoldAndShiftEscapeDeniesTheQueue() {
        var destructive = page(.approval)
        if var showing = destructive.revision.showing {
            showing.tier = .destructive
            destructive.revision.showing = showing
        }
        let early = destructive.applying(.holdBegan(.allowOnce)).applying(.holdReleased(after: HubRevision3Timing.destructiveHoldMilliseconds - 1))
        #expect(early.revision.pending == nil)
        #expect(early.revision.executed.isEmpty)
        let held = destructive.applying(.holdBegan(.allowOnce)).applying(.holdReleased(after: HubRevision3Timing.destructiveHoldMilliseconds))
        #expect(held.revision.pending?.action == .allowOnce)
        #expect(held.revision.pending?.holdMilliseconds == HubRevision3Timing.destructiveHoldMilliseconds)

        var queued = page(.approval)
        queued.roster.append(HubGroupSession(id: "s2", agent: "Agent A", project: "Fixture", status: .running, elapsedSeconds: 1))
        queued.sessions["s2"] = HubSessionState(status: .running, clockGeneration: 1)
        queued = queued.applying(.approvalRequested(request("s2", highRisk: false, command: "list more")))
        let denied = queued.applying(.key(.shiftEscape, command: false))
        #expect(denied.revision.pending?.deniesAllQueued == true)
        #expect(denied.revision.pending?.action == .deny)
        #expect(denied.revision.pending?.requestIDs == ["s1", "s2"])
    }

    @Test func undoBeforeSendCancelsTheAllow() {
        let tapped = AgentsPageHook.tapAllow(page(.approval))
        #expect(tapped.sends.isEmpty)
        let undone = AgentsPageHook.undo(tapped.page)
        #expect(undone.sends.isEmpty)
        let later = AgentsPageHook.advance(undone.page, ticks: 2)
        #expect(later.sends.isEmpty)
        #expect(later.page.revision.executed.allSatisfy { !$0.action.isApproval })
    }

    @Test func allowIsSentOnlyAfterTheUndoWindow() {
        let tapped = AgentsPageHook.tapAllow(page(.approval))
        #expect(tapped.sends.isEmpty)
        let midway = AgentsPageHook.advance(tapped.page, ticks: 1)
        #expect(midway.sends.isEmpty)
        let sent = AgentsPageHook.advance(midway.page, ticks: 1)
        #expect(sent.sends == [.allow])
    }

    @Test func destructiveRequiresTheHoldBeforeAnySend() {
        var destructive = page(.approval)
        if var showing = destructive.revision.showing {
            showing.tier = .destructive
            destructive.revision.showing = showing
        }
        let tapped = AgentsPageHook.tapAllow(destructive)
        #expect(tapped.sends.isEmpty)
        #expect(tapped.page.revision.pending == nil)
        let early = AgentsPageHook.hold(destructive, action: .allowOnce, milliseconds: HubRevision3Timing.destructiveHoldMilliseconds - 1)
        #expect(early.sends.isEmpty)
        #expect(early.page.revision.pending == nil)
        let held = AgentsPageHook.hold(destructive, action: .allowOnce, milliseconds: HubRevision3Timing.destructiveHoldMilliseconds)
        #expect(held.sends.isEmpty)
        #expect(held.page.revision.pending?.action == .allowOnce)
        let sent = AgentsPageHook.advance(held.page, ticks: 2)
        #expect(sent.sends == [.allow])
    }

    @Test func aDuplicateRequestKeepsTheShowingCommandAndTier() {
        let start = page(.approval)
        let duplicate = AgentsPageRequest(
            id: "s1", sessionID: "s1", tool: "Bash", highRisk: true, command: "show the diff", tier: .high)
        let next = start.applying(.approvalRequested(duplicate)).applying(.tick)
        #expect(next.showingRequest?.command == "list files")
        #expect(next.showingRequest?.tier == .low)
        #expect(next.revision.showing?.tier == .low)
        #expect(next.revision.waiting.isEmpty)
    }

    @Test func eachRequestKeepsItsOwnIdAndCommand() {
        var start = page(.approval)
        start.roster.append(HubGroupSession(id: "s2", agent: "Agent A", project: "Fixture", status: .running, elapsedSeconds: 1))
        start.sessions["s2"] = HubSessionState(status: .running, clockGeneration: 1)
        let other = AgentsPageRequest(
            id: "req-b", sessionID: "s2", tool: "Bash", highRisk: true, command: "show the diff", tier: .high)
        let queued = start.applying(.approvalRequested(other)).applying(.tick)
        #expect(queued.revision.showing?.id == "s1")
        #expect(queued.revision.showing?.tier == .low)
        #expect(queued.showingRequest?.command == "list files")
        #expect(queued.showingRequest?.tier == .low)
        #expect(queued.revision.waiting.map(\.id) == ["req-b"])
        #expect(queued.queuedRequests.first?.command == "show the diff")
        #expect(queued.queuedRequests.first?.tier == .high)
    }

    @Test func aClosedCardDoesNotHandAllowToTheNextCard() {
        var ready = page(.groups)
        let cardA = AgentsPageLive.request(approvalID: "card-a", sessionID: "s1", tool: "Bash", highRisk: false, command: "list files")
        #expect(cardA.id == "card-a")
        #expect(cardA.boundID == "card-a")
        ready = ready.applying(.approvalRequested(cardA))
        #expect(ready.revision.showing?.id == "card-a")
        let tapped = AgentsPageHook.tapAllow(ready)
        var gate = AgentsPageCardGate()
        let opened = gate.step(before: ready, after: tapped.page, currentCard: "card-a")
        gate = opened.0
        #expect(gate.boundID == "card-a")
        #expect(opened.1.isEmpty)
        let finished = AgentsPageHook.advance(tapped.page, ticks: 2)
        let toB = gate.step(before: tapped.page, after: finished.page, currentCard: "card-b")
        #expect(toB.1.isEmpty)
        #expect(finished.page.revision.executed.last?.action == .allowOnce)
        var stillA = AgentsPageCardGate()
        let openedA = stillA.step(before: ready, after: tapped.page, currentCard: "card-a")
        stillA = openedA.0
        let kept = stillA.step(before: tapped.page, after: finished.page, currentCard: "card-a")
        #expect(kept.1 == [.allow])
    }

    @Test func aSingleReturnOnADestructiveCardDoesNotApprove() {
        var destructive = page(.approval)
        if var showing = destructive.revision.showing {
            showing.tier = .destructive
            destructive.revision.showing = showing
        }
        let pressed = AgentsPageDestructive.keyboard(destructive, key: .return)
        #expect(pressed.page.revision.pending?.action != .allowOnce)
        #expect(pressed.page.revision.pending?.action.isApproval != true)
    }

    @Test func aDestructiveActivateDeniesAndConfirmHolds() {
        var destructive = page(.approval)
        if var showing = destructive.revision.showing {
            showing.tier = .destructive
            destructive.revision.showing = showing
        }
        let tapped = AgentsPageDestructive.activate(destructive)
        #expect(tapped.page.revision.pending?.action == .deny)
        #expect(tapped.page.revision.pending?.action.isApproval == false)
        let down = AgentsPageDestructive.keyDown(destructive, key: .return)
        #expect(down.page.revision.pending == nil)
        let short = AgentsPageDestructive.keyUp(down.page, key: .return, elapsedMilliseconds: HubRevision3Timing.destructiveHoldMilliseconds - 1)
        #expect(short.page.revision.pending?.action.isApproval != true)
        let again = AgentsPageDestructive.keyDown(destructive, key: .return)
        let held = AgentsPageDestructive.keyUp(again.page, key: .return, elapsedMilliseconds: 1_500)
        #expect(held.page.revision.pending?.action == .allowOnce)
        #expect(held.page.revision.pending?.holdMilliseconds == 1_500)
        let two = AgentsPageDestructive.keyUp(
            AgentsPageDestructive.keyDown(destructive, key: .two).page,
            key: .two,
            elapsedMilliseconds: 1_400)
        #expect(two.page.revision.pending?.action == .allowForThisSession)
        #expect(two.page.revision.pending?.holdMilliseconds == 1_400)
        let stray = AgentsPageDestructive.keyUp(destructive, key: .return, elapsedMilliseconds: 1_500)
        #expect(stray.page.revision.pending == nil)
        let spoken = AgentsPageDestructive.confirm(destructive, action: .allowOnce)
        #expect(AgentsPageDestructive.voiceOverConfirmLabel(.allowOnce) == "Confirm Allow once")
        #expect(AgentsPageDestructive.voiceOverConfirmLabel(.allowOnce, armed: true) == "Confirm Allow once again")
        #expect(spoken.page.voiceOverArmed == .allowOnce)
        #expect(spoken.page.revision.pending?.action.isApproval != true)
        let switched = AgentsPageDestructive.confirm(spoken.page, action: .allowForThisSession)
        #expect(switched.page.revision.pending == nil)
        #expect(switched.page.voiceOverArmed == .allowForThisSession)
        let second = AgentsPageDestructive.confirm(spoken.page, action: .allowOnce)
        #expect(second.page.revision.pending?.action == .allowOnce)
        #expect(second.page.revision.pending?.holdMilliseconds == nil)
    }

    @Test func theHoldFillStepsUnderReduceMotionAndUndoShowsItsCountdown() {
        let early = AgentsPageHoldFill.progress(heldMilliseconds: 600, reduceMotion: false)
        #expect(early.fraction == 0.5)
        #expect(early.animates)
        let stepped = AgentsPageHoldFill.progress(heldMilliseconds: 600, reduceMotion: true)
        #expect(stepped.fraction == 0)
        #expect(stepped.animates == false)
        let done = AgentsPageHoldFill.progress(heldMilliseconds: HubRevision3Timing.destructiveHoldMilliseconds, reduceMotion: true)
        #expect(done.fraction == 1)
        #expect(done.animates == false)
        let pending = page(.approval).applying(.approve)
        #expect(AgentsPageUndoChip.countdown(pending) == "2 s")
        #expect(pending.announcement == HubRevision3Speech.pending(.allowOnce, deniesAllQueued: false))
        #expect(HubRevision3Timing.undoMilliseconds == 2_000)
        #expect(HubRevision3Timing.destructiveHoldMilliseconds == 1_200)
    }

    @Test func exhaustiveTransitionTable() {
        let failures = AgentsPageOracle.failures()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func theAgentsPageKeepsTheExistingOpenSpring() throws {
        let source = try String(contentsOf: notchViewURL(), encoding: .utf8)
        #expect(source.contains("SessionListView("))
        #expect(source.contains("HubTranscriptView("))
        #expect(source.contains("HubDecisionRow("))
        #expect(source.contains("HubScreenMachine.copy"))
        #expect(source.contains(".applying(.tryAgain)"))
        #expect(source.contains(".applying(.dismiss)"))
        #expect(source.contains(".applying(.open("))
        #expect(source.contains("selectedTab != .agents"))
        #expect(!source.contains("openWindow()"))
        #expect(!source.contains("ChatModel.shared.openWindow"))
        #expect(source.contains(".animation(open ? TopBarStyle.openSpring : TopBarStyle.closeMotion, value: model.presentation)"))
        #expect(source.contains(".animation(TopBarStyle.pageSpring, value: panelHeightKey)"))
    }
}

private enum AgentsFixture: String, CaseIterable {
    case empty, connecting, connectionError, groups, selected, approval, failed, quiet
}

private enum AgentsProbe: String, CaseIterable {
    case showHome, showTab, socketOpening, socketOpenedEmpty, socketFailed, lastSessionEnded
    case tryAgain, select, clearSelection, toggleGroup, approvalRequested, approve, deny
    case dismiss, activity, open, hover, tick, undo, panelClosed, newChat, focus
}

private func page(_ fixture: AgentsFixture) -> AgentsPage {
    var page = AgentsPage.fresh()
    page.panelClosed = false
    switch fixture {
    case .empty:
        return page
    case .connecting:
        page.screen.screen = .loading
        return page
    case .connectionError:
        page.screen = HubScreenState(screen: .connectionError, reason: "The socket closed.")
        return page
    case .groups:
        return grouped(page, selected: nil, status: .running, reason: nil)
    case .selected:
        return grouped(page, selected: "s1", status: .running, reason: nil)
    case .approval:
        var ready = grouped(page, selected: "s1", status: .running, reason: nil)
        ready.sessions["s1"] = HubSessionState(status: .needsApproval, clockGeneration: 1, previous: .running)
        ready.roster[0].status = .needsApproval
        ready.groups = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: ready.roster)
        ready.showingRequest = request("s1", highRisk: false, command: "list files")
        ready.requestDetails["s1"] = ready.showingRequest
        ready.revision = HubRevision3State(
            showing: HubRevision3Request(id: "s1", sessionID: "s1", tier: .low),
            remainingMilliseconds: HubRevision3Timing.countdownMilliseconds
        )
        ready.approvalGrown = true
        ready.secondsLeft = AgentsPage.countdownStart
        return ready
    case .failed:
        return grouped(page, selected: "s1", status: .error(.failed), reason: "The service had an error")
    case .quiet:
        return grouped(page, selected: "s1", status: .error(.quiet), reason: "No activity for 5 min")
    }
}

private func grouped(_ page: AgentsPage, selected: String?, status: HubSessionStatus, reason: String?) -> AgentsPage {
    var page = page
    let session = HubGroupSession(id: "s1", agent: "Agent A", project: "Fixture", status: status, elapsedSeconds: 5)
    page.screen.screen = .ready
    page.roster = [session]
    page.sessions = ["s1": HubSessionState(status: status, clockGeneration: 1)]
    page.groups = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: page.roster)
    page.loadedGroups = true
    page.selectedID = selected
    if let reason { page.reasons["s1"] = reason }
    return page
}

private func request(_ id: String, highRisk: Bool, command: String) -> AgentsPageRequest {
    AgentsPageRequest(sessionID: id, tool: "Bash", highRisk: highRisk, command: command, tier: highRisk ? .high : .low)
}

private func notchViewURL() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<8 {
        let candidate = url.appendingPathComponent("Sources/Zeus/Notch/NotchView.swift")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        url.deleteLastPathComponent()
    }
    if let root = ProcessInfo.processInfo.environment["ZEUS_SOURCE"] {
        return URL(fileURLWithPath: root).appendingPathComponent("Sources/Zeus/Notch/NotchView.swift")
    }
    return URL(fileURLWithPath: #filePath)
}

/// Expected moves. Every other fixture and probe pair stays put, and never opens a window.
private enum AgentsPageOracle {
    static let moves: [String: String] = [
        "empty showHome": "entry=home",
        "empty socketOpening": "screen=loading",
        "empty newChat": "form",
        "empty panelClosed": "closed",
        "connecting showHome": "entry=home",
        "connecting socketOpenedEmpty": "screen=empty",
        "connecting socketFailed": "screen=connectionError",
        "connecting newChat": "form",
        "connecting panelClosed": "closed",
        "connectionError showHome": "entry=home",
        "connectionError socketOpenedEmpty": "screen=empty",
        "connectionError tryAgain": "screen=loading",
        "connectionError newChat": "form-empty",
        "connectionError panelClosed": "closed",
        "groups showHome": "entry=home",
        "groups socketFailed": "screen=connectionError",
        "groups lastSessionEnded": "screen=empty-clear",
        "groups select": "selected=s1",
        "groups toggleGroup": "collapsed",
        "groups approvalRequested": "grown",
        "groups open": "jump",
        "groups panelClosed": "closed",
        "groups newChat": "form",
        "selected showHome": "entry=home",
        "selected socketFailed": "screen=connectionError",
        "selected lastSessionEnded": "screen=empty-clear",
        "selected clearSelection": "selected=-",
        "selected toggleGroup": "collapsed",
        "selected approvalRequested": "grown",
        "selected open": "jump",
        "selected panelClosed": "closed",
        "selected newChat": "form",
        "approval showHome": "entry=home",
        "approval socketFailed": "screen=connectionError",
        "approval lastSessionEnded": "screen=empty-clear",
        "approval clearSelection": "selected=-",
        "approval toggleGroup": "collapsed",
        "approval approve": "approved",
        "approval deny": "denied",
        "approval open": "jump",
        "approval hover": "paused",
        "approval focus": "paused",
        "approval tick": "seconds=11",
        "approval panelClosed": "closed",
        "approval newChat": "form",
        "failed showHome": "entry=home",
        "failed socketFailed": "screen=connectionError",
        "failed lastSessionEnded": "screen=empty-clear",
        "failed clearSelection": "selected=-",
        "failed toggleGroup": "collapsed",
        "failed dismiss": "dismissed",
        "failed open": "jump",
        "failed panelClosed": "closed",
        "failed newChat": "form",
        "quiet showHome": "entry=home",
        "quiet socketFailed": "screen=connectionError",
        "quiet lastSessionEnded": "screen=empty-clear",
        "quiet clearSelection": "selected=-",
        "quiet toggleGroup": "collapsed",
        "quiet activity": "quiet-running",
        "quiet open": "jump",
        "quiet panelClosed": "closed",
        "quiet newChat": "form",
    ]

    static func failures() -> [String] {
        var failures: [String] = []
        for fixture in AgentsFixture.allCases {
            for probe in AgentsProbe.allCases {
                let start = page(fixture)
                let next = start.applying(signal(probe, on: start))
                let key = "\(fixture.rawValue) \(probe.rawValue)"
                let kind = moves[key] ?? "same"
                if next.openedWindow {
                    failures.append("\(key) opened a window")
                }
                if let problem = check(kind, start: start, next: next) {
                    failures.append("\(key) [\(kind)] \(problem)")
                }
            }
        }
        return failures
    }

    static func signal(_ probe: AgentsProbe, on start: AgentsPage) -> AgentsPageSignal {
        switch probe {
        case .showHome: return .show(.home)
        case .showTab: return .show(.tab)
        case .socketOpening: return .socketOpening
        case .socketOpenedEmpty: return .socketOpened(sessionCount: 0, failureSentence: nil)
        case .socketFailed: return .socketFailed("The socket closed.")
        case .lastSessionEnded: return .lastSessionEnded
        case .tryAgain: return .tryAgain
        case .select: return .select("s1")
        case .clearSelection: return .select(nil)
        case .toggleGroup: return .toggleGroup("Agent A")
        case .approvalRequested: return .approvalRequested(request("s1", highRisk: false, command: "list files"))
        case .approve: return .approve
        case .deny: return .deny
        case .dismiss: return .dismiss
        case .activity: return .activity("s1")
        case .open: return .open("s1")
        case .hover: return .hover(true)
        case .tick: return .tick
        case .undo: return .undo
        case .panelClosed: return .panel(closed: true)
        case .newChat: return .newChat(onChatTab: true)
        case .focus: return .focus(true)
        }
    }

    static func check(_ kind: String, start: AgentsPage, next: AgentsPage) -> String? {
        switch kind {
        case "same":
            return next == start ? nil : "expected the page to stay"
        case "entry=home":
            return next.entry == .home && same(start, next, except: \.entry) ? nil : "entry did not become home"
        case "screen=loading":
            return next.screen.screen == .loading && next.screen.reason == nil ? nil : "expected connecting"
        case "screen=empty":
            return next.screen.screen == .empty && next.screen.reason == nil ? nil : "expected empty"
        case "screen=empty-clear":
            guard next.screen.screen == .empty, next.roster.isEmpty, next.selectedID == nil, !next.approvalGrown else {
                return "expected an empty page with no rows"
            }
            return nil
        case "screen=connectionError":
            guard next.screen.screen == .connectionError, next.screen.reason == "The socket closed.", next.showsTryAgain else {
                return "expected connection error with Try again"
            }
            return nil
        case "selected=s1":
            return next.selectedID == "s1" && next.phase == .selected ? nil : "expected the row selected"
        case "selected=-":
            return next.selectedID == nil ? nil : "expected the selection cleared"
        case "collapsed":
            return next.groups.expanded.contains("Agent A") == false ? nil : "expected Agent A collapsed"
        case "grown":
            guard next.approvalGrown, !next.cardAbovePage, next.secondsLeft == 12, next.showingRequest?.sessionID == "s1" else {
                return "expected the row to grow"
            }
            return next.sessions["s1"]?.status == .needsApproval ? nil : "expected needs approval"
        case "jump":
            return next.jumpSessionID == "s1" && !next.openedWindow ? nil : "expected a jump and no window"
        case "closed":
            return next.panelClosed && !next.oneSecondTimerScheduled && !next.schedulesOneSecondTimer ? nil : "expected the clock off"
        case "form":
            return next.screen.chatForm && next.screen.screen == start.screen.screen ? nil : "expected the chat form remembered"
        case "form-empty":
            return next.screen.chatForm && next.screen.screen == .empty && next.screen.reason == nil ? nil : "expected new chat to clear the error"
        case "approved":
            guard next.revision.pending?.action == .allowOnce,
                  next.sessions["s1"]?.status == .needsApproval,
                  next.undoTicksLeft == 2,
                  next.revision.executed.isEmpty else {
                return "expected allow once to wait in the undo window"
            }
            return nil
        case "denied":
            guard next.revision.pending?.action == .deny,
                  next.revision.pending?.action.isApproval == false,
                  next.sessions["s1"]?.status == .needsApproval,
                  next.undoTicksLeft == 2 else {
                return "expected deny to wait in the undo window"
            }
            return nil
        case "paused":
            return next.countdownPaused && next.secondsLeft == start.secondsLeft ? nil : "expected the countdown to pause"
        case "seconds=11":
            return next.secondsLeft == 11 && next.showingRequest != nil && next.lastVerdict == nil ? nil : "expected 11 seconds left"
        case "dismissed":
            guard next.sessions["s1"]?.status == .done, next.reasons["s1"] == start.reasons["s1"], next.dismissTitle == nil else {
                return "expected Dismiss to become Done"
            }
            return next.sessions["s1"]?.clockGeneration == start.sessions["s1"]?.clockGeneration ? nil : "the clock moved"
        case "quiet-running":
            return next.sessions["s1"]?.status == .running && next.reasons["s1"] == nil ? nil : "expected the quiet error to clear"
        default:
            return "unknown expectation \(kind)"
        }
    }

    static func same<T: Equatable>(_ start: AgentsPage, _ next: AgentsPage, except keyPath: WritableKeyPath<AgentsPage, T>) -> Bool {
        var copy = next
        copy[keyPath: keyPath] = start[keyPath: keyPath]
        return copy == start
    }
}
