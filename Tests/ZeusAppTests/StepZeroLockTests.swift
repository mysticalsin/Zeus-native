import Testing
@testable import Zeus

@Suite("Step zero lock")
struct StepZeroLockTests {
    @Test func aFakeHostThatFailsAttachLeavesNoWindow() {
        var trace = armed()
        let made = trace.step(.lock)
        #expect(made == [.makeSpace])
        let attached = trace.step(.host(.makeSpace, ok: true))
        #expect(attached == [.attach])
        #expect(trace.state.spaceUp)
        let failed = trace.step(.host(.attach, ok: false))
        #expect(failed == [.destroy, .close, .census])
        #expect(trace.state.windowUp == false)
        #expect(trace.state.spaceUp == false)
        #expect(trace.state.failedStep == .attach)
        #expect(trace.state.phase == .stopped)
        #expect(trace.effects.contains(.show) == false)
        #expect(trace.effects.contains(.hide) == false)
    }

    @Test func aFalseCallEndsThePartWithThatStep() {
        var missed = armed()
        _ = missed.step(.lock)
        let make = missed.step(.host(.makeSpace, ok: false))
        #expect(make.isEmpty)
        #expect(missed.state.failedStep == .makeSpace)
        #expect(missed.state.windowUp == false)
        #expect(missed.state.spaceUp == false)
        #expect(missed.effects.contains(.attach) == false)
        #expect(missed.effects.contains(.show) == false)

        var shown = armed()
        _ = shown.step(.lock)
        _ = shown.step(.host(.makeSpace, ok: true))
        _ = shown.step(.host(.attach, ok: true))
        let show = shown.step(.host(.show, ok: false))
        #expect(show == [.destroy, .close, .census])
        #expect(shown.state.failedStep == .show)
        #expect(shown.state.windowUp == false)
        #expect(shown.state.phase == .stopped)
    }

    @Test func unlockAlwaysDestroys() {
        var trace = shown()
        let again = trace.step(.lock)
        #expect(again.isEmpty)
        #expect(trace.effects.filter { $0 == .makeSpace }.count == 1)
        let out = trace.step(.unlockNotice)
        #expect(out == [.hide, .destroy, .close, .census])
        #expect(out.contains(.destroy))
        #expect(trace.state.wayOut == .unlock)
        #expect(trace.state.windowUp == false)
        #expect(trace.state.spaceUp == false)
        #expect(trace.state.phase == .done)
        let second = trace.step(.unlockNotice)
        #expect(second.isEmpty)
        #expect(trace.effects.filter { $0 == .destroy }.count == 1)

        var opening = armed()
        _ = opening.step(.lock)
        _ = opening.step(.host(.makeSpace, ok: true))
        let early = opening.step(.unlockNotice)
        #expect(early.contains(.destroy))
        #expect(early.contains(.show) == false)
        #expect(opening.state.windowUp == false)
    }

    @Test func theDictionaryPollDestroysWhenNoUnlockArrives() {
        var trace = shown()
        let still = trace.step(.dictionary(unlocked: false))
        #expect(still.isEmpty)
        #expect(trace.state.phase == .locked)
        #expect(trace.state.windowUp)
        let out = trace.step(.dictionary(unlocked: true))
        #expect(out == [.hide, .destroy, .close, .census])
        #expect(trace.state.wayOut == .dictionary)
        #expect(trace.state.windowUp == false)
        #expect(trace.events.contains(.unlockNotice) == false)
    }

    @Test func theHardLimitDestroysWhenNeitherWayCame() {
        #expect(LockSection.cardLimitSeconds == 120)
        #expect(LockSection.lookingLimitSeconds == 300)
        #expect(LockSection.pollMilliseconds == 100)

        var trace = shown()
        _ = trace.step(.dictionary(unlocked: false))
        let early = trace.step(.waited(seconds: LockSection.cardLimitSeconds - 1))
        #expect(early.isEmpty)
        #expect(trace.state.phase == .locked)
        #expect(trace.state.waited == 119)
        let due = trace.step(.waited(seconds: 1))
        #expect(due == [.hide, .destroy, .close, .census])
        #expect(trace.state.wayOut == .hardLimit)
        #expect(trace.state.windowUp == false)
        #expect(trace.events.contains(.unlockNotice) == false)
        #expect(trace.events.contains(.dictionary(unlocked: true)) == false)

        var looking = shown()
        _ = looking.step(.looking)
        let held = looking.step(.waited(seconds: LockSection.cardLimitSeconds))
        #expect(held.isEmpty)
        #expect(looking.state.phase == .locked)
        let looked = looking.step(.waited(seconds: LockSection.lookingLimitSeconds - LockSection.cardLimitSeconds))
        #expect(looked.last == .census)
        #expect(looking.state.wayOut == .hardLimit)
        #expect(looking.state.waited == LockSection.lookingLimitSeconds)

        var idle = Trace()
        _ = idle.step(.looking)
        #expect(idle.effects.contains(.makeSpace) == false)
        var negativeTrace = shown()
        _ = negativeTrace.step(.waited(seconds: 0))
        _ = negativeTrace.step(.waited(seconds: -3))
        #expect(negativeTrace.state.waited == 0)
        #expect(negativeTrace.state.phase == .locked)
    }

