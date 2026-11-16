import Foundation
import Testing
@testable import ZeusCore

/// The pair of talk keys (docs/RIGHT-OPTION-TALK-PLAN.md part 2): the primary key (Control-Option) and the second talk key
/// (Right Option), one turn at a time, in front of two unchanged `VoiceKeyMachine`s. The search in `VoiceKeyWalkTests` (runs
/// K and K0) holds the rules over every order; these hold the exact effects of the orders the plan names.
@Suite struct TalkKeyPairTests {
    typealias Config = VoiceKeyMachine.Config
    typealias Effect = VoiceKeyMachine.Effect

    static let ctrl: UInt16 = 59, optL: UInt16 = 58, optR: UInt16 = 61, space: UInt16 = 49, letter: UInt16 = 8
    static let primary = Config(key: .controlOption, role: .talk, mode: .hold, confirm: 0.15, chord: 49)
    static let rightOption = Config(key: .rightOption, role: .talk, mode: .hold, confirm: 0.25)
    static let off = Config(key: nil, role: .talk, mode: .hold)

    /// A keyboard in front of the pair (or, for the equivalence test, in front of one bare machine), with the wakes kept
    /// as the adapter keeps them.
    final class Rig {
        var pair = TalkKeyPair()
        var machine: VoiceKeyMachine?
        var primary = TalkKeyPairTests.primary
        var second: Config
        var down: Set<UInt16> = []
        var wakes: [TimeInterval] = []
        var now: TimeInterval = 0
        var log: [Effect] = []

        init(second: Config = TalkKeyPairTests.rightOption, machineOnly: Bool = false) {
            self.second = second
            if machineOnly { machine = VoiceKeyMachine() }
        }

        /// Every effect so far, without the wakes.
        var effects: [Effect] { log.filter { if case .wake = $0 { return false } else { return true } } }
        var mods: ShortcutModifiers {
            down.reduce(into: ShortcutModifiers()) { $0.formUnion(ShortcutModifiers.modifier(forKeyCode: $1) ?? []) }
        }

        @discardableResult func feed(_ event: VoiceKeyMachine.Event) -> [Effect] {
            switch event {
            case .key(_, let at), .tick(let at, _): now = at
            case .abandon, .interrupt, .sweep: break
            }
            let out: [Effect]
            if machine != nil { out = machine!.handle(event, config: primary) } else { out = pair.handle(event, primary: primary, second: second) }
            log += out
            for case .wake(let after) in out { wakes.append(now + after) }
            return out
        }
        func wait(until t: TimeInterval) {
            while let due = wakes.filter({ $0 <= t }).min(), let index = wakes.firstIndex(of: due) {
                wakes.remove(at: index)
                feed(.tick(at: due, live: mods))
            }
            now = max(now, t)
        }
        func press(_ codes: UInt16..., at t: TimeInterval) {
            for code in codes {
                down.insert(code)
                feed(.key(.flags(keyCode: code, modifiers: mods), at: t))
            }
        }
        func release(_ codes: UInt16..., at t: TimeInterval) {
            for code in codes {
                down.remove(code)
                feed(.key(.flags(keyCode: code, modifiers: mods), at: t))
            }
        }
        func type(_ code: UInt16, at t: TimeInterval) { feed(.key(.keyDown(keyCode: code, modifiers: mods), at: t)) }
        func untype(_ code: UInt16, at t: TimeInterval) { feed(.key(.keyUp(keyCode: code), at: t)) }
        func tick(at t: TimeInterval) { feed(.tick(at: t, live: mods)) }
        /// The owner ends the turn it was given last, as `HotkeyMonitor.turnEnded` does.
        func abandon(turn: Int? = nil) { feed(.abandon(turn: turn ?? machine?.generation ?? pair.generation)) }
        func interrupt() { feed(.interrupt(live: mods)) }
        /// A mouse button goes down (the owner's decision: it cancels the second key's turn, armed or open).
        func mouse(at t: TimeInterval) {
            now = t
            let out = pair.mouseDown(at: t, primary: primary, second: second)
            log += out
            for case .wake(let after) in out { wakes.append(t + after) }
        }
    }

