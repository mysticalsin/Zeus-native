import Testing
@testable import ZeusCore

@Suite struct BrowserAgentStepBeatTests {
    @Test func aRealStepIsSpokenAndShown() {
        let beat = BrowserAgentStepBeat.make(step: 2, maxSteps: 8, action: "Clicking “Search”")
        #expect(beat.spoken == "Step 2 of 8. Clicking “Search”.")
        #expect(beat.bolt == "Clicking “Search”")
        #expect(beat.bolt.count <= BrowserAgentStepBeat.boltLimit)
    }

    @Test func aLongStepKeepsAShortSparkLine() {
        let action = "Typing a very long query into the search field and submitting"
        let beat = BrowserAgentStepBeat.make(step: 1, maxSteps: 4, action: action)
        #expect(beat.spoken == "Step 1 of 4. \(action).")
        #expect(beat.bolt.count <= BrowserAgentStepBeat.boltLimit)
        #expect(beat.bolt != action)
        #expect(action.hasPrefix(beat.bolt))
        #expect(!beat.bolt.hasSuffix(" "))
    }

    @Test func lookingAndWaitingStayOnTheSparkWithoutASecondSpeech() {
        let look = BrowserAgentStepBeat.make(step: 3, maxSteps: 8, action: "Looking at the page")
        #expect(look.spoken == nil)
        #expect(look.bolt == "Looking")
        let waiting = BrowserAgentStepBeat.make(step: 3, maxSteps: 8, action: "Waiting for your OK: Clicking “Buy”")
        #expect(waiting.spoken == nil)
        #expect(waiting.bolt == "Needs you")
        let page = BrowserAgentStepBeat.make(step: 4, maxSteps: 8, action: "Waiting for the page")
        #expect(page.spoken == "Step 4 of 8. Waiting for the page.")
        #expect(page.bolt == "Waiting for the page")
    }

    @Test func anEmptyStepShowsHereAndALowCountStillSpeaks() {
        let empty = BrowserAgentStepBeat.make(step: 1, maxSteps: 8, action: "   ")
        #expect(empty.spoken == nil)
        #expect(empty.bolt == "Here")
        let low = BrowserAgentStepBeat.make(step: 0, maxSteps: 0, action: "Going back")
        #expect(low.spoken == "Step 1 of 1. Going back.")
        #expect(low.bolt == "Going back")
    }
}
