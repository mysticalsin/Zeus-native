import Testing
import ZeusCore

@Suite struct ShownFailureTests {
    @Test func theSentencesNameTheNextStep() {
        #expect(ShownFailure.meetingSave.contains("Try again"))
        #expect(ShownFailure.meetingNotes.contains("transcript"))
        #expect(ShownFailure.dictationFile.contains("Try another"))
        #expect(!ShownFailure.engine("Speech").contains("/"))
    }
}
