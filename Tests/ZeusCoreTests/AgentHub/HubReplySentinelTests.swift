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
        #expect(HubReplyTTYReader.executable == "/bin/ps")
        let arguments = HubReplyTTYReader.arguments(forTTY: "/dev/ttys004")
        #expect(arguments == ["-o", "pid=,pgid=,tpgid=,stat=,comm=", "-t", "/dev/ttys004"])
        #expect(HubReplyTTYReader.arguments(forTTY: "/dev/ttys004;rm") == nil)
        #expect(arguments?.contains("-c") == false)
        let terminal = HubReplyForeground.queryScript(bundleID: "com.apple.Terminal", tty: "/dev/ttys004")
        #expect(!terminal.contains("keystroke"))
        #expect(!terminal.contains("do script"))
        #expect(!terminal.contains("do shell script"))
        #expect(!terminal.contains("last item"))
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
        #expect(type.contains("HubReplyJobGuard"))
        let wait = try #require(HubReplyWiringTests.functionBody("armReplyTimeout", in: hub))
        #expect(wait.contains("seconds(30)"))
        let page = try source("Sources/Zeus/TopBar/ChatPage.swift")
        #expect(page.contains("cardSentence"))
    }

    /// A missing foreground read used to release the line. It is refused.
    @Test func approveFailsClosedWhenTheForegroundWasNotRead() {
        var gate = waiting()
        let step = gate.perform(
            .approved, sessionID: session, field: "keep going",
            destinationCanTakeText: true, trusted: false, target: shown)
        #expect(step.typedLine == nil)
        #expect(step.state.draft == "keep going")
        #expect(step.state.receipt == .foregroundUnknown)
        #expect(step.state.status == .idle)
    }

    /// Every Cf scalar is a hidden mark, plus the extra scalars the category does not cover.
    @Test func everyFormatScalarIsAHiddenMark() {
        var missed: [String] = []
        var value: UInt32 = 0
        while value <= 0x10FFFF {
            if let scalar = Unicode.Scalar(value),
               scalar.properties.generalCategory == .format,
               !HubReplyHidden.isMark(scalar) {
                missed.append(String(format: "U+%04X", value))
                if missed.count == 8 { break }
            }
            value += 1
        }
        #expect(missed.isEmpty)
        let extras: [UInt32] = [
            0xFEFF, 0x00AD, 0x180E,
            0x2061, 0x2062, 0x2063, 0x2064,
            0xE0000, 0xE0001, 0xE007F,
            0xFE00, 0xFE0F, 0xE0100, 0xE01EF,
            0x061C, 0x200E, 0x200F, 0x202A, 0x202E, 0x2066, 0x2069,
            0x034F, 0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800,
        ]
        for extra in extras {
            let scalar = Unicode.Scalar(extra)!
            #expect(HubReplyHidden.isMark(scalar))
            let field = "hi\(Character(scalar))there"
            var gate = HubReplyDispatch(boundSessionID: session)
            let step = gate.perform(
                .send, sessionID: session, field: field,
                destinationCanTakeText: true, trusted: true)
            #expect(step.typedLine == nil)
            #expect(step.state.draft == field)
            #expect(step.state.receipt == .hiddenCharacter)
        }
        #expect(HubReplyHidden.isMark(Unicode.Scalar("A")) == false)
    }

    /// A path is not trusted because its last component is the agent name.
    /// A resolved real path is accepted only when it is on the allowlist.
    @Test func aSlashPathIsNotTheAgentByNameAlone() throws {
        #expect(HubReplyForeground.verdict(name: "/tmp/evil/claude", expected: ["claude"]) == .unknown)
        #expect(HubReplyForeground.verdict(name: "zsh", expected: ["claude"]) == .bareShell)
        #expect(HubReplyForeground.verdict(name: "/bin/zsh", expected: ["claude"]) == .bareShell)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zn283-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("claude")
        #expect(FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8)))
        let link = root.appendingPathComponent("via")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)
        let decoyDir = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: decoyDir, withIntermediateDirectories: true)
        let decoy = decoyDir.appendingPathComponent("claude")
        #expect(FileManager.default.createFile(atPath: decoy.path, contents: Data()))

        #expect(HubReplyForeground.verdict(name: "claude", expected: ["claude"], executablePath: link.path, allowedPaths: [binary.path]) == .agent)
        #expect(HubReplyForeground.verdict(name: link.path, expected: ["claude"], allowedPaths: [binary.path]) == .agent)
        #expect(HubReplyForeground.verdict(name: "claude", expected: ["claude"], executablePath: decoy.path, allowedPaths: [binary.path]) == .unknown)
        #expect(HubReplyForeground.verdict(name: "claude", expected: ["claude"], executablePath: link.path, allowedPaths: []) == .unknown)
        #expect(HubReplyForeground.verdict(name: "python", expected: ["claude"], executablePath: link.path, allowedPaths: [binary.path]) == .unknown)
    }

    /// Typing must not reuse the name read at Approve, and the script must carry the expected CLI.
    @Test func typingReprobesAndPassesTheExpectedCLI() throws {
        let hub = try source("Sources/Zeus/Agents/AgentHub.swift")
        let type = try #require(HubReplyWiringTests.functionBody("typeApprovedLine", in: hub))
        #expect(type.contains("script(for: info, text: line, expectedCLI:"))
        #expect(type.contains("HubReplyJobGuard"))
        #expect(type.contains("maySubmit"))
        #expect(type.contains("foregroundSnapshot"))
        #expect(!type.contains("approvedForeground"))
        #expect(!type.contains("last item"))
        #expect(!type.contains("else { return true }"))
    }

    /// Terminal's process list does not say which process is in the foreground.
    /// Taking the last item is a guess. The query and the typing script must not do that.
    @Test func terminalDoesNotGuessTheLastProcess() throws {
        let query = HubReplyForeground.queryScript(bundleID: "com.apple.Terminal", tty: "/dev/ttys004")
        #expect(!query.contains("last item of names"))
        let info = TerminalInfo(bundleID: "com.apple.Terminal", program: "Apple_Terminal", sessionID: nil, tty: "/dev/ttys004")
        let script = try #require(AgentReply.script(for: info, text: "keep going", expectedCLI: ["claude"]))
        #expect(!script.contains("last item of fgNames"))
        #expect(script.contains("return false"))
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
