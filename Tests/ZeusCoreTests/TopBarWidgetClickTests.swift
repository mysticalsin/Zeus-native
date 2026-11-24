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
        let agendaSecond = agenda.click(.agenda, at: now.addingTimeInterval(0.2))
        #expect(agendaSecond.effects.isEmpty)
        let agendaDetails = agenda.tick(at: now.addingTimeInterval(0.2 + TopBarWidgetClicks.doubleClickWindow))
        #expect(agendaDetails.effects == [.openDetails(.calendar)])
        #expect(agendaDetails.effects.contains(.selectNextEvent) == false)
        #expect(agendaDetails.arm == nil)

        var weather = TopBarWidgetClicks()
        _ = weather.click(.weather, at: now)
        let weatherSecond = weather.click(.weather, count: 2, at: now.addingTimeInterval(0.34))
        #expect(weatherSecond.effects.isEmpty)
        let weatherDetails = weather.tick(at: now.addingTimeInterval(0.34 + TopBarWidgetClicks.doubleClickWindow))
        #expect(weatherDetails.effects == [.openDetails(.weather)])
        #expect(weatherDetails.effects.contains(.refreshWeather) == false)

        var counted = TopBarWidgetClicks()
        _ = counted.click(.agenda, count: 2, at: now)
        #expect(counted.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)).effects == [.openDetails(.calendar)])

        var triple = TopBarWidgetClicks()
        _ = triple.click(.weather, count: 1, at: now)
        _ = triple.click(.weather, count: 2, at: now.addingTimeInterval(0.05))
        _ = triple.click(.weather, count: 3, at: now.addingTimeInterval(0.1))
        let tripled = triple.tick(at: now.addingTimeInterval(0.1 + TopBarWidgetClicks.doubleClickWindow))
        #expect(tripled.effects == [.tripleClick(.weather)])
        #expect(tripled.effects.contains(.openDetails(.weather)) == false)
        #expect(tripled.effects.contains(.refreshWeather) == false)

        var swipe = TopBarWidgetClicks()
        _ = swipe.click(.calendar, at: now)
        let embedded = swipe.rightSwipe(.calendar, distance: TopBarWidgetClicks.rightSwipeDistance)
        #expect(embedded.effects == [.embeddedDetails(.calendar)])
        #expect(embedded.arm == nil)
        #expect(swipe.tick(at: now.addingTimeInterval(1)).effects.isEmpty)
        #expect(TopBarWidgetClicks.route(.hold) == nil)
        #expect(TopBarWidgetClicks.route(.click(count: 2)) == .doubleClick)
        #expect(TopBarWidgetClicks.route(.click(count: 3)) == .tripleClick)
        #expect(TopBarWidgetClicks.route(.rightSwipe(dx: 36, dy: 0)) == .rightSwipe)
        #expect(TopBarWidgetClicks.route(.rightSwipe(dx: 40, dy: 30)) == nil)

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
        #expect(second.effects.isEmpty)
        let opened = clicks.tick(at: now.addingTimeInterval(0.2 + TopBarWidgetClicks.doubleClickWindow))
        #expect(opened.effects == [.openDetails(.calendar)])
        #expect(opened.effects.contains(.selectNextEvent) == false)
        #expect(opened.arm == nil)
        #expect(clicks.tick(at: now.addingTimeInterval(1)).effects.isEmpty)
    }

    @Test func aDoubleClickOnTheWeatherOpensDetails() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.weather, count: 2, at: now)
        #expect(clicks.click(.weather, count: 1, at: now.addingTimeInterval(0.05)).effects.isEmpty)
        let opened = clicks.tick(at: now.addingTimeInterval(0.05 + TopBarWidgetClicks.doubleClickWindow))
        #expect(opened.effects == [.openDetails(.weather)])
        #expect(opened.effects.contains(.refreshWeather) == false)
    }

    @Test func aTripleClickStaysATripleClick() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.focus, count: 3, at: now)
        let settled = clicks.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(settled.effects == [.tripleClick(.focus)])
        #expect(settled.effects.contains(.openDetails(.focus)) == false)
        #expect(settled.effects.contains(.toggleFocus) == false)
    }

    @Test func aRightSwipeEmbedsDetailsAndCancelsTheClick() {
        var clicks = TopBarWidgetClicks()
        _ = clicks.click(.music, at: now)
        let short = clicks.rightSwipe(.music, distance: TopBarWidgetClicks.rightSwipeDistance - 0.01)
        #expect(short.effects.isEmpty)
        #expect(short.arm == now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        let swiped = clicks.rightSwipe(.music, distance: TopBarWidgetClicks.rightSwipeDistance)
        #expect(swiped.effects == [.embeddedDetails(.music)])
        #expect(swiped.effects.contains(.openDetails(.music)) == false)
        #expect(clicks.tick(at: now.addingTimeInterval(1)).effects.isEmpty)
        #expect(TopBarWidgetClicks.isRightSwipe(dx: -40, dy: 0) == false)
        #expect(TopBarWidgetClicks.isRightSwipe(dx: 40, dy: 10))
        #expect(TopBarWidgetClicks.route(.hold) == nil)
        #expect(TopBarWidgetClicks.route(.click(count: 1)) == .click)
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

    @Test func theTransportPausesWhilePlayingAndPlaysWhilePaused() {
        #expect(TopBarWidgetClicks.transportTarget(isPlaying: true) == .pause)
        #expect(TopBarWidgetClicks.transportTarget(isPlaying: false) == .play)
        #expect(TopBarWidgetClicks.closedWingsShowTransport(liveWings: true, hasTrack: true))
        #expect(TopBarWidgetClicks.closedWingsShowTransport(liveWings: true, hasTrack: false) == false)
        #expect(TopBarWidgetClicks.closedWingsShowTransport(liveWings: false, hasTrack: true) == false)

        var playing = TopBarWidgetClicks()
        _ = playing.click(TopBarWidgetClicks.transportTarget(isPlaying: true), at: now)
        #expect(playing.tick(at: now.addingTimeInterval(0.35)).effects == [.pause])

        var paused = TopBarWidgetClicks()
        _ = paused.click(TopBarWidgetClicks.transportTarget(isPlaying: false), at: now)
        #expect(paused.tick(at: now.addingTimeInterval(0.35)).effects == [.play])
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
            (.pause, .music),
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
            #expect(second.effects.isEmpty)
            let opened = clicks.tick(at: now.addingTimeInterval(0.1 + TopBarWidgetClicks.doubleClickWindow))
            #expect(opened.effects == [.openDetails(details)])
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

    /// A click count of 2 waits out the same armed delay, then opens more information and does not play.
    @Test @MainActor func theSessionSleepsTheArmedDelayThenOpensMoreInformation() async {
        let session = TopBarWidgetClickSession()
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = start
        session.now = { clock }
        let gate = ClickSleepGate()
        session.sleep = { duration in
            await gate.sleep(duration)
            clock = start.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        }
        let opened = ClickBeacon()
        var effects: [TopBarWidgetEffect] = []
        session.tap(.agenda, count: 2) { effect in
            effects.append(effect)
            opened.hit()
        }
        await gate.armed.wait(for: 1)
        #expect(effects.isEmpty)
        gate.release()
        await opened.wait(for: 1)
        #expect(effects == [.openDetails(.calendar)])
    }

    /// Pause while playing, play while paused, both after the same 0.35 s window. A counted double click
    /// opens the music page and does not also send play or pause.
    @Test @MainActor func aPauseClickSettlesAtTheWindowAndADoubleClickDoesNotSendTransport() async {
        let playing = TopBarWidgetClickSession()
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = start
        playing.now = { clock }
        let pauseGate = ClickSleepGate()
        playing.sleep = { duration in
            await pauseGate.sleep(duration)
            clock = start.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        }
        let paused = ClickBeacon()
        var pauseEffects: [TopBarWidgetEffect] = []
        playing.tap(TopBarWidgetClicks.transportTarget(isPlaying: true)) { effect in
            pauseEffects.append(effect)
            paused.hit()
        }
        await pauseGate.armed.wait(for: 1)
        #expect(pauseEffects.isEmpty)
        #expect(abs(seconds(of: pauseGate.durations[0]) - 0.35) < 0.000_001)
        pauseGate.release()
        await paused.wait(for: 1)
        #expect(pauseEffects == [.pause])
        #expect(pauseEffects.contains(.openDetails(.music)) == false)

        clock = start
        let resting = TopBarWidgetClickSession()
        resting.now = { clock }
        let playGate = ClickSleepGate()
        resting.sleep = { duration in
            await playGate.sleep(duration)
            clock = start.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        }
        let played = ClickBeacon()
        var playEffects: [TopBarWidgetEffect] = []
        resting.tap(TopBarWidgetClicks.transportTarget(isPlaying: false)) { effect in
            playEffects.append(effect)
            played.hit()
        }
        await playGate.armed.wait(for: 1)
        playGate.release()
        await played.wait(for: 1)
        #expect(playEffects == [.play])
        #expect(playEffects.contains(.openDetails(.music)) == false)

        clock = start
        let doubled = TopBarWidgetClickSession()
        doubled.now = { clock }
        let detailsGate = ClickSleepGate()
        doubled.sleep = { duration in
            await detailsGate.sleep(duration)
            clock = start.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow)
        }
        let opened = ClickBeacon()
        var detailEffects: [TopBarWidgetEffect] = []
        doubled.tap(.pause, count: 2) { effect in
            detailEffects.append(effect)
            opened.hit()
        }
        await detailsGate.armed.wait(for: 1)
        #expect(detailEffects.isEmpty)
        detailsGate.release()
        await opened.wait(for: 1)
        #expect(detailEffects == [.openDetails(.music)])
        #expect(detailEffects.contains(.pause) == false)
        #expect(detailEffects.contains(.play) == false)
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
