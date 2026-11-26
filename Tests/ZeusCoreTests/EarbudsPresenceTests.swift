import Testing
@testable import ZeusCore

@Suite("Earbuds presence") struct EarbudsPresenceTests {
    private func audio(
        _ id: String, name: String = "Buds", paired: Bool = true,
        major: UInt8 = DeviceFacts.audioMajor, minor: UInt8 = DeviceFacts.headset
    ) -> DeviceFacts {
        DeviceFacts(id: EarbudsID(id), name: name, paired: paired, major: major, minor: minor)
    }

    private func step(_ state: EarbudsPresence.State, _ event: EarbudsPresence.Event) -> (EarbudsPresence.State, [EarbudsPresence.Effect]) {
        EarbudsPresence.reduce(state, event)
    }

    private func armed() -> EarbudsPresence.State {
        step(.off, .switched(on: true, access: .allowed)).0
    }

    private func seeded(_ facts: [DeviceFacts], now: Double = 0) -> (EarbudsPresence.State, [EarbudsPresence.Effect]) {
        let state = armed()
        return step(state, .started(seed: facts, now: now))
    }

    private func cues(_ effects: [EarbudsPresence.Effect]) -> [EarbudsCue] {
        effects.compactMap { if case .showCue(let cue) = $0 { return cue }; return nil }
    }

    private func reads(_ effects: [EarbudsPresence.Effect]) -> [Int] {
        effects.compactMap { if case .readBattery(_, let token) = $0 { return token }; return nil }
    }

    private func schedules(_ effects: [EarbudsPresence.Effect]) -> [(Int, Double)] {
        effects.compactMap { if case .scheduleRead(_, let token, let after) = $0 { return (token, after) }; return nil }
    }

    @Test func offFromEveryRouteStopsAndDropsDevices() {
        let watching = seeded([audio("a")]).0
        let asking = step(.off, .allowPressed(.notAsked)).0
        let routes: [EarbudsPresence.State] = [
            .off, watching, asking,
            EarbudsPresence.State(route: .needsAccess(.denied), nextToken: 3),
            EarbudsPresence.State(route: .away, nextToken: 4),
            EarbudsPresence.State(route: .eventsClosed, nextToken: 5),
        ]
        for state in routes {
            let (next, effects) = step(state, .switched(on: false, access: .allowed))
            #expect(next.route == .off)
            #expect(effects == [.stopWatching, .abandonRequest])
            #expect(EarbudsPresence.status(next, now: 0).shown == nil)
        }
    }

    @Test func aStoredOnWithoutAGrantNeverAsks() {
        let (state, effects) = step(.off, .switched(on: true, access: .notAsked))
        #expect(state.route == .needsAccess(.notAsked))
        #expect(effects.isEmpty)
        let denied = step(.off, .switched(on: true, access: .denied))
        #expect(denied.0.route == .needsAccess(.denied))
        #expect(denied.1.isEmpty)
    }

    @Test func allowAsksOnce() {
        let (asking, effects) = step(.off, .allowPressed(.notAsked))
        guard case .asking(let token) = asking.route else {
            Issue.record("expected asking")
            return
        }
        #expect(effects == [.requestAccess(token), .askTimeout(token: token, after: 60)])
        let again = step(asking, .allowPressed(.notAsked))
        #expect(again.0 == asking)
        #expect(again.1.isEmpty)
        let fromDenied = step(EarbudsPresence.State(route: .needsAccess(.denied)), .allowPressed(.notAsked))
        #expect(fromDenied.1.isEmpty)
    }

    @Test func theAnswerThenTheStoreEchoStartsOnce() {
        let (asking, _) = step(.off, .allowPressed(.notAsked))
        guard case .asking(let token) = asking.route else {
            Issue.record("expected asking")
            return
        }
        let (off, stored) = step(asking, .accessAnswered(token: token, access: .allowed))
        #expect(off.route == .off)
        #expect(stored == [.storeSwitch(true)])
        let (watching, started) = step(off, .switched(on: true, access: .allowed))
        #expect(started == [.startWatching])
        if case .watching = watching.route {} else { Issue.record("expected watching") }
        let echo = step(watching, .switched(on: true, access: .allowed))
        #expect(echo.0 == watching)
        #expect(echo.1.isEmpty)
        let allowedPress = step(EarbudsPresence.State(route: .needsAccess(.notAsked)), .allowPressed(.allowed))
        #expect(allowedPress.1 == [.storeSwitch(true)])
    }

