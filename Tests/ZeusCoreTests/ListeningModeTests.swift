import Testing
@testable import ZeusCore

@Suite("Listening mode") struct ListeningModeTests {
    private func step(
        _ state: ListeningModeMachine.State, _ event: ListeningModeMachine.Event
    ) -> (ListeningModeMachine.State, [ListeningModeMachine.Effect]) {
        ListeningModeMachine.reduce(state, event)
    }

    private func sample(
        mode: UInt32? = 2,
        mask: UInt32? = 3,
        transport: UInt32? = ListeningModeLink.fourCC("blue"),
        hasProperty: Bool = true,
        byteSize: Int = 4,
        key: ModeKey = ModeKey(objectID: 7, generation: 1),
        name: String = "Buds"
    ) -> ModeProbe {
        ModeProbe(
            key: key, uid: "uid-1", name: name, transportCode: transport,
            hasProperty: hasProperty, byteSize: byteSize, rawMode: mode, rawMask: mask
        )
    }

    private func modes(_ choices: [ModeChoice]?) -> [ListeningMode]? {
        choices?.map(\.mode)
    }

    private func probeToken(_ effects: [ListeningModeMachine.Effect]) -> Int? {
        for effect in effects {
            if case .probe(let token) = effect { return token }
        }
        return nil
    }

    private func opened(_ state: ListeningModeMachine.State = .off) -> (ListeningModeMachine.State, Int) {
        let dormant = step(state, .switched(on: true)).0
        let (waiting, effects) = step(dormant, .panelOpened)
        return (waiting, probeToken(effects)!)
    }

    private func readyNoiseCancelling() -> ListeningModeMachine.State {
        let (waiting, token) = opened()
        return step(waiting, .probed(token: token, probe: sample())).0
    }

    private func setting(
        from state: ListeningModeMachine.State, _ mode: ListeningMode
    ) -> (ListeningModeMachine.State, ListeningModeMachine.Effect) {
        let (next, effects) = step(state, .chosen(mode))
        return (next, effects[0])
    }

    @Test func valueMapBothWays() {
        let pairs: [(UInt32, ListeningMode)] = [
            (1, .off), (2, .noiseCancelling), (3, .transparency), (4, .adaptive),
        ]
        for (raw, mode) in pairs {
            #expect(ListeningModeCode.mode(raw) == mode)
            #expect(ListeningModeCode.code(mode) == raw)
        }
        #expect(ListeningModeCode.mode(0) == nil)
        #expect(ListeningModeCode.mode(5) == nil)
        #expect(ListeningModeCode.mode(UInt32.max) == nil)
    }

    @Test func maskChoices() {
        #expect(modes(ListeningModeMask.choices(raw: 0, current: .off)) == [.off])
        #expect(modes(ListeningModeMask.choices(raw: 1, current: .off)) == [.off, .noiseCancelling])
        #expect(modes(ListeningModeMask.choices(raw: 2, current: .off)) == [.off, .transparency])
        #expect(modes(ListeningModeMask.choices(raw: 3, current: .off)) == [.off, .noiseCancelling, .transparency])
        let seven = ListeningModeMask.choices(raw: 7, current: .off)
        #expect(modes(seven) == [.off, .noiseCancelling, .transparency])
        #expect(seven?.contains(where: { $0.mode == .adaptive }) == false)
        #expect(seven?.allSatisfy { $0.offer == .available } == true)
        #expect(ListeningModeMask.choices(raw: nil, current: .off) == nil)
        #expect(ListeningModeMask.choices(raw: 2, current: .noiseCancelling) == nil)
        #expect(ListeningModeMask.choices(raw: 0, current: .noiseCancelling) == nil)
        #expect(ListeningModeMask.choices(raw: 1, current: .transparency) == nil)
        #expect(ListeningModeMask.choices(raw: 3, current: .adaptive) == nil)
        #expect(modes(ListeningModeMask.choices(raw: 4, current: .adaptive)) == [.off])
        #expect(modes(ListeningModeMask.choices(raw: 5, current: .adaptive)) == [.off, .noiseCancelling])
    }

