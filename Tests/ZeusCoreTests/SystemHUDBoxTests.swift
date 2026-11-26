import Foundation
import Testing
@testable import ZeusCore

@Suite("System HUD box")
struct SystemHUDBoxTests {
    @Test func theLevelRulesUseTheHudConstants() {
        #expect(SystemHUDBox.coalesceInterval == 0.016)
        #expect(SystemHUDBox.valueDeltaThreshold == 0.004)
        #expect(SystemHUDBox.holdAfterChange == 1.2)
        #expect(SystemHUDBox.easeOut == 0.25)
        #expect(SystemHUDBox.segmentCount == 16)
        #expect(SystemHUDBox.burstInterval == 0.1)
        #expect(SystemHUDBox.idleInterval == 1)
        #expect(SystemHUDBox.burstWindow == 2)
    }

    @Test func sixteenSegmentsCoverTheLevel() {
        #expect(SystemHUDBox.segmentIndex(for: 0) == 0)
        #expect(SystemHUDBox.filledSegmentCount(for: 0) == 1)
        #expect(SystemHUDBox.segmentIndex(for: 0.0625) == 1)
        #expect(SystemHUDBox.segmentIndex(for: 0.5) == 8)
        #expect(SystemHUDBox.filledSegmentCount(for: 0.5) == 9)
        #expect(SystemHUDBox.segmentIndex(for: 1) == 15)
        #expect(SystemHUDBox.filledSegmentCount(for: 1) == 16)
        #expect(SystemHUDBox.segmentIndex(for: -1) == 0)
        #expect(SystemHUDBox.segmentIndex(for: 2) == 15)
    }

    @Test func aLevelThatIsNotFiniteUsesTheSameClamp() {
        #expect(SystemHUDBox.segmentIndex(for: .nan) == 15)
        #expect(SystemHUDBox.segmentIndex(for: .infinity) == 15)
        #expect(SystemHUDBox.segmentIndex(for: -.infinity) == 0)
        #expect(SystemHUDBox.filledSegmentCount(for: .nan) == 16)
    }

    @Test func aTinyChangeStaysQuietAndARealChangeReports() {
        #expect(!SystemHUDBox.shouldReport(previous: 0.5, next: 0.502))
        #expect(SystemHUDBox.shouldReport(previous: 0.5, next: 0.51))
        #expect(!SystemHUDBox.shouldReport(previous: 0, next: 0.004))
        #expect(SystemHUDBox.shouldReport(previous: 0, next: 0.01, threshold: 0.005))
        #expect(!SystemHUDBox.shouldReport(previous: 0, next: 0.01, threshold: 0.02))
    }

    @Test func stepsAreOneSixteenthAndOneSixtyFourth() {
        #expect(SystemHUDBox.stepDelta(fine: false) == 1.0 / 16.0)
        #expect(SystemHUDBox.stepDelta(fine: true) == 1.0 / 64.0)
        #expect(SystemHUDBox.steppedValue(0.5, direction: 1, fine: false) == 0.5625)
        #expect(SystemHUDBox.steppedValue(0.5, direction: -1, fine: true) == 0.5 - 1.0 / 64.0)
        #expect(SystemHUDBox.steppedValue(0.5, direction: 0, fine: false) == 0.5)
        #expect(SystemHUDBox.steppedValue(0.01, direction: -1, fine: false) == 0)
        #expect(SystemHUDBox.steppedValue(0.99, direction: 1, fine: false) == 1)
    }

    @Test func theCueLastsForTheHoldThatIsLeftPlusTheEase() {
        #expect(SystemHUDBox.cueDuration(sinceLastChange: 0) == SystemHUDBox.holdAfterChange + SystemHUDBox.easeOut)
        #expect(SystemHUDBox.cueDuration(sinceLastChange: 1.2) == SystemHUDBox.easeOut)
        #expect(SystemHUDBox.cueDuration(sinceLastChange: 2) == SystemHUDBox.easeOut)
        #expect(SystemHUDBox.cueDuration(sinceLastChange: -1) == SystemHUDBox.holdAfterChange + 1 + SystemHUDBox.easeOut)
    }

    @Test func burstsCloserThanTheWindowBecomeOneTime() {
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        let merged = SystemHUDBox.coalesceTimes([
            t0,
            t0.addingTimeInterval(0.005),
            t0.addingTimeInterval(0.01),
            t0.addingTimeInterval(0.2),
        ])
        #expect(merged.count == 2)
        #expect(merged.first.map { abs($0.timeIntervalSince(t0) - 0.01) < 0.0001 } == true)
        #expect(merged.dropFirst().first.map { abs($0.timeIntervalSince(t0) - 0.2) < 0.0001 } == true)
        #expect(SystemHUDBox.coalesceTimes([]).isEmpty)
    }

    @Test func aBackwardPairCollapsesToTheLaterSample() {
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        let merged = SystemHUDBox.coalesceTimes([t0.addingTimeInterval(1), t0])
        #expect(merged.count == 1)
        #expect(merged.first.map { abs($0.timeIntervalSince(t0)) < 0.0001 } == true)
    }

    @Test func theFastPollLastsOnlyThroughTheBurst() {
        #expect(SystemHUDBox.interval(sinceLastChange: 0) == SystemHUDBox.burstInterval)
        #expect(SystemHUDBox.interval(sinceLastChange: SystemHUDBox.burstWindow - 0.01) == SystemHUDBox.burstInterval)
        #expect(SystemHUDBox.interval(sinceLastChange: SystemHUDBox.burstWindow) == SystemHUDBox.idleInterval)
        #expect(SystemHUDBox.interval(sinceLastChange: 3600) == SystemHUDBox.idleInterval)
        #expect(SystemHUDBox.interval(sinceLastChange: -1) == SystemHUDBox.burstInterval)
        #expect(SystemHUDBox.interval(sinceLastChange: .nan) == SystemHUDBox.idleInterval)
        #expect(SystemHUDBox.interval(sinceLastChange: .infinity) == SystemHUDBox.idleInterval)
    }

    @Test func pollingStaysOffWhenNothingIsShownOrTheDisplaysSleep() {
        #expect(!SystemHUDBox.shouldPoll(brightnessEnabled: false, keyboardBacklightEnabled: false, displaysAsleep: false))
        #expect(!SystemHUDBox.shouldPoll(brightnessEnabled: true, keyboardBacklightEnabled: true, displaysAsleep: true))
        #expect(SystemHUDBox.shouldPoll(brightnessEnabled: true, keyboardBacklightEnabled: false, displaysAsleep: false))
        #expect(SystemHUDBox.shouldPoll(brightnessEnabled: false, keyboardBacklightEnabled: true, displaysAsleep: false))
    }
}