    @Test func aTimeoutLetsTheButtonAskAgainAndDropsALateAnswer() {
        let (asking, _) = step(.off, .allowPressed(.notAsked))
        guard case .asking(let token) = asking.route else {
            Issue.record("expected asking")
            return
        }
        let (waiting, effects) = step(asking, .askTimedOut(token))
        #expect(waiting.route == .needsAccess(.notAsked))
        #expect(effects == [.abandonRequest])
        let late = step(waiting, .accessAnswered(token: token, access: .allowed))
        #expect(late.0 == waiting)
        #expect(late.1.isEmpty)
        let staleTimeout = step(waiting, .askTimedOut(token))
        #expect(staleTimeout.1.isEmpty)
        let (again, asked) = step(waiting, .allowPressed(.notAsked))
        #expect(asked.contains { if case .requestAccess = $0 { return true }; return false })
        guard case .asking = again.route else {
            Issue.record("expected a new ask")
            return
        }
    }

    @Test func aDeniedAnswerStaysNeedsAccess() {
        let (asking, _) = step(.off, .allowPressed(.notAsked))
        guard case .asking(let token) = asking.route else {
            Issue.record("expected asking")
            return
        }
        let (state, effects) = step(asking, .accessAnswered(token: token, access: .denied))
        #expect(state.route == .needsAccess(.denied))
        #expect(effects.isEmpty)
        let (back, started) = step(state, .accessRead(.allowed))
        #expect(started == [.startWatching])
        if case .watching = back.route {} else { Issue.record("expected watching") }
    }

    @Test func seedThenDisconnectCuesOnce() {
        let (state, seeded) = seeded([audio("a", name: "Secret")])
        #expect(cues(seeded).isEmpty)
        #expect(seeded.contains { if case .watchDisconnect = $0 { return true }; return false })
        #expect(reads(seeded).count == 1)
        let (next, effects) = step(state, .disconnected(id: EarbudsID("a"), now: 3))
        #expect(cues(effects).count == 1)
        #expect(cues(effects).first?.event == .disconnected)
        #expect(effects.contains(.unwatch(EarbudsID("a"))))
        #expect(EarbudsPresence.status(next, now: 3).shown == nil)
    }

    @Test func aQuietConnectThenALaterDisconnectCuesOnce() {
        let (state, _) = seeded([])
        let (connected, during) = step(state, .connected(audio("a"), now: 0.5))
        #expect(cues(during).isEmpty)
        #expect(schedules(during).map(\.1) == [1, 2.5])
        let (_, after) = step(connected, .disconnected(id: EarbudsID("a"), now: 3))
        #expect(cues(after).map(\.event) == [.disconnected])
        #expect(after.contains(.unwatch(EarbudsID("a"))))
    }

    @Test func resyncThenDisconnectCuesOnce() {
        let (state, _) = seeded([audio("a")])
        let (synced, quiet) = step(state, .resynced(seed: [audio("a")], now: 1))
        #expect(quiet.isEmpty)
        let (_, effects) = step(synced, .disconnected(id: EarbudsID("a"), now: 3))
        #expect(cues(effects).map(\.event) == [.disconnected])
        #expect(effects.contains(.unwatch(EarbudsID("a"))))
    }

    @Test func aRepeatConnectGivesNoCue() {
        let (state, _) = seeded([])
        let (once, first) = step(state, .connected(audio("a", name: "Buds"), now: 10))
        #expect(cues(first).map(\.event) == [.connected])
        let (twice, second) = step(once, .connected(audio("a", name: "Buds Two"), now: 11))
        #expect(second.isEmpty)
        #expect(EarbudsPresence.status(twice, now: 11).shown?.name == "Buds Two")
    }

    @Test func unpairedAndNonAudioChangeNothing() {
        let (state, _) = seeded([])
        let ignored = [
            audio("u", paired: false),
            audio("m", major: 0x05),
            audio("n", minor: 0x04),
        ]
        for facts in ignored {
            let (next, effects) = step(state, .connected(facts, now: 10))
            #expect(next == state)
            #expect(effects.isEmpty)
        }
        #expect(audio("h", minor: DeviceFacts.handsFree).qualifies)
        #expect(audio("p", minor: DeviceFacts.headphones).qualifies)
        #expect(!audio("x", minor: 0x03).qualifies)
    }