    @Test func releaseFloorAndUnboundProbes() {
        #expect(ListeningModeRelease.verifiedFrom.major == 27)
        #expect(ListeningModeRelease.verifiedFrom.minor == 2)
        #expect(ListeningModeRelease.allowed(major: 27, minor: 2))
        #expect(ListeningModeRelease.allowed(major: 27, minor: 3))
        #expect(ListeningModeRelease.allowed(major: 28, minor: 0))
        #expect(!ListeningModeRelease.allowed(major: 27, minor: 1))
        #expect(!ListeningModeRelease.allowed(major: 26, minor: 9))
        let floor = (major: 27, minor: 2)
        #expect(sample().bound(release: floor) != nil)
        #expect(sample(transport: ListeningModeLink.fourCC("blea")).bound(release: floor) != nil)
        #expect(sample(transport: ListeningModeLink.fourCC("usb ")).bound(release: floor) == nil)
        #expect(sample(transport: ListeningModeLink.fourCC("airp")).bound(release: floor) == nil)
        #expect(sample(transport: ListeningModeLink.fourCC("bltn")).bound(release: floor) == nil)
        #expect(sample(transport: nil).bound(release: floor) == nil)
        #expect(sample(transport: 0).bound(release: floor) == nil)
        #expect(sample(hasProperty: false).bound(release: floor) == nil)
        #expect(sample(byteSize: 8).bound(release: floor) == nil)
        #expect(sample(mode: 0).bound(release: floor) == nil)
        #expect(sample(mode: nil).bound(release: floor) == nil)
        #expect(sample(mode: 5).bound(release: floor) == nil)
        #expect(sample(mode: UInt32.max).bound(release: floor) == nil)
        #expect(sample(mask: nil).bound(release: floor) == nil)
        #expect(sample(mode: 1, mask: 0).bound(release: floor) == nil)
        #expect(sample(mode: 2, mask: 2).bound(release: floor) == nil)
        #expect(sample().bound(release: (major: 27, minor: 1)) == nil)
        #expect(sample().bound(release: (major: 26, minor: 0)) == nil)
        #expect(sample().bound(release: (major: 28, minor: 0)) != nil)
    }

    @Test func nothingIsProbedWhileThePanelIsClosed() {
        let (dormant, turnedOn) = step(.off, .switched(on: true))
        #expect(dormant.route == .dormant)
        #expect(turnedOn.isEmpty)
        let closed = step(dormant, .panelOpened)
        #expect(closed.0.route == .absent)
        #expect(probeToken(closed.1) != nil)
        let stillOff = step(.off, .panelOpened)
        #expect(stillOff.0.route == .off)
        #expect(stillOff.1.isEmpty)
        let dropped = step(dormant, .probed(token: 1, probe: sample()))
        #expect(dropped.0 == dormant)
        #expect(dropped.1.isEmpty)
        let ignored = step(dormant, .outputChanged)
        #expect(ignored.0 == dormant)
        #expect(ignored.1.isEmpty)
        var low = ListeningModeMachine.State(releaseMinor: 1)
        low = step(low, .switched(on: true)).0
        let (waiting, effects) = step(low, .panelOpened)
        let (hidden, follow) = step(waiting, .probed(token: probeToken(effects)!, probe: sample()))
        #expect(hidden.route == .absent)
        #expect(follow.isEmpty)
        #expect(ListeningModeMachine.status(hidden) == .hidden)
    }

    @Test func speakersThenABoundProbe() {
        let (waiting, token) = opened()
        let (absent, quiet) = step(waiting, .probed(token: token, probe: sample(transport: ListeningModeLink.fourCC("bltn"))))
        #expect(absent.route == .absent)
        #expect(absent.flight == nil)
        #expect(quiet.isEmpty)
        #expect(ListeningModeMachine.status(absent) == .hidden)
        let (again, effects) = step(absent, .outputChanged)
        #expect(effects.contains(.stopListening))
        #expect(!effects.contains(.unwatchOutput))
        let next = probeToken(effects)!
        #expect(next != token)
        let (ready, listened) = step(again, .probed(token: next, probe: sample()))
        guard case .ready(let bound) = ready.route else {
            Issue.record("expected ready")
            return
        }
        #expect(bound.current == .noiseCancelling)
        #expect(listened == [.listen(bound.key)])
        if case .shown(_, _, let current, _, let pending) = ListeningModeMachine.status(ready) {
            #expect(current == .noiseCancelling)
            #expect(pending == nil)
        } else {
            Issue.record("expected a shown row")
        }
    }

