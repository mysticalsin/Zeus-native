import Testing
@testable import ZeusCore

@Suite struct WalkthroughRevisionTests {
    private var tour: Walkthrough {
        Walkthrough(title: "Fixture", steps: [.init(say: "First"), .init(say: "Second"), .init(say: "Third")])
    }

    @Test func doubleClickOnlyAdvancesItsOriginalStepOnce() {
        var session = WalkthroughSession(tour)
        let click = session.revision
        let first = session.next(ifRevision: click)
        let duplicate = session.next(ifRevision: click)
        #expect(first)
        #expect(!duplicate)
        #expect(session.index == 1)
    }

    @Test func lateClickCannotAdvanceAReplacementTourAtTheSameIndex() {
        let old = WalkthroughSession(tour)
        var replacement = WalkthroughSession(tour)
        let advanced = replacement.next(ifRevision: old.revision)
        #expect(!advanced)
        #expect(replacement.index == 0)
    }

    @Test func goingBackDoesNotRevalidateAnOldTimer() {
        var session = WalkthroughSession(tour)
        let timer = session.revision
        session.next()
        session.back()
        #expect(session.index == 0)
        let advanced = session.next(ifRevision: timer)
        #expect(!advanced)
    }

    @Test func stoppedAndEmptyToursCannotAdvance() {
        var session = WalkthroughSession(tour)
        let timer = session.revision
        session.cancel()
        let advanced = session.next(ifRevision: timer)
        #expect(!advanced)
        var empty = WalkthroughSession(Walkthrough(title: "Empty", steps: []))
        #expect(empty.current == nil)
        let emptyAdvanced = empty.next(ifRevision: empty.revision)
        #expect(!emptyAdvanced)
    }
}