    // MARK: Without a second key

    @Test func aPairWithNoSecondKeyGivesTheMachinesEffects() {
        func script(_ rig: Rig) {
            // A hold, a quick tap and its gap, a double tap that goes hands-free and is ended, the chord, a typed key.
            rig.press(Self.ctrl, Self.optL, at: 0); rig.wait(until: 0.5); rig.release(Self.optL, Self.ctrl, at: 0.6)
            rig.press(Self.ctrl, Self.optL, at: 2); rig.release(Self.optL, Self.ctrl, at: 2.1); rig.wait(until: 3)
            rig.press(Self.ctrl, Self.optL, at: 4); rig.release(Self.optL, Self.ctrl, at: 4.1)
            rig.press(Self.ctrl, Self.optL, at: 4.2); rig.release(Self.optL, Self.ctrl, at: 4.3); rig.wait(until: 5)
            rig.press(Self.ctrl, Self.optL, at: 6); rig.wait(until: 6.5); rig.release(Self.optL, Self.ctrl, at: 6.6)
            rig.press(Self.ctrl, Self.optL, at: 8); rig.wait(until: 8.3); rig.type(Self.space, at: 8.4)
            rig.untype(Self.space, at: 8.5); rig.release(Self.optL, Self.ctrl, at: 8.6)
            rig.press(Self.ctrl, Self.optL, at: 10); rig.wait(until: 10.3); rig.type(Self.letter, at: 10.4)
            rig.untype(Self.letter, at: 10.5); rig.release(Self.optL, Self.ctrl, at: 10.6); rig.wait(until: 12)
            rig.press(Self.optR, at: 13); rig.wait(until: 14); rig.release(Self.optR, at: 14.1); rig.wait(until: 15)
            rig.interrupt(); rig.press(Self.ctrl, Self.optL, at: 16); rig.wait(until: 16.5); rig.abandon(); rig.interrupt()
        }
        let bare = Rig(second: Self.off, machineOnly: true)
        let pair = Rig(second: Self.off)
        script(bare)
        script(pair)
        #expect(!bare.effects.isEmpty)
        #expect(pair.log == bare.log)
        #expect(pair.pair.generation == bare.machine?.generation)
        #expect(pair.pair.strays == 0)
    }

    // MARK: The second key alone