    @Test func absentKeepsTheWatchUntilThePanelCloses() {
        let (waiting, token) = opened()
        let (absent, _) = step(waiting, .probed(token: token, probe: sample(transport: ListeningModeLink.fourCC("airp"))))
        let (closed, effects) = step(absent, .panelClosed)
        #expect(closed.route == .dormant)
        #expect(effects == [.stopListening, .unwatchOutput])
        let later = step(closed, .outputChanged)
        #expect(later.0 == closed)
        #expect(later.1.isEmpty)
        let (reopened, watched) = step(closed, .panelOpened)
        #expect(watched.first == .watchOutput)
        #expect(probeToken(watched) != nil)
        #expect(reopened.route == .absent)
    }

    @Test func aStaleProbeIsDropped() {
        let (waiting, first) = opened()
        let (moved, effects) = step(waiting, .outputChanged)
        let second = probeToken(effects)!
        let stale = step(moved, .probed(token: first, probe: sample()))
        #expect(stale.0 == moved)
        #expect(stale.1.isEmpty)
        let (ready, listened) = step(moved, .probed(token: second, probe: sample()))
        #expect(listened.count == 1)
        if case .ready = ready.route {} else { Issue.record("expected ready") }
    }

    @Test func chosenOutsideReadyEmitsNoWrite() {
        let (waiting, token) = opened()
        let (absent, _) = step(waiting, .probed(token: token, probe: sample(hasProperty: false)))
        let states = [ListeningModeMachine.State.off, step(.off, .switched(on: true)).0, absent]
        for state in states {
            let (next, effects) = step(state, .chosen(.transparency))
            #expect(next == state)
            #expect(effects.isEmpty)
        }
    }

    @Test func chosenForTheCurrentOrRefusedModeEmitsNoWrite() {
        let ready = readyNoiseCancelling()
        let same = step(ready, .chosen(.noiseCancelling))
        #expect(same.0 == ready)
        #expect(same.1.isEmpty)
        let (failed, _) = setting(from: ready, .transparency)
        let (back, effects) = step(failed, .writeFinished(token: writeToken(failed), ok: false))
        guard case .ready(let bound) = back.route else {
            Issue.record("expected ready")
            return
        }
        #expect(bound.current == .noiseCancelling)
        #expect(bound.refused == .transparency)
        #expect(bound.choices.first { $0.mode == .transparency }?.offer == .refused)
        #expect(effects == [.announce(.stayed(.noiseCancelling))])
        let refused = step(back, .chosen(.transparency))
        #expect(refused.0 == back)
        #expect(refused.1.isEmpty)
        let (during, write) = setting(from: ready, .transparency)
        let pressed = step(during, .chosen(.off))
        #expect(pressed.0 == during)
        #expect(pressed.1.isEmpty)
        if case .write = write {} else { Issue.record("expected a write") }
    }

    @Test func aWriteIsReadBackBeforeReady() {
        let ready = readyNoiseCancelling()
        let (settingState, write) = setting(from: ready, .transparency)
        guard case .write(let key, let code, let token) = write else {
            Issue.record("expected a write")
            return
        }
        #expect(code == ListeningModeCode.code(.transparency))
        if case .setting(let setting) = settingState.route {
            #expect(setting.attempt == 1)
            #expect(setting.target == .transparency)
            #expect(setting.bound.current == .noiseCancelling)
        } else {
            Issue.record("expected setting")
        }
        if case .shown(_, _, let current, _, let pending) = ListeningModeMachine.status(settingState) {
            #expect(current == .noiseCancelling)
            #expect(pending == .transparency)
        } else {
            Issue.record("expected the old mode while the write is in flight")
        }
        let (waiting, scheduled) = step(settingState, .writeFinished(token: token, ok: true))
        #expect(scheduled == [.scheduleReadBack(key: key, token: token, after: ListeningModeMachine.readBackDelay)])
        #expect(ListeningModeMachine.readBackDelay == 0.5)
        if case .setting = waiting.route {} else { Issue.record("read back has not landed") }
        let (landed, announced) = step(waiting, .readBack(token: token, raw: 3))
        guard case .ready(let bound) = landed.route else {
            Issue.record("expected ready")
            return
        }
        #expect(bound.current == .transparency)
        #expect(bound.refused == nil)
        #expect(announced == [.announce(.changed(.transparency))])
        if case .shown(_, _, let current, _, let pending) = ListeningModeMachine.status(landed) {
            #expect(current == .transparency)
            #expect(pending == nil)
        }
        let echo = step(landed, .switched(on: true))
        #expect(echo.0 == landed)
        #expect(echo.1.isEmpty)
    }

