import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// The meeting card's motion read against an injected clock. The countdown ring is one linear sweep planned
/// when it appears; these cases sample that plan at chosen instants instead of waiting for real time.
@Suite("Meeting card motion")
struct ScribeMeetingCardMotionTests {
    private let total: TimeInterval = 5
    /// The machine's uptime when the countdown began, and its deadline.
    private let began: TimeInterval = 100
    private var deadline: TimeInterval { began + total }

    private func sweep(at elapsed: TimeInterval, reduceMotion: Bool = false) -> ScribeMeetingCardMotion.Sweep? {
        ScribeMeetingCardMotion.sweep(deadline: deadline, uptime: began + elapsed, total: total, reduceMotion: reduceMotion)
    }

    @Test func theRingStartsFullAndDrainsLinearlyOverTheWholeCountdown() throws {
        let plan = try #require(sweep(at: 0))
        #expect(plan.from == 1)
        #expect(plan.duration == 5)
        for (elapsed, share) in [(0.0, 1.0), (1.5, 0.7), (3.0, 0.4), (4.9, 0.02), (5.0, 0.0), (6.0, 0.0)] {
            #expect(abs(ScribeMeetingCardMotion.share(plan, elapsed: elapsed) - share) < 1e-9, "at \(elapsed) s")
        }
    }

    @Test func theShareFallsAtOneSteadyRateAcrossEveryPerSecondRedraw() throws {
        let plan = try #require(sweep(at: 0))
        var previous = ScribeMeetingCardMotion.share(plan, elapsed: 0)
        var steps: [Double] = []
        for tenth in 1...49 {
            let share = ScribeMeetingCardMotion.share(plan, elapsed: Double(tenth) / 10)
            steps.append(previous - share)
            previous = share
        }
        #expect(steps.allSatisfy { abs($0 - 0.02) < 1e-9 }, "the ring must neither jump nor stall at a redraw")
        // The digit changes at each whole second while the ring plan stays the one made at the start.
        let digits = [0.0, 0.4, 1.0, 1.5, 2.0, 3.0, 4.0, 4.9].map {
            ScribeMeetingCardText.seconds(deadline: deadline, now: began + $0)
        }
        #expect(digits == [5, 5, 4, 4, 3, 2, 1, 1])
    }

    @Test func aRingBornPartWayThroughContinuesTheSameLine() throws {
        let first = try #require(sweep(at: 0))
        for born in [1.0, 2.5, 3.0, 4.2] {
            let late = try #require(sweep(at: born))
            for step in [0.0, 0.3, 0.8] where born + step < 5 {
                let continued = ScribeMeetingCardMotion.share(late, elapsed: step)
                let original = ScribeMeetingCardMotion.share(first, elapsed: born + step)
                #expect(abs(continued - original) < 1e-9, "born at \(born) s, \(step) s later")
            }
            #expect(abs(late.duration - (total - born)) < 1e-9)
        }
    }

    @Test func nothingSweepsOncePastTheDeadline() {
        #expect(sweep(at: 5) == nil)
        #expect(sweep(at: 7.5) == nil)
        #expect(ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: deadline + 1, total: total, reduceMotion: false) == 0)
    }

    @Test func reduceMotionHasNoSweepWhileTheRingAndDigitStillStepDown() {
        var shares: [Double] = []
        var digits: [Int] = []
        for second in 0..<5 {
            let elapsed = Double(second)
            #expect(sweep(at: elapsed, reduceMotion: true) == nil)
            shares.append(ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: began + elapsed, total: total, reduceMotion: true))
            digits.append(ScribeMeetingCardText.seconds(deadline: deadline, now: began + elapsed))
        }
        for (got, want) in zip(shares, [1.0, 0.8, 0.6, 0.4, 0.2]) { #expect(abs(got - want) < 1e-9) }
        #expect(digits == [5, 4, 3, 2, 1])
    }

    @Test func withMotionTheDrawnShareIsTheStartingShareOfTheSweep() throws {
        for elapsed in [0.0, 1.0, 2.5] {
            let plan = try #require(sweep(at: elapsed))
            let drawn = ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: began + elapsed, total: total, reduceMotion: false)
            #expect(abs(plan.from - drawn) < 1e-9)
        }
    }

    @Test func entranceUsesTheAlertSpringAndDropAndReduceMotionOnlyFades() {
        let moving = ScribeMeetingCardMotion.entrance(reduceMotion: false)
        #expect(moving.animation == AlertStyle.stretch)
        #expect(moving.drop == 6)
        let still = ScribeMeetingCardMotion.entrance(reduceMotion: true)
        #expect(still.animation == .easeInOut(duration: AlertMotion.reducedFade))
        #expect(still.drop == 0)
    }

    @Test func aStateChangeInsideTheCardIsTheShortCrossfade() {
        #expect(ScribeMeetingCardMotion.crossfade == .easeInOut(duration: AlertMotion.reducedFade))
    }
}
