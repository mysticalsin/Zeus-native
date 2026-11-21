import Foundation
import Testing
@testable import ZeusCore

/// Hook lines drive one session through the session table. An observe-only source never
/// grows Approve. A failed socket is the connection-error screen. One finish is one sound
/// decision, and the extra finish sound stays off.
@Suite("Hook adapter")
struct HookAdapterTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 80_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func seed(_ status: HubSessionStatus) -> HubSessionState {
        HubSessionState(status: status, clockGeneration: 5, previous: .waitingForInput)
    }

    private func message(
        _ event: String,
        source: HookEvent.Source,
        sessionID: String = "s1",
        tool: String? = nil,
        command: String? = nil,
        needsDecision: Bool = false,
        autoApproves: Bool = false
    ) -> HubHookMessage {
        HubHookMessage(
            source: source,
            event: event,
            sessionID: sessionID,
            tool: tool,
            command: command,
            needsDecision: needsDecision,
            autoApproves: autoApproves
        )
    }

    /// The spec's hook-to-session map. Quiet tool, question, and permission lines are activity.
    /// A family that cannot ask never sends `approvalRequested`. A question never does either.
    private func mapped(
        _ event: String,
        status: HubSessionStatus,
        capable: Bool,
        tool: String?,
        command: String?,
        autoApproves: Bool
    ) -> HubSessionEvent? {
        if let command, HandsBlocklist.reason(command) != nil,
           event == "PermissionRequest" || event == "PreToolUse" || event == "PostToolUse" {
            return .failed
        }
        let question = HubHookFamily.isQuestion(event: event, tool: tool)
        let quiet = status == .error(.quiet)
        switch event {
        case "SessionStart":
            return .announced
        case "UserPromptSubmit":
            return .promptStarted
        case "PreToolUse":
            return quiet ? .activity : .toolActivity
        case "PostToolUse":
            if question, status == .waitingForInput { return .answerAccepted }
            return quiet ? .activity : .toolActivity
        case "PermissionRequest":
            if autoApproves, !question { return quiet ? .activity : .toolActivity }
            if question { return quiet ? .activity : .questionAsked }
            if capable { return quiet ? .activity : .approvalRequested }
            return quiet ? .activity : .toolActivity
        case "AskUserQuestion":
            return quiet ? .activity : .questionAsked
        case "Stop":
            return .finished
        case "StopFailure":
            return .failed
        case "SessionEnd":
            return .ended
        case "QuietForTheStallLimit":
            return .quietForTheStallLimit
        case "AgentResponse", "Notification":
            return nil
        default:
            return nil
        }
    }

    private func grow(
        event: String,
        before: HubSessionState,
        after: HubSessionState,
        capable: Bool,
        tool: String?,
        command: String?,
        autoApproves: Bool
    ) -> Bool {
        let question = HubHookFamily.isQuestion(event: event, tool: tool)
        let blocked = command.flatMap(HandsBlocklist.reason) != nil
        return event == "PermissionRequest"
            && capable
            && !question
            && !autoApproves
            && !blocked
            && before.status != .needsApproval
            && after.status == .needsApproval
    }

    @Test func oneSessionWalksRunningWaitingApprovalDoneAndError() {
        var book = HubHookBook()
        #expect(book.screen == .connectionError)
        #expect(book.screen.sentence == "Agents aren't connected.")
        #expect(book.screen.sentence != HubScreen.empty.sentence)

        book.open()
        #expect(book.screen == .empty)
        #expect(book.screen.sentence == "Nothing running")

        book.optIn()
        var step = book.apply(message("SessionStart", source: .codex), now: at(0))
        #expect(step.state.status == .loading)
        #expect(step.state.clockGeneration == 0)
        #expect(step.growsApprove == false)
        #expect(book.screen == .ready)

        step = book.apply(message("UserPromptSubmit", source: .codex), now: at(0))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == 1)
        #expect(step.state.clockPhase == .ticking)

        step = book.apply(message("PreToolUse", source: .codex, tool: "Read"), now: at(1))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == 1)
        #expect(step.growsApprove == false)

        step = book.apply(message("AskUserQuestion", source: .codex, needsDecision: true), now: at(2))
        #expect(step.state.status == .waitingForInput)
        #expect(step.state.clockGeneration == 1)
        #expect(step.growsApprove == false)
        #expect(step.soundDecisions.isEmpty)

        step = book.apply(message("PermissionRequest", source: .codex, tool: "Bash", needsDecision: true), now: at(3))
        #expect(step.state.status == .needsApproval)
        #expect(step.state.previous == .waitingForInput)
        #expect(step.state.clockGeneration == 1)
        #expect(step.growsApprove == true)

        step = book.resolve(sessionID: "s1", verdict: .deny, now: at(4))
        #expect(step.state.status == .waitingForInput)
        #expect(step.state.previous == nil)
        #expect(step.state.clockGeneration == 1)
        #expect(step.growsApprove == false)

        step = book.apply(message("PostToolUse", source: .codex, tool: "AskUserQuestion"), now: at(5))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == 1)

        step = book.apply(message("PermissionRequest", source: .codex, tool: "Bash", needsDecision: true), now: at(6))
        #expect(step.state.status == .needsApproval)
        #expect(step.state.previous == .running)
        #expect(step.growsApprove == true)

        step = book.resolve(sessionID: "s1", verdict: .allow, now: at(7))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == 1)
        #expect(step.growsApprove == false)

        step = book.apply(message("PermissionRequest", source: .codex, tool: "Bash"), now: at(8))
        step = book.resolve(sessionID: "s1", verdict: .ask, now: at(9))
        #expect(step.state.status == .running)

        step = book.apply(message("PermissionRequest", source: .codex, tool: "Bash"), now: at(10))
        step = book.resolve(sessionID: "s1", verdict: .allow, timedOut: true, now: at(11))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == 1)

        step = book.apply(message("Stop", source: .codex), now: at(21), systemFinishSound: true)
        #expect(step.state.status == .done)
        #expect(step.state.clockPhase == .frozen)
        #expect(step.state.clockGeneration == 1)
        #expect(step.growsApprove == false)
        #expect(step.soundDecisions.count == 1)
        #expect(step.soundDecisions[0].cues == [.done])
        #expect(step.playsExtraFinishSound == false)
        #expect(book.screen == .ready)

        step = book.apply(message("SessionEnd", source: .codex), now: at(22))
        #expect(step.state.status == .absent)
        #expect(book.sessions["s1"] == nil)
        #expect(book.screen == .empty)

        step = book.apply(message("SessionStart", source: .codex, sessionID: "s2"), now: at(30))
        step = book.apply(message("UserPromptSubmit", source: .codex, sessionID: "s2"), now: at(30))
        let runningGeneration = step.state.clockGeneration
        step = book.apply(message("StopFailure", source: .codex, sessionID: "s2"), now: at(31))
        #expect(step.state.status == .error(.failed))
        #expect(step.state.clockPhase == .frozen)
        #expect(step.state.clockGeneration == runningGeneration)
        #expect(step.soundDecisions.isEmpty)
        #expect(step.playsExtraFinishSound == false)

        step = book.apply(message("PreToolUse", source: .codex, sessionID: "s2", tool: "Read"), now: at(32))
        #expect(step.state.status == .error(.failed))

        step = book.apply(message("UserPromptSubmit", source: .codex, sessionID: "s2"), now: at(33))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == runningGeneration + 1)

        let restarted = step.state.clockGeneration
        step = book.apply(message("QuietForTheStallLimit", source: .codex, sessionID: "s2"), now: at(34))
        #expect(step.state.status == .error(.quiet))
        #expect(step.state.clockGeneration == restarted)
        #expect(step.state.clockPhase == .frozen)

        step = book.apply(message("PreToolUse", source: .codex, sessionID: "s2", tool: "Read"), now: at(35))
        #expect(step.state.status == .running)
        #expect(step.state.clockGeneration == restarted)
    }

    @Test func anObserveOnlySourceNeverGrowsApprove() {
        for source in HubHookFamily.observingSources {
            var book = HubHookBook(sessions: ["s9": seed(.running)], connection: .open)
            let step = book.apply(
                message("PermissionRequest", source: source, sessionID: "s9", tool: "Bash", needsDecision: true),
                now: at(0),
                systemFinishSound: true
            )
            #expect(step.growsApprove == false)
            #expect(step.state.status == .running)
            #expect(step.state.clockGeneration == 5)
            #expect(step.soundDecisions.isEmpty)
            #expect(step.playsExtraFinishSound == false)
            #expect(!HubHookFamily.canAsk(source))
        }
    }

    @Test func anObserveOnlyQuestionCanWaitWithoutApprove() {
        var book = HubHookBook(sessions: ["s9": seed(.running)], connection: .open)
        let step = book.apply(
            message("AskUserQuestion", source: .gemini, sessionID: "s9", needsDecision: true),
            now: at(0)
        )
        #expect(step.state.status == .waitingForInput)
        #expect(step.growsApprove == false)
    }

    @Test func askingFamiliesAreTheOnlyOnesThatCanApprove() {
        for source in HubHookFamily.askingSources {
            #expect(HubHookFamily.canAsk(source))
        }
        for source in HubHookFamily.observingSources {
            #expect(!HubHookFamily.canAsk(source))
        }
    }

    @Test func aQuestionDoesNotGrowApprove() {
        var book = HubHookBook(sessions: ["s1": seed(.running)], connection: .open)
        let step = book.apply(
            message("PermissionRequest", source: .codex, tool: "AskUserQuestion", needsDecision: true),
            now: at(0)
        )
        #expect(step.state.status == .waitingForInput)
        #expect(step.growsApprove == false)
    }

    @Test func aBlockedCommandFailsClosedWithoutApprove() {
        var book = HubHookBook(sessions: ["s1": seed(.running)], connection: .open)
        let step = book.apply(
            message("PermissionRequest", source: .codex, tool: "Bash", command: "rm notes", needsDecision: true),
            now: at(0)
        )
        #expect(step.state.status == .error(.failed))
        #expect(step.growsApprove == false)
        #expect(step.soundDecisions.isEmpty)
    }

    @Test func autoApproveDoesNotGrowApprove() {
        var book = HubHookBook(sessions: ["s1": seed(.running)], connection: .open)
        let step = book.apply(
            message("PermissionRequest", source: .codex, tool: "Read", needsDecision: true, autoApproves: true),
            now: at(0)
        )
        #expect(step.state.status == .running)
        #expect(step.growsApprove == false)
    }

    @Test func deniedAndTimedOutReturnToTheStoredStatus() {
        var waiting = HubHookBook(
            sessions: ["s1": HubSessionState(status: .needsApproval, clockGeneration: 2, previous: .waitingForInput)],
            connection: .open
        )
        let denied = waiting.resolve(sessionID: "s1", verdict: .deny, now: at(0))
        #expect(denied.state.status == .waitingForInput)
        #expect(denied.state.previous == nil)
        #expect(denied.state.clockGeneration == 2)

        var running = HubHookBook(
            sessions: ["s1": HubSessionState(status: .needsApproval, clockGeneration: 2, previous: .running)],
            connection: .open
        )
        let timedOut = running.resolve(sessionID: "s1", verdict: .allow, timedOut: true, now: at(0))
        #expect(timedOut.state.status == .running)
        #expect(timedOut.state.clockGeneration == 2)
        let again = running.resolve(sessionID: "s1", verdict: .ask, now: at(1))
        #expect(again.state.status == .running)

        var asking = HubHookBook(
            sessions: ["s1": HubSessionState(status: .needsApproval, clockGeneration: 2, previous: .running)],
            connection: .open
        )
        let asked = asking.resolve(sessionID: "s1", verdict: .ask, now: at(1))
        #expect(asked.state.status == .running)
        #expect(asked.state.clockGeneration == 2)
        #expect(asked.growsApprove == false)
    }

    @Test func everyHookPairFollowsTheSessionTable() {
        let events = [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "AskUserQuestion", "Stop", "StopFailure",
            "SessionEnd", "AgentResponse", "Notification", "QuietForTheStallLimit",
        ]
        for status in HubSessionStatus.allCases {
            for event in events {
                for capable in [true, false] {
                    let source: HookEvent.Source = capable ? .codex : .cursor
                    let before = seed(status)
                    var book = HubHookBook(sessions: ["s": before], connection: .open)
                    let step = book.apply(
                        message(event, source: source, sessionID: "s", needsDecision: true),
                        now: at(0),
                        systemFinishSound: true
                    )
                    let eventMapped = mapped(event, status: status, capable: capable, tool: nil, command: nil, autoApproves: false)
                    let expected = eventMapped.map { HubSessionMachine.next(before, $0) } ?? before
                    #expect(step.state == expected, "\(status.storedLabel) \(event) capable \(capable)")
                    #expect(step.rejection == nil)
                    #expect(
                        step.growsApprove == grow(
                            event: event, before: before, after: expected, capable: capable,
                            tool: nil, command: nil, autoApproves: false
                        )
                    )
                    #expect(step.playsExtraFinishSound == false)
                    #expect(step.soundDecisions.count == (event == "Stop" ? 1 : 0))
                    if event == "Stop" {
                        #expect(step.soundDecisions[0].cues.count <= 1)
                    }
                    if expected.status == .absent {
                        #expect(book.sessions["s"] == nil)
                    } else {
                        #expect(book.sessions["s"] == expected)
                    }
                }
            }
        }
    }

    @Test func questionAndBlockedPairsFollowTheSessionTable() {
        let tools = ["AskUserQuestion", "Bash"]
        let events = ["PermissionRequest", "PreToolUse", "PostToolUse"]
        for status in HubSessionStatus.allCases {
            for event in events {
                for tool in tools {
                    for capable in [true, false] {
                        let source: HookEvent.Source = capable ? .claudeCode : .gemini
                        let before = seed(status)
                        var book = HubHookBook(sessions: ["s": before], connection: .open)
                        let command = tool == "Bash" && event == "PermissionRequest" ? "rm notes" : nil
                        let step = book.apply(
                            message(event, source: source, sessionID: "s", tool: tool, command: command, needsDecision: true),
                            now: at(0),
                            systemFinishSound: true
                        )
                        let eventMapped = mapped(
                            event, status: status, capable: capable, tool: tool, command: command, autoApproves: false
                        )
                        let expected = eventMapped.map { HubSessionMachine.next(before, $0) } ?? before
                        #expect(step.state == expected, "\(status.storedLabel) \(event) \(tool) capable \(capable)")
                        #expect(
                            step.growsApprove == grow(
                                event: event, before: before, after: expected, capable: capable,
                                tool: tool, command: command, autoApproves: false
                            )
                        )
                        #expect(step.playsExtraFinishSound == false)
                        #expect(step.soundDecisions.isEmpty)
                    }
                }
            }
        }
    }

    @Test func oneFinishIsOneSoundDecisionAndTheExtraSoundStaysOff() {
        var armed = HubHookBook(connection: .open)
        armed.optIn()
        _ = armed.apply(message("SessionStart", source: .codex, sessionID: "a"), now: at(0))
        _ = armed.apply(message("UserPromptSubmit", source: .codex, sessionID: "a"), now: at(0))

        let short = armed.apply(message("Stop", source: .codex, sessionID: "a"), now: at(19), systemFinishSound: true)
        #expect(short.soundDecisions.count == 1)
        #expect(short.soundDecisions[0].cues == [])
        #expect(short.playsExtraFinishSound == false)

        var once = HubHookBook(connection: .open)
        once.optIn()
        _ = once.apply(message("SessionStart", source: .codex, sessionID: "a"), now: at(0))
        _ = once.apply(message("UserPromptSubmit", source: .codex, sessionID: "a"), now: at(0))
        let done = once.apply(message("Stop", source: .codex, sessionID: "a"), now: at(20), systemFinishSound: true)
        #expect(done.soundDecisions.count == 1)
        #expect(done.soundDecisions[0].cues == [.done])
        #expect(done.playsExtraFinishSound == false)

        var paired = HubHookBook(connection: .open)
        paired.optIn()
        _ = paired.apply(message("SessionStart", source: .codex, sessionID: "a"), now: at(0))
        _ = paired.apply(message("UserPromptSubmit", source: .codex, sessionID: "a"), now: at(0))
        _ = paired.apply(message("SessionStart", source: .codex, sessionID: "b"), now: at(0))
        _ = paired.apply(message("UserPromptSubmit", source: .codex, sessionID: "b"), now: at(0))
        let first = paired.apply(message("Stop", source: .codex, sessionID: "a"), now: at(30), systemFinishSound: true)
        let second = paired.apply(message("Stop", source: .codex, sessionID: "b"), now: at(31), systemFinishSound: true)
        #expect(first.soundDecisions.count == 1)
        #expect(first.soundDecisions[0].cues == [.done])
        #expect(second.soundDecisions.count == 1)
        #expect(second.soundDecisions[0].cues == [])
        #expect(first.playsExtraFinishSound == false)
        #expect(second.playsExtraFinishSound == false)

        var silent = HubHookBook(connection: .open)
        _ = silent.apply(message("SessionStart", source: .codex), now: at(0))
        _ = silent.apply(message("UserPromptSubmit", source: .codex), now: at(0))
        let quiet = silent.apply(message("Stop", source: .codex), now: at(40), systemFinishSound: true)
        #expect(quiet.soundDecisions.count == 1)
        #expect(quiet.soundDecisions[0].cues == [])
        #expect(quiet.playsExtraFinishSound == false)

        var optedOut = HubHookBook(connection: .open)
        optedOut.optIn()
        optedOut.optOut()
        _ = optedOut.apply(message("SessionStart", source: .codex), now: at(0))
        _ = optedOut.apply(message("UserPromptSubmit", source: .codex), now: at(0))
        let muted = optedOut.apply(message("Stop", source: .codex), now: at(40), systemFinishSound: true)
        #expect(muted.soundDecisions.count == 1)
        #expect(muted.soundDecisions[0].cues == [])
        #expect(muted.playsExtraFinishSound == false)
    }

    @Test func aFailedSocketIsTheConnectionErrorNotTheEmptySentence() {
        #expect(HubHookConnection.screen(.failed, sessionCount: 0) == .connectionError)
        #expect(HubHookConnection.screen(.failed, sessionCount: 2) == .connectionError)
        #expect(HubHookConnection.screen(.opening, sessionCount: 0) == .loading)
        #expect(HubHookConnection.screen(.open, sessionCount: 0) == .empty)
        #expect(HubHookConnection.screen(.open, sessionCount: 1) == .ready)

        let failed = HubHookConnection.screen(.failed, sessionCount: 0)
        #expect(failed.sentence == "Agents aren't connected.")
        #expect(failed.sentence != "Nothing running")
        #expect(failed.sentence?.contains("/") == false)
        #expect(failed.actionTitle == "Try again")
        #expect(HubScreen.empty.sentence == "Nothing running")
        #expect(HubScreen.empty.actionTitle == "New chat")

        var book = HubHookBook()
        #expect(book.screen == .connectionError)
        book.beginOpening()
        #expect(book.screen == .loading)
        book.fail()
        #expect(book.screen == .connectionError)
        book.open()
        #expect(book.screen == .empty)
        _ = book.apply(message("SessionStart", source: .codex), now: at(0))
        #expect(book.screen == .ready)
        book.fail()
        #expect(book.screen == .connectionError)
        #expect(book.sessions["s1"]?.status == .loading)
        #expect(book.screen.sentence != HubScreen.empty.sentence)
    }

    @Test func theSocketPathAndPeerAreCheckedBeforeALineIsTrusted() {
        let expected = "/fixture/zeus.sock"
        #expect(HubHookGate.acceptsSocketPath(expected, expected: expected))
        #expect(!HubHookGate.acceptsSocketPath("/fixture/other.sock", expected: expected))
        #expect(!HubHookGate.acceptsSocketPath("/tmp/zeus.sock", expected: expected))
        #expect(!HubHookGate.acceptsSocketPath("zeus.sock", expected: "zeus.sock"))
        #expect(!HubHookGate.acceptsSocketPath("/fixture/../zeus.sock", expected: "/fixture/../zeus.sock"))
        #expect(!HubHookGate.acceptsSocketPath("/fixture/./zeus.sock", expected: "/fixture/./zeus.sock"))
        #expect(!HubHookGate.acceptsSocketPath("/fixture//zeus.sock", expected: "/fixture//zeus.sock"))
        let tooLong = "/" + String(repeating: "a", count: HubHookGate.maximumPathBytes)
        #expect(!HubHookGate.acceptsSocketPath(tooLong, expected: tooLong))
        let hostile = "/fixture/zeus.sock\u{0}"
        #expect(!HubHookGate.acceptsSocketPath(hostile, expected: hostile))

        #expect(HubHookGate.admits(peer: .allow))
        #expect(!HubHookGate.admits(peer: .deny("peer uid 1 is not the owner")))
        #expect(!HubHookGate.admits(peer: PeerCheck.decide(.sameUser, ownUID: 501, peer: nil)))
        #expect(!HubHookGate.admits(peer: PeerCheck.decide(.sameUser, ownUID: 501, peer: PeerIdentity(uid: 0))))
        let sameUser = PeerCheck.decide(.sameUser, ownUID: 501, peer: PeerIdentity(uid: 501, executablePath: "/fixture/helper"))
        #expect(HubHookGate.admits(peer: sameUser))
    }

    @Test func hostileLinesFailClosedAndDoNotMoveTheSession() throws {
        let running = HubSessionState(status: .running, clockGeneration: 3, previous: nil)
        func book() -> HubHookBook {
            HubHookBook(sessions: ["s1": running], connection: .open)
        }

        var denied = book()
        let secret = "sk-live-secret-value"
        let permission = try JSONEncoder().encode(HookEvent(
            id: "evt-1", source: .codex, event: "PermissionRequest", session: "s1",
            tool: "Bash", input: .object(["command": .string(secret)]), needsDecision: true
        ))
        let dropped = denied.receive(line: permission, peer: .deny("peer uid 9 is not the owner"), now: at(0))
        #expect(dropped.rejection == .peerDenied)
        #expect(dropped.growsApprove == false)
        #expect(dropped.soundDecisions.isEmpty)
        #expect(denied.sessions["s1"] == running)
        #expect(String(describing: dropped.rejection).contains(secret) == false)

        var oversized = book()
        let huge = Data(count: HubHookGate.maximumMessageBytes + 1)
        let tooBig = oversized.receive(line: huge, peer: .allow, now: at(0))
        #expect(tooBig.rejection == .oversized)
        #expect(oversized.sessions["s1"] == running)

        let malformedSamples = [
            Data(),
            Data("{".utf8),
            Data("[]".utf8),
            Data("null".utf8),
            Data("\"Stop\"".utf8),
            Data("}{".utf8),
            Data([0x00]),
            Data("{\"v\":1,\"id\":\"e\",\"source\":\"codex\",\"event\":\"Stop\",\"session\":\"s1\"}".utf8),
            Data("{\"v\":2,\"id\":\"e\",\"source\":\"codex\",\"event\":\"Stop\",\"session\":\"s1\",\"needsDecision\":false}".utf8),
            Data("{\"v\":1,\"id\":\"e\",\"source\":\"codex\",\"event\":\"Stop\",\"session\":\"s1\",\"needsDecision\":\"yes\"}".utf8),
        ]
        for sample in malformedSamples {
            var target = book()
            let step = target.receive(line: sample, peer: .allow, now: at(0))
            #expect(step.rejection == .malformed)
            #expect(step.growsApprove == false)
            #expect(target.sessions["s1"] == running)
        }

        var unknownEvent = book()
        let droppedEvent = Data("{\"v\":1,\"id\":\"e\",\"source\":\"codex\",\"event\":\"DropAll\",\"session\":\"s1\",\"needsDecision\":true,\"detail\":\"\(secret)\"}".utf8)
        let unknown = unknownEvent.receive(line: droppedEvent, peer: .allow, now: at(0))
        #expect(unknown.rejection == .unknownEvent)
        #expect(unknown.growsApprove == false)
        #expect(unknownEvent.sessions["s1"] == running)
        #expect(String(describing: unknown.rejection).contains(secret) == false)

        var quiet = HubHookBook(
            sessions: ["s1": HubSessionState(status: .error(.quiet), clockGeneration: 4)],
            connection: .open
        )
        let stillQuiet = quiet.receive(line: droppedEvent, peer: .allow, now: at(0))
        #expect(stillQuiet.rejection == .unknownEvent)
        #expect(quiet.sessions["s1"]?.status == .error(.quiet))
        #expect(quiet.sessions["s1"]?.clockGeneration == 4)

        var unknownSource = book()
        let other = Data("{\"v\":1,\"id\":\"e\",\"source\":\"other\",\"event\":\"Stop\",\"session\":\"s1\",\"needsDecision\":false}".utf8)
        #expect(unknownSource.receive(line: other, peer: .allow, now: at(0)).rejection == .unknownSource)
        #expect(unknownSource.sessions["s1"] == running)

        var longID = book()
        let bigID = String(repeating: "a", count: HubHookGate.maximumIdentifierBytes + 1)
        let longLine = Data("{\"v\":1,\"id\":\"\(bigID)\",\"source\":\"codex\",\"event\":\"Stop\",\"session\":\"s1\",\"needsDecision\":false}".utf8)
        #expect(longID.receive(line: longLine, peer: .allow, now: at(0)).rejection == .unboundedField)
        #expect(longID.sessions["s1"] == running)

        var exactID = book()
        let fitted = String(repeating: "b", count: HubHookGate.maximumIdentifierBytes)
        let fittedLine = Data("{\"v\":1,\"id\":\"\(fitted)\",\"source\":\"codex\",\"event\":\"Notification\",\"session\":\"s1\",\"needsDecision\":false}".utf8)
        let fittedStep = exactID.receive(line: fittedLine, peer: .allow, now: at(0))
        #expect(fittedStep.rejection == nil)
        #expect(exactID.sessions["s1"] == running)

        var badSession = book()
        let brokenSession = Data("{\"v\":1,\"id\":\"e\",\"source\":\"codex\",\"event\":\"Stop\",\"session\":\"s1\\nhidden\",\"needsDecision\":false}".utf8)
        #expect(badSession.receive(line: brokenSession, peer: .allow, now: at(0)).rejection == .unboundedField)

        var deep = book()
        let nested = String(repeating: "{\"a\":", count: HubHookGate.maximumDepth + 1) + "1" + String(repeating: "}", count: HubHookGate.maximumDepth + 1)
        #expect(deep.receive(line: Data(nested.utf8), peer: .allow, now: at(0)).rejection == .unboundedField)
        #expect(deep.sessions["s1"] == running)

        var missingSession = book()
        let noSession = Data("{\"v\":1,\"id\":\"e\",\"source\":\"codex\",\"event\":\"Stop\",\"needsDecision\":false}".utf8)
        #expect(missingSession.receive(line: noSession, peer: .allow, now: at(0)).rejection == .malformed)
        #expect(missingSession.sessions["s1"] == running)
    }

    @Test func aClientCannotGrantItselfAutoApprove() throws {
        var book = HubHookBook(sessions: ["s1": seed(.running)], connection: .open)
        let line = Data("{\"v\":1,\"id\":\"e\",\"source\":\"codex\",\"event\":\"PermissionRequest\",\"session\":\"s1\",\"tool\":\"Bash\",\"needsDecision\":true,\"autoApproves\":true}".utf8)
        let inspected = try #require(try HubHookGate.inspect(line: line, peer: .allow).get())
        #expect(inspected.autoApproves == false)
        #expect(inspected.event == "PermissionRequest")
        let step = book.apply(inspected, now: at(0))
        #expect(step.growsApprove == true)
        #expect(step.state.status == .needsApproval)
        #expect(String(describing: step.rejection).contains("autoApproves") == false)
    }

    @Test func anEncodedEnvelopeRoundTripsOntoTheSession() throws {
        var book = HubHookBook()
        book.open()
        let started = try JSONEncoder().encode(HookEvent(
            id: "evt-1", source: .codex, event: "SessionStart", session: "s1", needsDecision: false
        ))
        let loading = book.receive(line: started, peer: .allow, now: at(0))
        #expect(loading.rejection == nil)
        #expect(loading.state.status == .loading)

        let prompted = try JSONEncoder().encode(HookEvent(
            id: "evt-2", source: .codex, event: "UserPromptSubmit", session: "s1",
            detail: "count the files", needsDecision: false
        ))
        let running = book.receive(line: prompted, peer: .allow, now: at(0))
        #expect(running.state.status == .running)
        #expect(running.growsApprove == false)

        let observed = try JSONEncoder().encode(HookEvent(
            id: "evt-3", source: .cursor, event: "PermissionRequest", session: "s1",
            tool: "Bash", needsDecision: true
        ))
        let held = book.receive(line: observed, peer: .allow, now: at(1), systemFinishSound: true)
        #expect(held.rejection == nil)
        #expect(held.state.status == .running)
        #expect(held.growsApprove == false)
        #expect(held.playsExtraFinishSound == false)
        #expect(held.soundDecisions.isEmpty)
    }
}
