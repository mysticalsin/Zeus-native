import Foundation
import Testing
@testable import ZeusCore

/// The revision 3 decision machine. Time is an injected millisecond count.
/// 1.199 s is 1,199 ms. 1.2 s is 1,200 ms. 1.99 s is 1,990 ms. 2.0 s is 2,000 ms.
@Suite("Hub revision 3 decision")
struct HubRevision3DecisionTests {
    @Test func aLowDecisionAllowsOnceAndDoesNotRunUntilUndoExpires() {
        let shown = show(.low)
        #expect(shown.phase == .showing)
        #expect(shown.remainingMilliseconds == 12_000)
        #expect(shown.visibleCount == 1)
        #expect(shown.waitingCount == 0)

        let decided = HubRevision3Decision.step(shown, .key(.`return`, command: false))
        #expect(decided.announcement == "Allow once. Undo.")
        #expect(decided.state.phase == .pendingUndo)
        #expect(decided.state.pending?.action == .allowOnce)
        #expect(decided.state.pending?.undoUntil == 2_000)
        #expect(decided.state.pending?.fromCountdown == false)
        #expect(decided.state.executed.isEmpty)
        #expect(decided.state.decisionShowing == false)
        #expect(decided.state.undoShowing)

        let early = HubRevision3Decision.step(decided.state, .advance(to: 1_990))
        #expect(early.state.pending != nil)
        #expect(early.state.executed.isEmpty)
        #expect(early.state.clock == 1_990)

        let last = HubRevision3Decision.step(decided.state, .advance(to: 1_999))
        #expect(last.state.pending != nil)
        #expect(last.state.executed.isEmpty)

        let done = HubRevision3Decision.step(decided.state, .advance(to: 2_000))
        #expect(done.state.executed.count == 1)
        #expect(done.state.executed[0].action == .allowOnce)
        #expect(done.state.executed[0].atMilliseconds == 2_000)
        #expect(done.state.executed[0].fromCountdown == false)
        #expect(done.state.pending == nil)
        #expect(done.state.phase == .idle)
        #expect(done.state.showing == nil)
    }

    @Test func undoAtOnePointNineNineSecondsRestoresTheDecision() {
        var state = show(.high)
        state = HubRevision3Decision.step(state, .replaceNote("keep this")).state
        state = HubRevision3Decision.step(state, .key(.two, command: false)).state
        #expect(state.pending?.action == .allowForThisSession)
        #expect(state.pending?.undoUntil == 2_000)

        let undone = HubRevision3Decision.step(state, .advance(to: 1_990))
        let restored = HubRevision3Decision.step(undone.state, .key(.undo, command: false))
        #expect(restored.announcement == "Undone.")
        #expect(restored.state.pending == nil)
        #expect(restored.state.executed.isEmpty)
        #expect(restored.state.showing?.tier == .high)
        #expect(restored.state.note == "keep this")
        #expect(restored.state.phase == .showing)
        #expect(restored.state.remainingMilliseconds == 12_000)

        let ignored = HubRevision3Decision.step(restored.state, .key(.undo, command: false))
        #expect(ignored.state == restored.state)
        #expect(ignored.announcement == nil)
    }

    @Test func destructiveApprovalRequiresAHoldOfOnePointTwoSeconds() {
        let shown = show(.destructive)
        for key in [HubDecisionKey.`return`, HubDecisionKey.two] {
            let tapped = HubRevision3Decision.step(shown, .key(key, command: false))
            #expect(tapped.state == shown)
            #expect(tapped.state.pending == nil)
            #expect(tapped.state.executed.isEmpty)
        }

        let holding = HubRevision3Decision.step(shown, .holdBegan(.allowOnce, at: 0))
        #expect(holding.state.phase == .holding)
        #expect(holding.state.holdBeganAt == 0)
        let early = HubRevision3Decision.step(holding.state, .holdReleased(at: 1_199))
        #expect(early.state.phase == .showing)
        #expect(early.state.pending == nil)
        #expect(early.state.executed.isEmpty)
        #expect(early.state.holdBeganAt == nil)

        let again = HubRevision3Decision.step(early.state, .holdBegan(.allowForThisSession, at: 1_199))
        let ready = HubRevision3Decision.step(again.state, .holdReleased(at: 1_199 + 1_200))
        #expect(ready.state.pending?.action == .allowForThisSession)
        #expect(ready.state.pending?.holdMilliseconds == 1_200)
        #expect(ready.state.pending?.tier == .destructive)
        #expect(ready.state.executed.isEmpty)
        #expect(ready.announcement == "Allow for this session. Undo.")

        let low = HubRevision3Decision.step(show(.low), .holdBegan(.allowOnce, at: 0))
        let tap = HubRevision3Decision.step(low.state, .holdReleased(at: 0))
        #expect(tap.state.pending?.action == .allowOnce)
        #expect(tap.state.pending?.holdMilliseconds == 0)
        #expect(tap.state.executed.isEmpty)
    }

