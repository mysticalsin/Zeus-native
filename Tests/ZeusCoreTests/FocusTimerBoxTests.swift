import Foundation
import Testing
@testable import ZeusCore

@Suite("Focus timer box")
struct FocusTimerBoxTests {
    private func calendar() -> Calendar { Calendar(identifier: .gregorian) }

    private func day(_ day: Int, hour: Int = 10) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func state(focus: TimeInterval = 60, rest: TimeInterval = 10,
                       phase: FocusTimerBox.Phase = .idle) -> FocusTimerBox.State {
        FocusTimerBox.State(focusLength: focus, restLength: rest, phase: phase)
    }

    @Test func theDefaultLengthsAreTwentyFiveAndFiveMinutes() {
        #expect(FocusTimerBox.defaultFocusLength == 25 * 60)
        #expect(FocusTimerBox.defaultRestLength == 5 * 60)
        #expect(FocusTimerBox.defaultExtend == 5 * 60)
        let fresh = FocusTimerBox.State()
        #expect(fresh.focusLength == 25 * 60)
        #expect(fresh.restLength == 5 * 60)
        #expect(fresh.phase == .idle)
        #expect(fresh.completedRounds == 0)
        #expect(fresh.adjustment == 0)
        #expect(fresh.timerRestores == nil)
    }

    @Test func theLongestRunIsThreeHours() {
        #expect(FocusTimerBox.longestMinutes == 180)
        #expect(FocusTimerBox.Dial.maxMinutes == 60)
        #expect(FocusTimerBox.Dial.step == 5)
    }

    @Test func formatRoundsUpToTheNextSecond() {
        #expect(FocusTimerBox.format(65) == "1:05")
        #expect(FocusTimerBox.format(0) == "0:00")
        #expect(FocusTimerBox.format(60) == "1:00")
        #expect(FocusTimerBox.format(59.01) == "1:00")
        #expect(FocusTimerBox.format(90) == "1:30")
        #expect(FocusTimerBox.format(90.2) == "1:31")
    }

    @Test func theDayKeyIsZeroPadded() {
        let calendar = calendar()
        #expect(FocusTimerBox.dayKey(day(8), calendar: calendar) == "2026-11-08")
        #expect(FocusTimerBox.dayKey(day(8, hour: 0), calendar: calendar) == "2026-11-08")
        #expect(FocusTimerBox.dayKey(day(9, hour: 23), calendar: calendar) == "2026-11-09")
    }

    @Test func anIdleTimerHasNoTimeLeftAndNoProgress() {
        let now = Date(timeIntervalSince1970: 1_000)
        let idle = state()
        #expect(FocusTimerBox.remaining(idle, at: now) == 0)
        #expect(FocusTimerBox.progress(idle, at: now) == 0)
        #expect(!FocusTimerBox.isPaused(idle))
        #expect(!FocusTimerBox.isRunning(idle))
        #expect(!FocusTimerBox.isPlainTimer(idle))
        #expect(FocusTimerBox.phaseLength(idle) == 60)
    }

