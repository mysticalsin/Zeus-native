import Foundation
import Testing
@testable import ZeusCore

// The search over every press order (docs/VOICE-KEY-MACHINE-PLAN.md, part 5).
//
// It walks the whole graph of reachable states of one hold key: each state is expanded once with every move and a
// visited set ends the search, so every order of presses and releases at every length is covered with no cut-off on
// length. Time moves in whole steps of 0.05 s, of which every threshold is a multiple, and the state key keeps ages
// (capped at 0.45 s, past every window) in place of times, so the graph is finite. After every move a checker reads
// rules I1 to I7 from the effects, the keys the machine has been told are down and `isLatched`; at every state the
// walk also lets go of everything, waits 0.5 s and presses the own set, and reads I8 and the last clause of I4.
//
// What reaches the machine, and when. A modifier key and a key the tiling matcher passes on send a monitor event; a key
// the real `TileKeyMatcher` consumes is forwarded as the event a monitor would have seen. The forwarded key reaches the
// machine at once, and a monitor event may be held back for one event, so the machine can hear a forwarded key before
// the flags event of the modifier pressed ahead of it. Time passes while an event is held, as it does when the main
// thread is busy: a wake can run with the event still queued, and then the live modifiers it carries are all the machine
// has of that key. A forwarded key that waited behind several later events is not modelled: with three modifiers let go
// and the arrow still held, the machine sees every key up and a start can follow, and no reducer can tell that from a
// clean press. The rules are therefore read against the keys the machine was told about, not against the keys physically
// down; a tick that is due for an armed press or a running hold tells the machine the live modifiers.
//
// A key is stamped with the time it happened, as the adapter does with `NSEvent.timestamp` and the tap's own timestamp:
// a held monitor event reaches the machine at its own earlier time, after up to `lagLimit` steps in which the main thread
// was busy, and a due wake may run before or after it. The rules read the keyboard as the machine had been told of it,
// at the key's own time: a start or a send that an overdue timer owes ahead of a key needs the own set to have been down
// alone for the delay, or the tap to have been let go for the gap, by then (`checkSettled`). A key-down that reports a
// modifier the machine has not heard of stands for that flags event, so a forwarded key ahead of a held Command does
// not start a turn either.
//
// The chord (docs/ULTRON-CHORD-PLAN.md). A run with `chord` has Space as a key. A Space that goes down while the own set is
// down alone, by the keys the machine has been told about and by the modifiers the key itself reports, is a clean chord: it
// is not foreign for I1, I3 and I6 until it or an own modifier goes up (the bookkeeping of that very step still reads it as
// clean, so a modifier let go with Space down is a clean release). I9: an event that only moves a clean chord's Space gives
// no start, send or cancel, but the effects an overdue timer owes ahead of it. The `swallowed` move is the Carbon hot key
// that takes Space away from the monitors: the key goes down or up and no event comes. Runs that read Space as a plain
// foreign key (dictation, shared, keyed, pointing, Fn) carry it as a full key; the costly runs B and B2 offer it only
// while Control and Option are down.
//
// The whole search takes minutes under load. `WALK_ONLY=A,B2` runs only the runs whose names start with one of those.
// Both of these are off by default: `WALK_PROGRESS=path` appends the size of each search to that file as it grows (the runner holds
// its output until it ends), `WALK_LIMIT=n` stops a search past n states, for measuring a run before it is put in the list.
//
// A wake belongs to the phase that asked for it: when the phase changes the old wakes are dropped, so a phase that
// forgets its own wake is caught instead of being covered by a stale one.
//
// What the adapter does around the machine is part of the search. A timer may be late: `waitLate` lets a due wake wait
// for the next event, so a key can reach the machine before the tick that was due ahead of it (`settle`), and the checker
// reads the effects that timer owes on the keyboard as it was. A config change reaches the machine with the next event of
// any kind (`flipQuiet`), a key. An ordinary key may come up with no event at all (`missUp`), and the adapter's sweep
// asks which ordinary keys are really down before each key event. After a `send` or `cancel` the owner stops listening and
// says so, as an `abandon` naming its turn; the owner may also refuse a turn it was asked to start (`refusing`). The
// machine's own count of open turns must agree with the rules after every step.
//
// Run H walks `PointingKeyGesture` under the same checker. The harness stands in for the monitor: an armed hold asks
// for one wake after its confirm, an active hold for the watchdog every 0.25 s, and each wake reaches the gesture as the
// call the monitor makes (`confirmElapsed` or `tick`) with the modifiers that are really down. Began is a start; ended
// and a timed out hold are a send; cancelled is a cancel. The gesture has no owner that abandons a turn and no config to
// flip, so those two moves are left out. Its 95 s bound is past the cap and stays with `PointingRobustnessTests`.

/// One physical key of a run.
struct WalkKey: Hashable, Sendable {
    let name: String
    let code: UInt16
    /// The modifier flag this key sets, nil for an ordinary key.
    let flag: ShortcutModifiers?
    /// The key is offered to the search only while these modifiers are down (or while it is itself down, so it can come up).
    var onlyWith: ShortcutModifiers?

    static let control = WalkKey(name: "Control", code: 59, flag: .control)
    static let option = WalkKey(name: "Option", code: 58, flag: .option)
    static let shift = WalkKey(name: "Shift", code: 56, flag: .shift)
    static let leftCommand = WalkKey(name: "LeftCommand", code: 55, flag: .command)
    static let rightCommand = WalkKey(name: "RightCommand", code: 54, flag: .command)
    static let globe = WalkKey(name: "Fn", code: 63, flag: .function)
    /// The second talk key (docs/RIGHT-OPTION-TALK-PLAN.md): a second physical key that sets the Option flag.
    static let rightOption = WalkKey(name: "RightOption", code: 61, flag: .option)
    static let leftArrow = WalkKey(name: "Left", code: 123, flag: nil)
    static let letterT = WalkKey(name: "T", code: 17, flag: nil)
    static let space = WalkKey(name: "Space", code: 49, flag: nil)
    /// Space, offered only while Control and Option are down: for the runs that are too costly with a full extra key.
    static let spaceOnPair = WalkKey(name: "Space", code: 49, flag: nil, onlyWith: [.control, .option])
}

/// One run: the physical keys, which of them are the key's own set, and the configs the key cycles through.
struct WalkRun: Sendable, CustomTestStringConvertible {
    let name: String
    let keys: [WalkKey]
    let ownCodes: [UInt16]
    /// The first is the start; a `flip` move goes to the next, and round to the first.
    let configs: [VoiceKeyMachine.Config]
    /// The key is read by `PointingKeyGesture`, not by the voice key machine.
    let pointing: Bool
    /// What the adapter and the owner may do besides pressing keys, each added only where a run's rules read it (every one
    /// multiplies the states): a due timer may run after the next key event; a config change may ride on the next event;
    /// an ordinary key may come up with no event; the owner may refuse the turns it is asked to start.
    let late: Bool
    let quietFlip: Bool
    let missed: Bool
    let refusal: Bool
    /// The adapter before it stamped keys with their own time: a held event reaches the machine at the time it is handled.
    /// Only the regression test that the search can see that mistake sets it.
    let processingTime: Bool
    /// The checker applies the chord rules and the search has the `swallowed` move: Space is the chord key.
    let chord: Bool
    /// Carbon takes every Space: its key-down and key-up are always swallowed, and only the live key state shows it.
    let carbon: Bool
    /// The adapter asks the live key state about the chord's Space on each flags event and tells the machine the key-down it
    /// missed (`HotkeyMonitor.feed`). Only the regression test that the search can see its absence turns it off.
    let injection: Bool
    /// Runs K and K0: the pair of talk keys. The second key's own view of the same keys, one element or none (a struct cannot
    /// hold itself), and the sets of keys pressed from rest to test each key (I8p).
    let secondViews: [WalkRun]
    let pressSets: [PressSet]
    /// The pair lets another key's start through (`TalkKeyPair.arbitrate`). Only the regression test that the search can see
    /// that mistake turns it off.
    let arbitrate: Bool
    /// The pair delivers the timers that fell due before a key ahead of that key, across both machines (`TalkKeyPair.deliverInOrder`).
    /// Only the regression test that the search can see a pair that does not turns it off.
    let inOrder: Bool
    /// A mouse button may go down while the second key is held (it cancels that key's turn, never the primary key's).
    let mouse: Bool

    struct PressSet: Sendable { var slot: Int; var codes: [UInt16] }

    let ownMask: UInt16
    /// A key of the own set may be one of several (Option is either side for Control-Option): the own set is down when every
    /// group has a key down. One singleton group for each own key where the run does not say.
    let groupMasks: [UInt16]
    let shiftMask: UInt16
    let ordinaryMask: UInt16
    /// The Space key's bit, 0 in a run without the chord.
    let chordMask: UInt16
    /// The modifier flags of the own set, what a key-down beside it reports.
    let ownFlags: ShortcutModifiers

    var testDescription: String { name }

    init(_ name: String, keys: [WalkKey], own: [UInt16], configs: [VoiceKeyMachine.Config], pointing: Bool = false,
         late: Bool = false, quietFlip: Bool = false, missed: Bool = false, refusal: Bool = false,
         processingTime: Bool = false, chord: Bool = false, carbon: Bool = false, injection: Bool = true,
         groups: [[UInt16]]? = nil, second: (own: [UInt16], configs: [VoiceKeyMachine.Config])? = nil,
         pressSets: [PressSet] = [], arbitrate: Bool = true, inOrder: Bool = true, mouse: Bool = false) {
        self.name = name
        self.mouse = mouse
        self.arbitrate = arbitrate
        self.inOrder = inOrder
        self.pressSets = pressSets
        self.secondViews = second.map { [WalkRun(name + ", second key", keys: keys, own: $0.own, configs: $0.configs, late: late,
                                                  quietFlip: quietFlip, refusal: refusal)] } ?? []
        self.injection = injection
        self.chord = chord
        self.carbon = carbon && chord
        self.processingTime = processingTime
        self.pointing = pointing
        self.late = late && !pointing
        self.quietFlip = quietFlip
        self.missed = missed
        self.refusal = refusal && !pointing
        self.keys = keys
        self.ownCodes = own
        self.configs = configs
        var ownBits: UInt16 = 0, shiftBits: UInt16 = 0, ordinaryBits: UInt16 = 0, chordBits: UInt16 = 0
        var flags: ShortcutModifiers = []
        for (index, key) in keys.enumerated() {
            let bit = UInt16(1) << UInt16(index)
            if own.contains(key.code) { ownBits |= bit; if let flag = key.flag { flags.insert(flag) } }
            if chord, key.code == WalkKey.space.code { chordBits |= bit }
            if key.flag == .shift { shiftBits |= bit }
            if key.flag == nil { ordinaryBits |= bit }
        }
        ownMask = ownBits
        groupMasks = (groups ?? own.map { [$0] }).map { group in
            keys.enumerated().reduce(UInt16(0)) { $0 | (group.contains($1.element.code) ? UInt16(1) << UInt16($1.offset) : 0) }
        }
        shiftMask = shiftBits
        ordinaryMask = ordinaryBits
        chordMask = chordBits
        ownFlags = flags
    }

    private typealias Config = VoiceKeyMachine.Config
    private static let basic: [WalkKey] = [.control, .option, .leftCommand, .shift, .leftArrow, .space]
    private static let rightCommandKeys: [WalkKey] = [.control, .option, .rightCommand, .shift, .leftArrow, .space]
    private static let rightCommandKeysOnPair: [WalkKey] = [.control, .option, .rightCommand, .shift, .leftArrow, .spaceOnPair]
    private static let controlOption: [UInt16] = [59, 58]

    private static func hold(_ role: VoiceKeyMachine.Role, _ key: Shortcut, confirm: TimeInterval, chord: UInt16? = nil) -> Config {
        Config(key: key, role: role, mode: .hold, confirm: confirm, chord: chord)
    }

    /// K and K0 (docs/RIGHT-OPTION-TALK-PLAN.md): the pair of talk keys. Primary Control-Option with the chord, second Right Option
    /// with the 0.25 s confirm and no chord. Option is either side for the primary key, so Control with Right Option is its own
    /// set; Left Option alone is nothing, and beside Right Option it is foreign to the second key.
    static func talkPair(_ name: String, primaryConfirm: TimeInterval, late: Bool, arbitrate: Bool = true, space: Bool = true,
                         leftOption: Bool = true, refusal: Bool = true, inOrder: Bool = true, flip: Bool = false, mouse: Bool = false) -> WalkRun {
        let primary = hold(.talk, .controlOption, confirm: primaryConfirm, chord: 49)
        let second = Config(key: .rightOption, role: .talk, mode: .hold, confirm: 0.25)
        // K-flip turns the second key off and on, riding on the next key event, while the primary key stays as it is.
        let sets = [PressSet(slot: 0, codes: leftOption ? [59, 58] : [59, 61]), PressSet(slot: 1, codes: [61])]
            + (leftOption ? [PressSet(slot: 0, codes: [59, 61])] : [])
        return WalkRun(name, keys: [.control] + (leftOption ? [.option] : []) + [.rightOption, .leftArrow] + (space ? [.spaceOnPair] : []),
                       own: [59, 58, 61], configs: flip ? [primary, primary] : [primary], late: late, quietFlip: flip, refusal: refusal,
                       chord: true, groups: [[59], [58, 61]],
                       second: (own: [61], configs: flip ? [second, Config(key: nil, role: .talk, mode: .hold)] : [second]),
                       pressSets: sets, arbitrate: arbitrate, inOrder: inOrder, mouse: mouse)
    }

