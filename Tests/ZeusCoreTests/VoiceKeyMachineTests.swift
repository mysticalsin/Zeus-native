import Foundation
import Testing
@testable import ZeusCore

/// The voice key machine, row by row of the transition table in docs/VOICE-KEY-MACHINE-PLAN.md part 4.3, then the press
/// orders the reviews found and each behaviour the plan changes on purpose (C1 to C18). The search in
/// `VoiceKeyWalkTests` holds the rules over every order; these hold the exact effects of the ones worth naming.
@Suite struct VoiceKeyMachineTests {
    typealias Machine = VoiceKeyMachine
    typealias Config = VoiceKeyMachine.Config
    typealias Effect = VoiceKeyMachine.Effect

    static let ctrl: UInt16 = 59, opt: UInt16 = 58, shift: UInt16 = 56, cmdL: UInt16 = 55, cmdR: UInt16 = 54, fn: UInt16 = 63
    static let left: UInt16 = 123, space: UInt16 = 49, c: UInt16 = 8

    /// A keyboard in front of one machine: modifier keys and ordinary keys at the times the test gives.
    struct Rig {
        var machine = Machine()
        var config: Config
        var down: Set<UInt16> = []
        var log: [Effect] = []
        /// When the machine asked to be woken, as the adapter would keep them.
        var wakes: [TimeInterval] = []
        var now: TimeInterval = 0

        init(_ config: Config) { self.config = config }

        var mods: ShortcutModifiers {
            down.reduce(into: ShortcutModifiers()) { $0.formUnion(ShortcutModifiers.modifier(forKeyCode: $1) ?? []) }
        }
        var tag: String { machine.tag }

        @discardableResult mutating func feed(_ event: Machine.Event) -> [Effect] {
            switch event {
            case .key(_, let at), .tick(let at, _): now = at
            case .abandon, .interrupt, .sweep: break
            }
            let effects = machine.handle(event, config: config)
            log += effects
            for case .wake(let after) in effects { wakes.append(now + after) }
            return effects
        }
        /// Lets time pass: every wake that falls due by `t` is delivered, in order, with the modifiers really down.
        mutating func wait(until t: TimeInterval) {
            while let due = wakes.filter({ $0 <= t }).min(), let index = wakes.firstIndex(of: due) {
                wakes.remove(at: index)
                feed(.tick(at: due, live: mods))
            }
            now = max(now, t)
        }
        @discardableResult mutating func press(_ codes: UInt16..., at t: TimeInterval) -> [Effect] {
            var out: [Effect] = []
            for code in codes {
                down.insert(code)
                out += feed(.key(.flags(keyCode: code, modifiers: mods), at: t))
            }
            return out
        }
        @discardableResult mutating func release(_ codes: UInt16..., at t: TimeInterval) -> [Effect] {
            var out: [Effect] = []
            for code in codes {
                down.remove(code)
                out += feed(.key(.flags(keyCode: code, modifiers: mods), at: t))
            }
            return out
        }
        /// An ordinary key goes down with the modifiers held, plus whatever flag it carries itself.
        @discardableResult mutating func type(_ code: UInt16, carrying extra: ShortcutModifiers = [], at t: TimeInterval) -> [Effect] {
            feed(.key(.keyDown(keyCode: code, modifiers: mods.union(extra)), at: t))
        }
        @discardableResult mutating func untype(_ code: UInt16, at t: TimeInterval) -> [Effect] {
            feed(.key(.keyUp(keyCode: code), at: t))
        }
        @discardableResult mutating func tick(at t: TimeInterval, live: ShortcutModifiers? = nil) -> [Effect] {
            feed(.tick(at: t, live: live ?? mods))
        }
        /// The owner ends a turn: the latest one the machine started unless the test names another.
        @discardableResult mutating func abandon(turn: Int? = nil) -> [Effect] { feed(.abandon(turn: turn ?? machine.generation)) }
        /// The adapter asks the system which ordinary keys are down, and tells the machine.
        @discardableResult mutating func sweep(live: Set<UInt16> = []) -> [Effect] { feed(.sweep(live: live)) }
        @discardableResult mutating func interrupt(live: ShortcutModifiers? = nil) -> [Effect] {
            feed(.interrupt(live: live ?? mods))
        }
        /// A quick tap of a whole key: down, then up `length` later.
        mutating func tap(_ codes: [UInt16], at t: TimeInterval, length: TimeInterval = 0.125) {
            for code in codes { press(code, at: t) }
            for code in codes.reversed() { release(code, at: t + length) }
        }
    }

    // MARK: Configs

    static func talk(confirm: TimeInterval = 0) -> Config {
        Config(key: .controlOption, role: .talk, mode: .hold, confirm: confirm)
    }
    static func dictation(confirm: TimeInterval = 0) -> Config {
        Config(key: .rightCommand, role: .dictation, mode: .hold, confirm: confirm)
    }
    static func dictationOnControlOption(confirm: TimeInterval = 0) -> Config {
        Config(key: .controlOption, role: .dictation, mode: .hold, confirm: confirm)
    }
    static let sharedDictation = Config(key: .controlOption, role: .dictation, mode: .shared)
    static let sharedTalk = Config(key: .controlOption, role: .talk, mode: .shared)
    static func sharedTalk(confirm: TimeInterval) -> Config {
        Config(key: .controlOption, role: .talk, mode: .shared, confirm: confirm)
    }
    static let toggle = Config(key: .rightCommand, role: .dictation, mode: .toggle)

    static let pair: [UInt16] = [ctrl, opt]

    /// A talk rig in hands-free: two quick taps, a turn open and the key up.
    static func latchedTalk(confirm: TimeInterval = 0) -> Rig {
        var rig = Rig(talk(confirm: confirm))
        rig.tap(pair, at: 0)
        rig.tap(pair, at: 0.25)
        return rig
    }

    // MARK: Row 1 and 2: the press that does not open a turn

    @Test func row1VoiceOverRefusesAPressOncePerPressInEveryMode() {
        for mode in [Machine.Mode.hold, .shared, .toggle] {
            var rig = Rig(Config(key: .controlOption, role: .talk, mode: mode, voiceOverHoldsKey: true))
            #expect(rig.press(Self.ctrl, Self.opt, at: 0) == [.refused], "mode \(mode)")
            #expect(rig.tag == "spent")
            #expect(rig.press(Self.shift, at: 0.125) == [], "the refusal is not repeated by the next key")
            #expect(rig.release(Self.shift, Self.opt, Self.ctrl, at: 0.25) == [])
            #expect(rig.press(Self.ctrl, Self.opt, at: 1) == [.refused], "a new press is refused again")
        }
    }

