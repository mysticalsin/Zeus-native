import Testing
@testable import Zeus

@Suite("System source canary")
struct SystemSourceCanaryTests {
    @Test func aFreshStateShowsNothing() {
        let state = SystemSourceCanary.State()
        #expect(state.slot == nil)
        #expect(state.refusal == nil)
        let held = SystemSourceCanary.reduce(state, .hold(seconds: SystemSourceCanary.holdLimitSeconds))
        #expect(held.slot == nil)
        #expect(SystemSourceCanary.displayEffect(before: state, .hold(seconds: 3), after: held) == .none)
        let cleared = SystemSourceCanary.reduce(state, .clear)
        #expect(cleared == state)
        #expect(SystemSourceCanary.displayEffect(before: state, .clear, after: cleared) == .none)
    }

    @Test func anOpenPublishShowsZeusTheTokenAndPlaying() throws {
        let before = SystemSourceCanary.State()
        let command = SystemSourceCanary.Command.publish(token: "ab12", gates: .open)
        let after = SystemSourceCanary.reduce(before, command)
        let slot = try #require(after.slot)
        #expect(slot.title == SystemSourceCanary.title)
        #expect(slot.title == "Zeus")
        #expect(slot.album == "ab12")
        #expect(slot.playbackRate == SystemSourceCanary.playingRate)
        #expect(after.refusal == nil)
        #expect(SystemSourceCanary.displayEffect(before: before, command, after: after) == .show(slot))
    }

    @Test func lockedAsleepAndAnInactiveSessionEachPublishNothing() {
        let token = "abc"
        let locked = publish(token, gates: SystemSourceCanary.Gates(locked: true, asleep: false, sessionActive: true))
        #expect(locked.slot == nil)
        #expect(locked.refusal == .locked)
        #expect(effect(of: .publish(token: token, gates: SystemSourceCanary.Gates(locked: true, asleep: false, sessionActive: true)), from: locked) == .none)

        let asleep = publish(token, gates: SystemSourceCanary.Gates(locked: false, asleep: true, sessionActive: true))
        #expect(asleep.slot == nil)
        #expect(asleep.refusal == .asleep)

        let away = publish(token, gates: SystemSourceCanary.Gates(locked: false, asleep: false, sessionActive: false))
        #expect(away.slot == nil)
        #expect(away.refusal == .sessionInactive)
    }

    @Test func lockedWinsWhenTheOtherGatesFailToo() {
        let gates = SystemSourceCanary.Gates(locked: true, asleep: true, sessionActive: false)
        let state = publish("zz", gates: gates)
        #expect(state.refusal == .locked)
        #expect(state.slot == nil)

        let asleep = publish("zz", gates: SystemSourceCanary.Gates(locked: false, asleep: true, sessionActive: false))
        #expect(asleep.refusal == .asleep)
    }

    @Test func aTokenOutsideLowercaseHexPublishesNothing() {
        for token in ["", "ABC", "ab c", "g", "Zeus", "ab12\n"] {
            let state = publish(token)
            #expect(state.slot == nil, "token \(token)")
            #expect(state.refusal == .token, "token \(token)")
            #expect(SystemSourceCanary.slot(token: token) == nil)
        }
    }

    @Test func theTokenByteLimitIsTheHelperLineCap() {
        let full = String(repeating: "a", count: SystemSourceCanary.tokenByteLimit)
        let over = String(repeating: "b", count: SystemSourceCanary.tokenByteLimit + 1)
        let published = publish(full)
        #expect(published.slot?.album == full)
        #expect(published.slot?.title == "Zeus")
        let refused = publish(over)
        #expect(refused.slot == nil)
        #expect(refused.refusal == .token)
    }

    @Test func aSecondPublishKeepsTheFirstEntry() {
        let first = publish("aa")
        let command = SystemSourceCanary.Command.publish(token: "bb", gates: .open)
        let second = SystemSourceCanary.reduce(first, command)
        #expect(second.slot?.album == "aa")
        #expect(second.refusal == .alreadyPublished)
        #expect(SystemSourceCanary.displayEffect(before: first, command, after: second) == .none)

        let locked = SystemSourceCanary.Gates(locked: true, asleep: false, sessionActive: true)
        let duringLock = SystemSourceCanary.reduce(first, .publish(token: "cc", gates: locked))
        #expect(duringLock.slot?.album == "aa")
        #expect(duringLock.refusal == .alreadyPublished)
    }

    @Test func clearRemovesTheEntryEvenWhileLocked() {
        let up = publish("de")
        let cleared = SystemSourceCanary.reduce(up, .clear)
        #expect(cleared.slot == nil)
        #expect(cleared.refusal == nil)
        #expect(SystemSourceCanary.displayEffect(before: up, .clear, after: cleared) == .remove)
        let again = SystemSourceCanary.reduce(cleared, .clear)
        #expect(again == cleared)
        #expect(SystemSourceCanary.displayEffect(before: cleared, .clear, after: again) == .none)
    }

    @Test func twoSecondsKeepsTheEntryAndThreeSecondsClearsIt() {
        let up = publish("ff")
        let early = SystemSourceCanary.reduce(up, .hold(seconds: SystemSourceCanary.holdLimitSeconds - 1))
        #expect(early.slot?.album == "ff")
        #expect(SystemSourceCanary.displayEffect(before: up, .hold(seconds: 2), after: early) == .none)
        let due = SystemSourceCanary.reduce(up, .hold(seconds: SystemSourceCanary.holdLimitSeconds))
        #expect(due.slot == nil)
        #expect(SystemSourceCanary.displayEffect(before: up, .hold(seconds: 3), after: due) == .remove)
        let late = SystemSourceCanary.reduce(up, .hold(seconds: 4))
        #expect(late.slot == nil)
        let negative = SystemSourceCanary.reduce(up, .hold(seconds: -1))
        #expect(negative.slot?.album == "ff")
    }

    @Test func aPublishAfterClearOrHoldShowsTheNewToken() throws {
        let cleared = SystemSourceCanary.reduce(publish("11"), .clear)
        let again = SystemSourceCanary.reduce(cleared, .publish(token: "22", gates: .open))
        #expect(again.slot?.album == "22")
        #expect(again.slot?.title == "Zeus")
        #expect(again.refusal == nil)

        let held = SystemSourceCanary.reduce(publish("33"), .hold(seconds: 3))
        let next = SystemSourceCanary.reduce(held, .publish(token: "44", gates: .open))
        let shown = try #require(next.slot)
        #expect(shown == SystemSourceCanary.slot(token: "44"))
        #expect(SystemSourceCanary.displayEffect(before: held, .publish(token: "44", gates: .open), after: next) == .show(shown))
    }
}

private func publish(
    _ token: String,
    gates: SystemSourceCanary.Gates = .open
) -> SystemSourceCanary.State {
    SystemSourceCanary.reduce(.init(), .publish(token: token, gates: gates))
}

private func effect(
    of command: SystemSourceCanary.Command,
    from after: SystemSourceCanary.State
) -> SystemSourceCanary.DisplayEffect {
    SystemSourceCanary.displayEffect(before: .init(), command, after: after)
}