    @Test func aNinthDeviceReplacesTheOldestDisconnectedOne() {
        let ids = (1 ... 8).map { "d\($0)" }
        let (state, _) = seeded(ids.map { audio($0) })
        let (full, ignored) = step(state, .connected(audio("ninth"), now: 10))
        #expect(ignored.isEmpty)
        #expect(full == state)
        let (gap, left) = step(full, .disconnected(id: EarbudsID("d1"), now: 10))
        #expect(left.contains(.unwatch(EarbudsID("d1"))))
        let (replaced, effects) = step(gap, .connected(audio("ninth"), now: 12))
        #expect(effects.contains(.unwatch(EarbudsID("d1"))))
        #expect(effects.contains(.watchDisconnect(EarbudsID("ninth"))))
        #expect(EarbudsPresence.status(replaced, now: 12).shown?.id == EarbudsID("ninth"))
        let (still, extra) = step(replaced, .connected(audio("extra"), now: 30))
        #expect(extra.isEmpty)
        #expect(still == replaced)
    }

    @Test func theCueLimitDropsTheSecondConnectAndTheLevelsCueShowsOnce() {
        let (state, _) = seeded([])
        let (connected, first) = step(state, .connected(audio("a", name: "Secret"), now: 10))
        #expect(cues(first).first?.levels.isEmpty == true)
        let pair = schedules(first)
        #expect(pair.map(\.1) == [1, 2.5])
        let (due, oneRead) = step(connected, .readDue(id: EarbudsID("a"), token: pair[0].0))
        let burst = step(due, .readDue(id: EarbudsID("a"), token: pair[1].0))
        #expect(reads(oneRead) == [pair[0].0])
        #expect(reads(burst.1).isEmpty)
        let (read, levels) = step(due, .batteryRead(
            id: EarbudsID("a"), token: pair[0].0, raw: [.left: 80], answering: [.left], now: 11
        ))
        #expect(cues(levels).map(\.event) == [.connected])
        #expect(cues(levels).first?.levels[.left] == .fresh(80))
        let (secondDue, secondRead) = step(read, .readDue(id: EarbudsID("a"), token: pair[1].0))
        #expect(reads(secondRead) == [pair[1].0])
        let (_, secondLevels) = step(secondDue, .batteryRead(
            id: EarbudsID("a"), token: pair[1].0, raw: [.left: 90], answering: [.left], now: 12
        ))
        #expect(cues(secondLevels).isEmpty)
        let (down, offCue) = step(read, .disconnected(id: EarbudsID("a"), now: 20))
        #expect(cues(offCue).map(\.event) == [.disconnected])
        let (_, onCue) = step(down, .connected(audio("a", name: "Secret"), now: 25))
        #expect(cues(onCue).isEmpty)
    }

    @Test func aClosedRouteCuesWithoutLevels() {
        let (state, _) = seeded([])
        let (closed, _) = step(state, .batteryRouteChecked(open: false))
        #expect(EarbudsPresence.status(closed, now: 10).batteryClosed)
        let (connected, effects) = step(closed, .connected(audio("a"), now: 10))
        #expect(cues(effects).first?.levels.isEmpty == true)
        let pair = schedules(effects)
        let (_, due) = step(connected, .readDue(id: EarbudsID("a"), token: pair[0].0))
        #expect(reads(due).isEmpty)
        #expect(EarbudsPresence.status(connected, now: 10).batteryClosed)
    }

    @Test func aStaleReadAfterDisconnectIsDropped() {
        let (state, seededEffects) = seeded([audio("a")])
        let token = reads(seededEffects)[0]
        let (read, _) = step(state, .batteryRead(
            id: EarbudsID("a"), token: token, raw: [.left: 80], answering: [.left], now: 0
        ))
        let (down, _) = step(read, .disconnected(id: EarbudsID("a"), now: 1))
        let (stale, effects) = step(down, .batteryRead(
            id: EarbudsID("a"), token: token, raw: [.left: 40], answering: [.left], now: 1
        ))
        #expect(effects.isEmpty)
        #expect(stale == down)
        let (back, _) = step(stale, .connected(audio("a"), now: 3))
        #expect(EarbudsPresence.status(back, now: 3).shown?.levels[.left] == .lastKnown(80))
    }

