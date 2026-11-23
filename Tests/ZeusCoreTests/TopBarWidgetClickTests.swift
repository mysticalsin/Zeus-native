import Foundation
import Testing
@testable import ZeusCore

/// Top-bar summary clicks. The clock is passed in. No player, no network, no capture.
@Suite struct TopBarWidgetClickTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func aPlayClickIssuesPlayAndNotDetails() {
        var clicks = TopBarWidgetClicks()
        let down = clicks.click(.play, at: now)
        #expect(down.effects.isEmpty)
        #expect(down.arm == now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        let early = clicks.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow - 0.001))
        #expect(early.effects.isEmpty)
        let settled = clicks.tick(at: now.addingTimeInterval(TopBarWidgetClicks.doubleClickWindow))
        #expect(settled.effects == [.play])
        #expect(settled.effects.contains(.openDetails(.music)) == false)
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
        let clicks = TopBarWidgetClicks()
        #expect(clicks.showDetails(.weather) == .openDetails(.weather))
        #expect(clicks.showDetails(.agenda) == .openDetails(.calendar))
        #expect(clicks.showDetails(.nowPlaying) == .openDetails(.music))
    }

    @Test func reducedMotionSnapsTheDetailsTransition() {
        #expect(TopBarWidgetClicks.detailsDuration(reduceMotion: true) == 0)
        #expect(TopBarWidgetClicks.detailsDuration(reduceMotion: false) == MotionTokens.crossfadeDuration)
        #expect(MotionTokens.crossfadeDuration > 0)
    }
}