    @Test func theCountdownPausesResumesAndExpiresAsDeny() {
        var state = show(.low)
        state = HubRevision3Decision.step(state, .advance(to: 3_000)).state
        #expect(state.remainingMilliseconds == 9_000)
        #expect(state.pending == nil)

        let hovered = HubRevision3Decision.step(state, .pause(.hover, active: true))
        #expect(hovered.announcement == "Countdown paused.")
        state = hovered.state
        let whileHovered = HubRevision3Decision.step(state, .advance(to: 8_000))
        #expect(whileHovered.state.remainingMilliseconds == 9_000)
        #expect(whileHovered.state.executed.isEmpty)
        #expect(whileHovered.state.pending == nil)

        state = HubRevision3Decision.step(whileHovered.state, .pause(.focus, active: true)).state
        state = HubRevision3Decision.step(state, .pause(.voiceOverFocus, active: true)).state
        let still = HubRevision3Decision.step(state, .pause(.hover, active: false))
        #expect(still.announcement == nil)
        #expect(still.state.pauses == [.focus, .voiceOverFocus])
        let stillHeld = HubRevision3Decision.step(still.state, .advance(to: 10_000))
        #expect(stillHeld.state.remainingMilliseconds == 9_000)

        state = HubRevision3Decision.step(stillHeld.state, .pause(.focus, active: false)).state
        let resumed = HubRevision3Decision.step(state, .pause(.voiceOverFocus, active: false))
        #expect(resumed.announcement == "Countdown resumed.")
        #expect(resumed.state.pauses.isEmpty)

        let expired = HubRevision3Decision.step(resumed.state, .advance(to: 19_000))
        #expect(expired.state.pending?.action == .deny)
        #expect(expired.state.pending?.fromCountdown == true)
        #expect(expired.state.pending?.action.isApproval == false)
        #expect(expired.state.pending?.undoUntil == 21_000)
        #expect(expired.state.executed.isEmpty)
        #expect(expired.announcement == "Deny. Undo.")
        #expect(expired.state.pending?.action != .allowOnce)
        #expect(expired.state.pending?.action != .allowForThisSession)
    }

    @Test func eachPauseReasonHoldsTheCountdownOnItsOwn() {
        for reason in HubCountdownPause.allCases {
            var state = show(.high)
            state = HubRevision3Decision.step(state, .pause(reason, active: true)).state
            state = HubRevision3Decision.step(state, .advance(to: 4_000)).state
            #expect(state.remainingMilliseconds == 12_000)
            #expect(state.pending == nil)
            state = HubRevision3Decision.step(state, .pause(reason, active: false)).state
            state = HubRevision3Decision.step(state, .advance(to: 5_000)).state
            #expect(state.remainingMilliseconds == 11_000)
        }
    }

    @Test func aClockJumpStillWaitsOutTheUndoWindowBeforeDeny() {
        let mid = HubRevision3Decision.step(show(.destructive), .advance(to: 13_000))
        #expect(mid.state.pending?.action == .deny)
        #expect(mid.state.pending?.fromCountdown == true)
        #expect(mid.state.executed.isEmpty)
        #expect(mid.state.clock == 13_000)
        #expect(mid.state.pending?.undoUntil == 14_000)

        let jumped = HubRevision3Decision.step(show(.destructive), .advance(to: 14_500))
        #expect(jumped.state.executed.count == 1)
        #expect(jumped.state.executed[0].action == .deny)
        #expect(jumped.state.executed[0].fromCountdown == true)
        #expect(jumped.state.executed[0].action.isApproval == false)
        #expect(jumped.state.executed[0].atMilliseconds == 14_000)
        #expect(jumped.state.pending == nil)
        #expect(jumped.state.clock == 14_500)
        #expect(jumped.state.phase == .idle)
    }