    @Test func anUnknownDisconnectIsSilent() {
        let (state, _) = seeded([audio("a")])
        let (next, effects) = step(state, .disconnected(id: EarbudsID("missing"), now: 3))
        #expect(next == state)
        #expect(effects.isEmpty)
    }

    @Test func sleepKillsTheInFlightRead() {
        let (state, seededEffects) = seeded([audio("a")])
        let token = reads(seededEffects)[0]
        let (asleep, _) = step(state, .willSleep)
        let (killed, dropped) = step(asleep, .batteryRead(
            id: EarbudsID("a"), token: token, raw: [.left: 90], answering: [.left], now: 1
        ))
        #expect(dropped.isEmpty)
        let (opened, panel) = step(killed, .panelOpened)
        let fresh = reads(panel)
        #expect(fresh.count == 1)
        #expect(fresh[0] != token)
        let (read, _) = step(opened, .batteryRead(
            id: EarbudsID("a"), token: fresh[0], raw: [.left: 70], answering: [.left], now: 2
        ))
        let shown = EarbudsPresence.status(read, now: 2).shown
        #expect(shown?.levels[.left] == .fresh(70))
        #expect(shown?.levels[.left] != .fresh(90))
        #expect(shown?.levels[.left] != .lastKnown(90))
    }

    @Test func wakeHoldsTheQuietWindow() {
        let (state, _) = seeded([])
        let (awake, woke) = step(state, .woke(0))
        #expect(woke == [.resync])
        let (early, noCue) = step(awake, .connected(audio("a"), now: 0.5))
        #expect(cues(noCue).isEmpty)
        let (synced, resync) = step(early, .resynced(seed: [audio("a")], now: 1))
        #expect(cues(resync).isEmpty)
        let (_, later) = step(synced, .connected(audio("b"), now: 3))
        #expect(cues(later).map(\.event) == [.connected])
    }

    @Test func lockedCuesStayHiddenAfterUnlock() {
        let (state, _) = seeded([])
        let (locked, _) = step(state, .session(active: true, locked: true))
        let (on, connected) = step(locked, .connected(audio("a", name: "Secret"), now: 10))
        let (off, disconnected) = step(on, .disconnected(id: EarbudsID("a"), now: 11))
        #expect(cues(connected).isEmpty)
        #expect(cues(disconnected).isEmpty)
        let (open, effects) = step(off, .session(active: true, locked: false))
        #expect(cues(effects).isEmpty)
        #expect(EarbudsPresence.status(open, now: 12).shown == nil)
    }

    @Test func sessionAwayDropsEveryDeviceAndTheReturnSeedsQuietly() {
        let (state, _) = seeded([audio("a", name: "Secret")])
        let (away, stopped) = step(state, .session(active: false, locked: false))
        #expect(away.route == .away)
        #expect(stopped == [.stopWatching])
        #expect(EarbudsPresence.status(away, now: 1).shown == nil)
        let (back, started) = step(away, .session(active: true, locked: false))
        #expect(started == [.startWatching])
        let (_, seed) = step(back, .started(seed: [audio("a", name: "Secret")], now: 4))
        #expect(cues(seed).isEmpty)
        #expect(reads(seed).count == 1)
    }

    @Test func aDeniedReadWhileWatchingStopsIt() {
        let (state, _) = seeded([audio("a")])
        let (next, effects) = step(state, .accessRead(.denied))
        #expect(next.route == .needsAccess(.denied))
        #expect(effects == [.stopWatching])
        #expect(EarbudsPresence.status(next, now: 0).shown == nil)
        let failed = step(armed(), .registrationFailed)
        #expect(failed.0.route == .eventsClosed)
        #expect(failed.1 == [.stopWatching])
    }

    @Test func cueTextHidesTheNameAndTheAddress() {
        let cue = EarbudsCue(id: EarbudsID("aa:bb"), name: "Secret", event: .connected, levels: [:])
        #expect(String(describing: cue) == "earbuds")
        #expect(String(reflecting: cue) == "earbuds")
        #expect(Mirror(reflecting: cue).children.isEmpty)
        #expect(String(describing: cue.id) == "earbuds")
        let other = EarbudsCue(id: EarbudsID("cc"), name: "Secret", event: .connected, levels: [:])
        #expect(cue != other)
        let sample = String(describing: EarbudsStatus.snapshotSample)
        #expect(!sample.contains("\u{2014}"))
        #expect(!sample.contains("\u{2013}"))
    }
}
