import Foundation
import Testing
@testable import ZeusCore

/// The reply gate's transition table. A typed line is legal in one cell only:
/// the selected row, awaiting a decision, Approve, a destination that can take text,
/// and a cleaned line that can be embedded. Trust does not add a cell.
@Suite("Reply gate")
struct HubReplyGateTests {
    private let session = "s10"
    private let other = "s11"

    @Test func aSelectedReplyTypesOnlyAfterApproveAndKeepsTheDraft() {
        for trusted in [false, true] {
            var gate = HubReplyDispatch(boundSessionID: session)
            var log = KeystrokeLog()
            log.record(gate.perform(.textChanged, sessionID: session, field: "hello", destinationCanTakeText: true, trusted: trusted))
            let asked = gate.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: true, trusted: trusted)
            log.record(asked)
            #expect(asked.asksInline)
            #expect(asked.state.status == .awaitingDecision)
            #expect(asked.state.draft == "hello")
            #expect(asked.state.script == nil)
            #expect(log.lines.isEmpty)

            let denied = gate.perform(.denied, sessionID: session, field: "hello", destinationCanTakeText: true, trusted: trusted)
            log.record(denied)
            #expect(denied.state.status == .idle)
            #expect(denied.state.draft == "hello")
            #expect(denied.state.receipt == .notSent)
            #expect(denied.typedLine == nil)

            log.record(gate.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: true, trusted: trusted))
            let cancelled = gate.cancel(sessionID: session)
            log.record(cancelled)
            #expect(cancelled.state.status == .drafting)
            #expect(cancelled.state.draft == "hello")
            #expect(cancelled.state.receipt == nil)
            #expect(cancelled.state.script == nil)
            #expect(log.lines.isEmpty)

            let again = gate.cancel(sessionID: session)
            #expect(again.state == cancelled.state)
            #expect(again.typedLine == nil)

            log.record(gate.perform(.textChanged, sessionID: session, field: "hello there", destinationCanTakeText: true, trusted: trusted))
            log.record(gate.perform(.send, sessionID: session, field: "hello there", destinationCanTakeText: true, trusted: trusted))
            let approved = gate.perform(.approved, sessionID: session, field: "ignored", destinationCanTakeText: true, trusted: trusted, foreground: .agent)
            log.record(approved)
            #expect(log.lines == ["hello there"])
            #expect(approved.state.status == .sending)
            #expect(approved.state.script == "hello there")
            let second = gate.perform(.approved, sessionID: session, field: "hello there", destinationCanTakeText: true, trusted: trusted)
            log.record(second)
            #expect(second.typedLine == nil)
            #expect(log.lines == ["hello there"])

