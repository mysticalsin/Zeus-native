import Foundation
import Testing
@testable import ZeusCore

/// Top-bar summary clicks. The clock is passed in. No player, no network, no capture.
@Suite struct TopBarWidgetClickTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func playSkipAgendaWeatherAndReducedMotionUseThePassedClock() {
        var play = TopBarWidgetClicks()
        let down = play.click(.play, at: now)
        #expect(down.effects.isEmpty)
        #expect(down.arm == now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        let early = play.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow - 0.001))
        #expect(early.effects.isEmpty)
        let settled = play.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(settled.effects == [.play])
        #expect(settled.effects.contains(.openDetails(.music)) == false)

        var skip = TopBarWidgetClicks()
        _ = skip.click(.skip, at: now)
        let skipped = skip.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(skipped.effects == [.next])
        #expect(skipped.effects.contains(.openDetails(.music)) == false)

        var agenda = TopBarWidgetClicks()
        _ = agenda.click(.agenda, at: now)
        let agendaDetails = agenda.click(.agenda, at: now.addingTimeInterval(0.2))
        #expect(agendaDetails.effects == [.openDetails(.calendar)])
        #expect(agendaDetails.effects.contains(.selectNextEvent) == false)
        #expect(agendaDetails.arm == nil)

        var weather = TopBarWidgetClicks()
        _ = weather.click(.weather, at: now)
        let weatherDetails = weather.click(.weather, at: now.addingTimeInterval(0.34))
        #expect(weatherDetails.effects == [.openDetails(.weather)])
        #expect(weatherDetails.effects.contains(.refreshWeather) == false)

        var single = TopBarWidgetClicks()
        _ = single.click(.weather, at: now)
        #expect(single.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)).effects == [.refreshWeather])

