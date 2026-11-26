import Testing
@testable import ZeusCore

@Suite("System source machine")
struct SystemSourceMachineTests {
    @Test func nothingSpawnsWhileAGateIsMissing() {
        let idle = SystemSourceMachine.initial
        #expect(idle.phase == .off)
        #expect(idle.gates == [.sessionActive, .awake, .unlocked])

        var off = SystemSourceMachine.initial
        #expect(!spawned(apply(&off, .settingChanged(on: false))))

        var noServices = SystemSourceMachine.initial
        let held = apply(&noServices, .settingChanged(on: true))
        #expect(noServices.phase == .held(.servicesStopped))
        #expect(!spawned(held))

        var pinned = noServices
        let pin = apply(&pinned, .servicesStarted)
        #expect(pinned.phase == .held(.pinned))
        #expect(!spawned(pin))

        var asleep = started()
        #expect(!spawned(apply(&asleep, .willSleep)))
        #expect(asleep.phase == .held(.asleep))

        var locked = started()
        #expect(!spawned(apply(&locked, .screenLocked)))
        #expect(locked.phase == .held(.locked))

        var away = started()
        #expect(!spawned(apply(&away, .sessionResigned)))
        #expect(away.phase == .held(.sessionInactive))

        var early = SystemSourceMachine.initial
        _ = apply(&early, .settingChanged(on: true))
        _ = apply(&early, .followChanged(any: true))
        #expect(early.phase == .held(.servicesStopped))
        #expect(early.run == 0)
    }

    @Test func preflightRefusalNeverSpawns() {
        for verdict in [PreflightVerdict.systemTooOld, .interpreterMissing, .helperInvalid] {
            var state = started()
            let effects = apply(&state, .preflight(run: state.run, verdict: verdict, token: "zeal"))
            #expect(!spawned(effects))
            #expect(state.phase == .unavailable(reason(verdict)))
        }

        var passed = started()
        let effects = apply(&passed, .preflight(run: passed.run, verdict: .passed, token: "zeal"))
        #expect(spawned(effects))
        #expect(passed.phase == .starting)
        #expect(passed.token == "zeal")
    }

    @Test func handshakeRefusalNeverProves() {
        var missing = spawnedRun()
        let missingEffects = apply(&missing, .hello(run: missing.run, version: 1, missing: 2, childIsVendor: true))
        #expect(missing.phase == .unavailable(.symbolsMissing))
        #expect(stopped(missingEffects))
        #expect(!proving(missing.phase))

        var foreign = spawnedRun()
        _ = apply(&foreign, .hello(run: foreign.run, version: 1, missing: 0, childIsVendor: false))
        #expect(foreign.phase == .unavailable(.interpreterMissing))
        #expect(!proving(foreign.phase))

        var wrongVersion = spawnedRun()
        _ = apply(&wrongVersion, .hello(run: wrongVersion.run, version: 2, missing: 0, childIsVendor: true))
        #expect(wrongVersion.phase == .unavailable(.symbolsMissing))

        var early = spawnedRun()
        _ = apply(&early, .item(run: early.run, own: false, token: ""))
        #expect(early.phase == .unavailable(.routeClosed))
        #expect(early.phase != .live)
    }

    @Test func unansweredReadBacksOff() {
        var state = proving()
        let effects = apply(&state, .deadline(run: state.run, .read))
        #expect(state.phase == .backingOff)
        #expect(state.failures == 1)
        #expect(backoffDelay(effects) == 1)
        #expect(SystemSourceStatus.text(for: state.phase).word == "Restarting")

        var helloWait = spawnedRun()
        let timedOut = apply(&helloWait, .deadline(run: helloWait.run, .hello))
        #expect(helloWait.phase == .backingOff)
        #expect(backoffDelay(timedOut) == 1)
    }

    @Test func aRealItemProvesAndArmsStable() {
        var state = proving()
        let effects = apply(&state, .item(run: state.run, own: false, token: ""))
        #expect(state.phase == .live)
        #expect(state.report == .item)
        #expect(armed(effects, .stable, seconds: 300))
        #expect(state.failures == 0)
    }

    @Test func canaryProvesAndClears() {
        var state = proving()
        let startedCanary = apply(&state, .nothing(run: state.run))
        #expect(state.phase == .proving(.canary))
        #expect(publishedCanary(startedCanary, token: "zeal"))
        let proved = apply(&state, .item(run: state.run, own: true, token: "zeal"))
        #expect(state.phase == .live)
        #expect(clearedCanary(proved))
    }