    /// The runs of the search: A to I with A0 and E2, J (config changes ride on key events) and B2 (shipped dictation, late).
    static let all: [WalkRun] = [
        // A: shipped talk beside tiling, with the confirm. A0: the same without it.
        WalkRun("A talk hold Control-Option confirm 0.15", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0.15, chord: 49)], late: true, chord: true),
        WalkRun("A0 talk hold Control-Option confirm 0", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0, chord: 49)], late: true, refusal: true, chord: true),
        // B: shipped dictation, with Left Command as a sixth key and a config that flips hold, toggle and off.
        WalkRun("B dictation Right Command hold toggle off", keys: rightCommandKeysOnPair + [.leftCommand], own: [54],
                configs: [hold(.dictation, .rightCommand, confirm: 0.15),
                          Config(key: .rightCommand, role: .dictation, mode: .toggle),
                          Config(key: nil, role: .dictation, mode: .hold)]),
        WalkRun("C dictation hold Control-Option confirm 0.15", keys: basic, own: controlOption,
                configs: [hold(.dictation, .controlOption, confirm: 0.15)], late: true),
        WalkRun("D dictation shared Control-Option", keys: basic, own: controlOption,
                configs: [Config(key: .controlOption, role: .dictation, mode: .shared)], late: true),
        WalkRun("E talk shared Control-Option", keys: basic, own: controlOption,
                configs: [Config(key: .controlOption, role: .talk, mode: .shared)], late: true),
        // E2: the same beside tiling, where the press that ends a hands-free command turn waits out the confirm.
        WalkRun("E2 talk shared Control-Option confirm 0.15", keys: basic, own: controlOption,
                configs: [Config(key: .controlOption, role: .talk, mode: .shared, confirm: 0.15)], late: true),
        WalkRun("F dictation toggle Right Command", keys: rightCommandKeys, own: [54],
                configs: [Config(key: .rightCommand, role: .dictation, mode: .toggle)], missed: true),
        // G: the shipped Polyglot key, Control-Option-T, with T in place of the arrow.
        WalkRun("G toggle Control-Option-T", keys: [.control, .option, .leftCommand, .shift, .letterT, .leftArrow, .space], own: [59, 58, 17],
                configs: [Config(key: Shortcut(keyCode: 17, modifiers: [.control, .option]), role: .dictation, mode: .toggle)],
                missed: true),
        // H: shipped pointing, Control-Option, with the confirm. The config only carries the key and the confirm.
        WalkRun("H pointing Control-Option confirm 0.15", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0.15)], pointing: true, missed: true),
        // I: talk on Fn, the Globe key in place of Command.
        WalkRun("I talk hold Fn", keys: [.control, .option, .globe, .shift, .leftArrow, .space], own: [63],
                configs: [hold(.talk, .function, confirm: 0)], late: true, missed: true),
        // J: shipped dictation again with its config changes riding on key events. Run B delivers its flips on ticks of their own, so it cannot see a press that is both.
        WalkRun("J dictation Right Command hold toggle off, changes ride on events",
                keys: [.control, .rightCommand, .shift, .leftArrow, .space], own: [54],
                configs: [hold(.dictation, .rightCommand, confirm: 0.15),
                          Config(key: .rightCommand, role: .dictation, mode: .toggle),
                          Config(key: nil, role: .dictation, mode: .hold)], quietFlip: true),
        // B2: shipped dictation with late timers and keys heard late. B's three configs and these together took 450 s, so
        // the late search keeps B's keys and only its hold config.
        WalkRun("B2 dictation Right Command hold, late", keys: rightCommandKeysOnPair + [.leftCommand], own: [54],
                configs: [hold(.dictation, .rightCommand, confirm: 0.15)], late: true),
        // A1: shipped talk with no chord (VoiceOver is on, or Chat holds Control-Option-Space): Space is a plain foreign key.
        WalkRun("A1 talk hold Control-Option confirm 0.15, no chord", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0.15)], late: true),
        // A-carbon: the shipped chord where Carbon swallows every Space down and up, so no monitor ever hears it.
        WalkRun("A-carbon talk hold Control-Option confirm 0.15, every Space swallowed", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0.15, chord: 49)], late: true, chord: true, carbon: true),
        // K: the pair of talk keys, Control-Option and Right Option, one turn at a time. K0: the same with no confirm on the
        // primary key and no late timers.
        // Fallbacks of the plan's walk budget: K has no late timers and no Space (the full K did not finish in 30 minutes), K0 has no
        // Space (with it, past 730,000 states and still growing). The chord beside Right Option stays in the unit tests.
        talkPair("K talk pair Control-Option confirm 0.15 and Right Option confirm 0.25", primaryConfirm: 0.15, late: false, space: false),
        talkPair("K0 talk pair Control-Option confirm 0 and Right Option confirm 0.25", primaryConfirm: 0, late: false, space: false),
        // K-late and K-flip: the cross-machine orders that K and K0 cannot see, a timer that runs late and a second key that is turned
        // off or on between two keys. Three keys (no Left Option, no Space) keep them bounded.
        talkPair("K-late15 talk pair, late timers, primary confirm 0.15", primaryConfirm: 0.15, late: true, space: false, leftOption: false),
        talkPair("K-late0 talk pair, late timers, primary confirm 0", primaryConfirm: 0, late: true, space: false, leftOption: false),
        talkPair("K-flip talk pair, second key turned off and on", primaryConfirm: 0.15, late: false, space: false, leftOption: false,
                 refusal: false, flip: true, mouse: true),
    ]
}

// MARK: - The harness

/// How long a held monitor event may wait, in steps of 0.05 s: the main thread is busy for up to this long. It is as long
/// as the longest window (0.4 s), so a key can come inside a tap's gap and be heard after it.
private let lagLimit = 8
/// The lags the search tries: one inside the shortest delay (0.05 s), one just past the confirm (0.2 s), and the longest.
/// Every other lag falls in one of the same three cases against the delays (0.15, 0.25) and the gaps (0.35, 0.4).
private let lags = [1, 4, lagLimit]

/// What the machine had been told about the keyboard, at the time a key that arrives went down or up, as ages in steps
/// capped at 9: how long exactly the own set had been down (nil: it was not), and how long the own set had been let go
/// (nil: it was down).
private struct Arrival: Hashable {
    var alone: Int?
    var up: Int?
}

/// A monitor event held back for one event: the machine hears the next forwarded key first.
private struct Held: Hashable {
    enum Kind: UInt8 { case flags, down, up }
    var kind: Kind
    var code: UInt16
    var mods: UInt8
    var index: UInt8
    var pressed: Bool

    init(_ event: ShortcutEvent, index: Int, pressed: Bool) {
        self.index = UInt8(index)
        self.pressed = pressed
        switch event {
        case .flags(let code, let mods): kind = .flags; self.code = code; self.mods = mods.rawValue
        case .keyDown(let code, let mods): kind = .down; self.code = code; self.mods = mods.rawValue
        case .keyUp(let code): kind = .up; self.code = code; mods = 0
        }
    }

    var event: ShortcutEvent {
        let modifiers = ShortcutModifiers(rawValue: mods)
        switch kind {
        case .flags: return .flags(keyCode: code, modifiers: modifiers)
        case .down: return .keyDown(keyCode: code, modifiers: modifiers)
        case .up: return .keyUp(keyCode: code)
        }
    }
}

private enum Move: Hashable {
    /// A key goes down or up and its event reaches the machine at once; `toggleHeld`: the event of a modifier key or an
    /// unconsumed key waits for the next forwarded key.
    case toggle(Int), toggleHeld(Int), swallowed(Int), wait, waitHalfSecond, deliver, abandon, interrupt, flip
    /// The main thread was busy for this many steps while an event was held back: the event is then heard at the time it
    /// happened, ahead of the wakes that fell due meanwhile (`busy`), or after them (`catchUp`).
    case busy(Int), catchUp(Int)
    /// A mouse button goes down (run K-flip): foreign to the second key only.
    case mouse
    /// Time passes and a due timer waits for the next event. A config change that waits for the next event. An ordinary
    /// key comes up and no monitor hears. The owner starts or stops refusing the turns it is asked to start.
    case waitLate, flipQuiet, missUp(Int), refusing

    func text(_ run: WalkRun) -> String {
        switch self {
        case .toggle(let index): run.keys[index].name
        case .toggleHeld(let index): run.keys[index].name + " (event held)"
        case .swallowed(let index): run.keys[index].name + " (swallowed, no event)"
        case .wait: "wait 0.05"
        case .waitHalfSecond: "wait 0.5"
        case .deliver: "deliver"
        case .abandon: "abandon"
        case .interrupt: "interrupt"
        case .flip: "flip"
        case .busy(let steps): "busy \(steps) steps, then the held event, then the timers"
        case .catchUp(let steps): "wait \(steps) steps with the timers, then the held event"
        case .waitLate: "wait 0.05 (timers late)"
        case .flipQuiet: "flip (rides on the next event)"
        case .missUp(let index): run.keys[index].name + " up (no event)"
        case .refusing: "owner refuses turns"
        case .mouse: "mouse down"
        }
    }
}

private enum Kind { case key, tick, deliver, abandon, interrupt, flip, sweep, echo }

/// What the keys physically down say, for one run.
private struct Phys {
    var ownAll = false
    var foreignAny = false
    var onlyShift = false
    var exactOwn = false
    var anyDown = false

    /// `hidden`: keys that are down but do not count, a clean chord's Space.
    init(_ keysDown: UInt16, _ run: WalkRun, hidden: UInt16 = 0) {
        let down = keysDown & ~hidden
        ownAll = run.groupMasks.allSatisfy { down & $0 != 0 }
        let foreign = down & ~run.ownMask
        foreignAny = foreign != 0
        onlyShift = foreign != 0 && foreign & ~run.shiftMask == 0
        exactOwn = ownAll && foreign == 0
        anyDown = down != 0
    }
}

/// What the rules remember between steps. Part of the state key, so two paths that differ here are two states.
private struct Checker: Hashable {
    /// A turn (not a toggle) is open: from its `start` to its `send`, `cancel` or `abandon`.
    var turnOpen = false
    /// Something foreign was down since that start. Shift does not count for a dictation key.
    var foreign = false
    var shiftSeen = false
    /// A cancel happened and a key is still down (I2).
    var cancelled = false
    /// The whole own set was down with something foreign since everything was last up (I6).
    var bigger = false
    /// Starts of a toggle during the press now down (I7).
    var presses = 0
    /// Steps the own set has been down, capped.
    var pressAge = 0
    /// Something foreign was down at any time since this press began.
    var pressForeign = false
    var ownWasDown = false
    /// Space went down while the own set was down alone and neither it nor an own modifier has come up since.
    var chordClean = false
    /// Space came down clean and has not come up: it never makes an open turn foreign, even after a modifier has been let
    /// go with Space still down (a clean release). A new press of the own set beside it is another matter: only a clean
    /// Space is left out of I3 and I6.
    var chordForgiven = false
    /// By the physical keys, whatever any monitor heard: Space is down and went down while exactly the own set was down, and
    /// no other key has moved since. A start with a Space down that is not this one is a start the keyboard did not earn.
    var spaceClean = false
    /// The own set came down (as the machine was told) while a Space was physically down that was not `spaceClean`: a press
    /// beside a Space that the keyboard did not earn as a chord. The machine may have heard of that Space or not. A press
    /// judged at the physical state when it is heard, not when its keys went down, because that is what a start can follow.
    var dirtySpaceAtPress = false
}

private struct Edge {
    var cameDown = false
    var released = false
    /// The press that this step let go came down beside a Space the keyboard did not earn as a chord: the step that lets it go
    /// has already cleared `dirtySpaceAtPress`, and a quick press ends a hands-free turn at its release.
    var releasedDirty = false
}

/// The state of one search node. The machine is held as the four things it reads: the config, the flags-only modifier
/// set, the physical keys and the spoilers of its keyboard picture, `barred`, `chordSpoiled` and the phase with ages in place of
/// times. `ShortcutState.modifiers` is left out because nothing in the machine reads it.
private struct StateKey: Hashable {
    var down: UInt16
    var seen: UInt16
    var consumed: UInt16
    var held: Held?
    var wakes: [Int]
    var cfg: Int
    var config: VoiceKeyMachine.Config?
    var flags: ShortcutModifiers
    var deviceKeys: Set<UInt16>
    var keysDown: Set<UInt16>
    var spoilers: Set<UInt16>
    var barred: Bool
    var chordSpoiled: Bool
    var phase: VoiceKeyMachine.Phase
    var pointing: PointingNorm?
    var refusing: Bool
    var checker: Checker
    /// How long the keyboard has been exactly the own set, read by an armed press, and without it, read by a tap's gap.
    var aloneAge: Int?
    var upAge: Int?
    /// Runs K and K0: everything above for the second key, and what the pair itself and its rules remember.
    var second: SlotKey?
    var pairOwner: Int?
    var pairBar: Int?
    var pairCheck = PairCheck()
}

/// What the pair's rules remember between steps: which key's turn is open, and which key's turn ended while a key was still down.
private struct PairCheck: Hashable {
    var open: Int?
    var ended: Int?
}

/// The second slot of a pair as the state key holds it.
private struct SlotKey: Hashable {
    var seen: UInt16
    var wakes: [Int]
    var config: VoiceKeyMachine.Config?
    var flags: ShortcutModifiers
    var deviceKeys: Set<UInt16>
    var keysDown: Set<UInt16>
    var spoilers: Set<UInt16>
    var barred: Bool
    var chordSpoiled: Bool
    var phase: VoiceKeyMachine.Phase
    var checker: Checker
    var aloneAge: Int?
    var upAge: Int?
}

