import Foundation
import Testing
@testable import ZeusCore

@Suite("Trusted chat shell approval")
struct TrustedShellApprovalTests {
    private func bash(_ command: String) -> JSONValue { .object(["command": .string(command)]) }

    private func trusted() -> TrustedChats {
        var chats = TrustedChats()
        chats.trust("s1", agent: "agent", project: "repo")
        return chats
    }

    @Test func interpretersCopiesAndUnknownProgramsAsk() {
        let chats = trusted()
        let commands = [
            "python3 -c 'open(\"/tmp/zeus-sweep\",\"w\").close()'",
            "bash -c 'true'",
            "osascript -e 'return 1'",
            "node -e 'process.exit(0)'",
            "cp Notes.txt /tmp/notes-copy",
            "ln -s a b",
            "find . -name x -exec true \\;",
        ]
        for command in commands {
            #expect(!chats.autoApproves(session: "s1", tool: "Bash", input: bash(command), risk: .low), "\(command)")
        }
    }

    @Test func aHighHookRiskAlwaysAsksEvenForASafeCommand() {
        let chats = trusted()
        #expect(!chats.autoApproves(session: "s1", tool: "Bash", input: bash("ls -la"), risk: .high))
        #expect(chats.autoApproves(session: "s1", tool: "Bash", input: bash("ls -la"), risk: .low))
        #expect(chats.autoApproves(session: "s1", tool: "Bash", input: bash("swift build"), risk: .medium))
    }
}