    @Test func aSessionResignedNoticeDestroys() {
        var resigned = shown()
        let out = resigned.step(.sessionResigned)
        #expect(out == [.hide, .destroy, .close, .census])
        #expect(resigned.state.wayOut == .sessionResigned)
        #expect(resigned.state.windowUp == false)
        #expect(resigned.events.contains(.unlockNotice) == false)

        var active = shown()
        let notice = active.step(.sessionActive)
        #expect(notice.contains(.destroy))
        #expect(notice.last == .census)
        #expect(active.state.wayOut == .sessionActive)
        #expect(active.state.windowUp == false)
    }

    @Test func noMakeSpaceDuringAnL6Transition() {
        for transition in LockSection.Transition.allCases {
            var ready = armed()
            let entered = ready.step(.transition(transition))
            #expect(entered.isEmpty)
            #expect(entered.contains(.makeSpace) == false)
            #expect(ready.state.phase == .timeline)
            #expect(ready.state.transition == transition)
            let locked = ready.step(.lock)
            #expect(locked.isEmpty)
            #expect(ready.effects.contains(.makeSpace) == false)

            var up = shown()
            let left = up.step(.transition(transition))
            #expect(left == [.hide, .destroy, .close, .census])
            #expect(left.contains(.makeSpace) == false)
            #expect(up.state.spaceUp == false)
            #expect(up.state.windowUp == false)
            #expect(up.state.phase == .timeline)
            let again = up.step(.lock)
            #expect(again.isEmpty)
            #expect(up.effects.filter { $0 == .makeSpace }.count == 1)
            let ended = up.step(.transitionEnded)
            #expect(ended.isEmpty)
            #expect(up.state.phase == .ready)
            let remade = up.step(.lock)
            #expect(remade == [.makeSpace])
        }
    }

    @Test func theKeyCounterStoresCountsOnly() {
        var early = armed()
        _ = early.step(.panel(.key))
        _ = early.step(.panel(.button))
        #expect(early.state.keys == LockSection.KeyCounter())

        var trace = shown()
        _ = trace.step(.panel(.key))
        _ = trace.step(.panel(.key))
        _ = trace.step(.panel(.key))
        _ = trace.step(.panel(.mouseDown))
        _ = trace.step(.panel(.mouseDown))
        _ = trace.step(.panel(.button))
        #expect(trace.state.keys.buttonActions == 1)
        #expect(trace.state.keys.mouseDowns == 2)
        #expect(trace.state.keys.keyEvents == 3)
        let labels = Mirror(reflecting: trace.state.keys).children.compactMap(\.label)
        #expect(labels == ["buttonActions", "mouseDowns", "keyEvents"])
        for child in Mirror(reflecting: trace.state.keys).children {
            #expect(child.value is Int)
        }
    }