    @Test func aReadBackThatDiffersTwiceShowsTheReadValue() {
        let ready = readyNoiseCancelling()
        let (settingState, write) = setting(from: ready, .transparency)
        guard case .write(_, _, let token) = write else {
            Issue.record("expected a write")
            return
        }
        let (once, first) = step(settingState, .writeFinished(token: token, ok: true))
        #expect(first.count == 1)
        let (retry, second) = step(once, .readBack(token: token, raw: 1))
        #expect(second == [.scheduleReadBack(key: sample().key, token: token, after: 1)])
        #expect(ListeningModeMachine.readBackRetry == 1)
        if case .setting(let setting) = retry.route {
            #expect(setting.attempt == 2)
            #expect(setting.bound.current == .noiseCancelling)
        } else {
            Issue.record("expected the second read")
        }
        let (landed, effects) = step(retry, .readBack(token: token, raw: 1))
        guard case .ready(let bound) = landed.route else {
            Issue.record("expected ready")
            return
        }
        #expect(bound.current == .off)
        #expect(bound.refused == .transparency)
        #expect(bound.choices.first { $0.mode == .transparency }?.offer == .refused)
        #expect(effects == [.announce(.stayed(.off))])
        #expect(!effects.contains { if case .write = $0 { return true }; return false })
        let again = step(landed, .chosen(.transparency))
        #expect(again.1.isEmpty)
    }

    @Test func anExternalChangeDuringSettingIsIgnored() {
        let ready = readyNoiseCancelling()
        let (settingState, write) = setting(from: ready, .transparency)
        guard case .write(let key, _, _) = write else {
            Issue.record("expected a write")
            return
        }
        let ignored = step(settingState, .externalChange(key: key, raw: 1))
        #expect(ignored.0 == settingState)
        #expect(ignored.1.isEmpty)
        let other = step(settingState, .externalChange(key: ModeKey(objectID: 9, generation: 1), raw: 3))
        #expect(other.0 == settingState)
    }

    @Test func anOutputChangeDuringSettingDropsTheLateReadBack() {
        let ready = readyNoiseCancelling()
        let (settingState, write) = setting(from: ready, .transparency)
        guard case .write(_, _, let token) = write else {
            Issue.record("expected a write")
            return
        }
        let (armed, _) = step(settingState, .writeFinished(token: token, ok: true))
        let (moved, effects) = step(armed, .outputChanged)
        #expect(moved.route == .absent)
        #expect(effects.contains(.stopListening))
        #expect(probeToken(effects) != nil)
        let late = step(moved, .readBack(token: token, raw: 3))
        #expect(late.0 == moved)
        #expect(late.1.isEmpty)
        if case .shown = ListeningModeMachine.status(moved) {
            Issue.record("a dropped read back must not show the target")
        }
    }

    @Test func adaptiveIsShownAndNeverAChoice() {
        let (waiting, token) = opened()
        let adaptive = sample(mode: 4, mask: 5)
        let (ready, _) = step(waiting, .probed(token: token, probe: adaptive))
        guard case .ready(let bound) = ready.route else {
            Issue.record("expected ready")
            return
        }
        #expect(bound.current == .adaptive)
        #expect(bound.choices.map(\.mode) == [.off, .noiseCancelling])
        #expect(!bound.choices.contains { $0.mode == .adaptive })
        if case .shown(_, _, let current, let choices, _) = ListeningModeMachine.status(ready) {
            #expect(current == .adaptive)
            #expect(!choices.contains { $0.mode == .adaptive })
        } else {
            Issue.record("expected adaptive on screen")
        }
        let blocked = step(ready, .chosen(.adaptive))
        #expect(blocked.0 == ready)
        #expect(blocked.1.isEmpty)
        let (follow, effects) = step(readyNoiseCancelling(), .externalChange(key: sample().key, raw: 4))
        #expect(effects.isEmpty)
        if case .ready(let followed) = follow.route {
            #expect(followed.current == .adaptive)
            #expect(!followed.choices.contains { $0.mode == .adaptive })
        } else {
            Issue.record("expected the external adaptive value")
        }
    }

