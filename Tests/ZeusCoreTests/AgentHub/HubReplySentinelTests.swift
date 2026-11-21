import Foundation
import Testing
@testable import ZeusCore

/// Sentinel's review of the reply gate. Hidden characters are refused, not stripped.
/// The pending reply names the app and the tty, and Approve checks that tab again.
/// A bare shell, or an unknown foreground process, is not typed into.
@Suite("Reply sentinel")
struct HubReplySentinelTests {
    private let session = "session-1"
    private let shown = HubReplyTarget(app: "Terminal", tty: "/dev/ttys004", expectedCLI: ["claude"])

    @Test func hiddenCharactersAreRejectedAndLeftInTheDraft() {
        let marks: [Unicode.Scalar] = [
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}",
            "\u{2060}", "\u{061C}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
        ]
        for mark in marks {
            let field = "hi\(Character(mark))there"
            var gate = HubReplyDispatch(boundSessionID: session)
            let step = gate.perform(
                .send, sessionID: session, field: field,
                destinationCanTakeText: true, trusted: true)
            #expect(!step.asksInline)
            #expect(step.typedLine == nil)
            #expect(step.state.draft == field)
            #expect(step.state.receipt == .hiddenCharacter)
        }
    }

    @Test func approvingAHiddenCharacterDoesNotReleaseTheLine() {
        let field = "ok\u{200B}"
        var gate = HubReplyDispatch(
            state: HubReplyState(status: .awaitingDecision, draft: field),
            boundSessionID: session)
        let step = gate.perform(
            .approved, sessionID: session, field: field,
            destinationCanTakeText: true, trusted: false)
        #expect(step.typedLine == nil)
        #expect(step.state.draft == field)
        #expect(step.state.receipt == .hiddenCharacter)
    }

    @Test func thePendingReplyNamesTheAppAndTty() {
        #expect(HubReplyTargetGate.cardSentence(shown) == "Type this into Terminal on /dev/ttys004?")
        var gate = HubReplyDispatch(boundSessionID: session)
        let asked = gate.perform(
            .send, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: shown)
        #expect(asked.asksInline)
        #expect(asked.state.target == shown)
        #expect(asked.typedLine == nil)
    }

    @Test func approveRefusesWhenTheTabChangedOrVanished() {
        var changed = waiting()
        let other = HubReplyTarget(app: "Terminal", tty: "/dev/ttys009", expectedCLI: ["claude"])
        let moved = changed.perform(
            .approved, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: other, foreground: .agent)
        #expect(moved.typedLine == nil)
        #expect(moved.state.draft == "keep going")
        #expect(moved.state.receipt == .tabChanged)

        var gone = waiting()
        let missing = gone.perform(
            .approved, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: nil, foreground: .agent)
        #expect(missing.typedLine == nil)
        #expect(missing.state.receipt == .tabVanished)
    }

    @Test func approveTypesOnlyWhenTheSameTabIsStillTheAgent() {
        var gate = waiting()
        let step = gate.perform(
            .approved, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: shown, foreground: .agent)
        #expect(step.typedLine == "keep going")
    }

    @Test func aShellPromptOrAnUnknownProcessIsNotTyped() {
        var shell = waiting()
        let prompt = shell.perform(
            .approved, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: shown, foreground: .bareShell)
        #expect(prompt.typedLine == nil)
        #expect(prompt.state.draft == "keep going")
        #expect(prompt.state.receipt == .bareShell)

        var unknown = waiting()
        let unseen = unknown.perform(
            .approved, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: shown, foreground: .unknown)
        #expect(unseen.typedLine == nil)
        #expect(unseen.state.receipt == .foregroundUnknown)
    }

    @Test func foregroundNamesDistinguishTheAgentFromAShell() {
        #expect(HubReplyForeground.verdict(name: "zsh", expected: ["claude"]) == .bareShell)
        #expect(HubReplyForeground.verdict(name: "-bash", expected: ["claude"]) == .bareShell)
        #expect(HubReplyForeground.verdict(name: "claude", expected: ["claude"]) == .agent)
        #expect(HubReplyForeground.verdict(name: nil, expected: ["claude"]) == .unknown)
        #expect(HubReplyForeground.verdict(name: "python", expected: ["claude"]) == .unknown)
        #expect(HubReplyForeground.expectedCLI(agent: "Claude Code") == ["claude"])
        #expect(HubReplyForeground.expectedCLI(agent: "Codex") == ["codex"])
    }

    @Test func theForegroundQueryDoesNotTypeOrStartAShell() {
        let terminal = HubReplyForeground.queryScript(bundleID: "com.apple.Terminal", tty: "/dev/ttys004")
        #expect(terminal.contains("processes"))
        #expect(terminal.contains("/dev/ttys004"))
        #expect(!terminal.contains("keystroke"))
        #expect(!terminal.contains("do script"))
        #expect(!terminal.contains("do shell script"))
        let iterm = HubReplyForeground.queryScript(bundleID: "com.googlecode.iterm2", tty: "/dev/ttys004")
        #expect(iterm.contains("jobName"))
        #expect(!iterm.contains("keystroke"))
        #expect(!iterm.contains("do script"))
    }

    @Test func theHubShowsTheTargetAndChecksItAgainBeforeTyping() throws {
        let hub = try source("Sources/Zeus/Agents/AgentHub.swift")
        let approve = try #require(HubReplyWiringTests.functionBody("approveReply", in: hub))
        #expect(approve.contains("HubReplyTargetGate"))
        #expect(approve.contains("seconds(30)") == false)
        let type = try #require(HubReplyWiringTests.functionBody("typeApprovedLine", in: hub))
        #expect(type.contains("HubReplyForeground"))
        let wait = try #require(HubReplyWiringTests.functionBody("armReplyTimeout", in: hub))
        #expect(wait.contains("seconds(30)"))
        let page = try source("Sources/Zeus/TopBar/ChatPage.swift")
        #expect(page.contains("cardSentence"))
    }

    private func waiting() -> HubReplyDispatch {
        var gate = HubReplyDispatch(boundSessionID: session)
        _ = gate.perform(
            .send, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: shown)
        return gate
    }

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
