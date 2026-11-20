import Foundation
import Testing
@testable import ZeusCore

@Suite struct ClaudeRewriterTests {
    /// About 1 MB written while the reader is already running. A reader that waits until the
    /// writer returns fills the pipe and never finishes.
    @Test func aLargeOutputIsReadWhileTheProcessRuns() throws {
        let payload = Data(repeating: 0x61, count: 1_000_000)
        let stdout = Pipe()
        let stderr = Pipe()
        let collected = try RewriterStream.collect(stdout: stdout, stderr: stderr, timeout: 5) {
            stdout.fileHandleForWriting.write(payload)
            try stdout.fileHandleForWriting.close()
            try stderr.fileHandleForWriting.close()
        }
        #expect(collected.stdout.count == 1_000_000)
        #expect(collected.stdout.allSatisfy { $0 == 0x61 })
        #expect(collected.stderr.isEmpty)
    }

    @Test func theTimeoutStaysFortyFiveSeconds() {
        #expect(RewriterStream.timeout == 45)
    }

    /// The notch already has a rewriting phase. The rewrite enters it before the process returns.
    @Test func theTopBarPhaseIsRewritingBeforeTheProcessEnds() {
        let (state, _) = DictationFlow.reduce(.transcribing(turn: 7, source: .live), .rewriteStarted(turn: 7, source: .live))
        #expect(state.phase == .rewriting)
        #expect(DictationMode(key: "voice", name: "Voice").usesAI == false)
        #expect(DictationMode(key: "tidy", name: "Tidy", prompt: "tidy").usesAI == true)
    }
}
