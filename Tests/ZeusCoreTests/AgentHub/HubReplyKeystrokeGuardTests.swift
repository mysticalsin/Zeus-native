import Foundation
import Testing
@testable import ZeusCore

/// After the literal-keystroke reply lands, an approved Terminal script is keystrokes plus Return.
/// The reply guard still accepts only `do script` or `write text`, so this approved script is refused.
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
}
