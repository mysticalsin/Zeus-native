import Foundation
import Testing
@testable import ZeusCore

@Suite("Speaker discovery")
struct SpeakerDiscoveryTests {
    private static let room = SpeakerSighting(service: .airplay, rawName: "Living Room", model: "AudioAccessory1,1")
    private static let kitchen = SpeakerSighting(service: .airplay, rawName: "Kitchen", model: nil)
    private static let computer = SpeakerSighting(service: .raop, rawName: "aabbccddeeff@Office", model: "MacBookPro18,3")

    @Test func settingChangedOnNeverStartsABrowse() {
        let (state, effects) = SpeakerDiscovery.reduce(.off, .settingChanged(true))
        #expect(state.phase == .collapsed)
        #expect(state.speakers.isEmpty)
        #expect(effects.isEmpty)
        let (again, againEffects) = SpeakerDiscovery.reduce(state, .settingChanged(true))
        #expect(again == state)
        #expect(againEffects.isEmpty)
        let opened = self.opened()
        let (during, duringEffects) = SpeakerDiscovery.reduce(opened, .settingChanged(true))
        #expect(during == opened)
        #expect(duringEffects.isEmpty)
    }

    @Test func noEventInOffStartsABrowse() {
        let events: [SpeakerDiscovery.Event] = [
            .settingChanged(false),
            .partToggled,
            .listClosed,
            .results(token: 0, sightings: [Self.room]),
            .results(token: 1, sightings: [Self.room]),
            .noAccess(token: 0),
            .failed(token: 0),
        ]
        for event in events {
            let (state, effects) = SpeakerDiscovery.reduce(.off, event)
            #expect(state == .off)
            #expect(effects.isEmpty)
        }
    }

    @Test func openThenCloseStops() {
        let open = opened()
        #expect(open.token == 1)
        let (closed, effects) = SpeakerDiscovery.reduce(open, .partToggled)
        #expect(closed.phase == .collapsed)
        #expect(closed.speakers.isEmpty)
        #expect(effects == [.stopBrowse])
        let (late, lateEffects) = SpeakerDiscovery.reduce(closed, .results(token: open.token, sightings: [Self.room]))
        #expect(late == closed)
        #expect(lateEffects.isEmpty)
    }

    @Test func resultsFromAnOlderBrowseAreDropped() {
        let open = opened()
        let (closed, _) = SpeakerDiscovery.reduce(open, .partToggled)
        let (after, effects) = SpeakerDiscovery.reduce(closed, .results(token: open.token, sightings: [Self.room]))
        #expect(after == closed)
        #expect(effects.isEmpty)
        let (staleAccess, accessEffects) = SpeakerDiscovery.reduce(open, .noAccess(token: open.token &+ 9))
        #expect(staleAccess == open)
        #expect(accessEffects.isEmpty)
    }

    @Test func noAccessIsItsOwnState() {
        let open = opened()
        let (waiting, effects) = SpeakerDiscovery.reduce(open, .noAccess(token: open.token))
        #expect(waiting.phase == .waitingForAccess)
        #expect(waiting.token == open.token)
        #expect(effects.isEmpty)
        let (again, againEffects) = SpeakerDiscovery.reduce(waiting, .noAccess(token: waiting.token))
        #expect(again.phase == .waitingForAccess)
        #expect(againEffects.isEmpty)
    }

    @Test func noAccessThenResultsFindsSpeakersWithoutANewBrowse() {
        let waiting = waitingForAccess()
        let (found, effects) = SpeakerDiscovery.reduce(waiting, .results(token: waiting.token, sightings: [Self.room, Self.computer]))
        #expect(found.phase == .found)
        #expect(found.speakers == [NetworkSpeaker(name: "Living Room", kind: .homeSpeaker)])
        #expect(effects == [.record(.allowed)])
        #expect(effects.contains(.startBrowse(token: waiting.token)) == false)
    }

