import Testing
@testable import ZeusCore

@Suite("Prompt write")
struct StdinWriteTests {
    private struct Full: Error {}

    @Test func aThrownWriteIsReported() {
        #expect(StdinWrite.attempt { throw Full() } == "Full()")
    }

    @Test func aFinishedWriteIsSilent() {
        #expect(StdinWrite.attempt {} == nil)
    }
}