    @Test func canaryTimeoutClosesTheRoute() {
        var state = proving()
        _ = apply(&state, .nothing(run: state.run))
        let effects = apply(&state, .deadline(run: state.run, .canary))
        #expect(state.phase == .unavailable(.routeClosed))
        #expect(clearedCanary(effects))
        #expect(stopped(effects))
        #expect(!spawned(effects))
        #expect(SystemSourceStatus.text(for: state.phase).reasonCode == "R5")
    }

    @Test func doubtDoesNotPublishOrCloseEarly() {
        var state = proving()
        _ = apply(&state, .playerEvidence(playing: true))
        let effects = apply(&state, .nothing(run: state.run))
        #expect(armed(effects, .doubt, seconds: 5))
        #expect(!publishedCanary(effects, token: "zeal"))
        #expect(state.phase == .proving(.waiting))
    }

    @Test func playbackOnAnotherDeviceStaysLive() {
        var provingState = proving()
        _ = apply(&provingState, .playerEvidence(playing: true))
        _ = apply(&provingState, .nothing(run: provingState.run))
        let canary = apply(&provingState, .deadline(run: provingState.run, .doubt))
        #expect(publishedCanary(canary, token: "zeal"))
        #expect(provingState.phase == .proving(.canary))
        _ = apply(&provingState, .item(run: provingState.run, own: true, token: "zeal"))
        #expect(provingState.phase == .live)

        var liveState = live()
        _ = apply(&liveState, .playerEvidence(playing: true))
        let doubt = apply(&liveState, .nothing(run: liveState.run))
        #expect(!publishedCanary(doubt, token: "zeal"))
        _ = apply(&liveState, .deadline(run: liveState.run, .doubt))
        _ = apply(&liveState, .item(run: liveState.run, own: true, token: "zeal"))
        #expect(liveState.phase == .live)
    }

    @Test func oneDoubtPerPlayerSession() {
        var state = live()
        _ = apply(&state, .playerEvidence(playing: true))
        let first = apply(&state, .nothing(run: state.run))
        let second = apply(&state, .nothing(run: state.run))
        #expect(doubtArms(first) == 1)
        #expect(doubtArms(second) == 0)
        _ = apply(&state, .playerEvidence(playing: false))
        _ = apply(&state, .playerEvidence(playing: true))
        let again = apply(&state, .nothing(run: state.run))
        #expect(doubtArms(again) == 1)
    }

    @Test func backoffIsOneTwoFourEightThenStops() {
        var state = proving()
        var delays: [Double] = []
        for _ in 0..<4 {
            let failed = apply(&state, .deadline(run: state.run, .read))
            delays.append(backoffDelay(failed) ?? -1)
            _ = apply(&state, .deadline(run: state.run, .backoff))
            _ = apply(&state, .preflight(run: state.run, verdict: .passed, token: "zeal"))
            _ = apply(&state, .hello(run: state.run, version: 1, missing: 0, childIsVendor: true))
        }
        let fifth = apply(&state, .deadline(run: state.run, .read))
        #expect(delays == [1, 2, 4, 8])
        #expect(state.failures == 5)
        #expect(state.phase == .unavailable(.keepsFailing))
        #expect(backoffDelay(fifth) == nil)
        #expect(stopped(fifth))
    }

    @Test func failuresSurviveLiveUntilStable() {
        var state = proving()
        _ = apply(&state, .deadline(run: state.run, .read))
        _ = apply(&state, .deadline(run: state.run, .backoff))
        _ = apply(&state, .preflight(run: state.run, verdict: .passed, token: "zeal"))
        _ = apply(&state, .hello(run: state.run, version: 1, missing: 0, childIsVendor: true))
        _ = apply(&state, .item(run: state.run, own: false, token: ""))
        #expect(state.phase == .live)
        #expect(state.failures == 1)
        let stable = apply(&state, .deadline(run: state.run, .stable))
        #expect(state.failures == 0)
        #expect(state.phase == .live)
        #expect(armed(stable, .stable, seconds: 300))
    }

