import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// The meeting card's motion planned from plain numbers. The countdown ring is one linear sweep planned when it
/// appears; these cases sample that plan at chosen instants. `ScribeMeetingCardHostedMotionTests` watches the
/// sweep run in a hosted card.
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

/// The countdown ring read from the pixels of a hosted card, re-rendered once a second the way the machine will.
/// Real time passes here: SwiftUI runs the sweep itself, so the only clock that can drive it is the wall clock.
@MainActor
@Suite("Meeting card hosted motion", .serialized)
struct ScribeMeetingCardHostedMotionTests {
    private let total: TimeInterval = 5
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting() -> ScribeMeeting {
        let slot = ScribeCalendarSlot(id: "hosted", title: "Hosted", start: now, hasCallLink: true)
        return ScribeMeeting(key: "hosted", title: "Hosted", callApp: .other("Synthetic"), slot: slot)
    }

    private func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func countdown(deadline: TimeInterval, at moment: TimeInterval? = nil) -> ScribeMeetingCard {
        .countdown(meeting(), seconds: ScribeMeetingCardText.seconds(deadline: deadline, now: moment ?? uptime()),
                   deadline: deadline, total: total)
    }

    private func sleep(until moment: TimeInterval) async throws {
        let wait = moment - uptime()
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
    }

    private func offscreen<V: View>(_ view: V) -> (NSWindow, NSHostingView<V>) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: host.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }

    /// The light in the right edge of a view (the ring and Cancel; the words never reach it).
    private func light(_ view: NSView) throws -> Double {
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        var sum = 0.0
        let edge = Int(90 * Double(rep.pixelsWide) / Double(view.bounds.width))
        for x in max(0, rep.pixelsWide - edge)..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                sum += Double(color.redComponent * color.alphaComponent)
            }
        }
        return sum
    }

    /// The same card at rest with the ring full and with it empty: the two ends a reading is placed between.
    private func ends(card: (TimeInterval) -> ScribeMeetingCard) throws -> (full: Double, empty: Double) {
        func rest(_ share: Double) throws -> Double {
            let deadline = 1_000.0
            let (window, host) = offscreen(ScribeMeetingCardView(card: card(deadline), now: now,
                                                                 uptime: deadline - total * share, settled: true))
            defer { window.close() }
            return try light(host)
        }
        return (try rest(1), try rest(0))
    }

    private func share(_ reading: Double, _ ends: (full: Double, empty: Double)) -> Double {
        (reading - ends.empty) / (ends.full - ends.empty)
    }

    /// Re-renders once a second, reads at each of `marks` (seconds since the card was handed over) and returns
    /// each reading's share of the ring left.
    private func watch(began: TimeInterval, deadline: TimeInterval, marks: [TimeInterval],
                       render: (TimeInterval) -> Void, read: () throws -> Double) async throws -> [Double] {
        var readings: [Double] = []
        var nextRedraw = began + 1
        for mark in marks {
            while nextRedraw <= began + mark {
                try await sleep(until: nextRedraw)
                render(deadline)
                nextRedraw += 1
            }
            try await sleep(until: began + mark)
            readings.append(try read())
        }
        return readings
    }

    private func panel() -> ScribeMeetingCardPanel {
        ScribeMeetingCardPanel(actions: .init(), now: { Date(timeIntervalSince1970: 1_800_000_000) },
                               visibleFrame: { CGRect(x: -30_000, y: -30_000, width: 1440, height: 900) },
                               fade: { _, _, done in done?() })
    }

    private func expectSteadyFall(_ shares: [Double], at marks: [TimeInterval], sourceLocation: SourceLocation = #_sourceLocation) {
        for (got, mark) in zip(shares, marks) {
            let want = (total - mark) / total
            #expect(abs(got - want) < 0.12, "at \(mark) s the ring drew \(got), expected \(want)", sourceLocation: sourceLocation)
        }
    }

    @Test func aCountdownThatReplacesAnOfferDrainsAtOneSteadyRateAcrossEveryPerSecondRedraw() async throws {
        let card = panel()
        defer { card.window?.close() }
        let reference = try ends { .countdown(meeting(), seconds: 5, deadline: $0, total: total) }
        card.render(.offer(meeting(), blocked: nil))
        // Let the entrance land, as it has when the person sees the offer first.
        try await Task.sleep(for: .seconds(0.8))
        let began = uptime()
        let deadline = began + total
        card.render(countdown(deadline: deadline))
        let marks: [TimeInterval] = [0.1, 0.6, 1.1, 1.5, 2.1, 2.6, 3.0, 3.6, 4.1, 4.6, 4.9]
        let shares = try await watch(began: began, deadline: deadline, marks: marks,
                                     render: { card.render(countdown(deadline: $0)) },
                                     read: { share(try light(try #require(card.window?.contentView)), reference) })
        expectSteadyFall(shares, at: marks)
        for (before, after) in zip(shares, shares.dropFirst()) {
            #expect(after < before + 0.04, "the ring must never refill: \(shares)")
        }
    }

    @Test func aCountdownThatAppearsFromHiddenDrainsOverTheWholeCountdownNotOnTheEntranceSpring() async throws {
        let card = panel()
        defer { card.window?.close() }
        let reference = try ends { .countdown(meeting(), seconds: 5, deadline: $0, total: total) }
        let began = uptime()
        let deadline = began + total
        card.render(countdown(deadline: deadline))
        let marks: [TimeInterval] = [0.9, 1.5, 3.0, 4.9]
        let shares = try await watch(began: began, deadline: deadline, marks: marks,
                                     render: { card.render(countdown(deadline: $0)) },
                                     read: { share(try light(try #require(card.window?.contentView)), reference) })
        expectSteadyFall(shares, at: marks)
    }

    @Test func withReduceMotionTheRingStepsDownAtEachRedrawAndTheDigitStillCounts() async throws {
        func ring(_ deadline: TimeInterval, uptime: TimeInterval, still: Bool) -> some View {
            ScribeMeetingCardRing(deadline: deadline, uptime: uptime, total: total, reduceMotion: true, still: still)
                .id(deadline)
                .frame(width: 68, height: 34)
                .background(Color.black)
        }
        func rest(_ share: Double) throws -> Double {
            let (window, host) = offscreen(ring(1_000, uptime: 1_000 - total * share, still: true))
            defer { window.close() }
            return try light(host)
        }
        let reference = (full: try rest(1), empty: try rest(0))
        let began = uptime()
        let deadline = began + total
        let (window, host) = offscreen(ring(deadline, uptime: began, still: false))
        defer { window.close() }
        let marks: [TimeInterval] = [0.5, 0.95, 1.5, 1.95, 2.5]
        var digits: [Int] = []
        let shares = try await watch(began: began, deadline: deadline, marks: marks,
                                     render: { host.rootView = ring($0, uptime: uptime(), still: false) },
                                     read: {
            digits.append(ScribeMeetingCardText.seconds(deadline: deadline, now: uptime()))
            return share(try light(host), reference)
        })
        // One step per redraw and nothing in between: no sweep runs.
        for (got, want) in zip(shares, [1.0, 1.0, 0.8, 0.8, 0.6]) {
            #expect(abs(got - want) < 0.07, "the ring drew \(got), expected \(want); readings \(shares)")
        }
        #expect(digits == [5, 5, 4, 4, 3])
    }
}