    @Test func aRefusedNotRunningOrTimedOutPlayerGetsNoScript() {
        #expect(LockSection.Verb.allCases == [.playpause, .next, .previous])
        for check in [LockSection.Automation.refused, .notRunning, .timedOut] {
            var trace = players(music: check, spotify: .notRunning)
            _ = trace.step(.lock)
            _ = trace.step(.host(.makeSpace, ok: true))
            _ = trace.step(.host(.attach, ok: true))
            let showed = trace.step(.host(.show, ok: true))
            #expect(showed.isEmpty)
            _ = trace.step(.scriptAck(.music))
            _ = trace.step(.position(LockSection.nextNotBeforeSeconds + 9))
            _ = trace.step(.scriptAck(.music))
            _ = trace.step(.scriptAck(.spotify))
            #expect(trace.effects.contains { effect in
                if case .script = effect { return true }
                return false
            } == false)
            #expect(trace.state.scripts.isEmpty)
            #expect(trace.state.checks[.music] == check)
        }
    }

    @Test func automationIsReadBeforeTheFirstLock() {
        var idle = Trace()
        #expect(idle.step(.lock).isEmpty)
        #expect(idle.effects.contains(.makeSpace) == false)

        var trace = Trace()
        #expect(trace.step(.begin) == [.readAutomation(.music, asking: false)])
        let held = trace.step(.automation(.music, .notAsked))
        #expect(held.isEmpty)
        #expect(trace.state.phase == .asking(.music))
        #expect(trace.effects.contains(.makeSpace) == false)
        #expect(trace.step(.continueAsked) == [.readAutomation(.music, asking: true)])
        #expect(trace.step(.automation(.music, .allowed)) == [.readAutomation(.spotify, asking: false)])
        #expect(trace.step(.automation(.spotify, .timedOut)).isEmpty)
        #expect(trace.state.phase == .ready)
        #expect(trace.step(.lock) == [.makeSpace])
        _ = trace.step(.host(.makeSpace, ok: true))
        _ = trace.step(.host(.attach, ok: true))
        let showed = trace.step(.host(.show, ok: true))
        #expect(showed == [.script(.music, .playpause)])
        let read = trace.effects.firstIndex { effect in
            if case .readAutomation = effect { return true }
            return false
        }
        let made = trace.effects.firstIndex(of: .makeSpace)
        let script = trace.effects.firstIndex(of: .script(.music, .playpause))
        #expect(read != nil)
        #expect(made != nil)
        #expect(script != nil)
        #expect(read! < made!)
        #expect(made! < script!)
        #expect(trace.effects.contains(.script(.spotify, .playpause)) == false)

        #expect(trace.step(.scriptAck(.music)) == [.script(.music, .playpause)])
        #expect(trace.step(.position(LockSection.nextNotBeforeSeconds - 1)).isEmpty)
        #expect(trace.state.position == 20)
        #expect(trace.step(.position(LockSection.nextNotBeforeSeconds)) == [.script(.music, .next)])
        #expect(trace.step(.scriptAck(.music)) == [.script(.music, .previous)])
        #expect(trace.step(.scriptAck(.spotify)).isEmpty)
        #expect(LockSection.nextNotBeforeSeconds == 21)
    }

    @Test func theFirstWayOutWinsAndTheCensusIsLast() {
        var trace = shown()
        let out = trace.step(.unlockNotice)
        #expect(out.last == .census)
        let later = trace.step(.dictionary(unlocked: true))
        #expect(later.isEmpty)
        let limit = trace.step(.waited(seconds: LockSection.cardLimitSeconds))
        #expect(limit.isEmpty)
        let notice = trace.step(.sessionResigned)
        #expect(notice.isEmpty)
        #expect(trace.state.wayOut == .unlock)
        #expect(trace.effects.filter { $0 == .destroy }.count == 1)
        #expect(trace.effects.filter { $0 == .census }.count == 1)
    }
}

private struct Trace {
    var state = LockSection.fresh()
    var effects: [LockSection.Effect] = []
    var events: [LockSection.Event] = []

    mutating func step(_ event: LockSection.Event) -> [LockSection.Effect] {
        let (next, out) = LockSection.reduce(state, event)
        state = next
        effects.append(contentsOf: out)
        events.append(event)
        return out
    }
}

private func armed() -> Trace {
    players(music: .notRunning, spotify: .notRunning)
}

private func players(music: LockSection.Automation, spotify: LockSection.Automation) -> Trace {
    var trace = Trace()
    _ = trace.step(.begin)
    _ = trace.step(.automation(.music, music))
    if music == .notAsked {
        _ = trace.step(.continueAsked)
        _ = trace.step(.automation(.music, .refused))
    }
    _ = trace.step(.automation(.spotify, spotify))
    return trace
}

private func shown() -> Trace {
    var trace = armed()
    _ = trace.step(.lock)
    _ = trace.step(.host(.makeSpace, ok: true))
    _ = trace.step(.host(.attach, ok: true))
    _ = trace.step(.host(.show, ok: true))
    return trace
}