    @Test func aReturningGateAndCheckAgainResetFailures() {
        var state = proving()
        _ = apply(&state, .deadline(run: state.run, .read))
        #expect(state.failures == 1)
        _ = apply(&state, .screenLocked)
        _ = apply(&state, .screenUnlocked)
        #expect(state.failures == 0)
        #expect(state.phase == .starting)

        var closed = started()
        _ = apply(&closed, .preflight(run: closed.run, verdict: .helperInvalid, token: "zeal"))
        #expect(closed.phase == .unavailable(.helperInvalid))
        let run = closed.run
        _ = apply(&closed, .checkAgain)
        #expect(closed.phase == .starting)
        #expect(closed.run == run + 1)
        #expect(closed.failures == 0)

        var playing = live()
        let before = playing
        let ignored = apply(&playing, .checkAgain)
        #expect(ignored.isEmpty)
        #expect(playing == before)
    }

    @Test func lockStopsTheHelperAndClearsTheCanary() {
        var state = proving()
        _ = apply(&state, .nothing(run: state.run))
        let run = state.run
        let effects = apply(&state, .screenLocked)
        #expect(Array(effects.prefix(3)) == [.stop(run), .clearCanary, .dropEntry])
        #expect(state.phase == .held(.locked))
        #expect(!spawned(effects))
    }

    @Test func wakeDoesNotSpawnBeforeUnlock() {
        var state = live()
        _ = apply(&state, .willSleep)
        _ = apply(&state, .screenLocked)
        let run = state.run
        let woke = apply(&state, .didWake)
        #expect(!spawned(woke))
        #expect(!publishedCanary(woke, token: "zeal"))
        #expect(armed(woke, .settle, seconds: 2))
        let settled = apply(&state, .deadline(run: run, .settle))
        #expect(!spawned(settled))
        #expect(!preflighted(settled))
        #expect(!publishedCanary(settled, token: "zeal"))
        #expect(state.run == run)
        #expect(state.phase == .held(.locked))
    }

    @Test func unlockRetestsFromUnavailable() {
        var state = proving()
        _ = apply(&state, .nothing(run: state.run))
        _ = apply(&state, .deadline(run: state.run, .canary))
        #expect(state.phase == .unavailable(.routeClosed))
        _ = apply(&state, .screenLocked)
        let run = state.run
        let effects = apply(&state, .screenUnlocked)
        #expect(state.phase == .starting)
        #expect(state.run == run + 1)
        #expect(preflighted(effects))
        #expect(!spawned(effects))
    }

    @Test func aLockDuringSettleStartsNothing() {
        var state = live()
        _ = apply(&state, .willSleep)
        let run = state.run
        _ = apply(&state, .didWake)
        _ = apply(&state, .screenLocked)
        let settled = apply(&state, .deadline(run: run, .settle))
        #expect(!spawned(settled))
        #expect(!preflighted(settled))
        #expect(state.phase == .held(.locked))
        #expect(state.run == run)
    }

    @Test func pingWaitsThirtySeconds() {
        var state = live()
        let first = apply(&state, .musicPageOpened, now: 1_000)
        #expect(pinged(first))
        _ = apply(&state, .pong(run: state.run, id: state.pingID ?? -1))
        let early = apply(&state, .musicPageOpened, now: 1_029)
        #expect(!pinged(early))
        #expect(early.isEmpty)
        let later = apply(&state, .musicPageOpened, now: 1_030)
        #expect(pinged(later))
        _ = apply(&state, .pong(run: state.run, id: state.pingID ?? -1))
        let infinite = apply(&state, .musicPageOpened, now: .infinity)
        let missing = apply(&state, .musicPageOpened, now: .nan)
        #expect(!pinged(infinite))
        #expect(!pinged(missing))
        var quiet = proving()
        #expect(!pinged(apply(&quiet, .musicPageOpened, now: 5_000)))
    }

    @Test func commandsNeedLiveAndFourSlots() {
        var quiet = proving()
        let ignored = apply(&quiet, .command(.init(name: .pause, seconds: 0, app: "com.apple.Music")))
        #expect(!sent(ignored))
        #expect(quiet.pending.isEmpty)

        var state = live()
        let first = state.nextID
        for offset in 0..<4 {
            let name = SystemSourceMachine.Command.Name.pause
            let effects = apply(&state, .command(.init(name: name, seconds: 0, app: "com.apple.Music")))
            #expect(sentCommand(effects, id: first + offset))
        }
        #expect(state.pending == [first, first + 1, first + 2, first + 3])
        let dropped = apply(&state, .command(.init(name: .next, seconds: 0, app: "com.apple.Music")))
        #expect(dropped.isEmpty)
        #expect(state.pending.count == 4)
        _ = apply(&state, .ack(run: state.run, id: first, ok: true))
        #expect(state.pending.count == 3)
        let freed = apply(&state, .command(.init(name: .play, seconds: 0, app: "com.apple.Music")))
        #expect(sentCommand(freed, id: first + 4))
        #expect(state.pending.count == 4)
    }

