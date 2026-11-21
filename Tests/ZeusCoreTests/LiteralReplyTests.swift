import Foundation
import Testing
@testable import ZeusCore

@Suite("Literal terminal reply")
struct LiteralReplyTests {
    let terminal = TerminalInfo(bundleID: "com.apple.Terminal", program: "Apple_Terminal", sessionID: nil, tty: "/dev/ttys004")

    @Test func approvedTerminalReplyIsTypedNotRun() throws {
        let script = try #require(AgentReply.script(for: terminal, text: "hi $(id)"))
        let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(script.contains("keystroke"))
        #expect(!lines.contains { $0.hasPrefix("do script") })
        #expect(script.contains("hi $(id)"))
    }

    @Test func aQuoteCannotBecomeAShellCommand() throws {
        let script = try #require(AgentReply.script(for: terminal, text: #"say "$(id)" now"#))
        let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!lines.contains { $0.hasPrefix("do script") })
        #expect(lines.contains { $0.hasPrefix("keystroke") })
        #expect(script.contains(#"\"$(id)\""#))
    }

    @Test func newlinesAndControlsAreStrippedBeforeTyping() throws {
        #expect(AgentReply.sanitize("hi\u{2028}$(id)\u{7}") == "hi $(id)")
        let script = try #require(AgentReply.script(for: terminal, text: "hi\n$(id)"))
        #expect(!script.contains("do script"))
        #expect(script.contains("keystroke"))
        #expect(!script.contains("\n$(id)"))
    }

    @Test func longTextIsSeveralKeystrokes() throws {
        let script = try #require(AgentReply.script(for: terminal, text: String(repeating: "a", count: 45)))
        let strokes = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("keystroke \"") }
        #expect(strokes.count == 3)
        #expect(!script.contains("do script"))
    }
}