    @Test func resultsThenNoAccessWaits() {
        let open = opened()
        let (found, allowed) = SpeakerDiscovery.reduce(open, .results(token: open.token, sightings: [Self.kitchen]))
        #expect(found.phase == .found)
        #expect(allowed == [.record(.allowed)])
        let (waiting, effects) = SpeakerDiscovery.reduce(found, .noAccess(token: found.token))
        #expect(waiting.phase == .waitingForAccess)
        #expect(waiting.token == found.token)
        #expect(waiting.speakers.map(\.name) == ["Kitchen"])
        #expect(effects.isEmpty)
        let (searching, empty) = SpeakerDiscovery.reduce(waiting, .results(token: waiting.token, sightings: []))
        #expect(searching.phase == .searching)
        #expect(searching.speakers.isEmpty)
        #expect(empty.isEmpty)
    }

    @Test func closingFromWaitingRecordsDenialOnce() {
        let byPart = SpeakerDiscovery.reduce(waitingForAccess(), .partToggled)
        #expect(byPart.0.phase == .collapsed)
        #expect(byPart.0.speakers.isEmpty)
        #expect(byPart.1 == [.stopBrowse, .record(.noAccess)])

        let byList = SpeakerDiscovery.reduce(waitingForAccess(), .listClosed)
        #expect(byList.0.phase == .collapsed)
        #expect(byList.1 == [.stopBrowse, .record(.noAccess)])

        let bySetting = SpeakerDiscovery.reduce(waitingForAccess(), .settingChanged(false))
        #expect(bySetting.0.phase == .off)
        #expect(bySetting.0.speakers.isEmpty)
        #expect(bySetting.1 == [.stopBrowse, .record(.noAccess)])

        let (closed, first) = byPart
        let (_, second) = SpeakerDiscovery.reduce(closed, .listClosed)
        #expect(denials(first) + denials(second) == 1)
    }

    @Test func allowedIsRecordedOnlyAfterANonEmptyResult() {
        let open = opened()
        let (searching, emptyEffects) = SpeakerDiscovery.reduce(open, .results(token: open.token, sightings: []))
        #expect(searching.phase == .searching)
        #expect(emptyEffects.isEmpty)
        let (still, computers) = SpeakerDiscovery.reduce(searching, .results(token: searching.token, sightings: [Self.computer]))
        #expect(still.phase == .searching)
        #expect(computers.isEmpty)
        let (found, once) = SpeakerDiscovery.reduce(still, .results(token: still.token, sightings: [Self.room]))
        #expect(found.phase == .found)
        #expect(once == [.record(.allowed)])
        let (again, twice) = SpeakerDiscovery.reduce(found, .results(token: found.token, sightings: [Self.room, Self.kitchen]))
        #expect(again.phase == .found)
        #expect(again.speakers.map(\.name) == ["Living Room", "Kitchen"])
        #expect(twice.isEmpty)

        var named = open
        named.ownName = "Kitchen"
        let (withoutOwn, _) = SpeakerDiscovery.reduce(named, .results(token: named.token, sightings: [Self.kitchen, Self.room]))
        #expect(withoutOwn.speakers.map(\.name) == ["Living Room"])
    }

    @Test func reopeningAfterNoAccessBrowsesAgain() {
        let waiting = waitingForAccess()
        let (collapsed, stopped) = SpeakerDiscovery.reduce(waiting, .partToggled)
        #expect(stopped == [.stopBrowse, .record(.noAccess)])
        let (again, effects) = SpeakerDiscovery.reduce(collapsed, .partToggled)
        #expect(again.phase == .searching)
        #expect(again.token != waiting.token)
        #expect(effects == [.startBrowse(token: again.token)])
    }

