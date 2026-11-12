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
        let finished1 = run.finish(token)
        #expect(finished1)
        #expect(!run.isActive)
    }

    @Test func aSupersededRunFinishingLateDoesNotClearTheNewerRun() {
        // A cancelled voice turn used to clear `turnRunning` while the turn that replaced it was still working.
        var run = LatestRun()
        let old = run.begin()
        let new = run.begin()
        #expect(!run.isCurrent(old))
        let finished2 = run.finish(old)
        #expect(!finished2)
        #expect(run.isActive)
        let finished3 = run.finish(new)
        #expect(finished3)
        #expect(!run.isActive)
    }

    @Test func invalidateDropsTheRunInFlightAndGoesIdle() {
        var run = LatestRun()
        let token = run.begin()
        run.invalidate()
        #expect(!run.isActive)
        #expect(!run.isCurrent(token))
        let finished4 = run.finish(token)
        #expect(!finished4)
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
        let finished5 = run.finish(token)
        #expect(finished5)
        let finished6 = run.finish(token)
        #expect(finished6)
        #expect(!run.isActive)
        let next = run.begin()
        let finished7 = run.finish(token)
        #expect(!finished7)
        #expect(run.isActive)
        let finished8 = run.finish(next)
        #expect(finished8)
    }
}
