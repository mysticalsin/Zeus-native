import Foundation
import Testing
@testable import ZeusCore

/// The reducer in docs/NOTCH-FOCUS-PLAN.md, F2. Every route is reached through events.
@Suite("Focus machine")
struct SystemFocusMachineTests {
    typealias Machine = SystemFocusMachine
    typealias Read = Machine.Read

    static let turnedOff: [Machine.Effect] = [.cancelRead, .stopWatch, .cancelStat, .withdrawCue]
    static let cleared: [Machine.Effect] = [.stopWatch, .cancelStat]

    func stamp(inode: UInt64 = 1) -> Machine.Stamps {
        Machine.Stamps(
            assertions: Machine.Stamp(inode: inode, size: 20, seconds: 30, nanoseconds: 40),
            configurations: Machine.Stamp(inode: inode + 1, size: 21, seconds: 31, nanoseconds: 41)
        )
    }

    func focus(_ id: String, _ name: String? = "Work", symbol: String? = "moon.fill") -> Read {
        .ok(.on(Machine.Focus(id: id, name: name, symbol: symbol)))
    }

    func step(_ state: inout Machine.State, _ event: Machine.Event) -> [Machine.Effect] {
        let (next, effects) = Machine.reduce(state, event)
        state = next
        return effects
    }

    func switchedOn() -> Machine.State {
        var state = Machine.State()
        _ = step(&state, .settingChanged(true))
        return state
    }

    func finish(
        _ state: inout Machine.State,
        _ result: Read,
        now: Double = 0,
        stamps: Machine.Stamps? = nil
    ) -> [Machine.Effect] {
        let generation: Int
        switch state.flight {
        case .reading(let flight), .readingStale(let flight):
            generation = flight
        case .idle:
            Issue.record("expected a read in flight")
            return []
        }
        return step(
            &state,
            .readFinished(generation: generation, result: result, stamps: stamps ?? stamp(), now: now)
        )
    }

    /// Switch on, one baseline reading, and the watch reported as started.
    func named(
        _ id: String = "work",
        name: String? = "Work",
        symbol: String? = "moon.fill"
    ) -> Machine.State {
        var state = switchedOn()
        _ = finish(&state, focus(id, name, symbol: symbol))
        _ = step(&state, .watchStarted)
        return state
    }

    func change(_ state: inout Machine.State, _ result: Read, now: Double) -> [Machine.Effect] {
        _ = step(&state, .storeChanged)
        return finish(&state, result, now: now)
    }

    @Test func offIgnoresEveryEvent() {
        let start = Machine.State()
        let events: [Machine.Event] = [
            .settingChanged(false),
            .appBecameActive,
            .sessionBecameActive,
            .rowAppeared,
            .didWake,
            .storeChanged,
            .statTick,
            .readFinished(generation: 0, result: .ok(.off), stamps: stamp(), now: 1),
            .readFinished(generation: 4, result: .denied, stamps: nil, now: 1),
            .watchStarted,
            .watchFailed,
            .openSettingsPressed,
        ]
        for event in events {
            let (next, effects) = Machine.reduce(start, event)
            #expect(effects.isEmpty)
            #expect(next == start)
        }
    }

    @Test func detailsHiddenIsStoredWhileOff() {
        var state = Machine.State()
        #expect(step(&state, .detailsHidden(true)).isEmpty)
        #expect(state.detailsHidden)
        #expect(state.route == .off)
        #expect(state.enabled == false)
        let stored = state
        #expect(step(&state, .detailsHidden(true)).isEmpty)
        #expect(state == stored)
    }

    @Test func settingOnGivesOneRead() {
        var state = Machine.State()
        let effects = step(&state, .settingChanged(true))
        #expect(state.enabled)
        #expect(state.route == .checking)
        #expect(state.reading == .unknown)
        #expect(state.generation == 1)
        #expect(state.flight == .reading(1))
        #expect(effects == [.read(generation: 1, after: 0, ifChangedFrom: nil)])
        #expect(step(&state, .settingChanged(true)).isEmpty)
        #expect(step(&state, .watchStarted).isEmpty)
        #expect(state.watch == .none)
        #expect(state.flight == .reading(1))
    }

    @Test func launchOnGivesOneRead() {
        var state = Machine.State()
        let effects = step(&state, .launched(enabled: true, detailsHidden: true))
        #expect(state.detailsHidden)
        #expect(state.route == .checking)
        #expect(effects == [.read(generation: 1, after: 0, ifChangedFrom: nil)])
    }

