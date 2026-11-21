import Testing
@testable import ZeusCore

@Suite struct DuplexInterruptTests {
    @Test func interruptClosesAStreamingSessionAndADeviceChangeKeepsIt() throws {
        #expect(try VoiceSessionState.streaming.next(on: .interrupt) == .closing)
        #expect(try VoiceSessionState.streaming.next(on: .deviceChanged) == .streaming)
        #expect(try VoiceSessionState.starting.next(on: .deviceChanged) == .starting)
        #expect(throws: VoiceSessionError.illegalTransition(from: .closed, event: .interrupt)) {
            try VoiceSessionState.closed.next(on: .interrupt)
        }
    }
}