    @Test func switchingOffStopsBeforeAnythingElse() {
        var samples: [SystemSourceMachine.State] = []
        var held = SystemSourceMachine.initial
        _ = apply(&held, .settingChanged(on: true))
        samples.append(held)
        samples.append(started())
        samples.append(proving())
        var canary = proving()
        _ = apply(&canary, .nothing(run: canary.run))
        samples.append(canary)
        samples.append(live())
        var backing = proving()
        _ = apply(&backing, .deadline(run: backing.run, .read))
        samples.append(backing)
        var refused = started()
        _ = apply(&refused, .preflight(run: refused.run, verdict: .systemTooOld, token: "zeal"))
        samples.append(refused)

        for sample in samples {
            var state = sample
            let run = state.run
            let effects = apply(&state, .settingChanged(on: false))
            #expect(Array(effects.prefix(3)) == [.stop(run), .clearCanary, .dropEntry])
            #expect(state.phase == .off)
            #expect(state.run == run)
        }
    }

    @Test func aStaleRunIsIgnored() {
        var state = proving()
        #expect(state.run == 1)
        _ = apply(&state, .settingChanged(on: false))
        _ = apply(&state, .settingChanged(on: true))
        #expect(state.run == 2)
        let settled = state
        let effects = apply(&state, .hello(run: 1, version: 1, missing: 0, childIsVendor: true))
        #expect(effects.isEmpty)
        #expect(state == settled)
        let item = apply(&state, .item(run: 1, own: false, token: ""))
        #expect(item.isEmpty)
        #expect(state == settled)
    }

    @Test func statusWordsHaveSymbolsAndNoDashes() {
        let rows: [(SystemSourceMachine.Phase, String, String, String?)] = [
            (.off, "Off", "circle", nil),
            (.held(.servicesStopped), "Checking", "arrow.triangle.2.circlepath", nil),
            (.held(.sessionInactive), "Checking", "arrow.triangle.2.circlepath", nil),
            (.held(.asleep), "Checking", "arrow.triangle.2.circlepath", nil),
            (.held(.locked), "Checking", "arrow.triangle.2.circlepath", nil),
            (.held(.pinned), "Pinned", "pin", nil),
            (.starting, "Checking", "arrow.triangle.2.circlepath", nil),
            (.proving(.waiting), "Checking", "arrow.triangle.2.circlepath", nil),
            (.proving(.canary), "Checking", "arrow.triangle.2.circlepath", nil),
            (.live, "Ready", "checkmark.circle", nil),
            (.backingOff, "Restarting", "arrow.clockwise", nil),
            (.unavailable(.systemTooOld), "Unavailable", "exclamationmark.triangle", "R1"),
            (.unavailable(.interpreterMissing), "Unavailable", "exclamationmark.triangle", "R2"),
            (.unavailable(.helperInvalid), "Unavailable", "exclamationmark.triangle", "R3"),
            (.unavailable(.symbolsMissing), "Unavailable", "exclamationmark.triangle", "R4"),
            (.unavailable(.routeClosed), "Unavailable", "exclamationmark.triangle", "R5"),
            (.unavailable(.keepsFailing), "Unavailable", "exclamationmark.triangle", "R6"),
        ]
        for (phase, word, symbol, code) in rows {
            let status = SystemSourceStatus.text(for: phase)
            #expect(status.word == word)
            #expect(status.symbol == symbol)
            #expect(status.reasonCode == code)
            #expect(!status.word.contains("\u{2014}"))
            #expect(!status.word.contains("\u{2013}"))
            #expect(!status.symbol.contains("\u{2014}"))
            #expect(!status.symbol.contains("\u{2013}"))
        }
    }