        #expect(TopBarWidgetClicks.detailsDuration(reduceMotion: true) == 0)
        #expect(TopBarWidgetClicks.detailsDuration(reduceMotion: false) == MotionTokens.crossfadeDuration)
        #expect(MotionTokens.crossfadeDuration > 0)
    }

    @Test func aSkipClickIssuesNextAndNotDetails() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.skip, at: now)
        let settled = clicks.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(settled.effects == [.next])
        #expect(settled.effects.contains(.openDetails(.music)) == false)
    }

    @Test func aDoubleClickOnTheAgendaOpensDetails() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.agenda, at: now)
        let second = clicks.click(.agenda, at: now.addingTimeInterval(0.2))
        #expect(second.effects == [.openDetails(.calendar)])
        #expect(second.effects.contains(.selectNextEvent) == false)
        #expect(second.arm == nil)
        #expect(clicks.tick(at: now.addingTimeInterval(1)).effects.isEmpty)
    }

    @Test func aDoubleClickOnTheWeatherOpensDetails() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.weather, at: now)
        let second = clicks.click(.weather, at: now.addingTimeInterval(0.34))
        #expect(second.effects == [.openDetails(.weather)])
        #expect(second.effects.contains(.refreshWeather) == false)
    }

    @Test func aSingleClickDoesNotAlsoOpenDetails() {
        var weather = TopBarWidgetClicks()
        _ = weather.click(.weather, at: now)
        let settled = weather.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(settled.effects == [.refreshWeather])

        var agenda = TopBarWidgetClicks()
        _ = agenda.click(.agenda, at: now)
        #expect(agenda.tick(at: now.addingTimeInterval(0.35)).effects == [.selectNextEvent])

        var music = TopBarWidgetClicks()
        _ = music.click(.music, at: now)
        #expect(music.tick(at: now.addingTimeInterval(0.35)).effects == [.play])

        var playing = TopBarWidgetClicks()
        _ = playing.click(.nowPlaying, at: now)
        #expect(playing.tick(at: now.addingTimeInterval(0.35)).effects == [.play])
    }

    @Test func aSecondClickOnTheBoundaryIsANewSingleClick() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.calendar, at: now)
        let boundary = now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        let again = clicks.click(.calendar, at: boundary)
        #expect(again.effects == [.selectNextEvent])
        #expect(again.arm == boundary.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(again.effects.contains(.openDetails(.calendar)) == false)
    }

    @Test func eachSummaryKeepsItsOwnSingleAndDoubleClick() {
        let singles: [(TopBarWidgetTarget, TopBarWidgetEffect)] = [
            (.pause, .pause),
            (.month, .selectNextEvent),
            (.focus, .toggleFocus),
        ]
        for (target, effect) in singles {
            var clicks = TopBarWidgetClicks()
            _ = clicks.click(target, at: now)
            #expect(clicks.tick(at: now.addingTimeInterval(0.35)).effects == [effect])
        }
        let doubles: [(TopBarWidgetTarget, TopBarWidgetDetails)] = [
            (.play, .music),
            (.skip, .music),
            (.music, .music),
            (.nowPlaying, .music),
            (.calendar, .calendar),
            (.month, .calendar),
            (.focus, .focus),
            (.agents, .agents),
        ]
        for (target, details) in doubles {
            var clicks = TopBarWidgetClicks()
            _ = clicks.click(target, at: now)
            let second = clicks.click(target, at: now.addingTimeInterval(0.1))
            #expect(second.effects == [.openDetails(details)])
        }
        var agents = TopBarWidgetClicks()
        _ = agents.click(.agents, at: now)
        #expect(agents.tick(at: now.addingTimeInterval(0.35)).effects.isEmpty)
    }

    @Test func aClickOnAnotherChipSettlesTheFirst() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.play, at: now)
        let skip = clicks.click(.skip, at: now.addingTimeInterval(0.1))
        #expect(skip.effects == [.play])
        #expect(skip.arm == now.addingTimeInterval(0.1 + TopBarWidgetClicks.doubleClickWindow))
        let settled = clicks.tick(at: now.addingTimeInterval(0.1 + TopBarWidgetClicks.doubleClickWindow))
        #expect(settled.effects == [.next])
    }

    @Test func voiceOverOpensDetailsWithoutWaiting() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.play, at: now)
        #expect(clicks.showDetails(.weather) == .openDetails(.weather))
        #expect(clicks.tick(at: now.addingTimeInterval(1)).effects.isEmpty)
        #expect(clicks.showDetails(.agenda) == .openDetails(.calendar))
        #expect(clicks.showDetails(.nowPlaying) == .openDetails(.music))
    }

    @Test func anAccessibilityActivateRunsTheSingleActionOnly() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.weather, at: now)
        let step = clicks.activate(.skip)
        #expect(step.effects == [.next])
        #expect(step.arm == nil)
        #expect(clicks.tick(at: now.addingTimeInterval(1)).effects.isEmpty)
        #expect(clicks.activate(.play).effects == [.play])
        #expect(clicks.activate(.agents).effects.isEmpty)
    }

    @Test func reducedMotionSnapsTheDetailsTransition() {
        #expect(TopBarWidgetClicks.detailsDuration(reduceMotion: true) == 0)
        #expect(TopBarWidgetClicks.detailsDuration(reduceMotion: false) == MotionTokens.crossfadeDuration)
        #expect(MotionTokens.crossfadeDuration > 0)
    }

    /// The session waits the delay the machine armed. The sleeper records that delay and returns when the test says so.
    /// The clock moves when that wait ends, which is what the wall clock has done after a real sleep.
    @Test @MainActor func theSessionSleepsTheArmedDelayThenIssuesPlay() async {
        let session = TopBarWidgetClickSession()
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = start
        session.now = { clock }
        let gate = ClickSleepGate()
        session.sleep = { duration in
            await gate.sleep(duration)
            clock = start.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        }
        let played = ClickBeacon()
        var effects: [TopBarWidgetEffect] = []
        session.tap(.play) { effect in
            effects.append(effect)
            played.hit()
        }
        await gate.armed.wait(for: 1)
        #expect(gate.durations.count == 1)
        #expect(abs(seconds(of: gate.durations[0]) - TopBarWidgetClicks.doubleClickWindow) < 0.000_001)
        #expect(effects.isEmpty)
        gate.release()
        await played.wait(for: 1)
        #expect(effects == [.play])
    }

    /// A clock that has already reached the armed date does not sleep, and the single action still runs.
    @Test @MainActor func theSessionDoesNotSleepWhenTheClockIsAlreadyDue() async {
        let session = TopBarWidgetClickSession()
        let start = Date(timeIntervalSince1970: 1_000)
        var reads = 0
        session.now = {
            reads += 1
            return reads == 1 ? start : start.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        }
        let gate = ClickSleepGate()
        session.sleep = { await gate.sleep($0) }
        let applied = ClickBeacon()
        var effects: [TopBarWidgetEffect] = []
        session.tap(.skip) { effect in
            effects.append(effect)
            applied.hit()
        }
        await applied.wait(for: 1)
        #expect(gate.durations.isEmpty)
        #expect(effects == [.next])
    }
}

private func seconds(of duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
}

/// Wakes a test when a click step has happened, without a timer.
@MainActor
private final class ClickBeacon {
    private(set) var count = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func hit() {
        count += 1
        let ready = waiters.filter { $0.target <= count }
        waiters.removeAll { $0.target <= count }
        for waiter in ready { waiter.continuation.resume() }
    }

    func wait(for target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
        }
    }
}

/// Records the delay the session asked to sleep, and holds until the test releases it.
@MainActor
private final class ClickSleepGate {
    let armed = ClickBeacon()
    private(set) var durations: [Duration] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            armed.hit()
        }
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