            let done = gate.finished(sessionID: session, typed: true)
            log.record(done)
            #expect(done.state.status == .idle)
            #expect(done.state.draft == "")
            #expect(done.state.receipt == .sent)
            #expect(done.state.script == nil)
            #expect(log.lines == ["hello there"])
            #expect(log.lines.allSatisfy { !isScript($0) })
        }
    }

    @Test func timeoutAndAFailedScriptKeepTheDraftAndTypeNothing() {
        var gate = awaiting("again")
        let timed = gate.perform(.timedOut, sessionID: session, field: "again", destinationCanTakeText: true, trusted: true)
        #expect(timed.state.status == .idle)
        #expect(timed.state.draft == "again")
        #expect(timed.state.receipt == .notSent)
        #expect(timed.typedLine == nil)

        var sending = HubReplyDispatch(
            state: HubReplyState(status: .sending, draft: "again", script: "again"),
            boundSessionID: session)
        let failed = sending.finished(sessionID: session, typed: false)
        #expect(failed.state.status == .failed)
        #expect(failed.state.draft == "again")
        #expect(failed.state.receipt == .openSession)
        #expect(failed.state.script == nil)
        #expect(failed.typedLine == nil)
    }

    @Test func anEmptyReplyDoesNotAsk() {
        var gate = HubReplyDispatch(boundSessionID: session)
        for field in ["", "   ", " \n\t ", "\u{7}\r"] {
            let step = gate.perform(.send, sessionID: session, field: field, destinationCanTakeText: true, trusted: true)
            #expect(step.state.status == .idle)
            #expect(step.state.receipt == .typeSomethingFirst)
            #expect(step.state.draft == field)
            #expect(step.typedLine == nil)
            #expect(!step.asksInline)
        }
    }

    @Test func aDestinationThatCannotTakeTextNeverAsks() {
        for trusted in [false, true] {
            var gate = HubReplyDispatch(state: HubReplyState(status: .unsupported, draft: "stale"), boundSessionID: session)
            let step = gate.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: false, trusted: trusted)
            #expect(step.state.status == .unsupported)
            #expect(step.state.receipt == .openDestination)
            #expect(step.state.draft == "hello")
            #expect(step.state.script == nil)
            #expect(step.typedLine == nil)
            #expect(!step.asksInline)
        }
        var omitted = HubReplyDispatch(boundSessionID: session)
        let step = omitted.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: false, trusted: false)
        #expect(step.state.status == .unsupported)
        #expect(step.typedLine == nil)
    }

    @Test func aLaterSendAsksOnceTheDestinationCanTakeText() {
        var gate = HubReplyDispatch(boundSessionID: session)
        let refused = gate.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: false, trusted: true)
        #expect(refused.state.status == .unsupported)
        let asked = gate.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: true, trusted: true)
        #expect(asked.asksInline)
        #expect(asked.typedLine == nil)
        #expect(asked.state.draft == "hello")
    }

    @Test func trustDoesNotSkipTheReplyApproval() {
        let drafted = HubReplyDispatch(state: HubReplyState(status: .drafting, draft: "keep going"), boundSessionID: session)
        var trustedGate = drafted
        var plainGate = drafted
        let trusted = trustedGate.perform(.send, sessionID: session, field: "keep going", destinationCanTakeText: true, trusted: true)
        let plain = plainGate.perform(.send, sessionID: session, field: "keep going", destinationCanTakeText: true, trusted: false)
        #expect(trusted == plain)
        #expect(trusted.asksInline)
        #expect(trusted.typedLine == nil)
        #expect(trusted.state.script == nil)
        let trustedApproved = trustedGate.perform(.approved, sessionID: session, field: "keep going", destinationCanTakeText: true, trusted: true, foreground: .agent)
        let plainApproved = plainGate.perform(.approved, sessionID: session, field: "keep going", destinationCanTakeText: true, trusted: false, foreground: .agent)
        #expect(trustedApproved == plainApproved)
        #expect(trustedApproved.typedLine == "keep going")
    }

    @Test func anotherRowCannotReleaseALine() {
        var gate = awaiting("hello")
        let before = gate
        for event in HubReplyEvent.allCases {
            let step = gate.perform(event, sessionID: other, field: "pwned", destinationCanTakeText: true, trusted: true)
            #expect(step.typedLine == nil)
            #expect(!step.asksInline)
            #expect(step.state == before.state)
            #expect(gate == before)
        }
        let cancelled = gate.cancel(sessionID: other)
        #expect(cancelled.typedLine == nil)
        #expect(gate == before)
        let finished = gate.finished(sessionID: other, typed: true)
        #expect(finished.typedLine == nil)
        #expect(gate.state.status == .awaitingDecision)
    }

    @Test func leavingTheRowDropsTheApprovalWithoutTyping() {
        var gate = awaiting("hello")
        let step = gate.bind(other)
        #expect(step.typedLine == nil)
        #expect(step.state.status == .drafting)
        #expect(step.state.draft == "hello")
        #expect(step.state.script == nil)
        #expect(step.state.receipt == nil)
        #expect(gate.boundSessionID == other)
        let sent = gate.perform(.send, sessionID: session, field: "hello", destinationCanTakeText: true, trusted: true)
        #expect(sent.typedLine == nil)
        #expect(!sent.asksInline)
    }

    @Test func aReleasedLineIsNotTypedIntoTheNewlySelectedRow() {
        var gate = HubReplyDispatch(
            state: HubReplyState(status: .sending, draft: "hello", script: "hello"),
            boundSessionID: session)
        let step = gate.bind(other)
        #expect(step.typedLine == nil)
        #expect(step.state.script == nil)
        #expect(step.state.draft == "hello")
        #expect(gate.boundSessionID == other)
    }

    @Test func boundariesCleanTheLineAndDropWhatCannotBeEmbedded() {
        var gate = HubReplyDispatch(boundSessionID: session)
        let messy = gate.perform(
            .send,
            sessionID: session,
            field: "  run   the\ntests\r\nplease\u{7} ",
            destinationCanTakeText: true,
            trusted: true)
        #expect(messy.asksInline)
        let approved = gate.perform(.approved, sessionID: session, field: "nope", destinationCanTakeText: true, trusted: false, foreground: .agent)
        #expect(approved.typedLine == "run the tests please")

        var long = HubReplyDispatch(boundSessionID: session)
        let huge = String(repeating: "a", count: 2_001)
        _ = long.perform(.send, sessionID: session, field: huge, destinationCanTakeText: true, trusted: false)
        let capped = long.perform(.approved, sessionID: session, field: huge, destinationCanTakeText: true, trusted: true, foreground: .agent)
        #expect(capped.typedLine?.count == 2_000)
        #expect(capped.typedLine == String(repeating: "a", count: 2_000))

        var exact = HubReplyDispatch(boundSessionID: session)
        let full = String(repeating: "b", count: 2_000)
        _ = exact.perform(.send, sessionID: session, field: full, destinationCanTakeText: true, trusted: true)
        #expect(exact.perform(.approved, sessionID: session, field: full, destinationCanTakeText: true, trusted: false, foreground: .agent).typedLine == full)

        var injected = HubReplyDispatch(boundSessionID: session)
        let tail = String(repeating: "a", count: 2_000) + "\"; do shell script \"id"
        _ = injected.perform(.send, sessionID: session, field: tail, destinationCanTakeText: true, trusted: true)
        let typed = injected.perform(.approved, sessionID: session, field: tail, destinationCanTakeText: true, trusted: true, foreground: .agent)
        #expect(typed.typedLine == String(repeating: "a", count: 2_000))
        #expect(typed.typedLine?.contains("shell") == false)

        var separator = HubReplyDispatch(boundSessionID: session)
        let broken = "hello\u{2028}there"
        let refused = separator.perform(.send, sessionID: session, field: broken, destinationCanTakeText: true, trusted: true)
        #expect(refused.typedLine == nil)
        #expect(!refused.asksInline)
        #expect(refused.state.status == .idle)
        #expect(refused.state.receipt == .notSent)
        #expect(refused.state.draft == broken)
        #expect(refused.state.script == nil)
    }

    @Test func injectionStaysInsideThePayloadAndDoesNotRunBeforeApproval() throws {
        let line = "say \"hi\" \\o/"
        let escaped = try #require(HubReplyTyping.escape(line))
        #expect(escaped == "say \\\"hi\\\" \\\\o/")
        let script = "tell application \"Host\"\nwrite text \"\(escaped)\"\nend tell\n"
        #expect(HubReplyScriptGuard.mayRun(script: script, line: line, approved: false) == false)
        #expect(HubReplyScriptGuard.mayRun(script: script, line: line, approved: true))

        var gate = HubReplyDispatch(boundSessionID: session)
        let asked = gate.perform(.send, sessionID: session, field: line, destinationCanTakeText: true, trusted: true)
        #expect(asked.asksInline)
        #expect(asked.typedLine == nil)
        let approved = gate.perform(.approved, sessionID: session, field: line, destinationCanTakeText: true, trusted: true, foreground: .agent)
        #expect(approved.typedLine == line)
        #expect(isScript(approved.typedLine ?? "") == false)

        let breakout = "tell application \"Host\"\nwrite text \"hi\"\ndo shell script \"id\"\nend tell\n"
        #expect(HubReplyScriptGuard.mayRun(script: breakout, line: "hi", approved: true) == false)
        let keys = "write text \"hi\"\nkeystroke \"v\"\n"
        #expect(HubReplyScriptGuard.mayRun(script: keys, line: "hi", approved: true) == false)
        let doubled = "write text \"hi\"\nwrite text \"hi\"\n"
        #expect(HubReplyScriptGuard.mayRun(script: doubled, line: "hi", approved: true) == false)
        let repeatedWord = "tell application \"Host\"\nwrite text \"Host\"\n"
        #expect(HubReplyScriptGuard.mayRun(script: repeatedWord, line: "Host", approved: true))
        #expect(HubReplyScriptGuard.mayRun(script: "do script \"\(escaped)\" in t\n", line: line, approved: true) == false)
        let split = "write text \"hi\u{2028}\"\n"
        #expect(HubReplyScriptGuard.mayRun(script: split, line: "hi", approved: true) == false)
        #expect(HubReplyTyping.canType("hello\u{2029}there") == false)
        #expect(HubReplyTyping.canType("go\u{0085}on") == false)
        #expect(HubReplyTyping.canType("ok\u{009B}") == false)
        #expect(HubReplyTyping.canType("left\u{202E}right") == false)
        #expect(HubReplyTyping.canType("café 👍") )
        #expect(HubReplyTyping.escape("café 👍") != nil)
        #expect(HubReplyScriptGuard.mayRun(script: script, line: "other", approved: true) == false)
    }

    @Test func theTransitionTableTypesInOneCellAndTrustChangesNothing() {
        let drafts = [
            "keep going",
            "  keep   going\n",
            " \n\t ",
            "a\u{7}b",
            String(repeating: "a", count: 2_000),
            String(repeating: "a", count: 2_001),
            "hello\u{2028}there",
            "say \"hi\" \\o/",
            "",
        ]
        let statuses = HubReplyStatus.allCases
        for status in statuses {
            for draft in drafts {
                for event in HubReplyEvent.allCases {
                    for destination in [false, true] {
                        for matches in [false, true] {
                            let sessionID = matches ? session : other
                            var trustedGate = make(status: status, draft: draft)
                            var plainGate = trustedGate
                            let field = event == .textChanged || event == .send ? draft : "next"
                            let trustedStep = trustedGate.perform(event, sessionID: sessionID, field: field, destinationCanTakeText: destination, trusted: true, foreground: .agent)
                            let plainStep = plainGate.perform(event, sessionID: sessionID, field: field, destinationCanTakeText: destination, trusted: false, foreground: .agent)
                            #expect(trustedStep == plainStep)
                            #expect(trustedGate == plainGate)
                            expectClosed(
                                trustedStep,
                                status: status,
                                draft: draft,
                                event: event,
                                field: field,
                                destination: destination,
                                matches: matches)
                        }
                    }
                }
            }
        }
    }

    @Test func cancelIsExhaustiveAndNeverApproves() {
        for status in HubReplyStatus.allCases {
            for draft in ["keep going", "  hello\n", ""] {
                for matches in [false, true] {
                    let start = make(status: status, draft: draft)
                    var gate = start
                    let step = gate.cancel(sessionID: matches ? session : other)
                    #expect(step.typedLine == nil)
                    #expect(!step.asksInline)
                    if !matches {
                        #expect(gate == start)
                    } else if status == .awaitingDecision {
                        #expect(step.state.status == .drafting)
                        #expect(step.state.draft == draft)
                        #expect(step.state.receipt == nil)
                        #expect(step.state.script == nil)
                    } else {
                        #expect(step.state == start.state)
                    }
                    let afterFirst = gate
                    let second = gate.cancel(sessionID: matches ? session : other)
                    #expect(second.typedLine == nil)
                    #expect(gate == afterFirst)
                }
            }
        }
    }

    @Test func theGateSourceDoesNotBranchOnTrust() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZeusCore/AgentHub/HubReplyDispatch.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("if trusted"))
        #expect(!source.contains("guard trusted"))
        #expect(!source.contains("trusted ?"))
        #expect(!source.contains("autoApproves"))
        #expect(!source.contains("NSAppleScript"))
    }

    private func expectClosed(
        _ step: HubReplyDispatch.Step,
        status: HubReplyStatus,
        draft: String,
        event: HubReplyEvent,
        field: String,
        destination: Bool,
        matches: Bool
    ) {
        let waiting = status == .awaitingDecision || status == .sending
        let line = cleaned(draft)
        let sentLine = cleaned(field)
        let legalType: String? = {
            guard matches, event == .approved, status == .awaitingDecision, destination else { return nil }
            guard let line, HubReplyTyping.canType(line) else { return nil }
            return line
        }()
        let legalAsk = matches && event == .send && !waiting && destination && sentLine.map(HubReplyTyping.canType) == true
        #expect(step.typedLine == legalType)
        #expect(step.asksInline == legalAsk)
        if let typed = step.typedLine {
            #expect(HubReplyTyping.canType(typed))
            #expect(typed.count <= HubReplyTyping.maxLength)
            #expect(typed.unicodeScalars.allSatisfy { !HubReplyTyping.isBreak($0) })
            #expect(step.state.status == .sending)
            #expect(step.state.script == typed)
            #expect(isScript(typed) == false)
            let escaped = HubReplyTyping.escape(typed)
            #expect(escaped != nil)
            if let escaped {
                #expect(HubReplyScriptGuard.mayRun(script: "write text \"\(escaped)\"\n", line: typed, approved: false) == false)
            }
        }
        if matches, event == .denied || event == .timedOut, status == .awaitingDecision {
            #expect(step.state.status == .idle)
            #expect(step.state.draft == draft)
            #expect(step.state.receipt == .notSent)
            #expect(step.state.script == nil)
        }
        if matches, event == .send, !waiting, sentLine != nil, !destination {
            #expect(step.state.status == .unsupported)
            #expect(step.state.receipt == .openDestination)
            #expect(step.state.draft == field)
            #expect(step.state.script == nil)
        }
        if matches, event == .send, !waiting, sentLine == nil {
            #expect(step.state.status == .idle)
            #expect(step.state.receipt == .typeSomethingFirst)
            #expect(step.state.draft == field)
        }
        if matches, event == .send, !waiting, destination, let sentLine, !HubReplyTyping.canType(sentLine) {
            #expect(step.state.status == .idle)
            #expect(step.state.receipt == .notSent)
            #expect(step.state.draft == field)
            #expect(step.state.script == nil)
        }
        if !matches {
            #expect(step.typedLine == nil)
            #expect(!step.asksInline)
        }
    }

    private func awaiting(_ draft: String) -> HubReplyDispatch {
        HubReplyDispatch(state: HubReplyState(status: .awaitingDecision, draft: draft), boundSessionID: session)
    }

    private func make(status: HubReplyStatus, draft: String) -> HubReplyDispatch {
        let script: String? = status == .sending ? cleaned(draft) : nil
        return HubReplyDispatch(
            state: HubReplyState(status: status, draft: draft, script: script),
            boundSessionID: session)
    }

    /// The reply machine's cleaner, copied here so the oracle is not the gate itself.
    private func cleaned(_ text: String) -> String? {
        let flat = text.unicodeScalars.map { scalar -> Character in
            scalar.value < 0x20 || scalar.value == 0x7F ? " " : Character(scalar)
        }
        let line = String(flat).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return String(line.prefix(2_000))
    }

    private func isScript(_ line: String) -> Bool {
        line.contains("\n") || line.contains("tell application") || line.contains("do script") || line.contains("do shell script")
    }
}

private struct KeystrokeLog {
    private(set) var lines: [String] = []

    mutating func record(_ step: HubReplyDispatch.Step) {
        if let line = step.typedLine { lines.append(line) }
    }
}
