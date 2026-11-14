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

    @Test func theSweepStartsFullAndRunsForTheWholeCountdown() throws {
        let plan = try #require(sweep(at: 0))
        #expect(plan.from == 1)
        #expect(plan.duration == 5)
    }

    /// The share of the ring stroke that is drawn, read from the pixels of the ring view in its still form: the
    /// light it adds over an undrawn ring, against the light of a full one.
    @MainActor
    private func drawn(at elapsed: TimeInterval, reduceMotion: Bool = false) throws -> Double {
        func light(_ uptime: TimeInterval) throws -> Double {
            let ring = ScribeMeetingCardRing(deadline: deadline, uptime: uptime, total: total,
                                             reduceMotion: reduceMotion, still: true)
                .frame(width: 90, height: 40)
                .background(Color.black)
                .transaction { $0.animation = nil }
            let renderer = ImageRenderer(content: ring)
            renderer.scale = 2
            renderer.isOpaque = true
            let image = try #require(renderer.cgImage)
            let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            return (0..<image.width * image.height).reduce(0.0) { $0 + Double(bytes[$1 * 4]) }
        }
        let none = try light(deadline)
        return (try light(began + elapsed) - none) / (try light(began) - none)
    }

    @MainActor
    @Test func theRingDrawsTheShareLeftAtZeroOnePointFiveThreeAndFourPointNineSeconds() throws {
        for (elapsed, share) in [(0.0, 1.0), (1.5, 0.7), (3.0, 0.4), (4.9, 0.02)] {
            let got = try drawn(at: elapsed)
            #expect(abs(got - share) < 0.05, "at \(elapsed) s the ring drew \(got), expected \(share)")
        }
    }

    @MainActor
    @Test func theDrawnShareFallsAtOneSteadyRateAcrossEveryRedraw() throws {
        var previous = try drawn(at: 0)
        var steps: [Double] = []
        for half in 1...9 {
            let share = try drawn(at: Double(half) / 2)
            steps.append(previous - share)
            previous = share
        }
        // 0.5 s of a 5 s countdown is a tenth of the ring; neither a jump nor a stall at a redraw.
        #expect(steps.allSatisfy { abs($0 - 0.1) < 0.04 }, "steps were \(steps)")
        // The digit changes at each whole second while the ring keeps its line.
        let digits = [0.0, 0.4, 1.0, 1.5, 2.0, 3.0, 4.0, 4.9].map {
            ScribeMeetingCardText.seconds(deadline: deadline, now: began + $0)
        }
        #expect(digits == [5, 5, 4, 4, 3, 2, 1, 1])
    }

    @Test func aRingBornPartWayThroughStartsFromTheShareLeftAndEndsWithTheDeadline() throws {
        for born in [1.0, 2.5, 3.0, 4.2] {
            let late = try #require(sweep(at: born))
            #expect(abs(late.from - (total - born) / total) < 1e-9, "born at \(born) s")
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

    @MainActor
    @Test func reduceMotionStillDrawsTheShareLeftAtEveryRedraw() throws {
        for (elapsed, share) in [(0.0, 1.0), (1.5, 0.7), (3.0, 0.4), (4.9, 0.02)] {
            let got = try drawn(at: elapsed, reduceMotion: true)
            #expect(abs(got - share) < 0.05, "at \(elapsed) s the ring drew \(got), expected \(share)")
        }
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