/// A pointing gesture with ages in place of times, capped at 0.45 s like the machine's phase: the confirm and the 0.25 s
/// watchdog are inside it. The double Control tap (three timers in the gesture) is left out of the key: it only ever
/// returns `doubleTapControl`, which no rule reads, and it never changes what `feed` decides about a hold.
private struct PointingNorm: Hashable {
    var state: ShortcutState
    var active: Bool
    var blocked: Bool
    var waitForRelease: Bool
    var activeAge: Int?
    var armedAge: Int?

    init(_ gesture: PointingKeyGesture, now: TimeInterval) {
        func age(_ time: TimeInterval?) -> Int? { time.map { min(9, max(0, Int(((now - $0) / 0.05).rounded()))) } }
        state = gesture.state
        active = gesture.isActive
        blocked = gesture.blockedByVoiceOver
        waitForRelease = gesture.waitForRelease
        activeAge = age(gesture.activeSince)
        armedAge = age(gesture.armedSince)
    }
}

private extension VoiceKeyMachine {
    /// The phase with ages in place of times, capped at 0.45 s, past every window (the longest is 0.4 s): the same
    /// phase whenever it was reached. A key heard late is read at its own time inside one move, before any state is
    /// recorded, and every key after it is stamped no earlier than the state, so the cap holds.
    func normalizedPhase(at now: TimeInterval) -> Phase {
        func age(_ time: TimeInterval) -> TimeInterval { Double(min(9, max(0, Int(((now - time) / 0.05).rounded())))) * 0.05 }
        func ahead(_ time: TimeInterval) -> TimeInterval { Double(min(9, max(0, Int(((time - now) / 0.05).rounded())))) * 0.05 }
        switch phase {
        case .idle, .latched, .spent: return phase
        case .armed(let since, let press): return .armed(since: age(since), press: press)
        case .holding(let since, let second, let check, let shifted):
            return .holding(since: age(since), second: second, check: ahead(check), shifted: shifted)
        case .tapped(let at, let open): return .tapped(at: age(at), open: open)
        }
    }
}

private struct Sim {
    static let keymap = TileKeymap.defaults(base: .standard)
    static let gate = TileKeyGate(enabled: true)

    var plain = VoiceKeyMachine()
    /// Runs K and K0: the pair of talk keys stands in for the machine. The rules are read one slot at a time: `machine`,
    /// `checker`, `seen` and the rest are those of the slot that is selected (the primary between steps), and the other
    /// slot's judge waits in `other` (see `select`).
    var pair: TalkKeyPair?
    var activeSlot = 0
    var other = Judge()
    var pairCheck = PairCheck()
    /// Run H: the gesture stands in for the machine; the machine stays as it was made.
    var pointing: PointingKeyGesture?
    var down: UInt16 = 0
    /// The keys the machine has been told are down: the physical keys, less the events that are still on the way.
    /// The rules are read against this, because a key the machine was never told about cannot be told from no key.
    var seen: UInt16 = 0
    /// `seen` as it stood at the last `seenChanged`, to tell a key that has just arrived. Not part of the key: it always
    /// equals `seen` between two steps.
    var previouslySeen: UInt16 = 0
    /// The Space that is arriving is a clean chord by what the key itself reports. Not part of the key.
    var arrivingChord = false
    var consumed: UInt16 = 0
    /// At most one monitor event waits behind the next forwarded key.
    var held: Held?
    /// The step at which the held event happened: the time it carries when it reaches the machine.
    var heldStep = 0
    /// The step (the time its key carried) at which the keys the machine has been told about became exactly the own set,
    /// nil while they are not; the step at which the own set was let go, nil while it is down.
    var aloneSince: Int?
    var ownUpSince: Int? = 0
    /// What the machine had been told when the key now arriving went down or up, and how late it arrives.
    var arriving: Arrival?
    var arrivalLag = 0
    var wakes: Set<Int> = []
    var step = 0
    var cfg = 0
    var matcher = TileKeyMatcher()
    var checker = Checker()
    /// The owner refuses every turn it is asked to start.
    var refusing = false
    /// How many `start` effects the rules have seen. Not part of the key: the open turn is always the latest.
    var startCount = 0

    // Not part of the key: what the last move did.
    var edge = Edge()
    var log: [VoiceKeyMachine.Effect] = []
    var found: [String] = []

    var now: TimeInterval { Double(step) * 0.05 }

    /// The machine of the selected slot (the one machine of every run but K and K0).
    var machine: VoiceKeyMachine {
        get { guard let pair else { return plain }; return activeSlot == 0 ? pair.primary : pair.second }
        _modify {
            if pair == nil { yield &plain } else if activeSlot == 0 { yield &pair!.primary } else { yield &pair!.second }
        }
    }

    /// What the rules keep for one slot, swapped in while that slot is judged.
    struct Judge: Hashable {
        var seen: UInt16 = 0
        var previouslySeen: UInt16 = 0
        var checker = Checker()
        var aloneSince: Int?
        var ownUpSince: Int? = 0
        var wakes: Set<Int> = []
    }

    /// Judges the given slot from here on: its judge is swapped in and its machine read.
    mutating func select(_ slot: Int) {
        guard slot != activeSlot else { return }
        swap(&seen, &other.seen)
        swap(&previouslySeen, &other.previouslySeen)
        swap(&checker, &other.checker)
        swap(&aloneSince, &other.aloneSince)
        swap(&ownUpSince, &other.ownUpSince)
        swap(&wakes, &other.wakes)
        activeSlot = slot
    }

    var isLatchedNow: Bool { pair?.isLatched ?? machine.isLatched }
    var turnOpenNow: Bool { pair == nil ? checker.turnOpen : pairCheck.open != nil }
    var generationNow: Int { pair?.generation ?? machine.generation }
    /// Every wake the rules are waiting for, of both slots (the primary is selected between steps).
    var allWakes: Set<Int> { wakes.union(other.wakes) }

    init(_ run: WalkRun) {
        if !run.secondViews.isEmpty {
            var made = TalkKeyPair()
            made.arbitrate = run.arbitrate
            made.deliverInOrder = run.inOrder
            pair = made
        }
        guard run.pointing, let key = run.configs[0].key else { return }
        var gesture = PointingKeyGesture(shortcut: key)
        gesture.confirm = run.configs[0].confirm
        pointing = gesture
    }

    func key(_ run: WalkRun) -> StateKey {
        // The keyboard's own history is read only by a timer that is settled ahead of a key: a start of an armed press, a send
        // of a tap that waits out its gap.
        var armed = false, gapOpen = false
        switch machine.phase {
        case .armed: armed = true
        case .tapped(_, true): gapOpen = true
        default: break
        }
        var out = StateKey(down: down, seen: seen, consumed: consumed, held: held, wakes: wakes.map { max($0 - step, -2) }.sorted(), cfg: cfg,
                 config: machine.config, flags: machine.keys.flagModifiers, deviceKeys: machine.keys.deviceKeys,
                 keysDown: machine.keys.keysDown, spoilers: machine.keys.spoilers, barred: machine.barred, chordSpoiled: machine.chordSpoiled,
                 phase: machine.normalizedPhase(at: now), pointing: pointing.map { PointingNorm($0, now: now) },
                 refusing: refusing, checker: checker,
                 aloneAge: armed ? aloneSince.map { min(9, step - $0) } : nil, upAge: gapOpen ? ownUpSince.map { min(9, step - $0) } : nil)
        if let pair {
            var theirs = self
            theirs.select(1)
            out.second = theirs.slotKey()
            out.pairOwner = pair.owner.map { $0 == .primary ? 0 : 1 }
            out.pairBar = pair.bar.map { $0 == .primary ? 0 : 1 }
            out.pairCheck = pairCheck
        }
        return out
    }

    /// The selected slot as the state key holds it.
    private func slotKey() -> SlotKey {
        var armed = false, gapOpen = false
        switch machine.phase {
        case .armed: armed = true
        case .tapped(_, true): gapOpen = true
        default: break
        }
        return SlotKey(seen: seen, wakes: wakes.map { max($0 - step, -2) }.sorted(), config: machine.config,
                       flags: machine.keys.flagModifiers, deviceKeys: machine.keys.deviceKeys, keysDown: machine.keys.keysDown,
                       spoilers: machine.keys.spoilers, barred: machine.barred, chordSpoiled: machine.chordSpoiled,
                       phase: machine.normalizedPhase(at: now), checker: checker,
                       aloneAge: armed ? aloneSince.map { min(9, step - $0) } : nil,
                       upAge: gapOpen ? ownUpSince.map { min(9, step - $0) } : nil)
    }

    func liveModifiers(_ run: WalkRun) -> ShortcutModifiers {
        var live: ShortcutModifiers = []
        for (index, key) in run.keys.enumerated() where down & (UInt16(1) << UInt16(index)) != 0 {
            if let flag = key.flag { live.insert(flag) }
        }
        return live
    }

    func moves(_ run: WalkRun) -> [Move] {
        var out: [Move] = []
        for index in run.keys.indices {
            // A restricted key is offered while its modifiers are down, or while it is down itself and can come up.
            if let only = run.keys[index].onlyWith, down & (UInt16(1) << UInt16(index)) == 0, !liveModifiers(run).isSuperset(of: only) {
                continue
            }
            if run.carbon, run.chordMask == UInt16(1) << UInt16(index) {
                out.append(.swallowed(index))
                continue
            }
            out.append(.toggle(index))
            if held == nil { out.append(.toggleHeld(index)) }
            if run.chord, run.chordMask == UInt16(1) << UInt16(index) { out.append(.swallowed(index)) }
        }
        // Time passes while an event is held back: the main thread may be busy, and a wake runs on the same queue. Time
        // passes only inside one of the moves that end by handing the event over, for up to `lagLimit` steps, so no state
        // holds an event that is late. Pointing hears every key at the time it is handled.
        if held == nil || run.pointing || !run.late { out.append(.wait) }
        if held != nil {
            out.append(.deliver)
            if !run.pointing, run.late {
                for steps in lags {
                    out.append(.catchUp(steps))
                    if run.late { out.append(.busy(steps)) }
                }
            }
        }
        if pointing == nil { out.append(.abandon) }
        // A config change arrives on a tick of its own, which the walk keeps to a quiet keyboard.
        if run.configs.count > 1, held == nil { out.append(.flip) }
        if held == nil, down & run.ordinaryMask == 0 { out.append(.interrupt) }
        // A due timer may wait for the next event, for up to one step past its time.
        if run.late, held == nil, !allWakes.isEmpty, allWakes.allSatisfy({ step - $0 < 1 }) { out.append(.waitLate) }
        if run.quietFlip, run.configs.count > 1 { out.append(.flipQuiet) }
        if run.refusal { out.append(.refusing) }
        // The mouse is offered while Right Option is held: the second key's turn is armed or open.
        if run.mouse, pair != nil, let index = run.keys.firstIndex(where: { $0.code == 61 }), down & (UInt16(1) << UInt16(index)) != 0 {
            out.append(.mouse)
        }
        if run.missed, held == nil {
            // An own key whose key-up is lost is pressed again before anything can tell, so only foreign keys go missing.
            for index in run.keys.indices where run.keys[index].flag == nil && run.ownMask & (UInt16(1) << UInt16(index)) == 0 {
                let bit = UInt16(1) << UInt16(index)
                if down & bit != 0, seen & bit != 0, consumed & bit == 0 { out.append(.missUp(index)) }
            }
        }
        return out
    }

    /// The moves of the plain walk: the keys, a short and a long wait, and an abandon.
    func plainMoves(_ run: WalkRun) -> [Move] {
        run.keys.indices.map { Move.toggle($0) } + [.wait, .waitHalfSecond, .abandon]
    }

    // MARK: Applying a move

    mutating func apply(_ move: Move, _ run: WalkRun) {
        switch move {
        case .toggle(let index): toggle(index, hold: false, run)
        case .toggleHeld(let index): toggle(index, hold: true, run)
        case .swallowed(let index): swallow(index, run)
        case .wait: advance(run)
        case .waitHalfSecond: for _ in 0..<10 { advance(run) }
        case .deliver: flushHeld(run)
        case .abandon: feed(.abandon(turn: generationNow), .abandon, run)
        case .interrupt:
            // The resync takes the system's modifiers and forgets ordinary keys; the walk lets go of them first.
            seen &= ~run.ordinaryMask
            seenChanged(run)
            if let view = run.secondViews.first {
                select(1)
                seen &= ~view.ordinaryMask
                seenChanged(view)
                select(0)
            }
            feed(.interrupt(live: liveModifiers(run)), .interrupt, run)
        case .flip:
            cfg = (cfg + 1) % run.configs.count
            feed(.tick(at: now, live: liveModifiers(run)), .flip, run)
        case .busy(let steps):
            for _ in 0..<steps { advance(run, deliver: false) }
            flushHeld(run)
        case .catchUp(let steps):
            for _ in 0..<steps { advance(run) }
            flushHeld(run)
        case .waitLate: advance(run, deliver: false)
        case .flipQuiet: cfg = (cfg + 1) % run.configs.count
        case .missUp(let index): missUp(index, run)
        case .refusing: refusing.toggle()
        case .mouse: feedPair(.key(.keyUp(keyCode: TalkKeyPair.mouseCode), at: now), .key, run, key: nil, drain: true, mouse: true)
        }
        if !checker.ownWasDown { checker.pressForeign = false }
        if !other.checker.ownWasDown { other.checker.pressForeign = false }
    }

