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

    /// `typingLines` used to look for the lowercase spellings only, so a mixed-case
    /// command on its own line was invisible and the keystrokes still matched.
    @Test func mixedCaseAndOddSpacesDoNotPassTheKeystrokeGuard() throws {
        let line = "hi $(id)"
        let script = try #require(AgentReply.script(for: terminal, text: line))
        let extras = [
            "Do script \"id\"",
            "DO SCRIPT \"id\"",
            "dO sCrIpT \"id\"",
            "Do shell script \"id\"",
            "do\u{00A0}script \"id\"",
            "do\u{2003}script \"id\"",
            "Do\u{3000}script \"id\"",
            "do\u{200B} script \"id\"",
            "\u{FF24}\u{FF4F}\u{3000}\u{FF53}\u{FF43}\u{FF52}\u{FF49}\u{FF50}\u{FF54} \"id\"",
        ]
        for extra in extras {
            let tainted = script.replacingOccurrences(of: "activate", with: extra)
            #expect(HubReplyScriptGuard.mayRun(script: tainted, line: line, approved: true) == false)
        }
        let written = "tell application \"Host\"\nwrite text \"hi\"\nDo script \"id\"\nend tell\n"
        #expect(HubReplyScriptGuard.mayRun(script: written, line: "hi", approved: true) == false)
        let spaced = "tell application \"Host\"\nwrite text \"hi\"\ndo\u{00A0}script \"id\"\nend tell\n"
        #expect(HubReplyScriptGuard.mayRun(script: spaced, line: "hi", approved: true) == false)
    }

    /// The script must refuse to type unless the front app and the front tab are still the stored ones.
    @Test func theKeystrokeScriptAbortsUnlessFrontmostAndTtyMatch() throws {
        let script = try #require(AgentReply.script(for: terminal, text: "hi $(id)"))
        let key = try #require(script.range(of: "keystroke"))
        let before = String(script[..<key.lowerBound])
        #expect(before.contains("frontmost"))
        #expect(before.contains("return false"))
        #expect(before.contains("processes"))
        #expect(script.components(separatedBy: "/dev/ttys004").count - 1 >= 2)
        #expect(!before.contains("keystroke"))
    }

    /// A job that exited is read again in the script, before `write text` can reach a shell.
    @Test func iTermReprobesTheJobBeforeWriting() throws {
        let iterm = TerminalInfo(
            bundleID: "com.googlecode.iterm2",
            program: nil,
            sessionID: "w0t1p0:ABCD-1234",
            tty: "/dev/ttys004"
        )
        let script = try #require(AgentReply.script(for: iterm, text: "go"))
        let write = try #require(script.range(of: "write text"))
        let before = String(script[..<write.lowerBound])
        #expect(before.contains("jobName"))
        #expect(before.contains("frontmost"))
        #expect(before.contains("return false"))
        #expect(script.components(separatedBy: "/dev/ttys004").count - 1 >= 2)
    }

    @Test func theGuardedScriptsStillMayRun() throws {
        let line = "hi $(id)"
        let script = try #require(AgentReply.script(for: terminal, text: line, expectedCLI: ["claude"]))
        #expect(HubReplyScriptGuard.mayRun(script: script, line: line, approved: true))
        let key = try #require(script.range(of: "keystroke"))
        #expect(String(script[..<key.lowerBound]).contains("fg is \"claude\""))
        let iterm = TerminalInfo(bundleID: "com.googlecode.iterm2", program: nil, sessionID: "w0t1p0:ABCD-1234", tty: "/dev/ttys004")
        let written = try #require(AgentReply.script(for: iterm, text: "go", expectedCLI: ["claude"]))
        #expect(HubReplyScriptGuard.mayRun(script: written, line: "go", approved: true))
        #expect(written.contains("fg is \"claude\""))
    }
}

/// The tty foreground process group, not the last name in the process list.
@Suite("TTY foreground job")
struct HubReplyJobGuardTests {
    @Test func aLiveAgentInTheForegroundMayBeTyped() throws {
        let binary = try Self.file(named: "claude")
        let snapshot = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 50,
            processes: [
                Self.process(pid: 50, pgid: 50, name: "claude", path: binary),
                Self.process(pid: 10, pgid: 10, name: "zsh", path: "/bin/zsh"),
            ])
        #expect(HubReplyJobGuard.mayType(
            snapshot: snapshot, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [binary]))
    }

    @Test func aStoppedJobIsNotTheForeground() throws {
        let binary = try Self.file(named: "claude")
        let snapshot = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 10,
            processes: [
                Self.process(pid: 10, pgid: 10, name: "zsh", path: "/bin/zsh"),
                Self.process(pid: 50, pgid: 50, name: "claude", path: binary, stopped: true),
            ])
        #expect(HubReplyJobGuard.mayType(
            snapshot: snapshot, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [binary]) == false)
    }

    @Test func aBackgroundJobIsNotTheForeground() throws {
        let binary = try Self.file(named: "claude")
        let snapshot = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 10,
            processes: [
                Self.process(pid: 10, pgid: 10, name: "zsh", path: "/bin/zsh"),
                Self.process(pid: 50, pgid: 50, name: "claude", path: binary),
            ])
        #expect(HubReplyJobGuard.mayType(
            snapshot: snapshot, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [binary]) == false)
    }

    @Test func anEmptyCLIListFailsClosed() throws {
        let binary = try Self.file(named: "claude")
        let snapshot = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 50,
            processes: [Self.process(pid: 50, pgid: 50, name: "claude", path: binary)])
        #expect(HubReplyJobGuard.mayType(
            snapshot: snapshot, expectedApp: "Terminal", expectedCLI: [], allowedPaths: [binary]) == false)
        let empty = HubReplyTTYSnapshot(frontmostApp: "Terminal", foregroundPgid: nil, processes: [])
        #expect(HubReplyJobGuard.mayType(
            snapshot: empty, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [binary]) == false)
    }

    @Test func aChangedForegroundPgidBlocksReturn() throws {
        let binary = try Self.file(named: "claude")
        let before = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 50,
            processes: [Self.process(pid: 50, pgid: 50, name: "claude", path: binary)])
        let after = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 10,
            processes: [
                Self.process(pid: 10, pgid: 10, name: "zsh", path: "/bin/zsh"),
                Self.process(pid: 50, pgid: 50, name: "claude", path: binary),
            ])
        #expect(HubReplyJobGuard.maySubmit(
            before: before, after: after, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [binary]) == false)
    }

    @Test func claudeEvilIsNotTheAllowlistedCLI() throws {
        let real = try Self.file(named: "claude")
        let evil = try Self.file(named: "claude-evil")
        let byName = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 50,
            processes: [Self.process(pid: 50, pgid: 50, name: "claude-evil", path: evil)])
        #expect(HubReplyJobGuard.mayType(
            snapshot: byName, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [real]) == false)
        let byPath = HubReplyTTYSnapshot(
            frontmostApp: "Terminal",
            foregroundPgid: 50,
            processes: [Self.process(pid: 50, pgid: 50, name: "claude", path: evil)])
        #expect(HubReplyJobGuard.mayType(
            snapshot: byPath, expectedApp: "Terminal", expectedCLI: ["claude"], allowedPaths: [real]) == false)
    }

    private static func process(pid: Int32, pgid: Int32, name: String, path: String, stopped: Bool = false) -> HubReplyProcessFact {
        HubReplyProcessFact(pid: pid, pgid: pgid, name: name, executablePath: path, stopped: stopped)
    }

    private static func file(named name: String) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zn283-job-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        #expect(FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8)))
        return url.path
    }
}
