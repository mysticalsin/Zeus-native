import Testing
import ZeusCore

@Suite("Interview context")
struct InterviewContextTests {
    @Test func blankAndMissingNotesStayEmpty() {
        #expect(InterviewContext.storageKey == "opt.interview.context")
        #expect(InterviewContext.normalize(nil) == "")
        #expect(InterviewContext.normalize("   \n") == "")
    }

    @Test func surroundingSpaceDropsAndTheNoteItselfStays() {
        #expect(InterviewContext.normalize("  role\nstrengths  ") == "role\nstrengths")
    }

    @Test func aNotePastTheLimitKeepsTheFirstTwoThousandCharacters() {
        let long = String(repeating: "a", count: InterviewContext.limit + 25)
        let stored = InterviewContext.normalize(long)
        #expect(stored.count == InterviewContext.limit)
        #expect(stored == String(repeating: "a", count: InterviewContext.limit))
        #expect(InterviewContext.normalize(stored) == stored)
    }
}
