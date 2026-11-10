import Testing
@testable import ZeusCore

@Suite struct DictationExplicitCorrectionTests {
    @Test func noIMeantReplacesTheStaleWordBeforeInsert() {
        #expect(TranscriptPolish.prepareForInsert("Send it to Paul, no, I meant Marc.") == "Send it to Marc.")
        #expect(TranscriptPolish.prepareForInsert("Meet at three no I meant four pm.") == "Meet at four pm.")
        #expect(TranscriptPolish.prepareForInsert("Send it to Paul, no, I meant to Marc.") == "Send it to Marc.")
        #expect(TranscriptPolish.prepareForInsert("Send it to O'Connor, no, I meant to Marc.") == "Send it to Marc.")
    }

    @Test func repeatedPhraseCanRestartTheClause() {
        #expect(TranscriptPolish.prepareForInsert("Send it to Paul, no, I meant send it to Marc.") == "Send it to Marc.")
        #expect(TranscriptPolish.prepareForInsert("Keep this. Send it to Paul, no, I meant send it to Marc.") == "Keep this. Send it to Marc.")
    }

    @Test func quotedAndOrdinarySpeechArePreserved() {
        for text in ["She said \"Paul, no, I meant Marc\".", "She said “Paul, no, I meant Marc”.",
                     "She said 'Send it to Paul, no, I meant Marc'.", "She said ‘Paul, no, I meant Marc’.",
                     "I meant what I said.", "No, I meant the whole team.", "Send it to Paul, no, I meant..."] {
            #expect(TranscriptPolish.selfCorrect(text) == text)
        }
    }
}