    @Test func launchOffStaysOff() {
        var state = Machine.State()
        let effects = step(&state, .launched(enabled: false, detailsHidden: true))
        #expect(effects.isEmpty)
        #expect(state.detailsHidden)
        #expect(state.enabled == false)
        #expect(state.route == .off)
        #expect(state.flight == .idle)
    }

    @Test func staleGenerationIsDropped() {
        var state = switchedOn()
        let generation = state.generation
        let effects = step(&state, .settingChanged(false))
        #expect(effects == Self.turnedOff)
        #expect(state.generation == generation + 1)
        let landed = step(
            &state,
            .readFinished(generation: generation, result: focus("work"), stamps: stamp(), now: 2)
        )
        #expect(landed.isEmpty)
        #expect(state.route == .off)
        #expect(state.reading == .unknown)
        #expect(state.enabled == false)
    }

    @Test func deniedReachesNeedsAccessAndStopsTheWatch() {
        var state = named()
        _ = step(&state, .storeChanged)
        let effects = finish(&state, .denied)
        #expect(state.route == .needsAccess)
        #expect(state.reading == .unknown)
        #expect(state.stamps == nil)
        #expect(state.baselineTaken == false)
        #expect(state.flight == .idle)
        #expect(state.watch == .none)
        #expect(effects == Self.cleared)
    }

    @Test func missingReachesUnavailableAndStopsTheWatch() {
        var state = named()
        _ = step(&state, .storeChanged)
        let effects = finish(&state, .missing)
        #expect(state.route == .unavailable(.missing))
        #expect(state.reading == .unknown)
        #expect(state.stamps == nil)
        #expect(state.watch == .none)
        #expect(effects == Self.cleared)
    }

    @Test func unreadableReachesUnavailableAndStopsTheWatch() {
        let reasons: [Read.Reason] = [.tooLarge, .notAFile, .refused, .other]
        for reason in reasons {
            var state = named()
            _ = step(&state, .storeChanged)
            let effects = finish(&state, .unreadable(reason))
            #expect(state.route == .unavailable(.unreadable(reason)))
            #expect(state.reading == .unknown)
            #expect(state.malformedStreak == 0)
            #expect(state.watch == .none)
            #expect(effects == Self.cleared)
        }
        var checking = switchedOn()
        let first = finish(&checking, .unreadable(.malformed))
        #expect(checking.route == .unavailable(.unreadable(.malformed)))
        #expect(first == Self.cleared)
    }