    @Test func listClosedAndSettingOffStopAndForget() {
        let found = foundKitchen()
        let (closed, closedEffects) = SpeakerDiscovery.reduce(found, .listClosed)
        #expect(closed.phase == .collapsed)
        #expect(closed.speakers.isEmpty)
        #expect(closedEffects == [.stopBrowse])
        let (late, lateEffects) = SpeakerDiscovery.reduce(closed, .results(token: found.token, sightings: [Self.kitchen]))
        #expect(late == closed)
        #expect(lateEffects.isEmpty)

        let (off, offEffects) = SpeakerDiscovery.reduce(foundKitchen(), .settingChanged(false))
        #expect(off.phase == .off)
        #expect(off.speakers.isEmpty)
        #expect(off.recordedAllowed == false)
        #expect(offEffects == [.stopBrowse])
    }

    @Test func aFailureStopsAndALateResultIsDropped() {
        let open = opened()
        let (down, effects) = SpeakerDiscovery.reduce(open, .failed(token: open.token))
        #expect(down.phase == .unavailable)
        #expect(effects == [.stopBrowse])
        let (late, lateEffects) = SpeakerDiscovery.reduce(down, .results(token: open.token, sightings: [Self.room]))
        #expect(late == down)
        #expect(lateEffects.isEmpty)

        let waiting = waitingForAccess()
        let (failedWait, failedEffects) = SpeakerDiscovery.reduce(waiting, .failed(token: waiting.token))
        #expect(failedWait.phase == .unavailable)
        #expect(failedEffects == [.stopBrowse])

        let (reopened, browse) = SpeakerDiscovery.reduce(down, .partToggled)
        #expect(reopened.phase == .searching)
        #expect(browse == [.startBrowse(token: reopened.token)])

        let found = foundKitchen()
        let (kept, keptEffects) = SpeakerDiscovery.reduce(found, .failed(token: found.token))
        #expect(kept.phase == .unavailable)
        #expect(kept.speakers.map(\.name) == ["Kitchen"])
        #expect(keptEffects == [.stopBrowse])
    }

    @Test func wordsAreFreeOfDashes() {
        let symbols = [SpeakerKind.homeSpeaker.symbol, SpeakerKind.television.symbol, SpeakerKind.speaker.symbol]
        for word in SpeakerDiscovery.Words.all + symbols {
            #expect(!word.contains("\u{2014}"))
            #expect(!word.contains("\u{2013}"))
            #expect(!word.contains("-"))
        }
    }

    @Test @MainActor func aMainActorFakeConforms() {
        let fake = FakeSpeakerDiscovery()
        #expect(fake.state.phase == .off)
        fake.togglePart()
        #expect(fake.toggles == 1)
    }

    private func on() -> SpeakerDiscovery.State {
        let (state, effects) = SpeakerDiscovery.reduce(.off, .settingChanged(true))
        #expect(state.phase == .collapsed)
        #expect(effects.isEmpty)
        return state
    }

    private func opened() -> SpeakerDiscovery.State {
        let (state, effects) = SpeakerDiscovery.reduce(on(), .partToggled)
        #expect(state.phase == .searching)
        #expect(effects == [.startBrowse(token: state.token)])
        return state
    }

    private func waitingForAccess() -> SpeakerDiscovery.State {
        let open = opened()
        let (state, effects) = SpeakerDiscovery.reduce(open, .noAccess(token: open.token))
        #expect(state.phase == .waitingForAccess)
        #expect(effects.isEmpty)
        return state
    }

    private func foundKitchen() -> SpeakerDiscovery.State {
        let open = opened()
        let (state, effects) = SpeakerDiscovery.reduce(open, .results(token: open.token, sightings: [Self.kitchen]))
        #expect(state.phase == .found)
        #expect(effects == [.record(.allowed)])
        return state
    }

    private func denials(_ effects: [SpeakerDiscovery.Effect]) -> Int {
        effects.filter {
            if case .record(.noAccess) = $0 { return true }
            return false
        }.count
    }
}

@MainActor
private final class FakeSpeakerDiscovery: SpeakerDiscoveryControlling {
    var state = SpeakerDiscovery.State.off
    private(set) var toggles = 0

    func togglePart() { toggles += 1 }
}
