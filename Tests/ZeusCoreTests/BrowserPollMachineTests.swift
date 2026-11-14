import Foundation
import Testing
@testable import ZeusCore

@Suite struct BrowserPollMachineTests {
    private let playing = BrowserPollContext(followsAny: true, outputRunning: true, browserShown: true, browserShownPlaying: true)
    private let quiet = BrowserPollContext(followsAny: true)

    /// Runs events in order and returns the final state with every effect, oldest first.
    private func run(_ events: [BrowserPollEvent], from start: BrowserPollState = BrowserPollState()) -> (state: BrowserPollState, effects: [BrowserPollEffect]) {
        var state = start
        var effects: [BrowserPollEffect] = []
        for event in events {
            let step = BrowserPollMachine.next(state, event)
            state = step.0
            effects += step.1
        }
        return (state, effects)
    }

    private func step(_ state: BrowserPollState, _ event: BrowserPollEvent) -> (BrowserPollState, [BrowserPollEffect]) {
        BrowserPollMachine.next(state, event)
    }

    /// Setting on, Chrome running, a new enough extension and nothing in flight.
    private func ready() -> BrowserPollState {
        run([.settingOn, .chromeLaunched, .version("0.5.0")]).state
    }

    // MARK: Starting

    @Test func nothingPollsUntilTheSettingIsOnChromeRunsAndTheExtensionIsNewEnough() {
        var state = BrowserPollState()
        #expect(step(state, .tick(playing)).1.isEmpty)
        state = step(state, .settingOn).0
        #expect(step(state, .tick(playing)).1.isEmpty)
        let launched = step(state, .chromeLaunched)
        #expect(launched.1 == [.pingNow])
        #expect(step(launched.0, .tick(playing)).1.isEmpty, "a ping is in flight and the version is unknown")
        let versioned = step(launched.0, .version("0.5.0"))
        #expect(versioned.1 == [.schedule(0.5)])
        #expect(step(versioned.0, .tick(playing)).1 == [.pollNow])
    }

    @Test func turningTheSettingOnWhileChromeRunsPingsAtOnce() {
        let chrome = step(BrowserPollState(), .chromeLaunched).0
        #expect(step(chrome, .settingOn).1 == [.pingNow])
    }

    @Test func anOldExtensionIsNeverPolledAndGetsTheReloadHint() {
        let started = run([.settingOn, .chromeLaunched])
        for version in ["0.4.0", nil] as [String?] {
            let answered = step(started.state, .version(version))
            #expect(answered.1 == [.cancelTimer, .dropEntries, .hint(.reloadExtension)])
            #expect(step(answered.0, .tick(playing)).1 == [.pingNow], "a later tick looks again and never polls")
        }
    }

    // MARK: The loop

    @Test func aGoodReplyAsksForTheNextPollAfterTheDelayTheContextGives() {
        let state = ready()
        let polled = step(state, .tick(playing))
        #expect(polled.1 == [.pollNow])
        #expect(step(polled.0, .tick(playing)).1.isEmpty, "one request in flight")
        #expect(step(polled.0, .reply(playing)).1 == [.schedule(2)])
        let output = BrowserPollContext(followsAny: true, outputRunning: true, browserShown: false)
        #expect(step(polled.0, .reply(output)).1 == [.schedule(5)])
        #expect(step(polled.0, .reply(quiet)).1 == [.cancelTimer])
    }

    @Test func aTickWithNothingToWatchPollsNothing() {
        #expect(step(ready(), .tick(quiet)).1.isEmpty)
        #expect(step(ready(), .tick(BrowserPollContext(followsAny: false, outputRunning: true))).1.isEmpty)
    }

    @Test func chromeOutputStartingWakesTheLoopWhenItIsIdle() {
        let state = ready()
        #expect(step(state, .outputActivity(true)).1 == [.schedule(1)])
        #expect(step(state, .outputActivity(false)).1.isEmpty)
    }

    // MARK: Failures