    @Test func theQueueShowsACountAndTheNextDecisionStartsAfterUndo() {
        var state = show(.low, id: "one")
        state = HubRevision3Decision.step(state, .request(item("two", .high))).state
        state = HubRevision3Decision.step(state, .request(item("three", .destructive))).state
        #expect(state.waitingCount == 2)
        #expect(state.visibleCount == 3)
        #expect(state.waiting.map(\.id) == ["two", "three"])
        #expect(HubRevision3Speech.queue(2) == "2 waiting.")

        let duplicate = HubRevision3Decision.step(state, .request(item("two", .low)))
        #expect(duplicate.state == state)

        let decided = HubRevision3Decision.step(state, .key(.three, command: false))
        #expect(decided.state.pending?.action == .deny)
        #expect(decided.state.pending?.requestIDs == ["one"])
        #expect(decided.state.pending?.deniesAllQueued == false)
        #expect(decided.state.executed.isEmpty)
        #expect(decided.state.visibleCount == 3)

        let done = HubRevision3Decision.step(decided.state, .advance(to: 2_000))
        #expect(done.state.showing?.id == "two")
        #expect(done.state.showing?.tier == .high)
        #expect(done.state.waiting.map(\.id) == ["three"])
        #expect(done.state.remainingMilliseconds == 12_000)
        #expect(done.state.executed.map(\.requestIDs) == [["one"]])
        #expect(done.state.visibleCount == 2)
        #expect(done.announcement == "High. 1 waiting.")
    }

    @Test func shiftEscapeDeniesTheShowingDecisionAndEverythingQueued() {
        var state = show(.destructive, id: "one")
        state = HubRevision3Decision.step(state, .request(item("two", .low))).state
        state = HubRevision3Decision.step(state, .request(item("three", .high))).state

        let all = HubRevision3Decision.step(state, .key(.shiftEscape, command: false))
        #expect(all.announcement == "Deny all queued. Undo.")
        #expect(all.state.pending?.deniesAllQueued == true)
        #expect(all.state.pending?.action == .deny)
        #expect(all.state.pending?.requestIDs == ["one", "two", "three"])
        #expect(all.state.executed.isEmpty)
        #expect(all.state.showing?.id == "one")
        #expect(all.state.waiting.map(\.id) == ["two", "three"])

        let restored = HubRevision3Decision.step(all.state, .key(.undo, command: false))
        #expect(restored.state.showing?.id == "one")
        #expect(restored.state.waiting.map(\.id) == ["two", "three"])
        #expect(restored.state.pending == nil)
        #expect(restored.state.executed.isEmpty)

        let fired = HubRevision3Decision.step(all.state, .advance(to: 2_000))
        #expect(fired.state.showing == nil)
        #expect(fired.state.waiting.isEmpty)
        #expect(fired.state.phase == .idle)
        #expect(fired.state.executed.count == 1)
        #expect(fired.state.executed[0].deniesAllQueued)
        #expect(fired.state.executed[0].requestIDs == ["one", "two", "three"])
        #expect(fired.state.executed[0].action == .deny)
    }

    @Test func noteBoundsAreZeroTwoHundredEightyAndTwoHundredEightyOne() throws {
        let empty = HubRevision3Decision.step(show(.low), .key(.four, command: false))
        #expect(empty.state.pending?.action == .denyWithNote)
        #expect(empty.state.pending?.note == "")
        #expect(empty.state.executed.isEmpty)
        #expect(empty.announcement == "Deny with note. Undo.")

        let exact = String(repeating: "a", count: 280)
        #expect(exact.count == 280)
        var noted = HubRevision3Decision.step(show(.high), .replaceNote(exact))
        #expect(noted.state.note == exact)
        #expect(noted.state.pending == nil)
        noted = HubRevision3Decision.step(noted.state, .key(.four, command: false))
        #expect(noted.state.pending?.note == exact)
        #expect(noted.state.pending?.action == .denyWithNote)

        let over = String(repeating: "a", count: 281)
        #expect(over.count == 281)
        let shown = show(.low)
        let rejected = HubRevision3Decision.step(shown, .replaceNote(over))
        #expect(rejected.state == shown)
        #expect(rejected.state.note == "")
        #expect(rejected.state.pending == nil)

        let acute = "\u{0065}\u{0301}"
        let woman = "\u{1F469}\u{200D}\u{1F4BB}"
        #expect(acute.count == 1)
        #expect(woman.count == 1)
        let unicodeExact = String(repeating: woman, count: 280)
        #expect(unicodeExact.count == 280)
        #expect(unicodeExact.utf8.count > 280)
        var unicode = HubRevision3Decision.step(show(.destructive), .replaceNote(unicodeExact))
        #expect(unicode.state.note == unicodeExact)
        unicode = HubRevision3Decision.step(unicode.state, .key(.four, command: false))
        #expect(unicode.state.pending?.note == unicodeExact)
        #expect(unicode.state.pending?.note?.count == 280)

        let unicodeOver = unicodeExact + acute
        #expect(unicodeOver.count == 281)
        let blocked = HubRevision3Decision.step(show(.destructive), .replaceNote(unicodeOver))
        #expect(blocked.state.note == "")
        #expect(blocked.state.pending == nil)
        let denied = HubRevision3Decision.step(blocked.state, .key(.four, command: false))
        #expect(denied.state.pending?.note == "")
        #expect(denied.state.pending?.note != unicodeOver)
    }

