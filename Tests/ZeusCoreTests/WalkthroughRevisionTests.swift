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

    @Test func aMissingControlIsSpokenAndShown() {
        let step = Walkthrough.Step(say: "Click File", targetLabel: "File", waitForClick: true)
        let session = WalkthroughSession(Walkthrough(title: "Share", steps: [step]))
        let missing = step.cue(progress: session.progress, found: false)
        #expect(missing.bolt == "Not found")
        #expect(missing.spoken == "Step 1 of 1. Click File I couldn't find that on screen, so I'll keep going.")
        let found = step.cue(progress: session.progress, found: true)
        #expect(found.bolt == nil)
        #expect(found.spoken == "Step 1 of 1. Click File")
        let told = Walkthrough.Step(say: "Now look", waitForClick: false)
        #expect(told.cue(progress: session.progress, found: false).bolt == nil)
    }

    @Test func aMissingControlDoesNotHoldTheTour() {
        let named = Walkthrough.Step(say: "Click File", targetLabel: "File", waitForClick: true)
        let pointed = Walkthrough.Step(say: "Click here", target: PointTarget(x: 10, y: 20), waitForClick: true)
        let told = Walkthrough.Step(say: "Now look", waitForClick: false)
        #expect(!named.holdsForClick(found: false))
        #expect(named.holdsForClick(found: true))
        #expect(pointed.holdsForClick(found: true))
        #expect(!told.holdsForClick(found: true))
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