    @Test func row2AToggleFiresAtThePressAndOpensNoTurn() {
        var rig = Rig(Self.toggle)
        #expect(rig.press(Self.cmdR, at: 0) == [.start])
        #expect(rig.tag == "spent")
        #expect(rig.release(Self.cmdR, at: 0.5) == [])
        #expect(rig.tag == "idle")
        #expect(rig.press(Self.cmdR, at: 1) == [.start], "the next press fires again")
    }

    // MARK: Rows 3 to 5: beginning a press

    @Test func row3AHoldKeyWithNoConfirmStartsAtOnceAndAsksForACheck() {
        var rig = Rig(Self.talk())
        #expect(rig.press(Self.ctrl, at: 0) == [])
        #expect(rig.press(Self.opt, at: 0.125) == [.start, .wake(after: 0.25)])
        #expect(rig.tag == "holding")
    }

    @Test func row4WaitsOutTheConfirmTheDelayOrNothing() {
        var hold = Rig(Self.talk(confirm: 0.15))
        #expect(hold.press(Self.ctrl, Self.opt, at: 0) == [.wake(after: 0.15)])
        #expect(hold.tag == "armed first")
        var dictation = Rig(Self.sharedDictation)
        #expect(dictation.press(Self.ctrl, Self.opt, at: 0) == [.wake(after: 0.25)])
        var talk = Rig(Self.sharedTalk)
        #expect(talk.press(Self.ctrl, Self.opt, at: 0) == [], "the talk side of the shared key waits for its second tap")
        #expect(talk.tag == "armed first")
    }