    @Test func oneMalformedKeepsTheReadingAndRetriesOnce() {
        var state = named()
        let reading = state.reading
        let stamps = state.stamps
        _ = step(&state, .storeChanged)
        let effects = finish(&state, .unreadable(.malformed), now: 5)
        #expect(state.reading == reading)
        #expect(state.stamps == stamps)
        #expect(state.route == .named)
        #expect(state.malformedStreak == 1)
        #expect(state.baselineTaken)
        #expect(effects == [
            .read(generation: state.generation, after: Machine.malformedRetryDelay, ifChangedFrom: nil),
        ])
        let settled = finish(&state, focus("work"), now: 6)
        #expect(settled.isEmpty)
        #expect(state.malformedStreak == 0)
        #expect(state.route == .named)
        #expect(state.reading == reading)
    }

    @Test func twoMalformedReadsReachUnavailable() {
        var state = named()
        _ = step(&state, .storeChanged)
        _ = finish(&state, .unreadable(.malformed))
        let effects = finish(&state, .unreadable(.malformed))
        #expect(state.route == .unavailable(.unreadable(.malformed)))
        #expect(state.reading == .unknown)
        #expect(state.stamps == nil)
        #expect(state.baselineTaken == false)
        #expect(state.watch == .none)
        #expect(effects == Self.cleared)
    }

    @Test func malformedWithNoNameGoesUnavailable() {
        var state = named()
        _ = change(&state, .ok(.off), now: 1)
        _ = step(&state, .storeChanged)
        let effects = finish(&state, .unreadable(.malformed))
        #expect(state.route == .unavailable(.unreadable(.malformed)))
        #expect(state.reading == .unknown)
        #expect(effects == Self.cleared)
    }

    @Test func burstOfStoreChangedGivesOneRead() {
        var state = named()
        let first = step(&state, .storeChanged)
        let second = step(&state, .storeChanged)
        let third = step(&state, .storeChanged)
        #expect(second.isEmpty)
        #expect(third.isEmpty)
        guard case .read(let generation, let after, let from) = first.first else {
            Issue.record("a burst starts one read")
            return
        }
        #expect(first.count == 1)
        #expect(after == Machine.storeChangeDelay)
        #expect(from == nil)
        #expect(state.flight == .readingStale(generation))
    }

    @Test func changeDuringAReadGivesExactlyOneMore() {
        var state = named()
        let reading = state.reading
        let stamps = state.stamps
        _ = step(&state, .storeChanged)
        #expect(step(&state, .storeChanged).isEmpty)
        let effects = finish(&state, .unchanged, now: 4)
        #expect(state.reading == reading)
        #expect(state.stamps == stamps)
        #expect(state.cueTimes.isEmpty)
        guard case .read(let generation, let after, let from) = effects.first else {
            Issue.record("a stale finish starts one more read")
            return
        }
        #expect(effects.count == 1)
        #expect(after == 0)
        #expect(from == nil)
        #expect(state.flight == .reading(generation))
    }

    @Test func unchangedEndsTheFlightAndKeepsTheReading() {
        var state = named()
        let reading = state.reading
        let stamps = state.stamps
        _ = step(&state, .storeChanged)
        let effects = finish(&state, .unchanged, now: 9)
        #expect(effects.isEmpty)
        #expect(state.flight == .idle)
        #expect(state.reading == reading)
        #expect(state.stamps == stamps)
        #expect(state.route == .named)
        #expect(state.cueTimes.isEmpty)
    }

    @Test func baselineAfterSwitchOnGivesNoCue() {
        var state = switchedOn()
        let effects = finish(&state, focus("work"), now: 1)
        #expect(effects == [.startWatch])
        #expect(state.baselineTaken)
        #expect(state.route == .named)
        #expect(state.cueTimes.isEmpty)
        #expect(state.flight == .idle)
    }

    @Test func baselineAfterLaunchGivesNoCue() {
        var state = Machine.State()
        _ = step(&state, .launched(enabled: true, detailsHidden: false))
        let effects = finish(&state, focus("work"), now: 1)
        #expect(effects == [.startWatch])
        #expect(state.cueTimes.isEmpty)
    }

    @Test func baselineAfterNeedsAccessGivesNoCue() {
        var state = named()
        _ = step(&state, .appBecameActive)
        _ = finish(&state, .denied)
        #expect(state.baselineTaken == false)
        _ = step(&state, .appBecameActive)
        let effects = finish(&state, focus("work"), now: 3)
        #expect(effects == [.startWatch])
        #expect(state.cueTimes.isEmpty)
        #expect(state.route == .named)
    }

    @Test func baselineAfterUnavailableGivesNoCue() {
        var state = named()
        _ = step(&state, .didWake)
        _ = finish(&state, .missing)
        #expect(state.baselineTaken == false)
        _ = step(&state, .sessionBecameActive)
        let effects = finish(&state, focus("work", "Home", symbol: "house"), now: 4)
        #expect(effects == [.startWatch])
        #expect(state.cueTimes.isEmpty)
        if case .on(let focus) = state.reading {
            #expect(focus.name == "Home")
        } else {
            Issue.record("the baseline reading is on")
        }
    }

    @Test func onReplacedAndOffEachGiveOneCue() {
        var state = named()
        let off = change(&state, .ok(.off), now: 1)
        #expect(off == [.cue(Machine.Cue(label: "Focus off", symbol: "moon", on: false))])
        let turnedOn = change(&state, focus("home", "Home", symbol: "house"), now: 2)
        #expect(turnedOn == [.cue(Machine.Cue(label: "Home", symbol: "house", on: true))])
        let replaced = change(&state, focus("sleep", "Sleep", symbol: "moon.zzz"), now: 3)
        #expect(replaced == [.cue(Machine.Cue(label: "Sleep", symbol: "moon.zzz", on: true))])
    }

    @Test func sameIdAndNameGivesNoCue() {
        var state = named()
        let effects = change(&state, focus("work", "Work", symbol: "circle"), now: 2)
        #expect(effects.isEmpty)
        if case .on(let focus) = state.reading {
            #expect(focus.id == "work")
            #expect(focus.name == "Work")
            #expect(focus.symbol == "circle")
        } else {
            Issue.record("the reading stays on")
        }
    }

    @Test func fourthCueInsideThirtySecondsIsWithheldWhileReadingUpdates() {
        var state = named()
        #expect(change(&state, .ok(.off), now: 0).count == 1)
        #expect(change(&state, focus("b", "Beta"), now: 10).count == 1)
        #expect(change(&state, focus("c", "Gamma"), now: 20).count == 1)
        #expect(state.cueTimes == [0, 10, 20])
        let withheld = change(&state, focus("d", "Delta"), now: 25)
        #expect(withheld.isEmpty)
        #expect(state.cueTimes == [0, 10, 20])
        if case .on(let focus) = state.reading {
            #expect(focus.id == "d")
            #expect(focus.name == "Delta")
        } else {
            Issue.record("the withheld cue still updates the reading")
        }
        let later = change(&state, focus("e", "Epsilon"), now: 50.1)
        #expect(later == [.cue(Machine.Cue(label: "Epsilon", symbol: "moon.fill", on: true))])
    }

    @Test func eachRecheckReadsOnceAndNeverWhileOff() {
        let events: [Machine.Event] = [.appBecameActive, .sessionBecameActive, .rowAppeared, .didWake]
        let routes: [() -> Machine.State] = [
            { self.named() },
            {
                var state = self.switchedOn()
                _ = self.finish(&state, .denied)
                return state
            },
            {
                var state = self.switchedOn()
                _ = self.finish(&state, .missing)
                return state
            },
        ]
        for event in events {
            for make in routes {
                var state = make()
                let effects = step(&state, event)
                guard case .read(_, let after, let from) = effects.first else {
                    Issue.record("a recheck starts one read")
                    return
                }
                #expect(effects.count == 1)
                #expect(after == 0)
                #expect(from == nil)
                #expect(step(&state, event).isEmpty)
            }
            var off = Machine.State()
            #expect(step(&off, event).isEmpty)
            #expect(off == Machine.State())
            var checking = switchedOn()
            let generation = checking.generation
            #expect(step(&checking, event).isEmpty)
            #expect(checking.flight == .reading(generation))
        }
    }

    @Test func namedThenActivationThenDeniedClearsTheReading() {
        var state = named()
        #expect(step(&state, .appBecameActive).count == 1)
        let effects = finish(&state, .denied)
        #expect(state.route == .needsAccess)
        #expect(state.reading == .unknown)
        #expect(state.stamps == nil)
        #expect(effects == Self.cleared)
    }

    @Test func openSettingsPressedGivesAPaneOnlyInNeedsAccess() {
        var off = Machine.State()
        #expect(step(&off, .openSettingsPressed).isEmpty)
        var checking = switchedOn()
        #expect(step(&checking, .openSettingsPressed).isEmpty)
        var showing = named()
        #expect(step(&showing, .openSettingsPressed).isEmpty)
        var down = switchedOn()
        _ = finish(&down, .unreadable(.other))
        #expect(step(&down, .openSettingsPressed).isEmpty)
        var needs = switchedOn()
        _ = finish(&needs, .denied)
        #expect(step(&needs, .openSettingsPressed) == [.openPane])
        #expect(needs.route == .needsAccess)
    }

    @Test func watchFailedFallsBackToStatTicksThatCarryTheStamps() {
        var state = named()
        let stamps = state.stamps
        #expect(step(&state, .watchFailed) == [.scheduleStat(after: Machine.statInterval)])
        #expect(state.watch == .stat)
        let tick = step(&state, .statTick)
        guard case .read(let generation, let after, let from) = tick.first else {
            Issue.record("a stat tick reads with the last stamps")
            return
        }
        #expect(tick.count == 2)
        #expect(after == 0)
        #expect(from == stamps)
        #expect(tick[1] == .scheduleStat(after: Machine.statInterval))
        #expect(state.flight == .reading(generation))
        var events = named()
        #expect(step(&events, .statTick).isEmpty)
        #expect(events.watch == .events)
    }

    @Test func switchingOffFromEveryStateCancelsAndBumpsTheGeneration() {
        let checking = switchedOn()
        let showing = named()
        var needs = switchedOn()
        _ = finish(&needs, .denied)
        var down = switchedOn()
        _ = finish(&down, .missing)
        var statting = named()
        _ = step(&statting, .watchFailed)
        var inFlight = named()
        _ = step(&inFlight, .storeChanged)
        let states = [checking, showing, needs, down, statting, inFlight]
        for start in states {
            var state = start
            let generation = state.generation
            let effects = step(&state, .settingChanged(false))
            #expect(effects == Self.turnedOff)
            #expect(state.generation == generation + 1)
            #expect(state.enabled == false)
            #expect(state.route == .off)
            #expect(state.reading == .unknown)
            #expect(state.flight == .idle)
            #expect(state.watch == .none)
            #expect(state.stamps == nil)
            #expect(state.baselineTaken == false)
            let late = step(
                &state,
                .readFinished(generation: generation, result: focus("late"), stamps: stamp(), now: 8)
            )
            #expect(late.isEmpty)
            #expect(state.route == .off)
        }
    }

    @Test func detailsHiddenMasksTheNameAndWithdrawsTheCue() {
        var state = named()
        #expect(step(&state, .detailsHidden(true)) == [.withdrawCue])
        #expect(SystemFocusDisplay.surface(for: state).shown == .on(label: "Focus on", symbol: "moon.fill"))
        let masked = state
        #expect(step(&state, .detailsHidden(true)).isEmpty)
        #expect(state == masked)
        #expect(step(&state, .detailsHidden(false)).isEmpty)
        #expect(SystemFocusDisplay.surface(for: state).shown == .on(label: "Work", symbol: "moon.fill"))
        #expect(state.cueTimes.isEmpty)
    }

    @Test func cuesWhileHiddenCarryFocusOnOrFocusOffOnly() {
        var state = named()
        _ = step(&state, .detailsHidden(true))
        let off = change(&state, .ok(.off), now: 1)
        #expect(off == [.cue(Machine.Cue(label: "Focus off", symbol: "moon", on: false))])
        let on = change(&state, focus("home", "Home", symbol: "house"), now: 2)
        #expect(on == [.cue(Machine.Cue(label: "Focus on", symbol: "moon.fill", on: true))])
    }

    @Test func anOlderFinishCannotLandOnANewerRead() {
        var state = named()
        _ = step(&state, .storeChanged)
        let older = state.generation
        #expect(step(&state, .storeChanged).isEmpty)
        _ = finish(&state, .unchanged)
        let newer = state.generation
        #expect(newer == older + 1)
        let dropped = step(&state, .readFinished(generation: older, result: .denied, stamps: nil, now: 9))
        #expect(dropped.isEmpty)
        #expect(state.route == .named)
        #expect(state.reading == .on(Machine.Focus(id: "work", name: "Work", symbol: "moon.fill")))
        #expect(state.flight == .reading(newer))
    }

    @Test func edgeFollowsIdAndName() {
        let work = Machine.Reading.on(Machine.Focus(id: "work", name: "Work", symbol: "moon.fill"))
        let renamed = Machine.Reading.on(Machine.Focus(id: "work", name: "Deep Work", symbol: "moon.fill"))
        let resymbol = Machine.Reading.on(Machine.Focus(id: "work", name: "Work", symbol: "circle"))
        let home = Machine.Reading.on(Machine.Focus(id: "home", name: "Work", symbol: "house"))
        #expect(SystemFocusEdge.between(.off, work) == .turnedOn)
        #expect(SystemFocusEdge.between(.unknown, work) == .turnedOn)
        #expect(SystemFocusEdge.between(work, .off) == .turnedOff)
        #expect(SystemFocusEdge.between(work, home) == .replaced)
        #expect(SystemFocusEdge.between(work, renamed) == .replaced)
        #expect(SystemFocusEdge.between(work, resymbol) == nil)
        #expect(SystemFocusEdge.between(work, work) == nil)
        #expect(SystemFocusEdge.between(.off, .off) == nil)
        #expect(SystemFocusEdge.between(.unknown, .off) == nil)
        #expect(SystemFocusEdge.between(work, .unknown) == nil)
    }

    @Test func cueLimitHoldsThreeInsideThirtySeconds() {
        #expect(SystemFocusCueLimit.allows(times: [], now: 0))
        #expect(SystemFocusCueLimit.allows(times: [0, 10], now: 20))
        #expect(SystemFocusCueLimit.allows(times: [0, 10, 20], now: 30) == false)
        #expect(SystemFocusCueLimit.allows(times: [0, 10, 20], now: 30.001))
        #expect(SystemFocusCueLimit.allows(times: [0, 0, 0], now: 0) == false)
        #expect(SystemFocusCueLimit.window == 30)
        #expect(SystemFocusCueLimit.maximum == 3)
    }
}