    @Test func keysAreInactiveUntilADecisionIsShowingAndCommandDoesNothing() {
        let idle = HubRevision3State()
        let shown = show(.low)
        let pending = HubRevision3Decision.step(shown, .key(.escape, command: false)).state
        #expect(idle.phase == .idle)
        #expect(pending.undoShowing)

        for key in HubDecisionKey.allCases {
            for command in [false, true] {
                let idleOut = HubRevision3Decision.step(idle, .key(key, command: command))
                #expect(idleOut.state == idle)
                #expect(idleOut.announcement == nil)

                let commanded = HubRevision3Decision.step(shown, .key(key, command: true))
                #expect(commanded.state == shown)
                #expect(commanded.announcement == nil)

                let duringUndo = HubRevision3Decision.step(pending, .key(key, command: true))
                #expect(duringUndo.state == pending)
                if command == false, key != .undo {
                    let other = HubRevision3Decision.step(pending, .key(key, command: false))
                    #expect(other.state.executed == pending.executed)
                    #expect(other.state.pending != nil)
                    #expect(other.state.showing?.id == pending.showing?.id)
                }
            }
        }

        let undone = HubRevision3Decision.step(pending, .key(.undo, command: false))
        #expect(undone.state.pending == nil)
        #expect(undone.state.executed.isEmpty)
    }

    @Test func escapeAndThreeDenyWithoutApprovingAndAHoldLosesToTheCountdown() {
        for tier in HubRiskTier.allCases {
            for key in [HubDecisionKey.escape, HubDecisionKey.three] {
                let denied = HubRevision3Decision.step(show(tier), .key(key, command: false))
                #expect(denied.state.pending?.action == .deny)
                #expect(denied.state.pending?.fromCountdown == false)
                #expect(denied.state.pending?.deniesAllQueued == false)
                #expect(denied.state.executed.isEmpty)
                #expect(denied.state.pending?.action.isApproval == false)
            }
        }

        var holding = HubRevision3Decision.step(show(.destructive), .holdBegan(.allowOnce, at: 0)).state
        let lost = HubRevision3Decision.step(holding, .holdReleased(at: 12_000))
        #expect(lost.state.pending?.action == .deny)
        #expect(lost.state.pending?.fromCountdown == true)
        #expect(lost.state.pending?.action.isApproval == false)
        #expect(lost.state.executed.isEmpty)

        holding = HubRevision3Decision.step(show(.destructive), .holdBegan(.allowOnce, at: 0)).state
        let made = HubRevision3Decision.step(holding, .holdReleased(at: 11_999))
        #expect(made.state.pending?.action == .allowOnce)
        #expect(made.state.pending?.fromCountdown == false)
        #expect(made.state.pending?.holdMilliseconds == 11_999)
        #expect(made.state.executed.isEmpty)
    }

    @Test func anUnboundRequestIsRefusedAndTimeDoesNotRunBackwards() {
        let idle = HubRevision3State()
        for request in [
            item(" ", .low),
            item("id", .low, session: " \n\t"),
            item("", .high),
        ] {
            let refused = HubRevision3Decision.step(idle, .request(request))
            #expect(refused.state == idle)
        }

        let moved = HubRevision3Decision.step(show(.low), .advance(to: 1_000)).state
        #expect(moved.remainingMilliseconds == 11_000)
        let back = HubRevision3Decision.step(moved, .advance(to: 500))
        #expect(back.state == moved)
        #expect(back.announcement == nil)

        let same = HubRevision3Decision.step(moved, .advance(to: 1_000))
        #expect(same.state == moved)
    }

