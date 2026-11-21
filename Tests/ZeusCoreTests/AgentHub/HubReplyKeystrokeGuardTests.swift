import Foundation
import Testing
@testable import ZeusCore

/// An approved Terminal reply is the stripped line typed as keystrokes, then Return.
/// `do script` stays refused. iTerm still uses one `write text`. Approval is still required.
@Suite("Terminal keystroke reply guard")
struct HubReplyKeystrokeGuardTests {
    private let terminal = TerminalInfo(
        bundleID: "com.apple.Terminal",
        program: "Apple_Terminal",
        sessionID: nil,
        tty: "/dev/ttys004"
    )

    @Test func anApprovedTerminalKeystrokeReplyMayRun() throws {
        let line = "hi $(id)"
        let script = try #require(AgentReply.script(for: terminal, text: line))
        let rows = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!rows.contains { $0.hasPrefix("do script") })
        #expect(rows.contains("keystroke \"\(line)\""))
        #expect(rows.contains("keystroke return"))
        #expect(HubReplyScriptGuard.mayRun(script: script, line: line, approved: true))
    }

    @Test func approvalIsStillRequired() throws {
        let line = "hi $(id)"
        let script = try #require(AgentReply.script(for: terminal, text: line))
        #expect(HubReplyScriptGuard.mayRun(script: script, line: line, approved: false) == false)
    }

    @Test func terminalDoScriptStaysRefused() throws {
        let line = "say \"hi\" \\o/"
        let escaped = try #require(HubReplyTyping.escape(line))
        #expect(HubReplyScriptGuard.mayRun(script: "do script \"\(escaped)\" in t\n", line: line, approved: true) == false)
    }

    @Test func iTermWriteTextStillRuns() throws {
        let iterm = TerminalInfo(bundleID: "com.googlecode.iterm2", program: nil, sessionID: "w0t1p0:ABCD-1234", tty: nil)
        let script = try #require(AgentReply.script(for: iterm, text: "go"))
        #expect(script.contains("write text \"go\""))
        #expect(!script.contains("keystroke"))
        #expect(HubReplyScriptGuard.mayRun(script: script, line: "go", approved: true))
        #expect(HubReplyScriptGuard.mayRun(script: script, line: "go", approved: false) == false)
    }

    @Test func onlyTheStrippedLineAndReturnAreTyped() throws {
        let line = "hi $(id)"
        let script = try #require(AgentReply.script(for: terminal, text: line))
        let extra = script.replacingOccurrences(of: "keystroke return", with: "keystroke return\n                    keystroke \"rm\"")
        #expect(HubReplyScriptGuard.mayRun(script: extra, line: line, approved: true) == false)
        let commandReturn = script.replacingOccurrences(of: "keystroke return", with: "keystroke return using command down")
        #expect(HubReplyScriptGuard.mayRun(script: commandReturn, line: line, approved: true) == false)
        let keyCode = script.replacingOccurrences(of: "keystroke return", with: "key code 36")
        #expect(HubReplyScriptGuard.mayRun(script: keyCode, line: line, approved: true) == false)
        let shell = script.replacingOccurrences(of: "activate", with: "do shell script \"id\"")
        #expect(HubReplyScriptGuard.mayRun(script: shell, line: line, approved: true) == false)
        #expect(HubReplyScriptGuard.mayRun(script: script, line: "other", approved: true) == false)
    }

    @Test func quotesAndLongLinesStayInsideKeystrokes() throws {
        let quoted = "say \"$(id)\" now"
        let quotedScript = try #require(AgentReply.script(for: terminal, text: quoted))
        #expect(HubReplyScriptGuard.mayRun(script: quotedScript, line: quoted, approved: true))
        let long = String(repeating: "a", count: 45)
        let longScript = try #require(AgentReply.script(for: terminal, text: long))
        let strokes = longScript.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("keystroke \"") }
        #expect(strokes.count == 3)
        #expect(HubReplyScriptGuard.mayRun(script: longScript, line: long, approved: true))
    }

    @Test func wordsThatLookLikeCommandsStayInThePayload() throws {
        let line = "please write text \"now\""
        let script = try #require(AgentReply.script(for: terminal, text: line))
        #expect(script.contains("write text"))
        #expect(HubReplyScriptGuard.mayRun(script: script, line: line, approved: true))
    }
}
