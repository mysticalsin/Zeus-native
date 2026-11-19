import Foundation
import Testing
@testable import ZeusCore

/// The life of the tiling key tap as a pure state machine: off, starting, live, stopping and failed, and the events
/// that move it. The owner turns each effect into a system call; nothing here touches the system.
@Suite struct TileTapLifeTests {
    private typealias Life = TileTapLife

    private func life(after events: [Life.Event]) -> Life {
        var life = Life()
        for event in events { _ = life.handle(event) }
        return life
    }

    // MARK: Starting

    @Test func aNewTapIsOffAndNotRunning() {
        let life = Life()
        #expect(life.state == .off && !life.isRunning)
    }

    @Test func startingFromOffCreatesTheTapOnce() {
        var life = Life()
        #expect(life.handle(.startRequested) == .createTap)
        #expect(life.state == .starting && life.isRunning)
        #expect(life.handle(.startRequested) == .none, "a second start while starting creates nothing")
        #expect(life.state == .starting)
    }

    @Test func theTapIsLiveOnceTheThreadHasInstalledIt() {
        var life = Life()
        _ = life.handle(.startRequested)
        #expect(life.handle(.installed) == .none)
        #expect(life.state == .live && life.isRunning)
    }

    @Test func aTapThatCannotBeCreatedGoesBackToOffAndMayBeTriedAgain() {
        var life = Life()
        _ = life.handle(.startRequested)
        #expect(life.handle(.createFailed) == .none)
        #expect(life.state == .off && !life.isRunning)
        #expect(life.handle(.startRequested) == .createTap, "off again, so a later start tries again")
    }

    @Test func startingALiveTapOnlyTurnsItBackOn() {
        var life = life(after: [.startRequested, .installed])
        #expect(life.handle(.startRequested) == .enableTap)
        #expect(life.state == .live)
    }

    // MARK: The system turning it off

    @Test func aDisableThatHealthForgivesTurnsTheTapBackOn() {
        var life = life(after: [.startRequested, .installed])
        #expect(life.handle(.systemDisabled(.reenable)) == .enableTap)
        #expect(life.state == .live)
    }

    @Test func aDisableThatHealthGivesUpOnLeavesTheTapOffAndFailed() {
        var life = life(after: [.startRequested, .installed])
        #expect(life.handle(.systemDisabled(.giveUp)) == .disableTap)
        #expect(life.state == .failed && !life.isRunning)
        #expect(life.handle(.systemDisabled(.reenable)) == .disableTap, "a failed tap is never turned back on")
        #expect(life.state == .failed)
    }

    @Test func aFailedTapStaysFailedUntilItIsStoppedAndStartedAgain() {
        var life = life(after: [.startRequested, .installed, .systemDisabled(.giveUp)])
        #expect(life.handle(.startRequested) == .none, "start does not revive it")
        #expect(life.state == .failed && !life.isRunning)
        #expect(life.handle(.stopRequested) == .tearDown, "its thread and port are still there to remove")
        #expect(life.handle(.threadEnded) == .none)
        #expect(life.state == .off)
        #expect(life.handle(.startRequested) == .createTap)
    }

    @Test func aDisableBeforeTheTapIsInstalledCountsToo() {
        var starting = life(after: [.startRequested])
        #expect(starting.handle(.systemDisabled(.reenable)) == .enableTap)
        #expect(starting.state == .starting)
        #expect(starting.handle(.systemDisabled(.giveUp)) == .disableTap)
        #expect(starting.state == .failed)
    }

    // MARK: Stopping

    @Test func stoppingALiveTapTearsItDownThenIsOffWhenTheThreadEnds() {
        var life = life(after: [.startRequested, .installed])
        #expect(life.handle(.stopRequested) == .tearDown)
        #expect(life.state == .stopping && !life.isRunning)
        #expect(life.handle(.threadEnded) == .none)
        #expect(life.state == .off)
    }

    @Test func stoppingWhileStartingTearsDownAndALateInstallChangesNothing() {
        var life = life(after: [.startRequested])
        #expect(life.handle(.stopRequested) == .tearDown)
        #expect(life.state == .stopping)
        #expect(life.handle(.installed) == .none, "the thread installed just before it saw the stop")
        #expect(life.state == .stopping)
    }

    @Test func stoppingTwiceTearsDownOnce() {
        var life = life(after: [.startRequested, .installed])
        #expect(life.handle(.stopRequested) == .tearDown)
        #expect(life.handle(.stopRequested) == .none)
        #expect(life.state == .stopping)
    }

    @Test func stoppingAnOffTapDoesNothing() {
        var life = Life()
        #expect(life.handle(.stopRequested) == .none)
        #expect(life.state == .off)
    }

    @Test func nothingStartsWhileAStopIsFinishingAndSystemEventsAreIgnored() {
        var life = life(after: [.startRequested, .installed, .stopRequested])
        #expect(life.handle(.startRequested) == .none)
        #expect(!life.isRunning && life.state == .stopping)
        #expect(life.handle(.systemDisabled(.reenable)) == .none, "a tap on its way out is not turned back on")
        #expect(life.handle(.systemDisabled(.giveUp)) == .none)
        #expect(life.state == .stopping)
        #expect(life.handle(.createFailed) == .none)
        #expect(life.state == .stopping)
    }

    @Test func aThreadThatEndsByItselfLeavesTheTapOffWithNothingToTearDown() {
        for first in [[Life.Event.startRequested], [.startRequested, .installed], [.startRequested, .installed, .systemDisabled(.giveUp)]] {
            var life = life(after: first)
            #expect(life.handle(.threadEnded) == .none)
            #expect(life.state == .off && !life.isRunning)
        }
    }

    @Test func eventsThatMeanNothingInOffAreIgnored() {
        for event: Life.Event in [.createFailed, .installed, .systemDisabled(.reenable), .systemDisabled(.giveUp), .threadEnded] {
            var life = Life()
            #expect(life.handle(event) == .none, "\(event)")
            #expect(life.state == .off)
        }
    }

    // MARK: Switching on and off many times

    @Test func everyCreateIsMatchedByOneTearDownAcrossManyCycles() {
        var life = Life()
        var created = 0
        var torn = 0
        for cycle in 0..<500 {
            if life.handle(.startRequested) == .createTap { created += 1 }
            if cycle % 3 != 0 { _ = life.handle(.installed) }
            if cycle % 7 == 0 { _ = life.handle(.systemDisabled(.giveUp)) }
            if life.handle(.stopRequested) == .tearDown { torn += 1 }
            _ = life.handle(.threadEnded)
            #expect(life.state == .off, "cycle \(cycle)")
        }
        #expect(created == 500 && torn == 500, "created \(created), torn down \(torn)")
    }

    @Test func aCreateFailureNeedsNoTearDown() {
        var life = Life()
        var created = 0
        var torn = 0
        for _ in 0..<50 {
            if life.handle(.startRequested) == .createTap { created += 1 }
            _ = life.handle(.createFailed)
            if life.handle(.stopRequested) == .tearDown { torn += 1 }
        }
        #expect(created == 50 && torn == 0)
    }
}