    @Test func aTimeoutKeepsTheStateForThreePollsThenDropsIt() {
        var state = ready()
        var dropped = 0
        for round in 1...4 {
            state = step(state, .tick(playing)).0
            let result = step(state, .timedOut)
            state = result.0
            #expect(result.1.contains(.schedule(5)), "round \(round)")
            if result.1.contains(.dropEntries) { dropped += 1 }
            if round < 3 { #expect(!result.1.contains(.dropEntries), "round \(round)") }
            if round == 3 { #expect(result.1.contains(.dropEntries)) }
        }
        #expect(dropped == 1)
    }

    @Test func aGoodReplyResetsTheFailureCount() {
        var state = ready()
        for _ in 0..<2 {
            state = step(step(state, .tick(playing)).0, .timedOut).0
        }
        state = step(step(state, .tick(playing)).0, .reply(playing)).0
        for _ in 0..<2 {
            let result = step(step(state, .tick(playing)).0, .timedOut)
            state = result.0
            #expect(!result.1.contains(.dropEntries))
        }
    }

    @Test func notConnectedWhileChromeRunsPingsBeforePollingAgain() {
        var state = step(ready(), .tick(playing)).0
        let failed = step(state, .notConnected)
        state = failed.0
        #expect(failed.1 == [.schedule(5)])
        let next = step(state, .tick(playing))
        #expect(next.1 == [.pingNow], "a ping comes before any poll")
        let stillDown = step(next.0, .notConnected)
        #expect(stillDown.1 == [.schedule(10)])
        #expect(step(stillDown.0, .tick(playing)).1 == [.pingNow])
    }

    @Test func theBackOffIsFiveTenTwentyFortySixtyAndStaysAtSixty() {
        var state = ready()
        var delays: [TimeInterval] = []
        for _ in 0..<7 {
            let result = step(state, .notConnected)
            state = result.0
            for case .schedule(let delay) in result.1 { delays.append(delay) }
        }
        #expect(delays == [5, 10, 20, 40, 60, 60, 60])
    }

    @Test func threeNotConnectedInARowDropTheEntries() {
        var state = ready()
        var drops: [Int] = []
        for round in 1...4 {
            let result = step(state, .notConnected)
            state = result.0
            if result.1.contains(.dropEntries) { drops.append(round) }
        }
        #expect(drops == [3])
    }

    @Test func aPingThatAnswersAfterABackOffResetsAndPollsAgain() {
        var state = ready()
        state = step(state, .notConnected).0
        state = step(state, .notConnected).0
        let ping = step(state, .tick(playing))
        #expect(ping.1 == [.pingNow])
        let good = step(ping.0, .version("0.5.0"))
        #expect(good.1 == [.schedule(0.5)])
        #expect(step(good.0, .tick(playing)).1 == [.pollNow])
        #expect(step(step(good.0, .tick(playing)).0, .notConnected).1 == [.schedule(5)], "the back-off starts over")
    }

    // MARK: Stopping

    @Test func chromeQuittingStopsTheLoopAndDropsTheEntries() {
        let state = ready()
        let quit = step(state, .chromeQuit)
        #expect(quit.1 == [.cancelTimer, .dropEntries])
        #expect(step(quit.0, .tick(playing)).1.isEmpty)
        #expect(step(quit.0, .notConnected).1.isEmpty, "a late failure from the last poll does nothing")
        #expect(step(quit.0, .reply(playing)).1.isEmpty)
        #expect(step(quit.0, .chromeLaunched).1 == [.pingNow], "and it starts again when Chrome launches")
    }

    @Test func theSettingOffStopsTheLoopAndDropsTheEntries() {
        let off = step(ready(), .settingOff)
        #expect(off.1 == [.cancelTimer, .dropEntries])
        #expect(step(off.0, .tick(playing)).1.isEmpty)
        #expect(step(off.0, .chromeLaunched).1.isEmpty)
    }

    @Test func aPinStopsPollingAndDropsTheEntriesAndAnyPlayerStartsItAgain() {
        let pinned = step(ready(), .followChanged(followsAny: false))
        #expect(pinned.1 == [.cancelTimer, .dropEntries])
        #expect(step(pinned.0, .tick(BrowserPollContext(followsAny: false, outputRunning: true, browserShown: true, browserShownPlaying: true))).1.isEmpty)
        #expect(step(pinned.0, .outputActivity(true)).1.isEmpty)
        let again = step(pinned.0, .followChanged(followsAny: true))
        #expect(again.1 == [.schedule(1)])
    }

    @Test func screenSleepPausesPollingAndWakeResumesIt() {
        let asleep = step(ready(), .screensSlept)
        #expect(asleep.1 == [.cancelTimer])
        #expect(step(asleep.0, .tick(playing)).1.isEmpty)
        #expect(step(asleep.0, .outputActivity(true)).1.isEmpty)
        #expect(step(asleep.0, .screensWoke).1 == [.schedule(1)])
    }

    @Test func wakingWithNothingToResumeSchedulesNothing() {
        #expect(step(BrowserPollState(), .screensWoke).1.isEmpty)
    }

    // MARK: Command results

    @Test func aStaleTargetDropsTheItemWithNoRetry() {
        let result = step(ready(), .staleTarget)
        #expect(result.1 == [.dropTarget])
        #expect(result.0 == ready(), "the loop is unchanged")
    }

    @Test func notSupportedHintsOnceUntilChromeStartsAgain() {
        let first = step(ready(), .notSupported)
        #expect(first.1 == [.hint(.commandNotSupported)])
        #expect(step(first.0, .notSupported).1.isEmpty)
        let restarted = run([.chromeQuit, .chromeLaunched, .version("0.5.0")], from: first.0)
        #expect(step(restarted.state, .notSupported).1 == [.hint(.commandNotSupported)])
    }

    // MARK: Status

    @Test func theReloadHintShowsOnlyWhileChromeRunsAndTheExtensionIsOld() {
        let old = run([.settingOn, .chromeLaunched, .version("0.4.0")]).state
        #expect(old.needsExtensionReload)
        #expect(!ready().needsExtensionReload)
        #expect(!step(old, .chromeQuit).0.needsExtensionReload)
        #expect(!step(old, .settingOff).0.needsExtensionReload)
    }
}