    @Test func offFromEveryStateStops() {
        let (waiting, token) = opened()
        let (absent, _) = step(waiting, .probed(token: token, probe: sample(byteSize: 8)))
        let ready = readyNoiseCancelling()
        let (inFlight, _) = setting(from: ready, .off)
        let states: [ListeningModeMachine.State] = [
            .off, step(.off, .switched(on: true)).0, absent, ready, inFlight,
        ]
        for state in states {
            let (next, effects) = step(state, .switched(on: false))
            #expect(next.route == .off)
            #expect(next.flight == nil)
            #expect(effects == [.stopListening, .unwatchOutput])
            #expect(ListeningModeMachine.status(next) == .hidden)
        }
    }

    @Test func aCloseDuringSettingWaitsForTheReadBack() {
        let ready = readyNoiseCancelling()
        let (settingState, write) = setting(from: ready, .transparency)
        guard case .write(_, _, let token) = write else {
            Issue.record("expected a write")
            return
        }
        let (armed, _) = step(settingState, .writeFinished(token: token, ok: true))
        let (closing, held) = step(armed, .panelClosed)
        #expect(held.isEmpty)
        if case .setting(let setting) = closing.route {
            #expect(setting.closeAfter)
            #expect(setting.token == token)
        } else {
            Issue.record("expected the read back to stay in flight")
        }
        let (done, effects) = step(closing, .readBack(token: token, raw: 3))
        #expect(done.route == .dormant)
        #expect(effects == [
            .announce(.changed(.transparency)), .stopListening, .unwatchOutput,
        ])
        #expect(ListeningModeMachine.status(done) == .hidden)
        let second = step(done, .panelClosed)
        #expect(second.1.isEmpty)
        let (moved, dropped) = step(closing, .outputChanged)
        #expect(moved.route == .dormant)
        #expect(dropped == [.stopListening, .unwatchOutput])
        let late = step(moved, .readBack(token: token, raw: 3))
        #expect(late.0 == moved)
        #expect(late.1.isEmpty)
    }

    @Test func anUnreadableReadBackHidesTheRow() {
        let ready = readyNoiseCancelling()
        let (settingState, write) = setting(from: ready, .transparency)
        guard case .write(_, _, let token) = write else {
            Issue.record("expected a write")
            return
        }
        let (armed, _) = step(settingState, .writeFinished(token: token, ok: true))
        let (hidden, effects) = step(armed, .readBack(token: token, raw: nil))
        #expect(hidden.route == .absent)
        #expect(effects == [.stopListening])
        #expect(!effects.contains(.unwatchOutput))
        #expect(ListeningModeMachine.status(hidden) == .hidden)
        let unknown = step(armed, .readBack(token: token, raw: 9))
        #expect(unknown.0.route == .absent)
        #expect(unknown.1 == [.stopListening])
        let (moved, next) = step(hidden, .outputChanged)
        #expect(probeToken(next) != nil)
        #expect(moved.route == .absent)
    }

    @Test func anExternalChangeFollowsTheDevice() {
        let ready = readyNoiseCancelling()
        let key = sample().key
        let (followed, effects) = step(ready, .externalChange(key: key, raw: 3))
        #expect(effects.isEmpty)
        if case .ready(let bound) = followed.route {
            #expect(bound.current == .transparency)
        } else {
            Issue.record("expected ready")
        }
        let same = step(followed, .externalChange(key: key, raw: 3))
        #expect(same.0 == followed)
        let wrong = step(followed, .externalChange(key: ModeKey(objectID: 1, generation: 2), raw: 1))
        #expect(wrong.0 == followed)
        let (hidden, stopped) = step(followed, .externalChange(key: key, raw: 0))
        #expect(hidden.route == .absent)
        #expect(stopped == [.stopListening])
        let text = [
            String(describing: ListeningMode.noiseCancelling),
            String(describing: ListeningMode.adaptive),
            String(describing: ModeOutcome.changed(.transparency)),
            String(describing: ModeOutcome.stayed(.off)),
            String(describing: ListeningModeMachine.status(ready)),
        ].joined(separator: " ")
        #expect(!text.contains("\u{2014}"))
        #expect(!text.contains("\u{2013}"))
    }

    private func writeToken(_ state: ListeningModeMachine.State) -> Int {
        if case .setting(let setting) = state.route { return setting.token }
        return -1
    }
}