    @Test func aRunningTimerCountsDownAndStopsAtZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        let running = FocusTimerBox.State(focusLength: 60, restLength: 10, phase: .focus,
                                           endsAt: start.addingTimeInterval(60))
        #expect(FocusTimerBox.remaining(running, at: start.addingTimeInterval(20)) == 40)
        #expect(FocusTimerBox.remaining(running, at: start.addingTimeInterval(60)) == 0)
        #expect(FocusTimerBox.remaining(running, at: start.addingTimeInterval(90)) == 0)
        #expect(FocusTimerBox.isRunning(running))
        #expect(!FocusTimerBox.isPaused(running))
    }

    @Test func aPauseHoldsTheRemainderAndIgnoresTheClock() {
        let start = Date(timeIntervalSince1970: 1_000)
        var running = state(phase: .focus)
        FocusTimerBox.start(&running, .focus, at: start)
        FocusTimerBox.pause(&running, at: start.addingTimeInterval(20))
        #expect(FocusTimerBox.isPaused(running))
        #expect(!FocusTimerBox.isRunning(running))
        #expect(running.endsAt == nil)
        #expect(FocusTimerBox.remaining(running, at: start.addingTimeInterval(500)) == 40)
        FocusTimerBox.resume(&running, at: start.addingTimeInterval(100))
        #expect(!FocusTimerBox.isPaused(running))
        #expect(running.endsAt == start.addingTimeInterval(140))
        #expect(FocusTimerBox.remaining(running, at: start.addingTimeInterval(100)) == 40)
    }

    @Test func pauseAndResumeDoNothingWhenTheyDoNotApply() {
        let now = Date(timeIntervalSince1970: 1_000)
        var idle = state()
        FocusTimerBox.pause(&idle, at: now)
        #expect(idle.phase == .idle)
        #expect(idle.pausedRemaining == nil)
        #expect(idle.endsAt == nil)
        var running = state(phase: .focus)
        FocusTimerBox.start(&running, .focus, at: now)
        let end = running.endsAt
        FocusTimerBox.resume(&running, at: now.addingTimeInterval(5))
        #expect(running.endsAt == end)
        #expect(running.pausedRemaining == nil)
        #expect(running.phase == .focus)
    }

    @Test func progressRunsFromTheStartOfThePhaseToTheEnd() {
        let start = Date(timeIntervalSince1970: 1_000)
        var running = state()
        FocusTimerBox.start(&running, .focus, at: start)
        #expect(FocusTimerBox.progress(running, at: start) == 0)
        #expect(FocusTimerBox.progress(running, at: start.addingTimeInterval(30)) == 0.5)
        #expect(FocusTimerBox.progress(running, at: start.addingTimeInterval(60)) == 1)
        #expect(FocusTimerBox.progress(running, at: start.addingTimeInterval(90)) == 1)
        let zero = FocusTimerBox.State(focusLength: 0, restLength: 10, phase: .focus, endsAt: start)
        #expect(FocusTimerBox.progress(zero, at: start) == 0)
    }

    @Test func startingFocusClearsAPauseAndUsesTheFocusLength() {
        let start = Date(timeIntervalSince1970: 1_000)
        var paused = FocusTimerBox.State(focusLength: 60, restLength: 10, phase: .focus,
                                          pausedRemaining: 12, adjustment: 9)
        FocusTimerBox.start(&paused, .focus, at: start)
        #expect(paused.phase == .focus)
        #expect(paused.pausedRemaining == nil)
        #expect(paused.adjustment == 0)
        #expect(paused.endsAt == start.addingTimeInterval(60))
        #expect(paused.focusLength == 60)
    }

    @Test func startingIdleStopsAndRestoresAPlainTimer() {
        let start = Date(timeIntervalSince1970: 1_000)
        var plain = FocusTimerBox.State(focusLength: 60, restLength: 10, phase: .focus,
                                         endsAt: start.addingTimeInterval(60), timerRestores: 1_500,
                                         adjustment: 4)
        FocusTimerBox.start(&plain, .idle, at: start)
        #expect(plain.phase == .idle)
        #expect(plain.focusLength == 1_500)
        #expect(plain.timerRestores == nil)
        #expect(plain.endsAt == nil)
        #expect(plain.pausedRemaining == nil)
        #expect(plain.adjustment == 0)
        #expect(!FocusTimerBox.isPlainTimer(plain))
    }

    @Test func startingRestUsesTheRestLength() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = FocusTimerBox.State(focusLength: 60, restLength: 10, pausedRemaining: 2, adjustment: 3)
        FocusTimerBox.start(&timer, .rest, at: start)
        #expect(timer.phase == .rest)
        #expect(timer.endsAt == start.addingTimeInterval(10))
        #expect(timer.adjustment == 0)
        #expect(timer.pausedRemaining == nil)
        #expect(FocusTimerBox.phaseLength(timer) == 10)
    }

    @Test func extendWhileIdleGrowsTheNextRoundAndStopsAtThreeHours() {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = state(focus: 1_500, rest: 300)
        FocusTimerBox.extend(&timer, by: FocusTimerBox.defaultExtend, at: now)
        #expect(timer.focusLength == 1_800)
        #expect(timer.phase == .idle)
        timer.focusLength = Double(FocusTimerBox.longestMinutes) * 60
        FocusTimerBox.extend(&timer, by: 300, at: now)
        #expect(timer.focusLength == Double(FocusTimerBox.longestMinutes) * 60)
    }

    @Test func extendWhileRunningPushesTheEndAndTheCapHolds() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = state(focus: 25 * 60, rest: 5 * 60)
        FocusTimerBox.setTime(&timer, minutes: 40, at: start)
        #expect(timer.focusLength == 2_400)
        FocusTimerBox.extend(&timer, by: 300, at: start)
        #expect(timer.focusLength == 2_700)
        FocusTimerBox.start(&timer, .focus, at: start)
        FocusTimerBox.extend(&timer, by: 300, at: start)
        #expect(FocusTimerBox.remaining(timer, at: start) == 3_000)
        #expect(FocusTimerBox.phaseLength(timer) == 3_000)
        #expect(timer.adjustment == 300)

        var paused = FocusTimerBox.State(focusLength: 60, restLength: 10, phase: .focus, pausedRemaining: 40)
        FocusTimerBox.extend(&paused, by: 300, at: start)
        #expect(paused.pausedRemaining == 340)
        #expect(paused.endsAt == nil)
        #expect(paused.adjustment == 300)

        let cap = Double(FocusTimerBox.longestMinutes) * 60
        var full = FocusTimerBox.State(focusLength: cap, restLength: 10, phase: .focus,
                                        endsAt: start.addingTimeInterval(cap))
        FocusTimerBox.extend(&full, by: 300, at: start)
        #expect(full.endsAt == start.addingTimeInterval(cap))
        #expect(full.adjustment == 0)
    }

    @Test func setTimeSetsTheRoundOrWhatIsLeft() {
        let start = Date(timeIntervalSince1970: 1_000)
        var idle = state(focus: 1_500, rest: 300)
        FocusTimerBox.setTime(&idle, minutes: 0, at: start)
        #expect(idle.focusLength == 60)
        FocusTimerBox.setTime(&idle, minutes: 500, at: start)
        #expect(idle.focusLength == Double(FocusTimerBox.longestMinutes) * 60)
        FocusTimerBox.setTime(&idle, minutes: 40, at: start)
        #expect(idle.focusLength == 2_400)
        #expect(idle.phase == .idle)

        var running = state(focus: 1_500, rest: 300, phase: .focus)
        FocusTimerBox.setTime(&running, minutes: 10, at: start)
        #expect(running.endsAt == start.addingTimeInterval(600))
        #expect(running.adjustment == 600 - 1_500)
        #expect(FocusTimerBox.remaining(running, at: start) == 600)
        #expect(running.focusLength == 1_500)

        var rest = FocusTimerBox.State(focusLength: 1_500, restLength: 300, phase: .rest)
        FocusTimerBox.setTime(&rest, minutes: 10, at: start)
        #expect(rest.adjustment == 600 - 300)
        #expect(rest.endsAt == start.addingTimeInterval(600))

        var held = FocusTimerBox.State(focusLength: 1_500, restLength: 300, phase: .focus, pausedRemaining: 20)
        FocusTimerBox.setTime(&held, minutes: 10, at: start)
        #expect(held.pausedRemaining == 600)
        #expect(held.endsAt == nil)
        #expect(held.adjustment == 600 - 1_500)
    }

    @Test func aPlainTimerEndsWithoutABreakAndRestoresTheFocusLength() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = state(focus: 1_500, rest: 300)
        FocusTimerBox.startTimer(&timer, seconds: 60, at: start)
        #expect(FocusTimerBox.isPlainTimer(timer))
        #expect(timer.timerRestores == 1_500)
        #expect(timer.focusLength == 60)
        #expect(timer.phase == .focus)
        #expect(timer.endsAt == start.addingTimeInterval(60))
        #expect(FocusTimerBox.remaining(timer, at: start) == 60)
        #expect(FocusTimerBox.tick(&timer, at: start.addingTimeInterval(61)) == .focus)
        #expect(timer.phase == .idle)
        #expect(timer.focusLength == 1_500)
        #expect(timer.timerRestores == nil)
        #expect(timer.completedRounds == 0)
        #expect(!FocusTimerBox.isPlainTimer(timer))
    }

    @Test func aSecondPlainTimerKeepsTheOriginalFocusLength() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = state(focus: 1_500, rest: 300)
        FocusTimerBox.startTimer(&timer, seconds: 60, at: start)
        FocusTimerBox.startTimer(&timer, seconds: 30, at: start.addingTimeInterval(5))
        #expect(timer.timerRestores == 1_500)
        #expect(timer.focusLength == 30)
        #expect(timer.endsAt == start.addingTimeInterval(35))
        #expect(FocusTimerBox.tick(&timer, at: start.addingTimeInterval(40)) == .focus)
        #expect(timer.focusLength == 1_500)
        #expect(timer.phase == .idle)
    }

    @Test func tickBeforeTheEndLeavesThePhaseAlone() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = state()
        FocusTimerBox.start(&timer, .focus, at: start)
        #expect(FocusTimerBox.tick(&timer, at: start.addingTimeInterval(59)) == nil)
        #expect(timer.phase == .focus)
        #expect(timer.endsAt == start.addingTimeInterval(60))
        #expect(timer.completedRounds == 0)
    }

    @Test func aFinishedFocusStartsTheBreakAndCountsTheRound() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = state(focus: 60, rest: 10)
        FocusTimerBox.start(&timer, .focus, at: start)
        #expect(FocusTimerBox.tick(&timer, at: start.addingTimeInterval(60)) == .focus)
        #expect(timer.phase == .rest)
        #expect(timer.completedRounds == 1)
        #expect(timer.roundsDay == FocusTimerBox.dayKey(start.addingTimeInterval(60)))
        #expect(timer.endsAt == start.addingTimeInterval(70))
        #expect(timer.adjustment == 0)
        #expect(FocusTimerBox.tick(&timer, at: start.addingTimeInterval(70)) == .rest)
        #expect(timer.phase == .idle)
        #expect(timer.endsAt == nil)
        #expect(timer.completedRounds == 1)
    }

    @Test func aFinishedFocusOnANewDayStartsTheCountAtOne() {
        let calendar = calendar()
        let earlier = day(8)
        let later = day(9)
        var timer = FocusTimerBox.State(focusLength: 60, restLength: 30, phase: .focus,
                                         endsAt: later, completedRounds: 4,
                                         roundsDay: FocusTimerBox.dayKey(earlier, calendar: calendar))
        #expect(FocusTimerBox.roundsToday(timer, at: earlier, calendar: calendar) == 4)
        #expect(FocusTimerBox.roundsToday(timer, at: later, calendar: calendar) == 0)
        #expect(FocusTimerBox.tick(&timer, at: later) == .focus)
        #expect(timer.completedRounds == 1)
        #expect(timer.roundsDay == FocusTimerBox.dayKey(later, calendar: calendar))
        #expect(timer.phase == .rest)
        #expect(FocusTimerBox.roundsToday(timer, at: later, calendar: calendar) == 1)
        let saved = FocusTimerBox.State(focusLength: 1_500, restLength: 300, completedRounds: 4)
        #expect(FocusTimerBox.roundsToday(saved, at: earlier, calendar: calendar) == 0)
    }

    @Test func aTickWhilePausedDoesNothing() {
        let now = Date(timeIntervalSince1970: 1_000)
        var paused = FocusTimerBox.State(focusLength: 60, restLength: 10, phase: .focus, pausedRemaining: 10)
        #expect(FocusTimerBox.tick(&paused, at: now) == nil)
        #expect(paused.phase == .focus)
        #expect(paused.pausedRemaining == 10)
        #expect(paused.completedRounds == 0)
        #expect(paused.endsAt == nil)
    }

    @Test func stopClearsTheRunAndRestoresAPlainLength() {
        let start = Date(timeIntervalSince1970: 1_000)
        var plain = FocusTimerBox.State(focusLength: 60, restLength: 10, phase: .focus,
                                         endsAt: start.addingTimeInterval(40), timerRestores: 1_500,
                                         adjustment: 8)
        FocusTimerBox.stop(&plain)
        #expect(plain.phase == .idle)
        #expect(plain.focusLength == 1_500)
        #expect(plain.timerRestores == nil)
        #expect(plain.endsAt == nil)
        #expect(plain.adjustment == 0)

        var normal = FocusTimerBox.State(focusLength: 90, restLength: 10, phase: .rest,
                                          endsAt: start, pausedRemaining: 4, adjustment: 2)
        FocusTimerBox.stop(&normal)
        #expect(normal.focusLength == 90)
        #expect(normal.phase == .idle)
        #expect(normal.pausedRemaining == nil)
        #expect(normal.endsAt == nil)
        #expect(normal.adjustment == 0)
    }

    @Test func theDialReadsClockwiseFromTwelve() {
        #expect(FocusTimerBox.Dial.fraction(dx: 0, dy: 0) == 0)
        #expect(FocusTimerBox.Dial.fraction(dx: 0, dy: -10) == 0)
        #expect(abs(FocusTimerBox.Dial.fraction(dx: 10, dy: 0) - 0.25) < 1e-9)
        #expect(abs(FocusTimerBox.Dial.fraction(dx: 0, dy: 10) - 0.5) < 1e-9)
        #expect(abs(FocusTimerBox.Dial.fraction(dx: -10, dy: 0) - 0.75) < 1e-9)
    }

    @Test func theDialSnapsToFiveMinutesAndReachesBothEnds() {
        #expect(FocusTimerBox.Dial.minutes(fraction: 0.5) == 30)
        #expect(FocusTimerBox.Dial.minutes(fraction: 0.26) == 15)
        #expect(FocusTimerBox.Dial.minutes(fraction: 0.001, previous: 10) == 5)
        #expect(FocusTimerBox.Dial.minutes(fraction: 0.999, previous: 55) == 60)
        #expect(FocusTimerBox.Dial.minutes(fraction: 0, previous: 55) == 60)
        #expect(FocusTimerBox.Dial.minutes(fraction: 0, previous: 0) == 5)
        #expect(FocusTimerBox.Dial.minutes(fraction: -0.2, previous: 0) == 5)
        #expect(FocusTimerBox.Dial.minutes(fraction: 1.4, previous: 0) == 60)
        #expect(FocusTimerBox.Dial.minutes(fraction: 0.5, previous: 10) == 30)
    }
}