    @Test func aRequestThatArrivesDuringUndoIsKeptWhenTheDecisionIsUndone() {
        var state = HubRevision3Decision.step(show(.low, id: "one"), .key(.escape, command: false)).state
        state = HubRevision3Decision.step(state, .request(item("two", .high))).state
        #expect(state.waiting.map(\.id) == ["two"])
        #expect(state.pending != nil)
        let restored = HubRevision3Decision.step(state, .key(.undo, command: false))
        #expect(restored.state.showing?.id == "one")
        #expect(restored.state.waiting.map(\.id) == ["two"])
        #expect(restored.state.pending == nil)
        #expect(restored.state.executed.isEmpty)
        #expect(restored.state.visibleCount == 2)
    }

    @Test func countdownSpeechStaysADenial() {
        #expect(HubRevision3Speech.countdown(remainingMilliseconds: 12_000, paused: false) == "12 s left, then it's denied.")
        #expect(HubRevision3Speech.countdown(remainingMilliseconds: 12_000, paused: true) == "Countdown paused. 12 s left, then it's denied.")
        #expect(HubRevision3Speech.countdown(remainingMilliseconds: 0, paused: false) == "0 s left, then it's denied.")
        #expect(HubRevision3Speech.revealed(tier: .destructive, waiting: 0) == "Destructive. Nothing waiting.")
        #expect(HubRevision3Speech.queue(1) == "1 waiting.")
        for seconds in 0..<13 {
            let line = HubRevision3Speech.countdown(remainingMilliseconds: seconds * 1_000, paused: false)
            #expect(line.contains("approv") == false)
            #expect(line.contains("denied."))
        }
    }

    @Test func transitionsKeepTheQueueNoteAndCountdownInsideTheirBounds() {
        let fixtures = [
            HubRevision3State(),
            show(.low),
            show(.destructive),
            paused(show(.high), .hover),
            HubRevision3Decision.step(show(.destructive), .holdBegan(.allowOnce, at: 0)).state,
            HubRevision3Decision.step(show(.low), .key(.escape, command: false)).state,
        ]
        let notes = ["", String(repeating: "a", count: 280), String(repeating: "b", count: 281), "\u{0065}\u{0301}"]
        for state in fixtures {
            for key in HubDecisionKey.allCases {
                for command in [false, true] {
                    let outcome = HubRevision3Decision.step(state, .key(key, command: command))
                    expectBounds(outcome.state, clockAtLeast: state.clock, executedAtLeast: state.executed.count)
                    if command || state.showing == nil && state.pending == nil {
                        #expect(outcome.state == state)
                    }
                }
            }
            for reason in HubCountdownPause.allCases {
                for active in [false, true] {
                    let outcome = HubRevision3Decision.step(state, .pause(reason, active: active))
                    expectBounds(outcome.state, clockAtLeast: state.clock, executedAtLeast: state.executed.count)
                }
            }
            for action in HubDecisionAction.allCases {
                let began = HubRevision3Decision.step(state, .holdBegan(action, at: state.clock))
                expectBounds(began.state, clockAtLeast: state.clock, executedAtLeast: state.executed.count)
                if !action.isApproval || state.decisionShowing == false {
                    #expect(began.state.pending == state.pending)
                    #expect(began.state.executed == state.executed)
                }
            }
            for note in notes {
                let replaced = HubRevision3Decision.step(state, .replaceNote(note))
                expectBounds(replaced.state, clockAtLeast: state.clock, executedAtLeast: state.executed.count)
                #expect(replaced.state.note.count <= 280)
                if note.count > 280 || state.decisionShowing == false {
                    #expect(replaced.state.note == state.note)
                } else {
                    #expect(replaced.state.note == note)
                }
            }
            let backward = HubRevision3Decision.step(state, .advance(to: state.clock - 1))
            #expect(backward.state == state)
            let stayed = HubRevision3Decision.step(state, .advance(to: state.clock))
            #expect(stayed.state == state)
        }
    }