    @Test func rightOptionHeldPastTheConfirmStartsOneTurnAndReleaseSends() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.2)
        #expect(rig.effects == [], "nothing before the quarter second")
        rig.wait(until: 0.5)
        #expect(rig.effects == [.start])
        #expect(rig.pair.owner == .second)
        rig.release(Self.optR, at: 0.6)
        #expect(rig.effects == [.start, .send])
        #expect(rig.pair.owner == nil)
        #expect(rig.pair.generation == 1)
        #expect(rig.pair.strays == 0)
    }

    @Test func rightOptionWithALetterInsideTheConfirmStartsNothing() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.type(Self.letter, at: 0.1)
        rig.wait(until: 0.6)
        rig.untype(Self.letter, at: 0.7)
        rig.release(Self.optR, at: 0.8)
        rig.wait(until: 1.5)
        #expect(rig.effects == [], "an accent typed at speed opens no microphone")
        // Everything is up: the next press acts.
        rig.press(Self.optR, at: 2)
        rig.wait(until: 2.5)
        rig.release(Self.optR, at: 2.6)
        #expect(rig.effects == [.start, .send])
    }

    @Test func rightOptionHeldThenALetterCancelsAndNeverSends() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.4)
        rig.type(Self.letter, at: 0.5)
        rig.untype(Self.letter, at: 0.55)
        rig.wait(until: 1)
        rig.release(Self.optR, at: 1.1)
        rig.wait(until: 2)
        #expect(rig.effects == [.start, .cancel])
        #expect(rig.pair.owner == nil)
    }

    @Test func leftOptionNeverStarts() {
        let rig = Rig()
        rig.press(Self.optL, at: 0)
        rig.wait(until: 1)
        rig.release(Self.optL, at: 1.1)
        rig.press(Self.optL, at: 2)
        rig.type(Self.letter, at: 2.4)
        rig.release(Self.optL, at: 2.6)
        rig.wait(until: 4)
        #expect(rig.effects == [], "Left Option alone, or with a letter, never talks")
        #expect(rig.pair.generation == 0)
    }

    @Test func leftOptionJoiningARightOptionTurnCancelsIt() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.4)
        rig.press(Self.optL, at: 0.5)
        rig.wait(until: 1)
        rig.release(Self.optL, at: 1.1)
        rig.release(Self.optR, at: 1.2)
        rig.wait(until: 2)
        #expect(rig.effects == [.start, .cancel])
    }

    @Test func rightOptionWithSpaceIsForeign() {
        let early = Rig()
        early.press(Self.optR, at: 0)
        early.type(Self.space, at: 0.1)
        early.wait(until: 0.8)
        early.untype(Self.space, at: 0.9)
        early.release(Self.optR, at: 1)
        early.wait(until: 2)
        #expect(early.effects == [], "Space inside the confirm drops the press")
        let late = Rig()
        late.press(Self.optR, at: 0)
        late.wait(until: 0.4)
        late.type(Self.space, at: 0.5)
        late.release(Self.optR, at: 0.6)
        late.wait(until: 2)
        #expect(late.effects == [.start, .cancel], "Space after the start cancels it, the second key has no chord")
    }

    // MARK: Both keys

    @Test func controlThenRightOptionIsThePrimaryTurnOnly() {
        let rig = Rig()
        rig.press(Self.ctrl, at: 0)
        rig.press(Self.optR, at: 0.05)
        rig.wait(until: 0.8)
        #expect(rig.effects == [.start])
        #expect(rig.pair.owner == .primary)
        rig.release(Self.optR, at: 0.9)
        rig.release(Self.ctrl, at: 1)
        rig.wait(until: 2)
        #expect(rig.effects == [.start, .send])
        #expect(rig.pair.generation == 1)
    }

    @Test func rightOptionThenControlInsideTheConfirmIsThePrimaryTurnOnly() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.press(Self.ctrl, at: 0.1)
        rig.wait(until: 0.8)
        #expect(rig.effects == [.start])
        #expect(rig.pair.owner == .primary)
        rig.release(Self.ctrl, at: 0.9)
        rig.release(Self.optR, at: 1)
        rig.wait(until: 2)
        #expect(rig.effects == [.start, .send])
        #expect(rig.pair.generation == 1)
    }

    @Test func rightOptionHeldThenControlCancelsAndStartsNothingUntilAllUp() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.4)
        rig.press(Self.ctrl, at: 0.5)
        rig.wait(until: 1.5)
        #expect(rig.effects == [.start, .cancel], "the second turn is cancelled and the primary start is swallowed")
        #expect(rig.pair.owner == nil)
        rig.release(Self.ctrl, at: 1.6)
        rig.press(Self.ctrl, at: 1.7)
        rig.wait(until: 2.5)
        #expect(rig.effects == [.start, .cancel], "the other key waits while any key is down")
        rig.release(Self.ctrl, at: 2.6)
        rig.release(Self.optR, at: 2.7)
        rig.wait(until: 3.5)
        rig.press(Self.optR, at: 4)
        rig.wait(until: 4.5)
        rig.release(Self.optR, at: 4.6)
        #expect(rig.effects == [.start, .cancel, .start, .send], "once every key is up the key acts again")
        #expect(rig.pair.strays == 0)
    }

    @Test func rightOptionDuringAPrimaryTurnChangesNothing() {
        let rig = Rig()
        rig.press(Self.ctrl, Self.optL, at: 0)
        rig.wait(until: 0.3)
        rig.press(Self.optR, at: 0.4)
        rig.wait(until: 1.5)
        rig.release(Self.optR, at: 1.6)
        rig.wait(until: 2)
        #expect(rig.effects == [.start], "Right Option joining or leaving the held pair does nothing")
        rig.release(Self.optL, Self.ctrl, at: 2.1)
        #expect(rig.effects == [.start, .send])
        #expect(rig.pair.generation == 1)
    }

    @Test func rightOptionDoesNotEndAPrimaryHandsFreeTurn() {
        let rig = Rig()
        rig.press(Self.ctrl, Self.optL, at: 0); rig.release(Self.optL, Self.ctrl, at: 0.1)
        rig.press(Self.ctrl, Self.optL, at: 0.2); rig.release(Self.optL, Self.ctrl, at: 0.3)
        rig.wait(until: 1)
        #expect(rig.effects == [.start])
        #expect(rig.pair.isLatched)
        rig.press(Self.optR, at: 1.5)
        rig.wait(until: 2.5)
        rig.release(Self.optR, at: 2.6)
        rig.wait(until: 3)
        #expect(rig.effects == [.start], "Right Option neither ends nor adds a turn")
        #expect(rig.pair.isLatched)
        rig.press(Self.ctrl, Self.optL, at: 4)
        rig.wait(until: 4.5)
        rig.release(Self.optL, Self.ctrl, at: 4.6)
        #expect(rig.effects == [.start, .send], "the key that opened it ends it")
    }

    @Test func controlOptionDoesNotEndASecondHandsFreeTurn() {
        let rig = Rig()
        rig.press(Self.optR, at: 0); rig.release(Self.optR, at: 0.1)
        rig.press(Self.optR, at: 0.2); rig.release(Self.optR, at: 0.3)
        rig.wait(until: 1)
        #expect(rig.effects == [.start])
        #expect(rig.pair.isLatched)
        rig.press(Self.ctrl, Self.optL, at: 1.5)
        rig.wait(until: 2.5)
        rig.release(Self.optL, Self.ctrl, at: 2.6)
        rig.wait(until: 3)
        #expect(rig.effects == [.start], "Control-Option neither ends nor adds a turn")
        #expect(rig.pair.isLatched)
        rig.press(Self.optR, at: 4)
        rig.wait(until: 4.5)
        rig.release(Self.optR, at: 4.6)
        #expect(rig.effects == [.start, .send], "the key that opened it ends it")
    }

    @Test func doubleTapRightOptionLatchesAndTheNextPressEndsIt() {
        let rig = Rig()
        rig.press(Self.optR, at: 0); rig.release(Self.optR, at: 0.1)
        rig.press(Self.optR, at: 0.2); rig.release(Self.optR, at: 0.3)
        rig.wait(until: 1)
        #expect(rig.effects == [.start])
        #expect(rig.pair.isLatched)
        #expect(rig.pair.owner == .second)
        rig.press(Self.optR, at: 2)
        rig.wait(until: 2.5)
        rig.release(Self.optR, at: 2.6)
        rig.wait(until: 3)
        #expect(rig.effects == [.start, .send])
        #expect(!rig.pair.isLatched)
        #expect(rig.pair.owner == nil)
    }

    @Test func aStartFromTheOtherKeyNeverReachesTheOwner() {
        // A hands-free turn on Right Option; Control-Option is held: its machine would start, the pair says nothing.
        let rig = Rig()
        rig.press(Self.optR, at: 0); rig.release(Self.optR, at: 0.1)
        rig.press(Self.optR, at: 0.2); rig.release(Self.optR, at: 0.3)
        rig.press(Self.ctrl, Self.optL, at: 1)
        rig.wait(until: 3)
        #expect(rig.effects.filter { $0 == .start }.count == 1)
        #expect(rig.pair.generation == 1, "one turn is open, so one start was counted")
        // And the other way round: a primary hands-free turn, Right Option held.
        let back = Rig()
        back.press(Self.ctrl, Self.optL, at: 0); back.release(Self.optL, Self.ctrl, at: 0.1)
        back.press(Self.ctrl, Self.optL, at: 0.2); back.release(Self.optL, Self.ctrl, at: 0.3)
        back.press(Self.optR, at: 1)
        back.wait(until: 3)
        #expect(back.effects.filter { $0 == .start }.count == 1)
        #expect(back.pair.generation == 1)
        // Beside a held primary turn too.
        let held = Rig()
        held.press(Self.ctrl, Self.optL, at: 0)
        held.wait(until: 0.5)
        held.press(Self.optR, at: 0.6)
        held.wait(until: 2)
        #expect(held.effects.filter { $0 == .start }.count == 1)
        #expect(held.pair.generation == 1)
    }

    @Test func theOwnersAbandonEndsOnlyItsTurn() {
        let rig = Rig()
        rig.press(Self.optR, at: 0); rig.release(Self.optR, at: 0.1)
        rig.press(Self.optR, at: 0.2); rig.release(Self.optR, at: 0.3)
        rig.wait(until: 1)
        #expect(rig.pair.owner == .second)
        rig.abandon(turn: 1)
        #expect(rig.pair.owner == nil)
        #expect(!rig.pair.isLatched)
        // Nothing was sent or cancelled by the abandon, and the next press starts a new turn.
        rig.press(Self.optR, at: 2)
        rig.wait(until: 2.5)
        #expect(rig.effects == [.start, .start])
        #expect(rig.pair.generation == 2)
        // The other key's machine had no turn, so its picture of a turn is not touched: a primary hold still starts.
        rig.release(Self.optR, at: 2.6)
        rig.press(Self.ctrl, Self.optL, at: 4)
        rig.wait(until: 4.5)
        #expect(rig.pair.owner == .primary)
        rig.abandon(turn: 3)
        #expect(rig.pair.owner == nil)
        rig.release(Self.optL, Self.ctrl, at: 4.6)
        #expect(rig.effects == [.start, .start, .send, .start])
    }

    @Test func anAbandonOfAnOldTurnIsIgnored() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.5)
        rig.release(Self.optR, at: 0.6)
        rig.press(Self.ctrl, Self.optL, at: 2)
        rig.wait(until: 2.5)
        #expect(rig.pair.owner == .primary)
        #expect(rig.pair.generation == 2)
        rig.abandon(turn: 1)
        #expect(rig.pair.owner == .primary, "the echo of the first turn does not end the second")
        rig.release(Self.optL, Self.ctrl, at: 2.6)
        #expect(rig.effects == [.start, .send, .start, .send])
    }

    @Test func turningTheSecondKeyOffMidHoldCancelsItsTurn() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.4)
        #expect(rig.effects == [.start])
        rig.second = Self.off
        rig.tick(at: 0.5)
        #expect(rig.effects == [.start, .cancel])
        #expect(rig.pair.owner == nil)
        rig.release(Self.optR, at: 0.6)
        rig.wait(until: 1.5)
        #expect(rig.effects == [.start, .cancel], "nothing is sent for it after")
    }

    @Test func changingThePrimaryKeyLeavesASecondTurnAlone() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.4)
        rig.primary = Config(key: .function, role: .talk, mode: .hold, confirm: 0)
        rig.tick(at: 0.5)
        rig.wait(until: 1)
        #expect(rig.effects == [.start])
        #expect(rig.pair.owner == .second)
        rig.release(Self.optR, at: 1.1)
        #expect(rig.effects == [.start, .send])
    }

    @Test func sleepCancelsTheOpenTurnOnce() {
        let second = Rig()
        second.press(Self.optR, at: 0)
        second.wait(until: 0.4)
        second.feed(.interrupt(live: [.option]))
        #expect(second.effects == [.start, .cancel])
        #expect(second.pair.owner == nil)
        let primary = Rig()
        primary.press(Self.ctrl, Self.optL, at: 0)
        primary.wait(until: 0.4)
        primary.feed(.interrupt(live: [.control, .option]))
        #expect(primary.effects == [.start, .cancel])
        #expect(primary.pair.owner == nil)
        #expect(second.pair.strays == 0 && primary.pair.strays == 0)
    }

    @Test func bothMachinesKeepOnePicture() {
        let rig = Rig()
        func same(_ note: String) { #expect(rig.pair.primary.keys == rig.pair.second.keys, "\(note)") }
        rig.press(Self.optR, at: 0); same("Right Option")
        rig.press(Self.ctrl, at: 0.1); same("Control joins")
        rig.type(Self.letter, at: 0.2); same("a letter")
        rig.untype(Self.letter, at: 0.3); same("the letter up")
        rig.press(Self.optL, at: 0.4); same("Left Option")
        rig.release(Self.optR, at: 0.5); same("Right Option up")
        rig.type(Self.space, at: 0.6); same("Space")
        rig.release(Self.ctrl, Self.optL, at: 0.7); same("the rest up")
        #expect(rig.pair.keys == rig.pair.primary.keys)
    }

    // MARK: Timers that fall due before a key, across both machines (review of the pair, major 1)

    /// The same keys with the main thread busy: no timer runs until the end, so every wake that fell due is still owed when the
    /// next key arrives. The effects must be those of the timers running on time.
    private func run(_ rig: Rig, late: Bool, _ steps: [(Double, Bool, [UInt16])]) {
        for (time, down, codes) in steps {
            if !late { rig.wait(until: time) }
            for code in codes {
                if code == Self.letter {
                    if down { rig.type(code, at: time) } else { rig.untype(code, at: time) }
                } else if down {
                    rig.press(code, at: time)
                } else {
                    rig.release(code, at: time)
                }
            }
        }
        rig.wait(until: (steps.last?.0 ?? 0) + 3)
    }

    @Test func aGapSendDueBeforeTheSecondKeyStartsIsDeliveredAheadOfItsRelease() {
        // Control-Option held 0.1 s and let go at once (no confirm: a turn is open for the 0.4 s gap, due at 0.5). Right Option goes down
        // at 0.2 (its start is due at 0.45) and up at 0.6, with the main thread busy meanwhile.
        let steps: [(Double, Bool, [UInt16])] = [(0, true, [Self.ctrl, Self.optL]), (0.1, false, [Self.optL, Self.ctrl]),
                                                  (0.2, true, [Self.optR]), (0.6, false, [Self.optR])]
        let onTime = Rig(), late = Rig()
        onTime.primary = Config(key: .controlOption, role: .talk, mode: .hold, confirm: 0)
        late.primary = onTime.primary
        run(onTime, late: false, steps)
        run(late, late: true, steps)
        #expect(onTime.effects == [.start, .send], "on time: the second key's start is swallowed, the gap sends once")
        #expect(late.effects == onTime.effects, "late: \(late.effects)")
    }

    @Test func aSecondStartDueBeforeTheControlKeyActsFirstWhateverTheLateOrder() {
        // Control-Option with no confirm starts at the press. Right Option held from 0 (its start is due at 0.25), Control at 0.3.
        let steps: [(Double, Bool, [UInt16])] = [(0, true, [Self.optR]), (0.3, true, [Self.ctrl]), (0.5, false, [Self.ctrl, Self.optR])]
        let onTime = Rig(), late = Rig()
        onTime.primary = Config(key: .controlOption, role: .talk, mode: .hold, confirm: 0)
        late.primary = onTime.primary
        run(onTime, late: false, steps)
        run(late, late: true, steps)
        #expect(onTime.effects == [.start, .cancel], "on time: Right Option starts, Control cancels it, nothing starts until all up")
        #expect(late.effects == onTime.effects, "late: \(late.effects)")
        #expect(late.pair.owner == nil)
    }

    @Test func aGapSendThatSettlesOnTheSecondKeyDownDoesNotBarASecondPressThatCameAfterIt() {
        // The gap send is due at 0.5. Right Option goes down at 0.6, after it in real time, so nothing was down when the turn ended.
        let steps: [(Double, Bool, [UInt16])] = [(0, true, [Self.ctrl, Self.optL]), (0.1, false, [Self.optL, Self.ctrl]),
                                                  (0.6, true, [Self.optR]), (1.2, false, [Self.optR])]
        let onTime = Rig(), late = Rig()
        onTime.primary = Config(key: .controlOption, role: .talk, mode: .hold, confirm: 0)
        late.primary = onTime.primary
        run(onTime, late: false, steps)
        run(late, late: true, steps)
        #expect(onTime.effects == [.start, .send, .start, .send], "on time: the second press starts after its confirm")
        #expect(late.effects == onTime.effects, "late: \(late.effects)")
    }

    /// Every short order of the keys at a few times, with the timers on time and with them all late: the same effects.
    @Test func timersThatRunLateGiveTheEffectsOfTimersThatRunOnTime() {
        let keys: [UInt16] = [Self.ctrl, Self.optL, Self.optR, Self.letter]
        let gaps: [Double] = [0.1, 0.3, 0.5]
        var problems: [String] = []
        var scripts = 0
        func build(_ depth: Int, _ steps: [(Double, Bool, [UInt16])], _ time: Double, _ down: Set<UInt16>) {
            if depth == 4 {
                scripts += 1
                for confirm in [0.0, 0.15] where problems.count < 5 {
                    let onTime = Rig(), late = Rig()
                    onTime.primary = Config(key: .controlOption, role: .talk, mode: .hold, confirm: confirm, chord: 49)
                    late.primary = onTime.primary
                    run(onTime, late: false, steps)
                    run(late, late: true, steps)
                    if onTime.effects != late.effects || late.pair.strays != 0 {
                        problems.append("confirm \(confirm), \(steps): on time \(onTime.effects), late \(late.effects)")
                    }
                }
                return
            }
            for key in keys {
                for gap in gaps {
                    var next = down
                    let pressing = !next.contains(key)
                    if pressing { next.insert(key) } else { next.remove(key) }
                    build(depth + 1, steps + [(time + gap, pressing, [key])], time + gap, next)
                }
            }
        }
        build(0, [], 0, [])
        #expect(scripts == 20_736)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    // MARK: The mouse (owner decision, review of the pair, minor b)

    @Test func rightOptionHeldPastTheConfirmThenAMouseDownCancelsAndNeverSends() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.wait(until: 0.5)
        rig.mouse(at: 0.6)
        rig.wait(until: 1)
        rig.release(Self.optR, at: 1.1)
        rig.wait(until: 2)
        #expect(rig.effects == [.start, .cancel], "an Option-click or Option-drag is not a talk turn: \(rig.effects)")
        #expect(rig.pair.owner == nil)
        // Nothing starts until every key is up, then the key acts again.
        rig.press(Self.optR, at: 3)
        rig.wait(until: 3.5)
        rig.release(Self.optR, at: 3.6)
        #expect(rig.effects == [.start, .cancel, .start, .send])
    }

    @Test func aMouseDownInsideTheConfirmDropsThePress() {
        let rig = Rig()
        rig.press(Self.optR, at: 0)
        rig.mouse(at: 0.1)
        rig.wait(until: 1)
        rig.release(Self.optR, at: 1.1)
        rig.wait(until: 2)
        #expect(rig.effects == [], "nothing started, nothing to cancel: \(rig.effects)")
        rig.press(Self.optR, at: 3)
        rig.wait(until: 3.5)
        rig.release(Self.optR, at: 3.6)
        #expect(rig.effects == [.start, .send], "once every key is up the key acts again")
    }

    @Test func aMouseDownLeavesThePrimaryKeyAndAHandsFreeSecondTurnAlone() {
        let primary = Rig()
        primary.press(Self.ctrl, Self.optL, at: 0)
        primary.wait(until: 0.5)
        primary.mouse(at: 0.6)
        primary.release(Self.optL, Self.ctrl, at: 0.7)
        #expect(primary.effects == [.start, .send], "Control-Option is unchanged: \(primary.effects)")
        let handsFree = Rig()
        handsFree.press(Self.optR, at: 0); handsFree.release(Self.optR, at: 0.1)
        handsFree.press(Self.optR, at: 0.2); handsFree.release(Self.optR, at: 0.3)
        handsFree.mouse(at: 1)
        handsFree.wait(until: 2)
        #expect(handsFree.effects == [.start] && handsFree.pair.isLatched, "a click during a hands-free turn is not Option-click")
    }
}