    @Test func row5TheDelayStartsTheTurnAndAnEarlyTickDoesNothing() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.0625) == [])
        #expect(rig.tick(at: 0.15) == [.start, .wake(after: 0.25)])
        #expect(rig.tag == "holding")
        var shared = Rig(Self.sharedDictation)
        shared.press(Self.ctrl, Self.opt, at: 0)
        #expect(shared.tick(at: 0.125) == [])
        #expect(shared.tick(at: 0.25) == [.start, .wake(after: 0.25)])
    }

    @Test func row5TheEndingPressSendsAfterTheConfirm() {
        var rig = Self.latchedTalk(confirm: 0.15)
        #expect(rig.press(Self.ctrl, Self.opt, at: 4) == [.wake(after: 0.15)])
        #expect(rig.tag == "armed ending" && rig.machine.isLatched)
        #expect(rig.tick(at: 4.15) == [.send])
        #expect(rig.tag == "spent" && !rig.machine.isLatched)
    }

    // MARK: Rows 6 to 8: a press that has not acted yet

    @Test func row6ASecondQuickTapLatchesAndStartsTheTurn() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.tap(Self.pair, at: 0)
        #expect(rig.tag == "tapped")
        #expect(rig.log == [.wake(after: 0.15)], "the first tap starts nothing")
        rig.press(Self.ctrl, Self.opt, at: 0.25)
        #expect(rig.release(Self.opt, at: 0.375) == [.start])
        #expect(rig.tag == "latched" && rig.machine.isLatched)
    }

    @Test func row6AQuickFirstTapWaitsAndASlowOneSharedTalkTapIsNothing() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.release(Self.opt, at: 0.0625) == [])
        #expect(rig.tag == "tapped")
        var shared = Rig(Self.sharedTalk)
        shared.press(Self.ctrl, Self.opt, at: 0)
        #expect(shared.release(Self.opt, at: 0.5) == [])
        #expect(shared.tag == "idle", "held past the tap time, so it is no tap")
    }

    @Test func row6TheEndingPressLetGoCleanlySendsOnce() {
        var rig = Self.latchedTalk(confirm: 0.15)
        rig.press(Self.ctrl, Self.opt, at: 4)
        #expect(rig.release(Self.opt, at: 4.0625) == [.send])
        #expect(rig.tag == "idle" && !rig.machine.isLatched)
    }

    @Test func row7ASharedDictationKeyLetGoBeforeTheDelayDoesNothing() {
        var rig = Rig(Self.sharedDictation)
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.release(Self.opt, at: 0.125) == [])
        #expect(rig.tag == "idle")
        #expect(rig.tick(at: 0.25) == [], "the old wake finds nothing to do")
    }

    @Test func row8AForeignKeyDropsAPressThatHasNotActed() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.press(Self.cmdL, at: 0.0625) == [])
        #expect(rig.tag == "idle" && rig.machine.barred)
        #expect(rig.tick(at: 0.15) == [], "no turn starts on the larger chord")
    }

    @Test func row8ALargerChordLeavesAHandsFreeTurnAsItWas() {
        var rig = Self.latchedTalk(confirm: 0.15)
        rig.press(Self.ctrl, Self.opt, at: 4)
        #expect(rig.press(Self.cmdL, at: 4.0625) == [])
        #expect(rig.tag == "latched" && rig.machine.isLatched)
        #expect(rig.tick(at: 4.15) == [])
        #expect(rig.type(Self.left, carrying: .function, at: 4.2) == [], "typing neither sends nor cancels it")
    }

    @Test func row8ShiftDropsADictationPressThatHasNotActed() {
        var rig = Rig(Self.dictation(confirm: 0.15))
        rig.press(Self.cmdR, at: 0)
        #expect(rig.press(Self.shift, at: 0.0625) == [])
        #expect(rig.tag == "idle")
    }

    // MARK: Rows 9 to 14: a turn is open and the key is down

    @Test func row9ALongHoldIsSentAtTheRelease() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.release(Self.opt, at: 1) == [.send])
        #expect(rig.tag == "idle")
    }

    @Test func row9AQuickFirstTapWaitsOutTheGapAndASecondOneLatches() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.release(Self.opt, at: 0.125) == [.wake(after: 0.4)])
        #expect(rig.tag == "tapped open")
        rig.release(Self.ctrl, at: 0.125)
        rig.press(Self.ctrl, Self.opt, at: 0.25)
        #expect(rig.tag == "holding second")
        #expect(rig.release(Self.opt, at: 0.375) == [])
        #expect(rig.tag == "latched" && rig.machine.isLatched)
    }

    @Test func row9AShiftedDictationIsSentAtTheReleaseNeverTappedOrLatched() {
        var rig = Rig(Self.dictation())
        rig.press(Self.cmdR, at: 0)
        rig.press(Self.shift, at: 0.0625)
        #expect(rig.release(Self.shift, at: 0.09375) == [])
        #expect(rig.release(Self.cmdR, at: 0.125) == [.send], "a quick release of a Shift press is sent, not a tap")
        #expect(rig.tag == "idle" && !rig.machine.isLatched)
    }

    @Test func row10ASharedDictationHoldIsSentAtTheRelease() {
        var rig = Rig(Self.sharedDictation)
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.tick(at: 0.25)
        #expect(rig.release(Self.opt, at: 1) == [.send])
        #expect(rig.tag == "idle")
    }

    @Test func row11AForeignKeyCancelsAnOpenHoldAndNothingStartsUntilEverythingIsUp() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.press(Self.cmdL, at: 0.5) == [.cancel])
        #expect(rig.tag == "idle" && rig.machine.barred)
        #expect(rig.release(Self.cmdL, at: 0.75) == [], "the smaller hold that is left starts nothing")
        #expect(rig.release(Self.opt, Self.ctrl, at: 1) == [])
        #expect(rig.press(Self.ctrl, Self.opt, at: 2) == [.start, .wake(after: 0.25)], "everything was up in between")
    }

    @Test func row12And13ShiftOnADictationHoldMarksItAndTheReleaseSendsOnce() {
        var rig = Rig(Self.dictation())
        rig.press(Self.cmdR, at: 0)
        #expect(rig.press(Self.shift, at: 0.5) == [])
        #expect(rig.tag == "holding shifted")
        #expect(rig.release(Self.cmdR, at: 1) == [.send], "the key let go with Shift still down: Return")
        #expect(rig.tag == "idle")
        #expect(rig.release(Self.shift, at: 1.25) == [])
    }

    @Test func row14TheCheckAsksAgainAndAStaleTickDoesNothing() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.125) == [], "not due")
        #expect(rig.tick(at: 0.25) == [.wake(after: 0.25)])
        #expect(rig.tick(at: 0.3125) == [], "the next check is at 0.5")
        #expect(rig.tag == "holding")
    }

    @Test func row14AMissedReleaseIsFoundByTheCheckAndSendsTheTurn() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.25) == [.wake(after: 0.25)])
        #expect(rig.tick(at: 0.5, live: []) == [.send], "the system says the keys are up and no event told us")
        #expect(rig.tag == "idle")
        #expect(rig.machine.keys.flagModifiers.isEmpty)
    }

    @Test func row14AMissedReleaseBeforeTheDelayReadsAsAQuickTap() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.15, live: .control) == [])
        #expect(rig.tag == "tapped", "Option was let go unseen: a quick first tap that started nothing")
    }

    // MARK: Rows 5, 14 and 21 when the wake runs before the flags event of a modifier that joined

    /// The wake can run while the flags event of a Command pressed after the pair is still queued behind a busy main
    /// thread: the tick's live modifiers are the only word the machine has of it, and they read as that event would.
    private static let pairAndCommand: ShortcutModifiers = [.control, .option, .command]

    @Test func row5ACommandOnlyTheLiveModifiersShowStartsNothing() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.15, live: Self.pairAndCommand) == [], "no turn opens on a chord pressed as a chord")
        #expect(rig.tag == "idle" && rig.machine.barred)
        #expect(rig.press(Self.cmdL, at: 0.2) == [], "the queued event finds nothing to cancel")
        #expect(rig.release(Self.cmdL, Self.opt, Self.ctrl, at: 0.5) == [])
        #expect(rig.press(Self.ctrl, Self.opt, at: 2) == [.wake(after: 0.15)], "everything was up in between")
    }

    @Test func row8ShiftOnlyTheLiveModifiersShowDropsADictationPressToo() {
        var rig = Rig(Self.dictation(confirm: 0.15))
        rig.press(Self.cmdR, at: 0)
        #expect(rig.tick(at: 0.15, live: [.command, .shift]) == [])
        #expect(rig.tag == "idle" && rig.machine.barred)
    }

    @Test func row21ACommandOnlyTheLiveModifiersShowDoesNotSendAHandsFreeTurn() {
        var rig = Self.latchedTalk(confirm: 0.15)
        rig.press(Self.ctrl, Self.opt, at: 4)
        #expect(rig.tick(at: 4.15, live: Self.pairAndCommand) == [], "the press that was to end the turn was a chord")
        #expect(rig.tag == "latched" && rig.machine.isLatched)
        #expect(rig.press(Self.cmdL, at: 4.2) == [])
        #expect(rig.release(Self.cmdL, Self.opt, Self.ctrl, at: 4.5) == [])
        #expect(rig.press(Self.ctrl, Self.opt, at: 6) == [.wake(after: 0.15)], "a clean press ends it")
        #expect(rig.tick(at: 6.15) == [.send])
    }

    @Test func row14ACommandOnlyTheLiveModifiersShowCancelsTheOpenTurn() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.25, live: Self.pairAndCommand) == [.cancel])
        #expect(rig.tag == "idle" && rig.machine.barred)
        #expect(rig.press(Self.cmdL, at: 0.3) == [], "the queued event cancels nothing again")
        #expect(rig.release(Self.cmdL, Self.opt, Self.ctrl, at: 0.5) == [])
    }

    @Test func row14ShiftOnlyTheLiveModifiersShowMarksADictationHoldAndKeepsTheCheck() {
        var rig = Rig(Self.dictationOnControlOption())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.tick(at: 0.25, live: [.control, .option, .shift]) == [.wake(after: 0.25)], "the next check is still asked for")
        #expect(rig.tag == "holding shifted")
        #expect(rig.press(Self.shift, at: 0.3) == [])
        #expect(rig.release(Self.opt, at: 1) == [.send], "the key let go with Shift still down: Return")
        var command = Rig(Self.dictationOnControlOption())
        command.press(Self.ctrl, Self.opt, at: 0)
        #expect(command.tick(at: 0.25, live: Self.pairAndCommand) == [.cancel], "any other modifier cancels it")
    }

    // MARK: Rows 15 to 19: after a quick tap

    @Test func row15APressInsideTheGapContinuesTheTurnAsASecondTap() {
        var rig = Rig(Self.talk())
        rig.tap(Self.pair, at: 0)
        #expect(rig.press(Self.ctrl, Self.opt, at: 0.25) == [.wake(after: 0.25)], "the turn is already open: no second start")
        #expect(rig.tag == "holding second")
    }

    @Test func row15ALateTickDoesNotMergeTwoTurns() {
        var rig = Rig(Self.talk())
        rig.tap(Self.pair, at: 0)
        #expect(rig.press(Self.ctrl, Self.opt, at: 0.75) == [.send, .start, .wake(after: 0.25)],
                "the first turn was due at 0.525: it is sent, then a new one starts")
        #expect(rig.tag == "holding")
    }

    @Test func row16AForeignKeyCancelsATurnThatWaitsOutItsGap() {
        var rig = Rig(Self.talk())
        rig.tap(Self.pair, at: 0)
        #expect(rig.type(Self.c, at: 0.25) == [.cancel])
        #expect(rig.tag == "idle")
        #expect(rig.tick(at: 0.525) == [], "nothing is sent later")
    }

    @Test func row17TheGapSendsAQuickTapsTurn() {
        var rig = Rig(Self.talk())
        rig.tap(Self.pair, at: 0)
        #expect(rig.tick(at: 0.25) == [])
        #expect(rig.tick(at: 0.525) == [.send])
        #expect(rig.tag == "idle")
    }

    @Test func row18APressAfterAnUnopenedTapIsASecondTapOnlyInsideTheGap() {
        var inside = Rig(Self.talk(confirm: 0.15))
        inside.tap(Self.pair, at: 0)
        #expect(inside.press(Self.ctrl, Self.opt, at: 0.25) == [.wake(after: 0.15)])
        #expect(inside.tag == "armed second")
        var outside = Rig(Self.talk(confirm: 0.15))
        outside.tap(Self.pair, at: 0)
        outside.press(Self.ctrl, Self.opt, at: 1)
        #expect(outside.tag == "armed first")
        #expect(outside.release(Self.opt, at: 1.125) == [], "a first tap again, not a latch")
    }

    @Test func row19AForeignKeyForgetsAnUnopenedTap() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.tap(Self.pair, at: 0)
        #expect(rig.type(Self.c, at: 0.1875) == [])
        #expect(rig.tag == "idle")
    }

    // MARK: Rows 20 to 22: ending a hands-free turn

    @Test func row20ThePressThatEndsAHandsFreeTurnSendsOnceAndStartsNothing() {
        var rig = Self.latchedTalk()
        #expect(rig.press(Self.ctrl, Self.opt, at: 4) == [.send])
        #expect(rig.tag == "spent")
        #expect(rig.press(Self.cmdL, at: 4.0625) == [], "a modifier joining the ending press cancels nothing")
        #expect(rig.release(Self.cmdL, at: 4.125) == [], "and letting it go starts nothing")
        #expect(rig.release(Self.opt, Self.ctrl, at: 4.25) == [])
        #expect(rig.log.filter { $0 == .cancel }.isEmpty)
        #expect(rig.log.filter { $0 == .start }.count == 1, "only the turn the two taps began")
    }

    @Test func row20OnTheSharedKeyTheNextPressSendsAndIsAFirstTap() {
        var rig = Rig(Self.sharedTalk)
        rig.tap(Self.pair, at: 0)
        rig.press(Self.ctrl, Self.opt, at: 0.25)
        #expect(rig.release(Self.opt, at: 0.375) == [.start], "two quick taps open a hands-free command turn")
        #expect(rig.press(Self.ctrl, Self.opt, at: 3) == [.send])
        #expect(rig.tag == "armed first")
    }

    @Test func row21WithAConfirmTheEndingPressWaitsForIt() {
        var rig = Self.latchedTalk(confirm: 0.15)
        #expect(rig.press(Self.ctrl, Self.opt, at: 3) == [.wake(after: 0.15)])
        #expect(rig.tag == "armed ending")
    }

    /// A shared talk key beside tiling: two quick taps open a hands-free command turn, and the press that ends it waits
    /// out the confirm like the ending press of a hold key.
    private static func latchedSharedTalk(confirm: TimeInterval) -> Rig {
        var rig = Rig(sharedTalk(confirm: confirm))
        rig.tap(pair, at: 0)
        rig.tap(pair, at: 0.25)
        return rig
    }

    @Test func row21OnTheSharedKeyAConfirmedEndingPressWaitsForTheConfirmAndThenSends() {
        var rig = Self.latchedSharedTalk(confirm: 0.15)
        #expect(rig.log.filter { $0 == .start }.count == 1, "two quick taps open the command turn")
        #expect(rig.press(Self.ctrl, Self.opt, at: 3) == [.wake(after: 0.15)], "nothing is sent at the key-down")
        #expect(rig.tag == "armed ending")
        #expect(rig.tick(at: 3.15) == [.send], "the set stayed down alone for the confirm")
        #expect(rig.tag == "armed first", "the same press counts as a first tap, as with a confirm of 0")
    }

    @Test func row6OnTheSharedKeyAConfirmedEndingPressLetGoCleanlySendsAtTheReleaseAndIsAFirstTap() {
        var rig = Self.latchedSharedTalk(confirm: 0.15)
        rig.press(Self.ctrl, Self.opt, at: 3)
        #expect(rig.release(Self.opt, at: 3.0625) == [.send])
        #expect(rig.tag == "tapped", "a quick press that ended a turn still counts as the first of two taps")
        #expect(rig.release(Self.ctrl, at: 3.125) == [])
        #expect(rig.tick(at: 3.15) == [], "the wake of the ending press is stale")
    }

    @Test func row8AFastTilingChordDoesNotEndASharedHandsFreeTurnWithAConfirm() {
        var rig = Self.latchedSharedTalk(confirm: 0.15)
        rig.press(Self.ctrl, at: 3)
        rig.press(Self.opt, at: 3.005)
        #expect(rig.press(Self.cmdL, at: 3.02) == [], "Command lands before the confirm: nothing is sent")
        #expect(rig.tag == "latched" && rig.machine.isLatched)
        #expect(rig.tick(at: 3.155) == [], "the wake finds the turn as it was")
        #expect(rig.release(Self.cmdL, Self.opt, Self.ctrl, at: 3.5) == [])
        #expect(rig.log.filter { $0 == .send || $0 == .cancel }.isEmpty, "the turn is neither sent nor cancelled")
        #expect(rig.press(Self.ctrl, Self.opt, at: 5) == [.wake(after: 0.15)], "a clean press ends it")
        #expect(rig.tick(at: 5.15) == [.send])
    }

    @Test func row22AFinishedPressIsForgottenWhenItsKeyIsLetGo() {
        var rig = Rig(Self.toggle)
        rig.press(Self.cmdR, at: 0)
        rig.release(Self.cmdR, at: 0.25)
        #expect(rig.tag == "idle")
        rig.press(Self.cmdR, at: 0.5)
        rig.press(Self.shift, at: 0.625)
        #expect(rig.tag == "idle", "a foreign key ends it as well")
    }

    // MARK: Rows 23 to 25: abandon, interrupt, and the rest

    @Test func row23AnAbandonEndsAnOpenTurnWithNoEffectAndBarsTheKeysThatAreStillDown() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.abandon() == [])
        #expect(rig.tag == "idle" && rig.machine.barred)
        rig.release(Self.opt, at: 0.5)
        #expect(rig.press(Self.opt, at: 0.625) == [], "Control is still down: nothing begins")
        rig.release(Self.opt, Self.ctrl, at: 1)
        #expect(rig.press(Self.ctrl, Self.opt, at: 2) == [.start, .wake(after: 0.25)])
    }

    @Test func row23AnAbandonEndsATappedAndAHandsFreeTurnToo() {
        var tapped = Rig(Self.talk())
        tapped.tap(Self.pair, at: 0)
        tapped.abandon()
        #expect(tapped.tag == "idle" && !tapped.machine.barred)
        #expect(tapped.tick(at: 0.525) == [], "the owner has ended it: nothing is sent")
        var latched = Self.latchedTalk()
        latched.abandon()
        #expect(latched.tag == "idle" && !latched.machine.isLatched)
    }

    @Test func row23AnAbandonWithNoOpenTurnChangesNothing() {
        var rig = Rig(Self.toggle)
        rig.press(Self.cmdR, at: 0)
        #expect(rig.abandon() == [])
        #expect(rig.tag == "spent", "a toggle has no turn to abandon")
        var idle = Rig(Self.talk())
        idle.press(Self.ctrl, at: 0)
        idle.abandon()
        #expect(idle.tag == "idle" && !idle.machine.barred)
    }

    /// A quick tap leaves tapped(open) and its tick is late, so the next press settles the old turn and opens a new one in
    /// one call: `[send, start, wake]`. The owner's echo of that `send` names the old turn.
    @Test func row23AnAbandonNamesItsTurnSoTheEchoOfASendCannotEndTheTurnOpenedWithIt() {
        var rig = Rig(Self.dictation())
        rig.tap([Self.cmdR], at: 0)
        #expect(rig.tag == "tapped open" && rig.machine.generation == 1)
        #expect(rig.press(Self.cmdR, at: 0.575) == [.send, .start, .wake(after: 0.25)])
        #expect(rig.machine.generation == 2 && rig.tag == "holding")
        #expect(rig.abandon(turn: 1) == [])
        #expect(rig.tag == "holding" && !rig.machine.barred, "the echo of the first turn leaves the second as it was")
        #expect(rig.release(Self.cmdR, at: 1) == [.send], "its key release still sends it")
    }

    @Test func row23AnAbandonOfTheCurrentTurnStillEndsIt() {
        var rig = Rig(Self.dictation())
        rig.tap([Self.cmdR], at: 0)
        rig.press(Self.cmdR, at: 0.575)
        #expect(rig.abandon(turn: 2) == [])
        #expect(rig.tag == "idle" && rig.machine.barred, "the key is still down")
        var refused = Rig(Self.talk())
        refused.press(Self.ctrl, Self.opt, at: 0)
        #expect(refused.abandon(turn: 1) == [])
        #expect(refused.tag == "idle", "the owner refused the press: the machine forgets the turn it started")
        #expect(refused.abandon(turn: 0) == [], "a number the machine never gave out changes nothing")
    }

    @Test func row24AnInterruptCancelsAnOpenTurnAndTakesTheLiveModifiers() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.interrupt(live: [.control, .option]) == [.cancel])
        #expect(rig.tag == "idle" && rig.machine.barred, "the keys are still down")
        var clear = Rig(Self.talk())
        clear.press(Self.ctrl, Self.opt, at: 0)
        #expect(clear.interrupt(live: []) == [.cancel])
        #expect(!clear.machine.barred)
        clear.down = []
        #expect(clear.press(Self.ctrl, Self.opt, at: 1) == [.start, .wake(after: 0.25)])
    }

    @Test func row24AnInterruptWithNoTurnOpenCancelsNothing() {
        var rig = Rig(Self.talk())
        #expect(rig.interrupt(live: []) == [])
        rig.press(Self.ctrl, at: 1)
        #expect(rig.interrupt(live: .control) == [])
        #expect(rig.machine.barred)
    }

    @Test func row25AStaleTickAndAnAbandonInIdleChangeNothing() {
        var rig = Rig(Self.talk())
        #expect(rig.tick(at: 5) == [])
        #expect(rig.abandon() == [])
        #expect(rig.tag == "idle")
        #expect(rig.type(Self.c, at: 6) == [])
    }

    // MARK: The prelude: the first config and a change of config

    @Test func theFirstPressAfterLaunchActs() {
        var rig = Rig(Self.talk())
        #expect(rig.machine.config == nil)
        #expect(rig.press(Self.ctrl, Self.opt, at: 0) == [.start, .wake(after: 0.25)], "the first config is no change")
        #expect(rig.machine.config == Self.talk())
    }

    @Test func aChangeOfKeyModeOrVoiceOverCancelsAnOpenTurnAndBarsTheKeysDown() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.config = Config(key: Shortcut(modifiers: [.option, .command]), role: .talk, mode: .hold)
        #expect(rig.release(Self.shift, at: 0.5) == [.cancel], "a different key: the turn is cancelled at the next event")
        #expect(rig.machine.barred)

        var mode = Rig(Self.talk())
        mode.press(Self.ctrl, Self.opt, at: 0)
        mode.config = Config(key: .controlOption, role: .talk, mode: .toggle)
        #expect(mode.tick(at: 0.125) == [.cancel], "the toggle setting flipped mid turn (C7)")

        var voiceOver = Rig(Self.talk())
        voiceOver.press(Self.ctrl, Self.opt, at: 0)
        voiceOver.config.voiceOverHoldsKey = true
        #expect(voiceOver.tick(at: 0.125) == [.cancel])
    }

    /// The adapter hands over the config with an event, so the press that reveals a change made with the mouse is also
    /// a key down. Nothing was held through the change, so that press is an ordinary press (I8).
    @Test func aPressThatRevealsAChangeOfConfigWithEveryKeyUpActsLikeAnyPress() {
        var rig = Rig(Self.dictation())
        rig.tap([Self.cmdR], at: 0, length: 1)
        rig.config = Self.toggle
        #expect(rig.press(Self.cmdR, at: 2) == [.start], "hold flipped to toggle")
        #expect(!rig.machine.barred)
        rig.release(Self.cmdR, at: 2.5)
        rig.config = Config(key: .rightCommand, role: .dictation, mode: .shared)
        #expect(rig.press(Self.cmdR, at: 3) == [.wake(after: 0.25)], "shared dictation waits out its 0.25 s delay")
        #expect(rig.tick(at: 3.25) == [.start, .wake(after: 0.25)])
        rig.release(Self.cmdR, at: 4)
        rig.config.voiceOverHoldsKey = true
        #expect(rig.press(Self.cmdR, at: 5) == [.refused], "VoiceOver took the key")
    }

    @Test func aPressThatRevealsAChangeCancelsTheHandsFreeTurnItLeavesAndThenActs() {
        var rig = Self.latchedTalk()
        rig.config = Config(key: .controlOption, role: .talk, mode: .toggle)
        #expect(rig.press(Self.ctrl, at: 5) == [.cancel])
        #expect(rig.press(Self.opt, at: 5) == [.start], "the turn is cancelled and the press toggles")
        #expect(rig.tag == "spent")
    }

    @Test func aChangeOfConfigStillBarsAKeyHeldThroughIt() {
        var rig = Rig(Self.toggle)
        rig.press(Self.cmdR, at: 0)
        rig.config = Config(key: .rightCommand, role: .dictation, mode: .hold)
        #expect(rig.press(Self.shift, at: 0.5) == [], "Right Command is down across the change: the press already counted")
        rig.release(Self.shift, at: 0.75)
        rig.release(Self.cmdR, at: 1)
        #expect(rig.press(Self.cmdR, at: 2) == [.start, .wake(after: 0.25)], "after everything is up the next press acts")
    }

    // MARK: A key-up nobody saw

    static let tab: UInt16 = 48

    /// Tab out of a username field into a password field: secure input turns on before Tab comes up, so no monitor sees
    /// the key-up and the picture keeps Tab down.
    @Test func aKeyWhoseKeyUpWasNeverSeenKillsTheVoiceKeyUntilASweepDropsIt() {
        var rig = Rig(Self.dictation())
        rig.type(Self.tab, at: 0)
        #expect(rig.press(Self.cmdR, at: 1) == [], "Tab reads as a foreign key beside Right Command")
        rig.release(Self.cmdR, at: 1.5)
        #expect(rig.machine.barred)
        #expect(rig.press(Self.cmdR, at: 2) == [], "and it stays dead")
        rig.release(Self.cmdR, at: 2.5)

        rig.sweep(live: [])
        #expect(!rig.machine.barred && rig.machine.keys.keysDown.isEmpty, "the system says Tab is up")
        #expect(rig.press(Self.cmdR, at: 3) == [.start, .wake(after: 0.25)])
    }

    @Test func aSweepKeepsTheKeysTheSystemStillReportsDown() {
        var rig = Rig(Self.dictation())
        rig.type(Self.tab, at: 0)
        rig.sweep(live: [Self.tab])
        #expect(rig.press(Self.cmdR, at: 1) == [], "Tab really is held: it stays foreign")
        #expect(rig.machine.keys.keysDown == [Self.tab])
    }

    @Test func aSweepReachesAKeyedKeyToo() {
        let polyglot = Config(key: Shortcut(keyCode: Self.c, modifiers: [.control, .option]), role: .dictation, mode: .toggle)
        var rig = Rig(polyglot)
        rig.type(Self.tab, at: 0)
        rig.press(Self.ctrl, Self.opt, at: 1)
        #expect(rig.type(Self.c, carrying: [.control, .option], at: 1.1) == [], "a key from before is foreign to a keyed key")
        rig.untype(Self.c, at: 1.2)
        rig.release(Self.opt, Self.ctrl, at: 1.3)
        rig.sweep(live: [])
        rig.press(Self.ctrl, Self.opt, at: 2)
        #expect(rig.type(Self.c, carrying: [.control, .option], at: 2.1) == [.start])
    }

    @Test func aNewConfirmIsOnlyStoredSoSwitchingTilingOnDoesNotEndAHandsFreeTurn() {
        var rig = Self.latchedTalk()
        rig.config.confirm = 0.15
        #expect(rig.tick(at: 5) == [])
        #expect(rig.machine.isLatched)
        #expect(rig.machine.config?.confirm == 0.15)
    }

    /// While the key is nil the machine reads nothing, but the picture is kept and a bar that every key up lifts is lifted.
    @Test func aKeyThatTurnsNilAndComesBackFindsTheBarLiftedOnceEveryKeyWasUp() {
        var rig = Rig(Self.dictation())
        rig.press(Self.cmdR, at: 0)
        rig.config.key = nil
        #expect(rig.release(Self.cmdR, at: 1) == [.cancel])
        #expect(rig.machine.barred == false, "everything is up")
        rig.config.key = .rightCommand
        #expect(rig.press(Self.cmdR, at: 2) == [.start, .wake(after: 0.25)], "the key is back and its first press acts")

        var held = Rig(Self.dictation())
        held.press(Self.cmdR, at: 0)
        held.config.key = nil
        held.press(Self.shift, at: 1)
        held.config.key = .rightCommand
        #expect(held.release(Self.shift, at: 2) == [] && held.machine.barred, "Right Command is still down: nothing begins")
    }

    @Test func aKeyThatTurnsNilStopsTheMachineAndCancelsTheTurn() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.config.key = nil
        #expect(rig.release(Self.opt, at: 1) == [.cancel], "C7: a key that turned nil cancels, it does not send")
        #expect(rig.press(Self.opt, at: 2) == [])
        #expect(rig.tag == "idle")
    }

    // MARK: The press orders the reviews found

    @Test func f1ControlOptionShiftCommandLeftSendsAndLatchesNothingWithTheConfirm() {
        var rig = Rig(Self.talk(confirm: 0.15))
        for round in 0..<2 {
            let t = TimeInterval(round) * 0.5
            rig.press(Self.ctrl, Self.opt, at: t)
            rig.press(Self.shift, at: t + 0.03125)
            rig.press(Self.cmdL, at: t + 0.0625)
            rig.type(Self.left, carrying: .function, at: t + 0.09375)
            rig.untype(Self.left, at: t + 0.125)
            rig.release(Self.cmdL, Self.shift, Self.opt, Self.ctrl, at: t + 0.1875)
            rig.wait(until: t + 0.45)
        }
        #expect(rig.log.filter { $0 != .wake(after: 0.15) }.isEmpty, "no start, no send, no cancel: only the wakes it asked for")
        #expect(!rig.machine.isLatched)
    }

    @Test func f1TheSameOrderWithNoConfirmCancelsAtShiftAndNeverSends() {
        var rig = Rig(Self.talk())
        for round in 0..<2 {
            let t = TimeInterval(round) * 0.5
            rig.press(Self.ctrl, Self.opt, at: t)
            rig.press(Self.shift, at: t + 0.03125)
            rig.press(Self.cmdL, at: t + 0.0625)
            rig.type(Self.left, carrying: .function, at: t + 0.09375)
            rig.untype(Self.left, at: t + 0.125)
            rig.release(Self.cmdL, Self.shift, Self.opt, Self.ctrl, at: t + 0.1875)
            rig.wait(until: t + 0.45)
        }
        #expect(!rig.log.contains(.send))
        #expect(rig.log.filter { $0 == .cancel }.count == 2, "each press is cancelled once")
        #expect(!rig.machine.isLatched)
    }

    @Test func f1SlowlyPressedWithTheConfirmElapsedIsCancelledAtShift() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.wait(until: 0.15)
        #expect(rig.press(Self.shift, at: 0.25) == [.cancel])
        rig.press(Self.cmdL, at: 0.375)
        rig.release(Self.cmdL, Self.shift, Self.opt, Self.ctrl, at: 0.5)
        rig.wait(until: 2)
        #expect(!rig.log.contains(.send))
    }

    @Test func theSwapChordOnADictationKeyOfControlOptionInsertsNothing() {
        var fast = Rig(Self.dictationOnControlOption(confirm: 0.15))
        fast.press(Self.ctrl, Self.opt, at: 0)
        fast.press(Self.shift, at: 0.03125)
        fast.press(Self.cmdL, at: 0.0625)
        fast.type(Self.left, carrying: .function, at: 0.09375)
        fast.untype(Self.left, at: 0.125)
        fast.release(Self.cmdL, Self.shift, Self.opt, Self.ctrl, at: 0.25)
        fast.wait(until: 2)
        #expect(!fast.log.contains(.send) && !fast.log.contains(.start))

        var slow = Rig(Self.dictationOnControlOption(confirm: 0.15))
        slow.press(Self.ctrl, Self.opt, at: 0)
        slow.wait(until: 0.15)
        slow.press(Self.shift, at: 0.25)
        #expect(slow.tag == "holding shifted")
        slow.press(Self.cmdL, at: 0.3125)
        slow.type(Self.left, carrying: .function, at: 0.375)
        slow.release(Self.cmdL, Self.shift, Self.opt, Self.ctrl, at: 0.5)
        slow.wait(until: 2)
        #expect(!slow.log.contains(.send), "Command joined while Shift was down: cancelled, not sent")
        #expect(slow.log.contains(.cancel))
    }

    @Test func theSwapChordOnRightCommandInsertsNothingInTheOtherOrder() {
        var rig = Rig(Self.dictation(confirm: 0.15))
        rig.press(Self.cmdR, at: 0)
        rig.press(Self.shift, at: 0.03125)
        rig.press(Self.ctrl, Self.opt, at: 0.0625)
        rig.type(Self.left, carrying: .function, at: 0.125)
        rig.untype(Self.left, at: 0.1875)
        rig.release(Self.opt, Self.ctrl, Self.shift, Self.cmdR, at: 0.25)
        rig.wait(until: 2)
        #expect(!rig.log.contains(.send) && !rig.log.contains(.start))
    }

    @Test func aForwardedKeyThatComesBeforeTheFlagsEventOfTheLastModifierStillCostsOnlyAWake() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.feed(.key(.keyDown(keyCode: Self.left, modifiers: [.control, .option, .command, .function]), at: 0.03125))
        rig.press(Self.cmdL, at: 0.0625)
        rig.tick(at: 0.15)
        rig.feed(.key(.keyUp(keyCode: Self.left), at: 0.1875))
        rig.release(Self.cmdL, Self.opt, Self.ctrl, at: 0.25)
        #expect(rig.log == [.wake(after: 0.15)])
    }

    @Test func aDictationPressThatShiftJoinedIsSentOnceEvenAsAQuickSecondTap() {
        var rig = Rig(Self.dictation())
        rig.tap([Self.cmdR], at: 0)
        rig.press(Self.cmdR, at: 0.25)
        rig.press(Self.shift, at: 0.28125)
        rig.release(Self.shift, at: 0.3125)
        rig.release(Self.cmdR, at: 0.375)
        #expect(rig.log.filter { $0 == .send }.count == 1)
        #expect(!rig.machine.isLatched, "a press Shift joined is never latched")
        #expect(rig.tag == "idle")
    }

    // MARK: Each behaviour the plan changes on purpose

    @Test func c1ShiftJoiningATalkHoldCancelsIt() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.press(Self.shift, at: 0.5) == [.cancel])
        rig.release(Self.shift, Self.opt, Self.ctrl, at: 1)
        rig.wait(until: 3)
        #expect(!rig.log.contains(.send))
    }

    @Test func c2AKeyJoiningADedicatedDictationHoldCancelsIt() {
        var rig = Rig(Self.dictation())
        rig.press(Self.cmdR, at: 0)
        #expect(rig.type(Self.c, at: 0.5) == [.cancel])
        rig.untype(Self.c, at: 0.625)
        rig.release(Self.cmdR, at: 1)
        #expect(!rig.log.contains(.send))
    }

    @Test func c3FnIsForeignOnTheSharedKeyBeforeAndDuringAHold() {
        var before = Rig(Self.sharedDictation)
        before.press(Self.ctrl, Self.opt, at: 0)
        before.press(Self.fn, at: 0.0625)
        #expect(before.tick(at: 0.25) == [], "the press was dropped")
        var during = Rig(Self.sharedDictation)
        during.press(Self.ctrl, Self.opt, at: 0)
        during.tick(at: 0.25)
        #expect(during.press(Self.fn, at: 0.5) == [.cancel])
        var command = Rig(Self.sharedDictation)
        command.press(Self.ctrl, Self.opt, at: 0)
        command.tick(at: 0.25)
        #expect(command.press(Self.cmdL, at: 0.5) == [.cancel])
    }

    @Test func c4ShiftOnASharedHoldIsReturnAndTheReleaseSendsOnce() {
        var rig = Rig(Self.sharedDictation)
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.tick(at: 0.25)
        #expect(rig.press(Self.shift, at: 0.5) == [])
        #expect(rig.release(Self.opt, at: 1) == [.send])
        #expect(rig.release(Self.shift, Self.ctrl, at: 1.25) == [])
    }

    @Test func c4ShiftLetGoFirstThenTheKeyIsStillOneSendAndNoLatch() {
        var rig = Rig(Self.dictation())
        rig.press(Self.cmdR, at: 0)
        rig.press(Self.shift, at: 0.5)
        #expect(rig.release(Self.shift, at: 0.625) == [])
        #expect(rig.release(Self.cmdR, at: 1) == [.send])
        #expect(!rig.machine.isLatched)
    }

    @Test func c5ATapWaitingOutItsGapIsCancelledByAForeignKeyOrModifier() {
        var key = Rig(Self.talk())
        key.tap(Self.pair, at: 0)
        #expect(key.type(Self.c, at: 0.25) == [.cancel])
        var modifier = Rig(Self.talk())
        modifier.tap(Self.pair, at: 0)
        #expect(modifier.press(Self.cmdL, at: 0.25) == [.cancel])
    }

    @Test func c6ALargerSetThatShrinksToTheKeysSetStartsNothing() {
        var talk = Rig(Self.talk())
        talk.press(Self.cmdL, Self.ctrl, Self.opt, at: 0)
        #expect(talk.release(Self.cmdL, at: 0.5) == [])
        #expect(talk.tag == "idle")
        var toggle = Rig(Config(key: .controlOption, role: .dictation, mode: .toggle))
        toggle.press(Self.cmdL, Self.ctrl, Self.opt, at: 0)
        #expect(toggle.release(Self.cmdL, at: 0.5) == [], "a toggle is not fired by the shrink")
        var dictation = Rig(Self.dictation())
        dictation.press(Self.cmdL, Self.cmdR, at: 0)
        #expect(dictation.release(Self.cmdL, at: 0.5) == [], "Left Command first, then Right Command: not a clean press")
    }

    @Test func c8TheVoiceOverRefusalComesOncePerPressWhateverComesNext() {
        var rig = Rig(Config(key: .controlOption, role: .talk, mode: .hold, voiceOverHoldsKey: true))
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.press(Self.cmdL, at: 0.25)
        rig.release(Self.cmdL, at: 0.5)
        rig.tick(at: 0.75)
        #expect(rig.log == [.refused])
    }

    @Test func c9AKeyedHoldKeyIsCancelledByAForeignModifierOrKey() {
        let optionSpace = Config(key: Shortcut(keyCode: Self.space, modifiers: .option), role: .talk, mode: .hold)
        var modifier = Rig(optionSpace)
        modifier.press(Self.opt, at: 0)
        #expect(modifier.type(Self.space, at: 0.0625) == [.start, .wake(after: 0.25)])
        #expect(modifier.press(Self.cmdL, at: 0.5) == [.cancel])
        var key = Rig(optionSpace)
        key.press(Self.opt, at: 0)
        key.type(Self.space, at: 0.0625)
        #expect(key.type(Self.c, at: 0.5) == [.cancel])
        #expect(!key.log.contains(.send))
    }

    @Test func c11AKeyedKeyPressedWhileAnotherKeyIsStillDownDoesNothingUntilEverythingIsUp() {
        let optionSpace = Config(key: Shortcut(keyCode: Self.space, modifiers: .option), role: .talk, mode: .hold)
        var rig = Rig(optionSpace)
        rig.type(Self.c, at: 0)
        rig.press(Self.opt, at: 0.0625)
        #expect(rig.type(Self.space, at: 0.125) == [])
        rig.untype(Self.c, at: 0.1875)
        #expect(rig.untype(Self.space, at: 0.25) == [])
        rig.type(Self.space, at: 0.3125)
        #expect(rig.log.isEmpty, "Option never went up")
        rig.untype(Self.space, at: 0.375)
        rig.release(Self.opt, at: 0.5)
        rig.press(Self.opt, at: 1)
        #expect(rig.type(Self.space, at: 1.0625) == [.start, .wake(after: 0.25)])
    }

    @Test func c12AForeignModifierTappedDuringOneTogglePressTogglesOnce() {
        var rig = Rig(Self.toggle)
        rig.press(Self.cmdR, at: 0)
        rig.press(Self.shift, at: 0.125)
        rig.release(Self.shift, at: 0.25)
        rig.press(Self.shift, at: 0.375)
        rig.release(Self.shift, at: 0.5)
        rig.release(Self.cmdR, at: 0.625)
        #expect(rig.log == [.start])
    }

    @Test func c13LeftCommandBesideRightCommandBarsAStartAndCancelsAHold() {
        var before = Rig(Self.dictation())
        before.press(Self.cmdL, Self.cmdR, at: 0)
        #expect(before.log.isEmpty)
        var during = Rig(Self.dictation())
        during.press(Self.cmdR, at: 0)
        #expect(during.press(Self.cmdL, at: 0.5) == [.cancel])
    }

    @Test func c14ALoneTapUnderTheConfirmDoesNothingAndADoubleTapStillLatches() {
        var rig = Rig(Self.talk(confirm: 0.15))
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.release(Self.opt, at: 0.09375)
        #expect(rig.tick(at: 0.15) == [], "the confirm tick of a press that ended finds nothing")
        #expect(!rig.log.contains(.start))
        rig.release(Self.ctrl, at: 0.09375)
        rig.press(Self.ctrl, Self.opt, at: 0.25)
        rig.release(Self.opt, at: 0.34375)
        #expect(rig.log.contains(.start) && rig.machine.isLatched)
    }

    @Test func c15AnArrowKeyAndItsFnFlagStartAnFnKeyNothing() {
        var rig = Rig(Config(key: .function, role: .talk, mode: .hold))
        rig.feed(.key(.keyDown(keyCode: Self.left, modifiers: .function), at: 0))
        rig.feed(.key(.keyUp(keyCode: Self.left), at: 0.125))
        #expect(rig.log.isEmpty)
        #expect(rig.press(Self.fn, at: 1) == [.start, .wake(after: 0.25)], "the Globe key itself still works")
    }

    @Test func c16ARefusedPressAbandonedIsNeitherSentNorCancelledByTheNextKey() {
        var rig = Rig(Self.talk())
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.abandon()
        #expect(rig.type(Self.c, at: 0.5) == [])
        rig.untype(Self.c, at: 0.625)
        rig.release(Self.opt, Self.ctrl, at: 1)
        #expect(rig.log == [.start, .wake(after: 0.25)])
    }

    @Test func c17AnInterruptCancelsAnOpenTurnAndTheCheckFindsAMissedRelease() {
        var rig = Rig(Self.dictation())
        rig.press(Self.cmdR, at: 0)
        #expect(rig.interrupt(live: []) == [.cancel])
        var missed = Rig(Self.dictation())
        missed.press(Self.cmdR, at: 0)
        missed.tick(at: 0.25)
        #expect(missed.tick(at: 0.5, live: []) == [.send])
    }

    @Test func c18TheOwnersOwnEndLetsTheNextPressStart() {
        var rig = Self.latchedTalk()
        rig.abandon()
        rig.down = []
        #expect(rig.press(Self.ctrl, Self.opt, at: 5) == [.start, .wake(after: 0.25)])
    }
}

private extension VoiceKeyMachine {
    /// The phase in words, so a test reads one line.
    var tag: String {
        switch phase {
        case .idle: "idle"
        case .armed(_, let press): "armed \(press)"
        case .holding(_, let second, _, let shifted): "holding" + (second ? " second" : "") + (shifted ? " shifted" : "")
        case .tapped(_, let open): open ? "tapped open" : "tapped"
        case .latched: "latched"
        case .spent: "spent"
        }
    }
}