    @Test func randomStepsNeverExecuteEarlyOrApproveFromTheCountdown() {
        var draw = RevisionDraw(state: 0x7E3A_12C0_0000_0003)
        var state = HubRevision3State()
        for _ in 0..<400 {
            let event = draw.event(clock: state.clock)
            let before = state.executed.count
            let outcome = HubRevision3Decision.step(state, event)
            expectBounds(outcome.state, clockAtLeast: state.clock, executedAtLeast: before)
            if case .key(_, true) = event {
                #expect(outcome.state == state)
            }
            if let pending = outcome.state.pending, outcome.state.clock < pending.undoUntil {
                #expect(outcome.state.executed.count == before)
            }
            for execution in outcome.state.executed where execution.fromCountdown {
                #expect(execution.action == .deny)
                #expect(execution.action.isApproval == false)
            }
            for execution in outcome.state.executed where execution.action.isApproval && execution.tier == .destructive {
                #expect((execution.holdMilliseconds ?? -1) >= 1_200)
            }
            state = outcome.state
        }
    }

    @Test func theMachineDoesNotReadTheWallClock() throws {
        let source = try machineSource()
        let banned = ["Date(", "Date.", "ContinuousClock", "SuspendingClock", "CFAbsoluteTime", "Task.sleep", ".now"]
        for word in banned {
            #expect(source.contains(word) == false)
        }
    }

    private func show(_ tier: HubRiskTier, id: String = "a") -> HubRevision3State {
        HubRevision3Decision.step(.init(), .request(item(id, tier))).state
    }

    private func item(_ id: String, _ tier: HubRiskTier, session: String = "session") -> HubRevision3Request {
        HubRevision3Request(id: id, sessionID: session, tier: tier)
    }

    private func paused(_ state: HubRevision3State, _ reason: HubCountdownPause) -> HubRevision3State {
        HubRevision3Decision.step(state, .pause(reason, active: true)).state
    }

    private func expectBounds(_ state: HubRevision3State, clockAtLeast clock: Int, executedAtLeast count: Int) {
        #expect(state.clock >= clock)
        #expect(state.executed.count >= count)
        #expect(state.remainingMilliseconds >= 0)
        #expect(state.remainingMilliseconds <= 12_000)
        #expect(state.note.count <= 280)
        #expect((state.pending?.note?.count ?? 0) <= 280)
        #expect(state.visibleCount == (state.showing == nil ? 0 : 1) + state.waitingCount)
        #expect(state.waitingCount == state.waiting.count)
        var ids = state.waiting.map(\.id)
        if let showing = state.showing { ids.append(showing.id) }
        #expect(Set(ids).count == ids.count)
        if state.pending != nil {
            #expect(state.phase == .pendingUndo)
            #expect(state.undoShowing)
            #expect(state.decisionShowing == false)
        } else if state.holdBeganAt != nil {
            #expect(state.phase == .holding)
            #expect(state.decisionShowing)
        } else if state.showing != nil {
            #expect(state.phase == .showing)
            #expect(state.decisionShowing)
        } else {
            #expect(state.phase == .idle)
            #expect(state.decisionShowing == false)
        }
        for execution in state.executed {
            #expect((execution.note?.count ?? 0) <= 280)
            if execution.fromCountdown {
                #expect(execution.action == .deny)
            }
            if execution.action.isApproval, execution.tier == .destructive {
                #expect((execution.holdMilliseconds ?? -1) >= 1_200)
            }
        }
    }

    private func machineSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/ZeusCore/AgentHub/HubRevision3Decision.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// A fixed generator so the property is the same on every run.
private struct RevisionDraw {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    mutating func event(clock: Int) -> HubRevision3Event {
        switch int(8) {
        case 0:
            let tier = HubRiskTier.allCases[int(HubRiskTier.allCases.count)]
            let session = int(5) == 0 ? "  " : "session"
            return .request(HubRevision3Request(id: "id-\(int(6))", sessionID: session, tier: tier))
        case 1:
            return .advance(to: clock + int(15_000))
        case 2:
            return .key(HubDecisionKey.allCases[int(HubDecisionKey.allCases.count)], command: int(4) == 0)
        case 3:
            return .pause(HubCountdownPause.allCases[int(HubCountdownPause.allCases.count)], active: int(2) == 0)
        case 4:
            return .holdBegan(HubDecisionAction.allCases[int(HubDecisionAction.allCases.count)], at: clock + int(3))
        case 5:
            return .holdReleased(at: clock + int(2_001))
        default:
            let count = int(6) == 0 ? 281 : int(281)
            return .replaceNote(String(repeating: "\u{0065}\u{0301}", count: count))
        }
    }
}