    /// A held event reaches the machine. `drain`: the timers that are due run after it. They do not when the flush is
    /// part of the next key's arrival: no time passes between the two, and the physical keys are already ahead.
    private mutating func flushHeld(_ run: WalkRun, drain: Bool = true) {
        guard let event = held?.event else { return }
        let (index, pressed) = (Int(held?.index ?? 0), held?.pressed ?? false)
        // The key carries the time it happened. Pointing, and an adapter that stamps keys with the time it handles them,
        // hear it at the time it is handled.
        // A run whose rules do not read lateness hears every key at the time it is handled, as pointing does.
        let stamped = run.pointing || run.processingTime || !run.late
        arrivalLag = run.pointing || !run.late ? 0 : step - heldStep
        held = nil
        feed(.key(event, at: stamped ? now : Double(step - arrivalLag) * 0.05), .deliver, run, key: (index, pressed), drain: drain)
        arrivalLag = 0
    }

    /// One monitor event reaches the machine, behind the one held back before it, or is held back itself.
    private mutating func monitor(_ event: ShortcutEvent, index: Int, pressed: Bool, hold: Bool, _ run: WalkRun) {
        flushHeld(run, drain: false)
        if hold {
            held = Held(event, index: index, pressed: pressed)
            heldStep = step
        } else {
            feed(.key(event, at: now), .key, run, key: (index, pressed))
        }
    }

    /// The Carbon hot key takes Space from the monitors: the key goes down or up and no event comes. The machine hears of a
    /// Space it never saw go down only when it comes up, and a Space whose release was swallowed is dropped by the sweep.
    private mutating func swallow(_ index: Int, _ run: WalkRun) {
        let bit = UInt16(1) << UInt16(index)
        let pressing = down & bit == 0
        notePhysical(index, pressing: pressing, run)
        down ^= bit
        if !pressing {
            let tile = TileKeyEvent(phase: .up, keyCode: run.keys[index].code, modifiers: liveModifiers(run))
            _ = matcher.decide(tile, keymap: Self.keymap, gate: Self.gate)
        }
    }

    private mutating func toggle(_ index: Int, hold: Bool, _ run: WalkRun) {
        let bit = UInt16(1) << UInt16(index)
        let key = run.keys[index]
        let pressing = down & bit == 0
        notePhysical(index, pressing: pressing, run)
        down ^= bit
        let live = liveModifiers(run)
        if key.flag != nil {
            monitor(.flags(keyCode: key.code, modifiers: live), index: index, pressed: pressing, hold: hold, run)
            return
        }
        // An ordinary key goes through the real tiling matcher first. A key it consumes never reaches the monitors:
        // it comes back as the forwarded event, at once, and so ahead of a monitor event that was held back.
        let marked = TileKeymap.fnMarkedKeyCodes.contains(key.code)
        let mods = marked ? live.union(.function) : live
        let tile = TileKeyEvent(phase: pressing ? .down : .up, keyCode: key.code, modifiers: mods)
        let decision = matcher.decide(tile, keymap: Self.keymap, gate: Self.gate)
        if let forwarded = decision.monitorEvent(for: tile) {
            if pressing { consumed |= bit } else { consumed &= ~bit }
            feed(.key(forwarded, at: now), .key, run, key: (index, pressing))
        } else {
            monitor(pressing ? .keyDown(keyCode: key.code, modifiers: mods) : .keyUp(keyCode: key.code), index: index,
                    pressed: pressing, hold: hold, run)
        }
    }

    private mutating func advance(_ run: WalkRun, deliver: Bool = true) {
        step += 1
        // The press ages under the confirm the machine knows; a config change that has not reached it yet changes nothing.
        let confirmSteps = Int(((machine.config ?? run.configs[cfg]).confirm / 0.05).rounded())
        if checker.ownWasDown, confirmSteps > 0 { checker.pressAge = min(checker.pressAge + 1, confirmSteps) }
        if let pair, let view = run.secondViews.first {
            let secondSteps = Int(((pair.second.config ?? view.configs[min(cfg, view.configs.count - 1)]).confirm / 0.05).rounded())
            if other.checker.ownWasDown, secondSteps > 0 { other.checker.pressAge = min(other.checker.pressAge + 1, secondSteps) }
        }
        if deliver { drainWakes(run) }
    }

    /// An ordinary key comes up and no monitor hears it. The tiling matcher, which watches every event, does.
    private mutating func missUp(_ index: Int, _ run: WalkRun) {
        let bit = UInt16(1) << UInt16(index)
        notePhysical(index, pressing: false, run)
        down &= ~bit
        let tile = TileKeyEvent(phase: .up, keyCode: run.keys[index].code, modifiers: liveModifiers(run))
        _ = matcher.decide(tile, keymap: Self.keymap, gate: Self.gate)
    }

    /// A physical key moves, before `down` changes: Space comes down clean only beside exactly the own set, and any other
    /// key moving while it is down ends that.
    private mutating func notePhysical(_ index: Int, pressing: Bool, _ run: WalkRun) {
        guard run.chord else { return }
        if run.chordMask == UInt16(1) << UInt16(index) {
            checker.spaceClean = pressing && Phys(down, run).exactOwn
        } else {
            checker.spaceClean = false
        }
    }

    /// Delivers every tick that is due, as the adapter would: each with the modifiers that are really down.
    private mutating func drainWakes(_ run: WalkRun) {
        var guardCount = 0
        while guardCount < 100 {
            let mine = wakes.filter { $0 <= step }.min()
            let theirs = other.wakes.filter { $0 <= step }.min()
            guard let due = [mine, theirs].compactMap({ $0 }).min() else { break }
            guardCount += 1
            if mine == due { wakes.remove(due) } else { other.wakes.remove(due) }
            feed(.tick(at: now, live: liveModifiers(run)), .tick, run)
        }
    }

    private mutating func feed(_ event: VoiceKeyMachine.Event, _ kind: Kind, _ run: WalkRun, key: (Int, Bool)? = nil,
                               drain: Bool = true) {
        if pair != nil { feedPair(event, kind, run, key: key, drain: drain); return }
        if key != nil { sweepStale(run); injectSwallowedSpace(event, run) }
        edge = Edge()
        let seenBefore = seen
        let config = run.configs[cfg]
        let configChange = changesConfig(config)
        let wasLatched = machine.isLatched
        let ticking = tickReadsLive
        let before = stage
        let stampStep = step - arrivalLag
        arriving = key == nil ? nil : Arrival(alone: aloneSince.map { min(9, stampStep - $0) }, up: ownUpSince.map { min(9, stampStep - $0) })
        // A Space that comes down beside the own set alone, by what the machine knows and by what the key reports, is clean.
        arrivingChord = false
        var chordMoved = false
        if run.chord, let (index, pressed) = key, run.chordMask == UInt16(1) << UInt16(index) {
            if pressed, case .key(.keyDown(_, let reported), _) = event {
                arrivingChord = Phys(seen, run).exactOwn && reported.subtracting(.function) == run.ownFlags
                chordMoved = arrivingChord
            } else if !pressed {
                chordMoved = !pressed && checker.chordClean
            }
        }
        var due: Overdue?
        if key != nil, !configChange, case .key(let shortcut, let time) = event { due = overdue(config, at: time, event: shortcut) }
        let owed = due?.effects ?? []
        let effects = handle(event, config: config)
        forgetDroppedSpace(after: event, run)
        log += effects
        // A wake belongs to the phase that asked for it. Once the phase has changed the old ones are dropped, so a
        // phase that forgets to ask for its own wake is caught, not covered by a stale one.
        if stage != before { wakes.removeAll() }
        for effect in effects {
            if case .wake(let after) = effect { wakes.insert(step + Int((after / 0.05).rounded())) }
        }
        if owed.isEmpty {
            noteKey(key, run)
            noteLive(event, acting: ticking && !configChange, run)
            checkEffects(effects, wasLatched: wasLatched, kind: kind, config: config, configChange: configChange,
                         seenBefore: seenBefore, run)
        } else {
            // A timer that was due before the key acts first, and its effects are read on the keyboard as it was.
            let timer = Array(effects.prefix(owed.count))
            if timer != owed { found.append("an overdue timer did not act before the key that came after it: \(effects)") }
            checkEffects(timer, wasLatched: wasLatched, kind: .tick, config: config, configChange: false, seenBefore: seenBefore, run)
            if let due { checkSettled(due) }
            noteKey(key, run)
            checkEffects(Array(effects.dropFirst(owed.count)), wasLatched: false, kind: kind, config: config, configChange: false,
                         seenBefore: seenBefore, run)
        }
        if chordMoved, kind == .key || kind == .deliver {
            let own = Array(effects.dropFirst(owed.count)).filter { if case .wake = $0 { return false } else { return true } }
            if !own.isEmpty { found.append("I9: an event that only moved a clean chord's Space gave \(own)") }
        }
        arrivingChord = false
        if case .abandon(let turn) = event, checker.turnOpen, turn == startCount { checker.turnOpen = false }
        checkEnd(wasLatched: wasLatched, seenBefore: seenBefore, key: key, config: config, run)
        runOwner(effects, config: config, run)
        if drain, held == nil, kind != .tick, kind != .sweep, kind != .echo { drainWakes(run) }
    }

    /// What one slot needs from before the pair hears an event.
    private struct Pre {
        var seenBefore: UInt16 = 0
        var wasLatched = false
        var ticking = false
        var configChange = false
        var owed: Overdue?
        var arriving: Arrival?
        var arrivingChord = false
        var chordMoved = false
        var stage = Stage(phase: .idle, pointing: 0)
        /// When the timer this slot owes ahead of the key was due.
        var dueAt: TimeInterval?
    }

    /// One event reaches the pair (runs K and K0). Each slot is judged as `feed` judges one key, on what the pair let through
    /// of its machine's effects; what the pair itself must keep (one open turn, the other key waits) is judged across both.
    private mutating func feedPair(_ event: VoiceKeyMachine.Event, _ kind: Kind, _ run: WalkRun, key: (Int, Bool)?, drain: Bool,
                                   mouse: Bool = false) {
        guard let view = run.secondViews.first else { return }
        if key != nil { sweepStale(run); injectSwallowedSpace(event, run) }
        let views = [run, view]
        let configs = [run.configs[cfg], view.configs[min(cfg, view.configs.count - 1)]]
        let stampStep = step - arrivalLag
        var pre = [Pre(), Pre()]
        for slot in 0..<2 {
            select(slot)
            let config = configs[slot], slotRun = views[slot]
            var p = Pre()
            p.seenBefore = seen
            p.wasLatched = machine.isLatched
            p.ticking = tickReadsLive && tickIsDue(config)
            p.configChange = changesConfig(config)
            p.stage = stage
            p.arriving = key == nil ? nil : Arrival(alone: aloneSince.map { min(9, stampStep - $0) }, up: ownUpSince.map { min(9, stampStep - $0) })
            if slotRun.chord, let (index, pressed) = key, slotRun.chordMask == UInt16(1) << UInt16(index) {
                if pressed, case .key(.keyDown(_, let reported), _) = event {
                    p.arrivingChord = Phys(seen, slotRun).exactOwn && reported.subtracting(.function) == slotRun.ownFlags
                    p.chordMoved = p.arrivingChord
                } else if !pressed {
                    p.chordMoved = checker.chordClean
                }
            }
            if key != nil, !p.configChange, case .key(let shortcut, let time) = event { p.owed = overdue(config, at: time, event: shortcut) }
            if p.owed != nil { p.dueAt = dueTime(config) }
            pre[slot] = p
        }
        select(0)
        let strays = pair?.strays ?? 0
        let barBefore = pair?.bar
        let ownerBefore = pair?.owner
        let time = now
        let tagged = (mouse ? pair?.mouseDownTagged(at: time, primary: configs[0], second: configs[1])
                            : pair?.handleTagged(event, primary: configs[0], second: configs[1])) ?? []
        let trace = pair?.trace ?? []
        log += tagged.map(\.effect)
        for slot in 0..<2 {
            select(slot)
            let config = configs[slot], slotRun = views[slot], p = pre[slot]
            let raw = trace.filter { $0.slot == (slot == 0 ? .primary : .second) }
            let owed = p.owed?.effects ?? []
            edge = Edge()
            arriving = p.arriving
            arrivingChord = p.arrivingChord
            forgetDroppedSpace(after: event, slotRun)
            // A wake belongs to the phase of the slot that asked for it.
            if stage != p.stage { wakes.removeAll() }
            for entry in raw where entry.emitted {
                if case .wake(let after) = entry.effect { wakes.insert(step + Int((after / 0.05).rounded())) }
            }
            if owed.isEmpty {
                noteKey(key, slotRun)
                noteLive(event, acting: p.ticking && !p.configChange, slotRun)
                checkEffects(raw.filter(\.emitted).map(\.effect), wasLatched: p.wasLatched, kind: kind, config: config,
                             configChange: p.configChange, seenBefore: p.seenBefore, slotRun)
            } else {
                let timerRaw = Array(raw.prefix(owed.count))
                if timerRaw.map(\.effect) != owed { found.append("an overdue timer did not act before the key that came after it: \(raw.map(\.effect))") }
                checkEffects(timerRaw.filter(\.emitted).map(\.effect), wasLatched: p.wasLatched, kind: .tick, config: config,
                             configChange: false, seenBefore: p.seenBefore, slotRun)
                if let due = p.owed { checkSettled(due) }
                noteKey(key, slotRun)
                checkEffects(raw.dropFirst(owed.count).filter(\.emitted).map(\.effect), wasLatched: false, kind: kind, config: config,
                             configChange: false, seenBefore: p.seenBefore, slotRun)
            }
            if p.chordMoved, kind == .key || kind == .deliver {
                let own = raw.dropFirst(owed.count).filter(\.emitted).map(\.effect).filter { if case .wake = $0 { return false } else { return true } }
                if !own.isEmpty { found.append("I9: an event that only moved a clean chord's Space gave \(own)") }
            }
            arrivingChord = false
            if case .abandon(let turn) = event, checker.turnOpen, turn == startCount { checker.turnOpen = false }
            checkEnd(wasLatched: p.wasLatched, seenBefore: p.seenBefore, key: key, config: config, slotRun)
        }
        select(0)
        judgeTimeOrder(trace: trace, owed: pre.map { $0.owed?.effects.count ?? 0 }, seenBefore: pre[0].seenBefore, barBefore: barBefore,
                       ownerBefore: ownerBefore)
        judgeDueOrder(trace: trace, owed: pre.map { $0.owed?.effects.count ?? 0 }, due: pre.map(\.dueAt))
        judgePair(trace.filter(\.emitted), event, strays: strays, seenBefore: pre[0].seenBefore)
        runOwner(tagged.map(\.effect), config: configs[0], run)
        if drain, held == nil, kind != .tick, kind != .sweep, kind != .echo { drainWakes(run) }
    }

