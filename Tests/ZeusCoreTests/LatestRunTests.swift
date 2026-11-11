import Testing
import ZeusCore

@Suite("Latest run")
struct LatestRunTests {
    @Test func startsIdleAndIsActiveBetweenBeginAndFinish() {
        var run = LatestRun()
        #expect(!run.isActive)
        let token = run.begin()
        #expect(run.isActive)
        #expect(run.isCurrent(token))
        #expect(run.finish(token))
        #expect(!run.isActive)
    }

    @Test func aSupersededRunFinishingLateDoesNotClearTheNewerRun() {
        // A cancelled voice turn used to clear `turnRunning` while the turn that replaced it was still working.
        var run = LatestRun()
        let old = run.begin()
        let new = run.begin()
        #expect(!run.isCurrent(old))
        #expect(!run.finish(old))
        #expect(run.isActive)
        #expect(run.finish(new))
        #expect(!run.isActive)
    }

    @Test func invalidateDropsTheRunInFlightAndGoesIdle() {
        var run = LatestRun()
        let token = run.begin()
        run.invalidate()
        #expect(!run.isActive)
        #expect(!run.isCurrent(token))
        #expect(!run.finish(token))
    }

    @Test func aReadStartedBeforeAWriteCannotPublishAfterIt() {
        var reads = LatestRun()
        let read = reads.begin()
        reads.invalidate() // the owner flipped the switch while the status read was in flight
        #expect(!reads.isCurrent(read))
        let later = reads.begin()
        #expect(reads.isCurrent(later))
    }

    @Test func finishingTwiceIsHarmless() {
        var run = LatestRun()
        let token = run.begin()
        #expect(run.finish(token))
        #expect(run.finish(token))
        #expect(!run.isActive)
        let next = run.begin()
        #expect(!run.finish(token))
        #expect(run.isActive)
        #expect(run.finish(next))
    }
}
