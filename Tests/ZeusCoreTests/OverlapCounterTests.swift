import Testing
import ZeusCore

@Suite("Overlap counter")
struct OverlapCounterTests {
    @Test func startsIdleAndIsActiveBetweenBeginAndEnd() {
        var counter = OverlapCounter()
        #expect(!counter.isActive)
        counter.begin()
        #expect(counter.isActive)
        counter.end()
        #expect(!counter.isActive)
    }

    @Test func theFirstOfTwoOverlappingOperationsFinishingDoesNotClearTheFlag() {
        // `busy = false` after the first finisher used to re-enable the buttons while the other still ran.
        var counter = OverlapCounter()
        counter.begin()
        counter.begin()
        counter.end()
        #expect(counter.isActive)
        counter.end()
        #expect(!counter.isActive)
    }

    @Test func anExtraEndNeverHidesTheNextOperation() {
        var counter = OverlapCounter()
        counter.end()
        counter.end()
        #expect(counter.running == 0)
        counter.begin()
        #expect(counter.isActive)
    }
}