    /// When the press or the tap a slot is in comes due: its confirm after the press, the 0.4 s gap after the tap.
    private func dueTime(_ config: VoiceKeyMachine.Config) -> TimeInterval? {
        switch machine.phase {
        case .armed(let since, _): return since + (config.mode == .hold ? config.confirm : 0)
        case .tapped(let at, true): return at + 0.4
        default: return nil
        }
    }

    /// I14: the effects that timers owed ahead of a key come out in the order the timers fell due, across both keys. A pair that runs each
    /// machine's late timer inside that machine's own call lets a send that fell due at 0.5 out before a start that fell due at 0.45.
    private mutating func judgeDueOrder(trace: [TalkKeyPair.Raw], owed: [Int], due: [TimeInterval?]) {
        var items: [(index: Int, due: TimeInterval)] = []
        for (position, slot) in [TalkKeyPair.Slot.primary, .second].enumerated() {
            guard owed[position] > 0, let when = due[position] else { continue }
            var count = 0
            for (index, entry) in trace.enumerated() where entry.slot == slot {
                defer { count += 1 }
                guard count < owed[position], entry.emitted else { continue }
                if case .wake = entry.effect { continue }
                items.append((index, when))
            }
        }
        items.sort { $0.index < $1.index }
        for pair in zip(items, items.dropFirst()) where pair.1.due < pair.0.due - 0.001 {
            found.append("I14: an effect that fell due at \(pair.0.due) s came out before one that fell due at \(pair.1.due) s")
        }
    }

    /// Timers that fell due before a key are the pair's to run first, in due order, across both keys (review of the pair, major 1). Two
    /// things a pair that runs each machine's timer inside that machine's own call gets wrong, read off what the machines returned:
    /// I12, a start that a timer owed ahead of the key was swallowed because of a turn that this very key opened; I13, a turn that
    /// a timer ended with every key up before the key came barred the other key, as if the key had been down.
    private mutating func judgeTimeOrder(trace: [TalkKeyPair.Raw], owed: [Int], seenBefore: UInt16, barBefore: TalkKeyPair.Slot?,
                                         ownerBefore: TalkKeyPair.Slot?) {
        guard let pair else { return }
        var timer: [TalkKeyPair.Raw] = [], later: [TalkKeyPair.Raw] = []
        for (index, slot) in [TalkKeyPair.Slot.primary, .second].enumerated() {
            let raw = trace.filter { $0.slot == slot }
            let ahead = raw.enumerated().filter { $0.offset < owed[index] || $0.element.timed }.map(\.element)
            timer += ahead
            later += raw.filter { entry in !ahead.contains(entry) }
        }
        for entry in timer where ownerBefore == nil && entry.effect == .start && !entry.emitted && entry.cause == .owner {
            if later.contains(where: { $0.effect == .start && $0.emitted && $0.slot != entry.slot }) {
                found.append("I12: the start of the \(entry.slot) key, due before the key that arrived, was swallowed for a turn that key opened")
            }
        }
        if seenBefore == 0, barBefore == nil, pair.bar != nil,
           timer.contains(where: { ($0.effect == .send || $0.effect == .cancel) && $0.emitted }) {
            found.append("I13: a turn that a timer ended with every key up barred the other key because of the key that arrived after it")
        }
    }

    /// The rules of the pair across both keys. I10: at most one turn is open, so a start while one is open is a violation. I11:
    /// after a turn ends with a key still down, the other key starts nothing until every key is up. P5: an effect belongs to
    /// the open turn, so a send or cancel with none open, or of the other key, is a violation (the pair never forwards one).
    private mutating func judgePair(_ emitted: [TalkKeyPair.Raw], _ event: VoiceKeyMachine.Event, strays: Int, seenBefore: UInt16) {
        let anyDownNow = seen != 0
        for raw in emitted {
            let (slot, effect) = (raw.slot, raw.effect)
            let index = slot == .primary ? 0 : 1
            // A timer the pair ran ahead of the key ended its turn before the key was down: what was down then is what stood before it.
            let anyDown = raw.timed ? seenBefore != 0 : anyDownNow
            switch effect {
            case .start:
                if let open = pairCheck.open {
                    found.append("I10: key \(index) started while the turn of key \(open) was open")
                }
                if let ended = pairCheck.ended, ended != index, anyDown {
                    found.append("I11: key \(index) started after the turn of key \(ended) ended, before every key was up")
                }
                pairCheck.open = index
            case .send, .cancel:
                if pairCheck.open != index { found.append("P5: key \(index) sent or cancelled with the open turn \(pairCheck.open.map(String.init) ?? "none")") }
                pairCheck.open = nil
                pairCheck.ended = anyDown ? index : nil
            case .refused, .wake:
                break
            }
        }
        if case .abandon(let turn) = event, turn == startCount, let open = pairCheck.open {
            pairCheck.open = nil
            pairCheck.ended = anyDownNow ? open : nil
        }
        if !anyDownNow { pairCheck.ended = nil }
        guard let pair else { return }
        if pair.strays != strays { found.append("P5: the pair met an effect of a turn that was not open") }
        if pair.generation != startCount { found.append("the pair counted \(pair.generation) starts and the rules saw \(startCount)") }
        let owner = pair.owner.map { $0 == .primary ? 0 : 1 }
        if owner != pairCheck.open { found.append("I10: the pair says the open turn is \(owner.map(String.init) ?? "none"), the rules say \(pairCheck.open.map(String.init) ?? "none")") }
    }

    /// The adapter's answer to a Space that Carbon hides, as `HotkeyMonitor.feed` gives it: on a flags event, when the chord is
    /// on and the live key state has Space down but the machine does not, the machine hears the Space key-down first, with
    /// the flags it had before this event, at the time of that event (not the time it is heard).
    private mutating func injectSwallowedSpace(_ event: VoiceKeyMachine.Event, _ run: WalkRun) {
        guard run.chord, run.injection, pointing == nil, case .key(.flags, let time) = event, run.configs[cfg].chord != nil,
              down & run.chordMask != 0, !machine.keys.keysDown.contains(WalkKey.space.code),
              let index = run.keys.indices.first(where: { run.chordMask == UInt16(1) << UInt16($0) }) else { return }
        feed(.key(.keyDown(keyCode: WalkKey.space.code, modifiers: machine.keys.flagModifiers), at: time), .key, run, key: (index, true))
    }

    /// A Space the machine has dropped by itself is forgotten by the rules too, but only where the machine may drop a key it
    /// was told about: a tick that found a modifier gone resyncs the picture, which forgets every ordinary key whether or not
    /// it is still down (the limit the header names for an arrow key), and an interrupt does the same. A Space dropped by any
    /// other event is the machine losing a key, which the rules must still see. Only for the chord runs.
    private mutating func forgetDroppedSpace(after event: VoiceKeyMachine.Event, _ run: WalkRun) {
        switch event {
        case .tick, .interrupt: break
        default: return
        }
        guard run.chord, pointing == nil, seen & run.chordMask != 0, !machine.keys.keysDown.contains(WalkKey.space.code) else { return }
        seen &= ~run.chordMask
        seenChanged(run)
    }

    /// The keys the machine has just been told about.
    private mutating func noteKey(_ key: (Int, Bool)?, _ run: WalkRun) {
        guard let (index, pressed) = key else { return }
        let bit = UInt16(1) << UInt16(index)
        if pressed { seen |= bit } else { seen &= ~bit }
        seenChanged(run)
        // A key heard late was pressed that long ago: the press has been down for that time already.
        let confirmSteps = Int(((machine.config ?? run.configs[cfg]).confirm / 0.05).rounded())
        if edge.cameDown, confirmSteps > 0 { checker.pressAge = min(arrivalLag, confirmSteps) }
    }

    /// A due tick of an armed press or a running hold carries the modifiers the system reports, and the machine has to read
    /// them as the flags events they stand for: from then on it has been told about every modifier key down, held back
    /// events included, and the rules are read against that. Of two keys that set one flag, only a key the machine was
    /// told about, or the only one down, counts: the live modifiers cannot say which side.
    private mutating func noteLive(_ event: VoiceKeyMachine.Event, acting: Bool, _ run: WalkRun) {
        guard acting, case .tick(_, let live?) = event else { return }
        var next = seen
        for (index, key) in run.keys.enumerated() {
            guard let flag = key.flag else { continue }
            let bit = UInt16(1) << UInt16(index)
            if !live.contains(flag) {
                next &= ~bit
            } else if down & bit != 0, !run.keys.indices.contains(where: { run.keys[$0].flag == flag && next & (UInt16(1) << UInt16($0)) != 0 }) {
                next |= bit
            }
        }
        guard next != seen else { return }
        seen = next
        seenChanged(run)
    }

    /// A tick that reaches a slot reads the live modifiers only when that slot's press or hold has something due: a tick delivered for
    /// the other key's timer, or ahead of its own check, changes nothing in the machine, so it tells the rules nothing either.
    private func tickIsDue(_ config: VoiceKeyMachine.Config) -> Bool {
        let t = now
        switch machine.phase {
        case .armed(let since, _): return config.mode != .hold || t - since >= config.confirm - 0.001
        case .holding(_, _, let check, _): return t >= check - 0.001
        default: return false
        }
    }

    /// A tick would act on the live modifiers: the machine has a press armed or a hold running, the gesture an armed hold.
    private var tickReadsLive: Bool {
        if let pointing { return pointing.isArmed }
        switch machine.phase {
        case .armed, .holding: return true
        default: return false
        }
    }

    /// The config differs from the one the machine last saw in what it reads (`VoiceKeyMachine.differs`).
    fileprivate func changesConfig(_ config: VoiceKeyMachine.Config) -> Bool {
        guard let old = machine.config else { return false }
        return old.key != config.key || old.mode != config.mode || old.voiceOverHoldsKey != config.voiceOverHoldsKey
    }

    /// What the machine owes a timer that came due before the key that is arriving now (rows 5 and 17), by the key's own
    /// time: the adapter has not delivered the tick yet, and the machine must not let the key change what the timer
    /// decides. Read from the phase and the times of the table, not from the wakes the machine asked for.
    private func overdue(_ config: VoiceKeyMachine.Config, at time: TimeInterval, event: ShortcutEvent) -> Overdue? {
        guard pointing == nil, let key = config.key else { return nil }
        let slack = 0.001
        switch machine.phase {
        case .tapped(let at, true):
            let gap = config.mode == .hold ? 0.4 : 0.35
            return time - at >= gap - slack ? Overdue(effects: [.send], steps: Int((gap / 0.05).rounded()), gap: true) : nil
        case .armed(let since, let press):
            let delay: TimeInterval?
            switch config.mode {
            case .hold: delay = config.confirm
            case .shared: delay = config.role == .dictation ? 0.25 : press == .ending && config.confirm > 0 ? config.confirm : nil
            case .toggle: delay = nil
            }
            guard let delay, time - since >= delay - slack else { return nil }
            // A key-down that reports a modifier the machine has not heard of stands for its flags event: the press is
            // dropped, and no timer is owed.
            if case .keyDown(_, let modifiers) = event,
               !modifiers.subtracting(.function).subtracting(machine.keys.flagModifiers).subtracting(key.modifiers).isEmpty {
                return nil
            }
            return Overdue(effects: press == .ending ? [.send] : [.start, .wake(after: 0.25)], steps: Int((delay / 0.05).rounded()), gap: false)
        default:
            return nil
        }
    }

    private struct Overdue {
        var effects: [VoiceKeyMachine.Effect]
        /// The delay or the gap, in steps.
        var steps: Int
        var gap: Bool
    }

    /// A timer the machine settled ahead of a key is judged at that key's own time, on the keys the machine had been told
    /// about (the times they carried): a start needs the own set to have been down alone for the delay by then, a send after
    /// a tap needs the own set to have been let go for the gap. A machine that read a key at the time it handled it fails
    /// this when the key had been pressed before the timer was due.
    private mutating func checkSettled(_ due: Overdue) {
        guard let arrival = arriving else { return }
        if due.gap {
            if let up = arrival.up, up < due.steps {
                found.append("I1: a quick tap's turn was sent by a key that came inside its gap, by the key's own time")
            }
        } else if (arrival.alone ?? -1) < due.steps {
            found.append("I1: a timer was settled ahead of a key that came before it was due: the own set had not been down alone for the delay at the key's own time")
        }
    }