    @Test func repeatedBadLinesAndAFloodFail() {
        var state = live()
        for _ in 0..<19 {
            let effects = apply(&state, .badLine(run: state.run))
            #expect(effects.isEmpty)
            #expect(state.phase == .live)
        }
        _ = apply(&state, .item(run: state.run, own: false, token: ""))
        for _ in 0..<19 {
            _ = apply(&state, .badLine(run: state.run))
            #expect(state.phase == .live)
        }
        let failed = apply(&state, .badLine(run: state.run))
        #expect(state.phase == .backingOff)
        #expect(state.failures == 1)
        #expect(stopped(failed))

        var flooded = live()
        _ = apply(&flooded, .flood(run: flooded.run))
        #expect(flooded.phase == .backingOff)
        #expect(flooded.failures == 1)
    }
}

private func apply(_ state: inout SystemSourceMachine.State, _ event: SystemSourceMachine.Event,
                   now: Double = 0) -> [SystemSourceMachine.Effect] {
    let (next, effects) = SystemSourceMachine.reduce(state, event, now: now)
    state = next
    return effects
}

private func started() -> SystemSourceMachine.State {
    var state = SystemSourceMachine.initial
    _ = apply(&state, .settingChanged(on: true))
    _ = apply(&state, .servicesStarted)
    _ = apply(&state, .followChanged(any: true))
    return state
}

private func spawnedRun() -> SystemSourceMachine.State {
    var state = started()
    _ = apply(&state, .preflight(run: state.run, verdict: .passed, token: "zeal"))
    return state
}

private func proving() -> SystemSourceMachine.State {
    var state = spawnedRun()
    _ = apply(&state, .hello(run: state.run, version: 1, missing: 0, childIsVendor: true))
    return state
}

private func live() -> SystemSourceMachine.State {
    var state = proving()
    _ = apply(&state, .item(run: state.run, own: false, token: ""))
    return state
}

private func reason(_ verdict: PreflightVerdict) -> SystemSourceMachine.Reason {
    switch verdict {
    case .passed: return .routeClosed
    case .systemTooOld: return .systemTooOld
    case .interpreterMissing: return .interpreterMissing
    case .helperInvalid: return .helperInvalid
    }
}

private func spawned(_ effects: [SystemSourceMachine.Effect]) -> Bool {
    effects.contains { if case .spawn = $0 { return true }; return false }
}

private func preflighted(_ effects: [SystemSourceMachine.Effect]) -> Bool {
    effects.contains { if case .preflight = $0 { return true }; return false }
}

private func stopped(_ effects: [SystemSourceMachine.Effect]) -> Bool {
    effects.contains { if case .stop = $0 { return true }; return false }
}

private func clearedCanary(_ effects: [SystemSourceMachine.Effect]) -> Bool {
    effects.contains { if case .clearCanary = $0 { return true }; return false }
}

private func publishedCanary(_ effects: [SystemSourceMachine.Effect], token: String) -> Bool {
    effects.contains { if case .publishCanary(let value) = $0 { return value == token }; return false }
}

private func pinged(_ effects: [SystemSourceMachine.Effect]) -> Bool {
    effects.contains { if case .send(_, .ping) = $0 { return true }; return false }
}

private func sent(_ effects: [SystemSourceMachine.Effect]) -> Bool {
    effects.contains { if case .send = $0 { return true }; return false }
}

private func sentCommand(_ effects: [SystemSourceMachine.Effect], id: Int) -> Bool {
    effects.contains { effect in
        if case .send(_, .command(let sentID, _)) = effect { return sentID == id }
        return false
    }
}

private func armed(_ effects: [SystemSourceMachine.Effect], _ deadline: SystemSourceMachine.Deadline,
                   seconds: Double) -> Bool {
    effects.contains { effect in
        if case .arm(_, let armedDeadline, let armedSeconds) = effect {
            return armedDeadline == deadline && armedSeconds == seconds
        }
        return false
    }
}

private func doubtArms(_ effects: [SystemSourceMachine.Effect]) -> Int {
    effects.filter { effect in
        if case .arm(_, .doubt, _) = effect { return true }
        return false
    }.count
}

private func backoffDelay(_ effects: [SystemSourceMachine.Effect]) -> Double? {
    for effect in effects {
        if case .arm(_, .backoff, let seconds) = effect { return seconds }
    }
    return nil
}

private func proving(_ phase: SystemSourceMachine.Phase) -> Bool {
    if case .proving = phase { return true }
    return false
}
