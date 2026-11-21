import Testing
import ZeusCore

@Suite struct ReturnEscapeClaimTests {
    @Test func theDictationCheckOwnsReturnAndEscape() {
        #expect(!ReturnEscapeClaim.meetingCardCanBecomeKey(dictationCheckVisible: true))
        #expect(ReturnEscapeClaim.meetingCardCanBecomeKey(dictationCheckVisible: false))
    }
}