    /// The adapter asks the system which ordinary keys are down before a key event, while the picture holds any, and the
    /// machine drops the others. The rules follow: a key the system says is up is up.
    private mutating func sweepStale(_ run: WalkRun) {
        let held = pointing?.state.keysDown ?? machine.keys.keysDown
        guard !held.isEmpty else { return }
        var live: Set<UInt16> = []
        for (index, key) in run.keys.enumerated() where key.flag == nil {
            if down & (UInt16(1) << UInt16(index)) != 0 { live.insert(key.code) }
        }
        // Each slot's rules drop the keys the system says are up.
        for slot in 0..<(run.secondViews.isEmpty ? 1 : 2) {
            select(slot)
            let slotRun = slot == 0 ? run : run.secondViews[0]
            var stale: UInt16 = 0
            for (index, key) in slotRun.keys.enumerated() where key.flag == nil {
                let bit = UInt16(1) << UInt16(index)
                if down & bit == 0, seen & bit != 0 { stale |= bit }
            }
            if stale != 0 { seen &= ~stale; seenChanged(slotRun) }
        }
        select(0)
        feed(.sweep(live: live), .sweep, run)
    }

    /// What the owner does with the effects of one call, in order: it stops listening when a turn is sent or cancelled
    /// and says so, naming its turn, and it may refuse a turn it is asked to start.
    private mutating func runOwner(_ effects: [VoiceKeyMachine.Effect], config: VoiceKeyMachine.Config, _ run: WalkRun) {
        guard pointing == nil else { return }
        var owner = startCount - effects.filter { $0 == .start }.count
        for effect in effects {
            switch effect {
            case .start:
                owner += 1
                if refusing, config.mode != .toggle { feed(.abandon(turn: owner), .echo, run) }
            case .send, .cancel:
                feed(.abandon(turn: owner), .echo, run)
            case .refused, .wake:
                break
            }
        }
    }

    /// The phase of the machine, or for run H whether the gesture is idle, armed or active.
    private var stage: Stage { Stage(phase: machine.phase, pointing: pointing.map { $0.isActive ? 2 : $0.isArmed ? 1 : 0 } ?? 0) }

    private struct Stage: Equatable {
        var phase: VoiceKeyMachine.Phase
        var pointing: Int
    }

    private mutating func handle(_ event: VoiceKeyMachine.Event, config: VoiceKeyMachine.Config) -> [VoiceKeyMachine.Effect] {
        guard var gesture = pointing else { return machine.handle(event, config: config) }
        let effects: [VoiceKeyMachine.Effect]
        switch event {
        case .key(let key, let time):
            effects = Self.effects(of: gesture.feed(key, at: time), gesture)
        case .tick(let time, let live):
            // The calls the monitor makes when a wake arrives: the confirm of an armed hold, the watchdog of an active one.
            if gesture.isArmed {
                effects = Self.effects(of: gesture.confirmElapsed(at: time, liveModifiers: live), gesture)
            } else if gesture.isActive {
                let output = gesture.tick(at: time, liveModifiers: live)
                effects = output == nil ? [.wake(after: 0.25)] : Self.effects(of: output, gesture)
            } else {
                effects = []
            }
        case .interrupt(let live):
            effects = Self.effects(of: gesture.interrupt(liveModifiers: live), gesture)
        case .abandon:
            effects = []
        case .sweep(let live):
            gesture.sweep { $0.intersection(live) }
            effects = []
        }
        pointing = gesture
        return effects
    }

    private static func effects(of output: PointingKeyGesture.Output?, _ gesture: PointingKeyGesture) -> [VoiceKeyMachine.Effect] {
        switch output {
        case .armed?: [.wake(after: gesture.confirm)]
        case .began?: [.start, .wake(after: 0.25)]
        case .ended?, .holdTimedOut?: [.send]
        case .cancelled?: [.cancel]
        case .escape?, .doubleTapControl?, nil: []
        }
    }

    // MARK: The rules

    private mutating func seenChanged(_ run: WalkRun) {
        // The step that makes Space clean, or ends its being clean, still reads it as clean: a modifier let go with Space
        // down is a clean release, and Space joining the own set is not foreign in the step it comes.
        let spaceCame = run.chordMask & seen != 0 && run.chordMask & previouslySeen == 0
        let hidden: UInt16 = checker.chordClean || (spaceCame && arrivingChord) ? run.chordMask : 0
        let phys = Phys(seen, run, hidden: hidden)
        let forgiven: UInt16 = hidden != 0 || checker.chordForgiven ? run.chordMask : 0
        let turnPhys = Phys(seen, run, hidden: forgiven)
        checker.chordClean = hidden != 0 && run.chordMask & seen != 0 && phys.ownAll
        checker.chordForgiven = forgiven != 0 && run.chordMask & seen != 0
        previouslySeen = seen
        // The times are the ones the keys carried, so a key heard late moves them back.
        let stampStep = step - arrivalLag
        if phys.exactOwn { if aloneSince == nil { aloneSince = stampStep } } else { aloneSince = nil }
        if phys.ownAll { ownUpSince = nil } else if ownUpSince == nil { ownUpSince = stampStep }
        let wasOwn = checker.ownWasDown
        if phys.ownAll, !wasOwn {
            checker.pressAge = 0
            checker.pressForeign = phys.foreignAny
            checker.dirtySpaceAtPress = run.chord && down & run.chordMask != 0 && !checker.spaceClean
            edge.cameDown = true
        } else if phys.ownAll {
            checker.pressForeign = checker.pressForeign || phys.foreignAny
        }
        if !phys.ownAll {
            if checker.dirtySpaceAtPress { edge.releasedDirty = true }
            checker.presses = 0
            checker.pressAge = 0
            checker.dirtySpaceAtPress = false
        }
        if wasOwn, !phys.ownAll { edge.released = true }
        if checker.turnOpen, turnPhys.foreignAny {
            if run.configs[0].role == .dictation, turnPhys.onlyShift { checker.shiftSeen = true } else { checker.foreign = true }
        }
        if phys.ownAll, phys.foreignAny { checker.bigger = true }
        if !phys.anyDown {
            checker.cancelled = false
            checker.bigger = false
        }
        checker.ownWasDown = phys.ownAll
    }

    private mutating func checkEffects(_ effects: [VoiceKeyMachine.Effect], wasLatched: Bool, kind: Kind,
                                       config: VoiceKeyMachine.Config, configChange: Bool, seenBefore: UInt16, _ run: WalkRun) {
        let phys = Phys(seen, run, hidden: checker.chordClean ? run.chordMask : 0)
        let turnPhys = Phys(seen, run, hidden: checker.chordForgiven ? run.chordMask : 0)
        let dictation = config.role == .dictation
        let confirmSteps = Int((config.confirm / 0.05).rounded())
        for effect in effects {
            switch effect {
            case .start:
                startCount += 1
                if run.pointing, confirmSteps > 0, checker.pressAge < confirmSteps || checker.pressForeign {
                    found.append("a pointing hold began before its own set had been down alone for the confirm")
                }
                if checker.cancelled { found.append("I2: start after a cancel, before every key was up") }
                if checker.bigger { found.append("I6: start after the own set was down with something foreign, before every key was up") }
                if run.chord, checker.dirtySpaceAtPress {
                    found.append("I6s: start of a press that came down beside a Space physically down that had not joined the own set alone, whether or not any monitor heard that Space")
                }
                if phys.ownAll, phys.foreignAny { found.append("I3: start on a larger chord") }
                if config.mode == .toggle {
                    checker.presses += 1
                    if checker.presses > 1 { found.append("I7: a toggle fired twice in one press") }
                } else {
                    if checker.turnOpen { found.append("I4: start while a turn is open") }
                    checker.turnOpen = true
                    checker.foreign = false
                    checker.shiftSeen = false
                    if turnPhys.foreignAny {
                        if dictation, turnPhys.onlyShift { checker.shiftSeen = true } else { checker.foreign = true }
                    }
                }
            case .send:
                if !checker.turnOpen {
                    found.append("I4: send without an open turn")
                } else if wasLatched {
                    let atPress = confirmSteps == 0 && edge.cameDown && phys.exactOwn
                    let stayedAlone = confirmSteps > 0 && (kind == .tick || kind == .flip) && phys.exactOwn && !checker.pressForeign
                        && checker.pressAge >= confirmSteps
                    let cleanRelease = confirmSteps > 0 && edge.released && !checker.pressForeign
                    if !(atPress || stayedAlone || cleanRelease) {
                        found.append("I1: a hands-free turn was sent by something other than a clean press of exactly the own set")
                    }
                    if run.chord, checker.dirtySpaceAtPress || edge.releasedDirty {
                        found.append("I6s: a hands-free turn was ended by a press that came down beside a Space physically down that had not joined the own set alone, whether or not any monitor heard that Space")
                    }
                } else {
                    if checker.foreign { found.append("I1: a turn was sent after something foreign was down") }
                    if checker.shiftSeen, phys.ownAll { found.append("I1: a Shift press was sent while its key was still down") }
                }
                checker.turnOpen = false
            case .cancel:
                if !checker.turnOpen { found.append("I4: cancel without an open turn") }
                if wasLatched, kind != .interrupt, kind != .flip, kind != .abandon, !configChange {
                    found.append("I1: a hands-free turn was cancelled by typing or a larger chord")
                }
                checker.turnOpen = false
                // A change of config bars the keys that were down before the call; the press that reveals it is new.
                checker.cancelled = phys.anyDown && (!configChange || seenBefore != 0)
            case .refused, .wake: break
            }
        }
    }

    /// The rules that read the machine as it stands after a whole call.
    private mutating func checkEnd(wasLatched: Bool, seenBefore: UInt16, key: (Int, Bool)?, config: VoiceKeyMachine.Config,
                                   _ run: WalkRun) {
        if pointing == nil {
            if pair == nil, machine.generation != startCount {
                found.append("the machine counted \(machine.generation) starts and the rules saw \(startCount)")
            }
            if machine.turnIsOpen != checker.turnOpen {
                found.append("I4: the machine says a turn is \(machine.turnIsOpen ? "open" : "closed"), the rules say \(checker.turnOpen ? "open" : "closed")")
            }
            // A press that comes down from a keyboard with everything up is never barred, whatever else the call did.
            if key?.1 == true, seenBefore == 0, config.key != nil, Phys(seen, run, hidden: checker.chordClean ? run.chordMask : 0).exactOwn, machine.barred {
                found.append("I8: a press from every key up found the machine barred")
            }
        }
        if machine.isLatched {
            if !checker.turnOpen { found.append("I4: hands-free with no open turn") }
            if !wasLatched, checker.foreign || checker.shiftSeen {
                found.append("I1: a turn went hands-free after something foreign was down")
            }
        }
    }
}

// MARK: - The search

private struct Report {
    var states = 0
    var moves = 0
    var seconds = 0.0
    var violations: [String] = []
    var visited: Set<Int> = []
}

private func path(_ run: WalkRun, to index: Int, parents: [Int], via: [Move]) -> String {
    var steps: [String] = []
    var at = index
    while at > 0 { steps.append(via[at].text(run)); at = parents[at] }
    return steps.reversed().joined(separator: ", ")
}

/// The rest states already pressed, so a state that comes to rest where an earlier one did is not pressed again.
private final class RestMemo {
    var seen: Set<Int> = []
}

/// The rest check of one state, on a copy: let go of everything, wait 0.5 s, press the own set (I8, last clause of I4).
/// What the press does depends only on the state at rest, which a great many states share, so it is tried once for each.
private func restCheck(_ sim: Sim, _ run: WalkRun, memo: RestMemo? = nil) -> [String] {
    var base = sim
    base.found = []
    base.apply(.deliver, run)
    for index in run.keys.indices where base.down & (UInt16(1) << UInt16(index)) != 0 { base.apply(.toggle(index), run) }
    base.apply(.deliver, run)
    for _ in 0..<10 { base.apply(.wait, run) }
    var out = base.found
    base.found = []
    if base.turnOpenNow != base.isLatchedNow {
        out.append("I4: with every key up and every timer run out, a turn is open and the machine is not hands-free (or the reverse)")
    }
    if let memo, !memo.seen.insert(base.key(run).hashValue).inserted { return out }
    let config = run.configs[base.cfg]
    guard config.key != nil, !config.voiceOverHoldsKey else { return out }
    let ownIndices = run.keys.indices.filter { run.ownMask & (UInt16(1) << UInt16($0)) != 0 }
    // I8c: from rest, pressing the own set and then Space acts as I8.
    var orders: [(slot: Int, order: [Int])] = [(0, ownIndices), (0, ownIndices.reversed())]
    if run.chord, let space = run.keys.indices.first(where: { run.chordMask == UInt16(1) << UInt16($0) }) {
        orders.append((0, ownIndices + [space]))
    }
    // I8p: from rest, pressing exactly either talk key's set acts, and when a hands-free turn is open only the key that opened
    // it ends it. The sets are the ones the run names, each key's own, in both orders.
    if !run.pressSets.isEmpty {
        orders = []
        for set in run.pressSets {
            let indices = set.codes.compactMap { code in run.keys.firstIndex { $0.code == code } }
            orders += [(set.slot, indices), (set.slot, indices.reversed())]
            if set.slot == 0, run.chord, let space = run.keys.indices.first(where: { run.chordMask == UInt16(1) << UInt16($0) }) {
                orders.append((0, indices + [space]))
            }
        }
    }
    for (slot, order) in orders {
        var sim = base
        sim.log = []
        let wasLatched = sim.isLatchedNow
        let owner = base.pair?.owner.map { $0 == .primary ? 0 : 1 }
        let secondView = run.secondViews.first
        let slotConfig = slot == 0 ? config : (secondView?.configs[min(base.cfg, secondView!.configs.count - 1)] ?? config)
        // A second key that is off has no press to test.
        if slot == 1, slotConfig.key == nil { continue }
        func tap(_ sim: inout Sim) {
            for index in order { sim.apply(.toggle(index), run) }
            sim.apply(.wait, run); sim.apply(.wait, run)
            for index in order.reversed() { sim.apply(.toggle(index), run) }
            sim.apply(.wait, run); sim.apply(.wait, run)
        }
        if slotConfig.mode == .shared, slotConfig.role == .talk, !wasLatched {
            tap(&sim); tap(&sim)
        } else {
            for index in order { sim.apply(.toggle(index), run) }
            let steps = slotConfig.mode == .shared ? 7 : Int((slotConfig.confirm / 0.05).rounded()) + 2
            for _ in 0..<steps { sim.apply(.wait, run) }
        }
        // A config change that is waiting for this press ends a hands-free turn by cancelling it, then the press acts.
        // A second key that was turned off or on and has not heard of it yet: the press carries the change, which ends its turn.
        let changing: Bool
        if let pair = base.pair, let view = secondView {
            changing = pair.second.config.map { $0.key != view.configs[min(base.cfg, view.configs.count - 1)].key } ?? false
        } else {
            changing = base.changesConfig(slotConfig)
        }
        var acted: Bool = wasLatched ? sim.log.contains(.send) || (changing && sim.log.contains(.cancel)) : sim.log.contains(.start)
        if wasLatched, let owner, owner != slot {
            // The other key of the pair: nothing happens, no start, no send, no cancel.
            // Only the key whose setting changed may be cancelled by the change (the second key, slot 1).
            acted = !sim.log.contains { $0 == .start || $0 == .send || ($0 == .cancel && !(changing && owner == 1)) }
        }
        if !acted {
            let names = order.map { run.keys[$0].name }.joined(separator: ", ")
            let rule = !run.pressSets.isEmpty ? "I8p" : order.contains { run.chordMask == UInt16(1) << UInt16($0) } ? "I8c" : "I8"
            out.append("\(rule): after letting go of everything and waiting 0.5 s, pressing \(names) did not act (latched \(wasLatched))")
        }
        out += sim.found
    }
    return out
}

/// One search node. The frontier holds these, not `Sim` values, so growing the frontier copies a pointer
/// rather than every machine. The effect log is not part of the state key and is cleared before a node is
/// stored: the rules read the effects of the move that produced them, and the rest check starts its own log.
private final class WalkNode {
    var sim: Sim
    init(_ sim: Sim) { self.sim = sim }
}

/// `until`: stop as soon as a violation of this rule (its prefix, such as "I9") has been found.
private func search(_ run: WalkRun, stopAtFirst: Bool = false, until: String? = nil) -> Report {
    let start = Date()
    var report = Report()
    var seen: [Int: Int] = [:]
    var parents = [0], via: [Move] = [.wait]
    var frontier: [WalkNode?] = []
    let root = Sim(run)
    seen[root.key(run).hashValue] = 0
    frontier.append(WalkNode(root))
    var seenRules: Set<String> = []
    let memo = RestMemo()

    func record(_ messages: [String], at index: Int, move: Move?) {
        for message in messages {
            let rule = String(message.prefix(while: { $0 != ":" }))
            guard seenRules.insert(rule + message).inserted, report.violations.count < 16 else { continue }
            var text = path(run, to: index, parents: parents, via: via)
            if let move { text += (text.isEmpty ? "" : ", ") + move.text(run) }
            report.violations.append("\(message) [after: \(text)]")
        }
    }

    // `WALK_PROGRESS=path` appends the size of the search to that file as it grows (the runner holds its output until it ends);
    // `WALK_LIMIT=n` stops it past n states (a violation), for measuring a run before it is put in the list.
    let progress = ProcessInfo.processInfo.environment["WALK_PROGRESS"]
    let limit = Int(ProcessInfo.processInfo.environment["WALK_LIMIT"] ?? "") ?? Int.max
    var cursor = 0
    while cursor < frontier.count {
        if let progress, cursor % 100_000 == 0 {
            let line = "[walk] \(run.name): \(seen.count) states, \(cursor) expanded, \(Int(Date().timeIntervalSince(start))) s\n"
            if let handle = FileHandle(forWritingAtPath: progress) ?? (FileManager.default.createFile(atPath: progress, contents: nil) ? FileHandle(forWritingAtPath: progress) : nil) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
        if seen.count > limit {
            report.violations.append("the search passed the limit of \(limit) states")
            break
        }
        if stopAtFirst, !report.violations.isEmpty { break }
        if let until, report.violations.contains(where: { $0.hasPrefix(until) }) { break }
        guard let node = frontier[cursor] else { cursor += 1; continue }
        let sim = node.sim
        frontier[cursor] = nil
        record(restCheck(sim, run, memo: memo), at: cursor, move: nil)
        for move in sim.moves(run) {
            var next = sim
            next.found = []
            next.apply(move, run)
            report.moves += 1
            record(next.found, at: cursor, move: move)
            next.found = []
            next.log = []
            let key = next.key(run).hashValue
            if seen[key] == nil {
                seen[key] = frontier.count
                parents.append(cursor)
                via.append(move)
                frontier.append(WalkNode(next))
            }
        }
        cursor += 1
    }
    report.states = seen.count
    report.seconds = Date().timeIntervalSince(start)
    if let progress, let handle = FileHandle(forWritingAtPath: progress) {
        handle.seekToEndOfFile()
        handle.write(Data("[walk] \(run.name): DONE \(seen.count) states, \(report.moves) moves, \(Int(report.seconds)) s\n".utf8))
        try? handle.close()
    }
    report.visited = Set(seen.keys)
    return report
}

/// Replays one order of moves through the harness and returns what the checker found.
private func replay(_ run: WalkRun, _ names: [String]) -> [String] {
    replayWithLog(run, names).found
}

/// The same, with the effects the machine returned on the way (without its wakes), in order. The rest check that follows
/// the moves runs on a copy and adds none.
private func replayWithLog(_ run: WalkRun, _ names: [String]) -> (found: [String], effects: [VoiceKeyMachine.Effect]) {
    var sim = Sim(run)
    var out: [String] = []
    for name in names {
        let move: Move
        switch name {
        case "wait": move = .wait
        case "wait 0.5": move = .waitHalfSecond
        case "deliver": move = .deliver
        case "wait 0.05 (timers late)": move = .waitLate
        case _ where name.hasPrefix("wait ") && name.hasSuffix(" steps with the timers, then the held event"):
            move = .catchUp(Int(name.dropFirst(5).prefix(while: { $0 != " " })) ?? 1)
        case _ where name.hasPrefix("busy ") && name.hasSuffix(" steps, then the held event, then the timers"):
            move = .busy(Int(name.dropFirst(5).prefix(while: { $0 != " " })) ?? 1)
        case _ where name.hasSuffix(" (event held)"):
            guard let index = run.keys.firstIndex(where: { $0.name == String(name.dropLast(" (event held)".count)) }) else { return (["unknown move \(name)"], []) }
            move = .toggleHeld(index)
        default:
            let swallowing = name.hasSuffix(" swallowed")
            let key = swallowing ? String(name.dropLast(" swallowed".count)) : name
            guard let index = run.keys.firstIndex(where: { $0.name == key }) else { return (["unknown move \(name)"], []) }
            move = swallowing ? .swallowed(index) : .toggle(index)
        }
        sim.found = []
        sim.apply(move, run)
        out += sim.found
    }
    let effects = sim.log.filter { if case .wake = $0 { return false } else { return true } }
    return (out + restCheck(sim, run), effects)
}

@Suite struct VoiceKeyWalkTests {
    /// Every run is searched. The runs do not share state, so they proceed together; one after another does not
    /// finish inside the suite.
    @Test func everyOrderOfPressesKeepsTheRules() {
        let only = ProcessInfo.processInfo.environment["WALK_ONLY"] ?? ""
        let runs = WalkRun.all.filter { run in
            only.isEmpty || only.split(separator: ",").contains { run.name.hasPrefix($0) }
        }
        let lock = NSLock()
        var problems: [String] = []
        DispatchQueue.concurrentPerform(iterations: runs.count) { index in
            let run = runs[index]
            let report = search(run)
            print("voice key walk \(run.name): \(report.states) states, \(report.moves) moves, \(String(format: "%.2f", report.seconds)) s")
            var found: [String] = []
            if !report.violations.isEmpty { found.append("\(run.name): \(report.violations.joined(separator: "\n"))") }
            if report.states <= 100 { found.append("\(run.name): the search found too few states to be a search") }
            guard !found.isEmpty else { return }
            lock.lock()
            problems.append(contentsOf: found)
            lock.unlock()
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// The mistake the search was blind to: an adapter that stamps a key with the time it handles it. A Command pressed
    /// 0.04 s after the pair and heard 0.2 s later then settles the confirm that was not due at its own time.
    @Test func theSearchSeesAnAdapterThatStampsKeysWithTheTimeItHandlesThem() {
        let shipped = WalkRun.all[0]
        let old = WalkRun("A with processing time", keys: shipped.keys, own: shipped.ownCodes, configs: shipped.configs,
                          late: true, processingTime: true)
        let report = search(old, stopAtFirst: true)
        #expect(report.violations.contains { $0.contains("own set had not been down alone for the delay") },
                "\(report.violations)")
    }

    /// The orders the reviews found (F1, and the swap chord on a dictation key), replayed by name: the first is the
    /// shipped talk key beside tiling, quickly and slowly, with the confirm and without it; the others dictation.
    @Test func theOrdersTheReviewsFoundKeepTheRules() {
        let order = ["Control", "Option", "Shift", "LeftCommand", "Left", "deliver", "Left", "deliver"]
        let release = ["LeftCommand", "Shift", "Option", "Control", "wait 0.5"]
        let slow = ["Control", "Option", "wait", "wait", "wait", "wait", "Shift", "LeftCommand", "Left", "deliver", "Left", "deliver"]
        var problems: [String] = []
        for run in [WalkRun.all[0], WalkRun.all[1]] {
            for sequence in [order, slow] {
                let found = replay(run, sequence + release)
                if !found.isEmpty { problems.append("\(run.name), \(sequence.joined(separator: ", ")): \(found[0])") }
                let twice = replay(run, sequence + release + sequence + release)
                if !twice.isEmpty { problems.append("twice, \(run.name), \(sequence.joined(separator: ", ")): \(twice[0])") }
            }
        }
        let swap = replay(WalkRun.all[3], order + release)
        if !swap.isEmpty { problems.append("dictation Control-Option: \(swap[0])") }
        let rightCommand = ["RightCommand", "Shift", "Control", "Option", "Left", "deliver", "Left", "deliver", "Option", "Control",
                            "Shift", "RightCommand", "wait 0.5"]
        let other = replay(WalkRun.all[2], rightCommand)
        if !other.isEmpty { problems.append("dictation Right Command: \(other[0])") }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// The chord orders the plan names, replayed with the effects asserted: the rules hold and the machine did exactly this.
    @Test func theChordOrdersKeepTheRules() {
        let talk = WalkRun.all[0]
        let release = ["Option", "Control", "wait 0.5"]
        typealias E = VoiceKeyMachine.Effect
        let cases: [(String, [String], [E])] = [
            ("the pair, then Space, held past the confirm, Space let go, then the pair",
             ["Control", "Option", "Space", "wait 0.5", "Space", "wait 0.5"] + release, [.start, .send]),
            ("the pair, Space, then a modifier let go with Space still down",
             ["Control", "Option", "wait 0.5", "Space", "Option", "Space", "Control", "wait 0.5"], [.start, .send]),
            ("Space first, then the pair", ["Space", "Control", "Option", "wait 0.5", "Space"] + release, []),
            ("Control, Space, Option", ["Control", "Space", "Option", "wait 0.5", "Space"] + release, []),
            ("Control, Space let go, Option", ["Control", "Space", "Space", "Option", "wait 0.5"] + release, []),
            ("the pair, then Space swallowed down and up",
             ["Control", "Option", "wait 0.5", "Space swallowed", "wait 0.5", "Space swallowed", "wait 0.5"] + release, [.start, .send]),
            ("the pair, Space down seen and up swallowed",
             ["Control", "Option", "wait 0.5", "Space", "Space swallowed", "wait 0.5"] + release, [.start, .send]),
            ("the pair then Space then Shift cancels",
             ["Control", "Option", "wait 0.5", "Space", "Shift", "wait 0.5", "Shift", "Space"] + release, [.start, .cancel]),
        ]
        var problems: [String] = []
        for (name, moves, expected) in cases {
            for run in [talk, WalkRun.all[1]] {
                let result = replayWithLog(run, moves)
                if !result.found.isEmpty { problems.append("\(name), \(run.name): \(result.found[0])") }
                if run.name == talk.name, result.effects != expected {
                    problems.append("\(name): the machine returned \(result.effects), expected \(expected)")
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// The orders of the Eighth pass (finding 1): Carbon swallows Space, and only the live key state shows it.
    @Test func theSwallowedSpaceOrdersKeepTheRules() {
        let carbon = WalkRun.all.first { $0.name.hasPrefix("A-carbon") }!
        let release = ["Option", "Control", "wait 0.5"]
        typealias E = VoiceKeyMachine.Effect
        let cases: [(String, [String], [E])] = [
            ("Space first, then the pair: not a chord, nothing starts",
             ["Space swallowed", "Control", "Option", "wait 0.5", "Space swallowed"] + release, []),
            ("the pair sends, Space stays, the pair again: nothing starts (I6)",
             ["Control", "Option", "wait 0.5", "Space swallowed", "Option", "Control", "wait 0.5", "Control", "Option", "wait 0.5",
              "Space swallowed"] + release, [.start, .send]),
            ("Control, Space, Option: Space came before the set",
             ["Control", "Space swallowed", "Option", "wait 0.5", "Space swallowed"] + release, []),
            ("the pair, Space clean, released, Space let go, the pair again starts",
             ["Control", "Option", "wait 0.5", "Space swallowed"] + release + ["Space swallowed", "Control", "Option", "wait 0.5"] + release,
             [.start, .send, .start, .send]),
        ]
        var problems: [String] = []
        for (name, moves, expected) in cases {
            let result = replayWithLog(carbon, moves)
            if !result.found.isEmpty { problems.append("\(name): \(result.found[0])") }
            if result.effects != expected { problems.append("\(name): the machine returned \(result.effects), expected \(expected)") }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// The mistake finding 1 was: an adapter that never tells the machine about a Space Carbon hides. With every Space
    /// swallowed and the live-state injection off, a start can follow a Space that was never clean.
    @Test func theSearchSeesAnAdapterThatNeverLearnsOfASwallowedSpace() {
        let carbon = WalkRun.all.first { $0.name.hasPrefix("A-carbon") }!
        let blind = WalkRun("A-carbon with no live-state injection", keys: carbon.keys, own: carbon.ownCodes, configs: carbon.configs,
                            late: true, chord: true, carbon: true, injection: false)
        let report = search(blind, until: "I6s")
        #expect(report.violations.contains { $0.hasPrefix("I6s") }, "\(report.violations)")
        print("voice key walk A-carbon, injection off: \(report.violations.first ?? "no violation")")
    }

    /// I6s judged only a `start`. A hands-free turn ended by a press that came down beside a swallowed Space, which the keyboard
    /// did not earn as a chord, is as wrong as a start there: the adapter that never learns of that Space must be reported when it
    /// ends the turn, whether the press stayed alone (ended by its tick) or was let go at once (ended by the release).
    @Test func theSearchSeesAHandsFreeTurnEndedBesideASwallowedSpace() {
        let carbon = WalkRun.all.first { $0.name.hasPrefix("A-carbon") }!
        let blind = WalkRun("A-carbon with no live-state injection", keys: carbon.keys, own: carbon.ownCodes, configs: carbon.configs,
                            late: true, chord: true, carbon: true, injection: false)
        let pair = ["Control", "Option", "Option", "Control"]
        let latched = pair + pair + ["wait 0.5", "Space swallowed"]
        let cases: [(String, [String])] = [
            ("a press that stays alone past the confirm", latched + ["Control", "Option", "wait 0.5", "Option", "Control", "wait 0.5"]),
            ("a press let go at once", latched + ["Control", "Option", "Option", "Control", "wait 0.5"]),
        ]
        for (name, moves) in cases {
            let found = replay(blind, moves)
            #expect(found.contains { $0.hasPrefix("I6s: a hands-free turn was ended") }, "\(name): \(found)")
        }
        // The shipped adapter hears of that Space, so the same orders break nothing.
        for (name, moves) in cases {
            let found = replay(carbon, moves)
            #expect(found.isEmpty, "\(name), with the injection: \(found)")
        }
    }

    /// The mistake the chord search must see: a machine that does not tolerate the chord reads a clean Space as foreign and
    /// cancels the turn. Run A with the chord rules on and the config's chord off must report I9.
    @Test func theSearchSeesAMachineThatDoesNotTolerateTheChord() {
        let shipped = WalkRun.all[0]
        let config = shipped.configs[0]
        let intolerant = WalkRun("A with the chord rules and a machine that has no chord", keys: shipped.keys, own: shipped.ownCodes,
                                 configs: [VoiceKeyMachine.Config(key: config.key, role: config.role, mode: config.mode,
                                                                  confirm: config.confirm, chord: nil)],
                                 late: true, chord: true)
        let report = search(intolerant, until: "I9")
        #expect(report.violations.contains { $0.hasPrefix("I9") }, "\(report.violations)")
    }

    /// The orders of docs/RIGHT-OPTION-TALK-PLAN.md part 2 (the cases asked about), replayed by name on the pair with the
    /// effects asserted: the rules hold on K and K0, and on K the pair did exactly this.
    @Test func theSecondKeyOrdersKeepTheRules() {
        let pair = WalkRun.all.first { $0.name.hasPrefix("K talk") }!
        let zero = WalkRun.all.first { $0.name.hasPrefix("K0") }!
        typealias E = VoiceKeyMachine.Effect
        let tap = ["Control", "Option", "Option", "Control", "Control", "Option", "Option", "Control", "wait 0.5"]
        let held = ["RightOption", "wait 0.5"]
        let rest = ["wait 0.5"]
        let cases: [(String, [String], [E])] = [
            ("Right Option held past the confirm", held + ["RightOption"] + rest, [.start, .send]),
            ("Right Option and a letter inside the confirm", ["RightOption", "Left", "wait 0.5", "Left", "RightOption"] + rest, []),
            ("Right Option held, then a letter", held + ["Left", "Left", "wait 0.5", "RightOption"] + rest, [.start, .cancel]),
            ("Left Option alone", ["Option", "wait 0.5", "Option"] + rest, []),
            ("Left Option joins a Right Option turn", held + ["Option", "wait 0.5", "Option", "RightOption"] + rest, [.start, .cancel]),
            ("Control, then Right Option", ["Control", "RightOption", "wait 0.5", "RightOption", "Control"] + rest, [.start, .send]),
            ("Right Option, then Control inside the confirm", ["RightOption", "Control", "wait 0.5", "Control", "RightOption"] + rest, [.start, .send]),
            ("Right Option held, then Control, then a fresh press",
             held + ["Control", "wait 0.5", "Control", "RightOption", "wait 0.5", "RightOption", "wait 0.5", "RightOption"] + rest,
             [.start, .cancel, .start, .send]),
            ("Right Option during a primary turn",
             ["Control", "Option", "wait 0.5", "RightOption", "wait 0.5", "RightOption", "Option", "Control"] + rest, [.start, .send]),
            ("Control let go while Control and Right Option are held",
             ["Control", "RightOption", "wait 0.5", "Control", "wait 0.5", "RightOption"] + rest, [.start, .send]),
            ("Right Option during a primary hands-free turn",
             tap + ["RightOption", "wait 0.5", "RightOption", "wait 0.5", "Control", "Option", "wait 0.5", "Option", "Control"] + rest,
             [.start, .send]),
            ("Control-Option during a Right Option hands-free turn",
             ["RightOption", "RightOption", "RightOption", "RightOption", "wait 0.5", "Control", "Option", "wait 0.5", "Option", "Control",
              "wait 0.5", "RightOption", "wait 0.5", "RightOption"] + rest, [.start, .send]),
            ("Right Option inside the gap of a primary tap",
             ["Control", "Option", "wait", "wait", "wait", "wait", "Option", "Control", "RightOption", "wait 0.5", "RightOption"] + rest,
             [.start, .send]),
            ("Control-Option inside the gap of a Right Option tap",
             ["RightOption", "wait", "wait", "wait", "wait", "wait", "RightOption", "Control", "Option", "wait 0.5", "Option", "Control"] + rest,
             [.start, .cancel]),
        ]
        var problems: [String] = []
        for (name, moves, expected) in cases {
            for run in [pair, zero] {
                let result = replayWithLog(run, moves)
                if !result.found.isEmpty { problems.append("\(name), \(run.name): \(result.found[0])") }
                if run.name == pair.name, result.effects != expected {
                    problems.append("\(name): the pair returned \(result.effects), expected \(expected)")
                }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// The mistake the pair exists to prevent: a pair that lets the other key's start through while a turn is open. K with
    /// the arbiter off must report I10.
    @Test func theSearchSeesAPairThatLetsTheOtherKeyStart() {
        let blind = WalkRun.talkPair("K with a pair that lets every start through", primaryConfirm: 0.15, late: true, arbitrate: false)
        let report = search(blind, until: "I10")
        #expect(report.violations.contains { $0.hasPrefix("I10") }, "\(report.violations)")
        print("voice key walk K, arbiter off: \(report.violations.first ?? "no violation")")
    }

    /// The mistake of the review of the pair: each machine settled its own overdue timer after the pair had ruled on the key, so a
    /// timer that was due first acted second. K-late with the delivery in due order off must be reported.
    @Test func theSearchSeesAPairThatDeliversTimersAfterTheKey() {
        let blind = WalkRun.talkPair("K-late with the timers after the key", primaryConfirm: 0, late: true, space: false,
                                     leftOption: false, inOrder: false)
        let report = search(blind, stopAtFirst: true)
        #expect(report.violations.contains { $0.hasPrefix("I12") || $0.hasPrefix("I13") },
                "\(report.violations)")
        print("voice key walk K-late, timers after the key: \(report.violations.first ?? "no violation")")
    }

    /// The first order of the review of the pair: Control-Option held 0.1 s and let go (no confirm, so a turn waits out the 0.4 s gap, due
    /// at 0.5), Right Option down at 0.2 (its start is due at 0.45), both timers late, then a key at 0.5. On time the second key's start
    /// comes first (swallowed, the gap is open) and the gap's send second. A pair that settles each machine's timer inside its own call
    /// lets the send out first and the start after it: effects out of due order (I14).
    @Test func theSearchSeesTimersThatActOutOfDueOrder() {
        let moves = ["Control", "Option", "wait", "wait", "Option", "Control", "wait", "wait", "RightOption", "wait", "wait", "wait", "wait",
                     "wait 0.05 (timers late)", "wait 0.05 (timers late)", "RightOption"]
        let blind = WalkRun.talkPair("K-late with the timers after the key, Left Option", primaryConfirm: 0, late: true, space: false,
                                     inOrder: false)
        let found = replay(blind, moves)
        #expect(found.contains { $0.hasPrefix("I14") }, "\(found)")
        let kept = WalkRun.talkPair("K-late with the timers in due order, Left Option", primaryConfirm: 0, late: true, space: false)
        let result = replayWithLog(kept, moves)
        #expect(result.found.isEmpty, "\(result.found)")
        #expect(result.effects == [.start, .send], "the second key's start is swallowed while the gap is open: \(result.effects)")
    }

    /// With no second key the pair is the machine: run A walked plainly to length 5 (66,429 sequences), the machine against the
    /// pair with the second key off, the same effects after every move.
    @Test func aPairWithoutASecondKeyActsAsTheMachine() {
        let run = WalkRun.all[0]
        let asPair = WalkRun(run.name + " as a pair", keys: run.keys, own: run.ownCodes, configs: run.configs, late: run.late, chord: true,
                             second: (own: [], configs: [VoiceKeyMachine.Config(key: nil, role: .talk, mode: .hold)]))
        var sequences = 0
        var problems: [String] = []
        func walk(_ machine: Sim, _ pair: Sim, depth: Int, trail: [Move]) {
            if depth == 5 || problems.count >= 4 { return }
            for move in machine.plainMoves(run) {
                var one = machine, two = pair
                one.found = []; two.found = []
                one.apply(move, run)
                two.apply(move, asPair)
                sequences += 1
                let trail = trail + [move]
                if one.log != two.log || !two.found.isEmpty || one.found != two.found {
                    problems.append("\(two.found.first ?? "the effects differ: \(one.log) against \(two.log)") [after: \(trail.map { $0.text(run) }.joined(separator: ", "))]")
                }
                walk(one, two, depth: depth + 1, trail: trail)
            }
        }
        walk(Sim(run), Sim(asPair), depth: 0, trail: [])
        print("voice key walk, pair against machine: \(sequences) sequences")
        #expect(sequences == 66_429)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    /// As a check on the state key: run A walked plainly from rest, every order up to five steps over nine moves (the eight of before and Space).
    /// It must meet no state the search did not, and break no rule.
    @Test func aPlainWalkOfRunAMeetsNoStateTheSearchDidNotAndBreaksNoRule() {
        let run = WalkRun.all[0]
        let visited = search(run).visited
        var sequences = 0
        var strangers = 0
        var problems: [String] = []
        func walk(_ sim: Sim, depth: Int, trail: [Move]) {
            if depth == 5 { return }
            for move in sim.plainMoves(run) {
                var next = sim
                next.found = []
                next.apply(move, run)
                sequences += 1
                let trail = trail + [move]
                if !visited.contains(next.key(run).hashValue), strangers < 3 {
                    strangers += 1
                    problems.append("a state the search did not reach after: \(trail.map { $0.text(run) }.joined(separator: ", "))")
                }
                var messages = next.found + restCheck(next, run)
                messages.removeAll { problems.contains($0) }
                if !messages.isEmpty, problems.count < 6 {
                    problems.append("\(messages[0]) [after: \(trail.map { $0.text(run) }.joined(separator: ", "))]")
                }
                walk(next, depth: depth + 1, trail: trail)
            }
        }
        walk(Sim(run), depth: 0, trail: [])
        print("voice key walk, plain: \(sequences) sequences")
        #expect(sequences == 66_429)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }
}
