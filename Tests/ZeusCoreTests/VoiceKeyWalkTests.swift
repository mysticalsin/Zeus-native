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
// the flags event of the modifier pressed ahead of it. Time does not pass while an event is held. A forwarded key that
// waited behind several later events is not modelled: with three modifiers let go and the arrow still held, the machine
// sees every key up and a start can follow, and no reducer can tell that from a clean press. The rules are therefore
// read against the keys the machine was told about, not against the keys physically down.
//
// A wake belongs to the phase that asked for it: when the phase changes the old wakes are dropped, so a phase that
// forgets its own wake is caught instead of being covered by a stale one.

/// One physical key of a run.
struct WalkKey: Hashable, Sendable {
    let name: String
    let code: UInt16
    /// The modifier flag this key sets, nil for an ordinary key.
    let flag: ShortcutModifiers?

    static let control = WalkKey(name: "Control", code: 59, flag: .control)
    static let option = WalkKey(name: "Option", code: 58, flag: .option)
    static let shift = WalkKey(name: "Shift", code: 56, flag: .shift)
    static let leftCommand = WalkKey(name: "LeftCommand", code: 55, flag: .command)
    static let rightCommand = WalkKey(name: "RightCommand", code: 54, flag: .command)
    static let globe = WalkKey(name: "Fn", code: 63, flag: .function)
    static let leftArrow = WalkKey(name: "Left", code: 123, flag: nil)
    static let letterT = WalkKey(name: "T", code: 17, flag: nil)
}

/// One run: the physical keys, which of them are the key's own set, and the configs the key cycles through.
struct WalkRun: Sendable, CustomTestStringConvertible {
    let name: String
    let keys: [WalkKey]
    let ownCodes: [UInt16]
    /// The first is the start; a `flip` move goes to the next, and round to the first.
    let configs: [VoiceKeyMachine.Config]

    let ownMask: UInt16
    let shiftMask: UInt16
    let ordinaryMask: UInt16

    var testDescription: String { name }

    init(_ name: String, keys: [WalkKey], own: [UInt16], configs: [VoiceKeyMachine.Config]) {
        self.name = name
        self.keys = keys
        self.ownCodes = own
        self.configs = configs
        var ownBits: UInt16 = 0, shiftBits: UInt16 = 0, ordinaryBits: UInt16 = 0
        for (index, key) in keys.enumerated() {
            let bit = UInt16(1) << UInt16(index)
            if own.contains(key.code) { ownBits |= bit }
            if key.flag == .shift { shiftBits |= bit }
            if key.flag == nil { ordinaryBits |= bit }
        }
        ownMask = ownBits
        shiftMask = shiftBits
        ordinaryMask = ordinaryBits
    }

    private typealias Config = VoiceKeyMachine.Config
    private static let basic: [WalkKey] = [.control, .option, .leftCommand, .shift, .leftArrow]
    private static let rightCommandKeys: [WalkKey] = [.control, .option, .rightCommand, .shift, .leftArrow]
    private static let controlOption: [UInt16] = [59, 58]

    private static func hold(_ role: VoiceKeyMachine.Role, _ key: Shortcut, confirm: TimeInterval) -> Config {
        Config(key: key, role: role, mode: .hold, confirm: confirm)
    }

    /// The nine runs of the plan.
    static let all: [WalkRun] = [
        // A: shipped talk beside tiling, with the confirm. A0: the same without it.
        WalkRun("A talk hold Control-Option confirm 0.15", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0.15)]),
        WalkRun("A0 talk hold Control-Option confirm 0", keys: basic, own: controlOption,
                configs: [hold(.talk, .controlOption, confirm: 0)]),
        // B: shipped dictation, with Left Command as a sixth key and a config that flips hold, toggle and off.
        WalkRun("B dictation Right Command hold toggle off", keys: rightCommandKeys + [.leftCommand], own: [54],
                configs: [hold(.dictation, .rightCommand, confirm: 0.15),
                          Config(key: .rightCommand, role: .dictation, mode: .toggle),
                          Config(key: nil, role: .dictation, mode: .hold)]),
        WalkRun("C dictation hold Control-Option confirm 0.15", keys: basic, own: controlOption,
                configs: [hold(.dictation, .controlOption, confirm: 0.15)]),
        WalkRun("D dictation shared Control-Option", keys: basic, own: controlOption,
                configs: [Config(key: .controlOption, role: .dictation, mode: .shared)]),
        WalkRun("E talk shared Control-Option", keys: basic, own: controlOption,
                configs: [Config(key: .controlOption, role: .talk, mode: .shared)]),
        WalkRun("F dictation toggle Right Command", keys: rightCommandKeys, own: [54],
                configs: [Config(key: .rightCommand, role: .dictation, mode: .toggle)]),
        // G: the shipped Polyglot key, Control-Option-T, with T in place of the arrow.
        WalkRun("G toggle Control-Option-T", keys: [.control, .option, .leftCommand, .shift, .letterT], own: [59, 58, 17],
                configs: [Config(key: Shortcut(keyCode: 17, modifiers: [.control, .option]), role: .dictation, mode: .toggle)]),
        // I: talk on Fn, the Globe key in place of Command.
        WalkRun("I talk hold Fn", keys: [.control, .option, .globe, .shift, .leftArrow], own: [63],
                configs: [hold(.talk, .function, confirm: 0)]),
    ]
}

// MARK: - The harness

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
    case toggle(Int), toggleHeld(Int), wait, waitHalfSecond, deliver, abandon, interrupt, flip

    func text(_ run: WalkRun) -> String {
        switch self {
        case .toggle(let index): run.keys[index].name
        case .toggleHeld(let index): run.keys[index].name + " (event held)"
        case .wait: "wait 0.05"
        case .waitHalfSecond: "wait 0.5"
        case .deliver: "deliver"
        case .abandon: "abandon"
        case .interrupt: "interrupt"
        case .flip: "flip"
        }
    }
}

private enum Kind { case key, tick, deliver, abandon, interrupt, flip }

/// What the keys physically down say, for one run.
private struct Phys {
    var ownAll = false
    var foreignAny = false
    var onlyShift = false
    var exactOwn = false
    var anyDown = false

    init(_ down: UInt16, _ run: WalkRun) {
        ownAll = down & run.ownMask == run.ownMask
        let foreign = down & ~run.ownMask
        foreignAny = foreign != 0
        onlyShift = foreign != 0 && foreign & ~run.shiftMask == 0
        exactOwn = down == run.ownMask
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
}

private struct Edge {
    var cameDown = false
    var released = false
}

/// The state of one search node. The machine is held as the four things it reads: the config, the flags-only modifier
/// set, the physical keys and the spoiled flag of its keyboard picture, `barred` and the phase with ages in place of
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
    var spoiled: Bool
    var barred: Bool
    var phase: VoiceKeyMachine.Phase
    var checker: Checker
}

private extension VoiceKeyMachine {
    /// The phase with ages in place of times, capped at 0.45 s, past every window (the longest is 0.4 s): the same
    /// phase whenever it was reached.
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

    var machine = VoiceKeyMachine()
    var down: UInt16 = 0
    /// The keys the machine has been told are down: the physical keys, less the events that are still on the way.
    /// The rules are read against this, because a key the machine was never told about cannot be told from no key.
    var seen: UInt16 = 0
    var consumed: UInt16 = 0
    /// At most one monitor event waits behind the next forwarded key.
    var held: Held?
    var wakes: Set<Int> = []
    var step = 0
    var cfg = 0
    var matcher = TileKeyMatcher()
    var checker = Checker()

    // Not part of the key: what the last move did.
    var edge = Edge()
    var log: [VoiceKeyMachine.Effect] = []
    var found: [String] = []

    var now: TimeInterval { Double(step) * 0.05 }

    func key(_ run: WalkRun) -> StateKey {
        StateKey(down: down, seen: seen, consumed: consumed, held: held, wakes: wakes.map { $0 - step }.sorted(), cfg: cfg,
                 config: machine.config, flags: machine.keys.flagModifiers, deviceKeys: machine.keys.deviceKeys,
                 keysDown: machine.keys.keysDown, spoiled: machine.keys.spoiled, barred: machine.barred,
                 phase: machine.normalizedPhase(at: now), checker: checker)
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
            out.append(.toggle(index))
            if held == nil { out.append(.toggleHeld(index)) }
        }
        // Time does not pass while an event is held back: it is a matter of one turn of the run loop.
        if held == nil { out.append(.wait) } else { out.append(.deliver) }
        out.append(.abandon)
        if run.configs.count > 1 { out.append(.flip) }
        if held == nil, down & run.ordinaryMask == 0 { out.append(.interrupt) }
        return out
    }

    /// The eight moves of the plain walk: the keys, a short and a long wait, and an abandon.
    func plainMoves(_ run: WalkRun) -> [Move] {
        run.keys.indices.map { Move.toggle($0) } + [.wait, .waitHalfSecond, .abandon]
    }

    // MARK: Applying a move

    mutating func apply(_ move: Move, _ run: WalkRun) {
        switch move {
        case .toggle(let index): toggle(index, hold: false, run)
        case .toggleHeld(let index): toggle(index, hold: true, run)
        case .wait: advance(run)
        case .waitHalfSecond: for _ in 0..<10 { advance(run) }
        case .deliver: flushHeld(run)
        case .abandon: feed(.abandon, .abandon, run)
        case .interrupt: feed(.interrupt(live: liveModifiers(run)), .interrupt, run)
        case .flip:
            cfg = (cfg + 1) % run.configs.count
            feed(.tick(at: now, live: liveModifiers(run)), .flip, run)
        }
        if !checker.ownWasDown { checker.pressForeign = false }
    }

    private mutating func flushHeld(_ run: WalkRun) {
        guard let event = held?.event else { return }
        let (index, pressed) = (Int(held?.index ?? 0), held?.pressed ?? false)
        held = nil
        feed(.key(event, at: now), .deliver, run, key: (index, pressed))
    }

    /// One monitor event reaches the machine, behind the one held back before it, or is held back itself.
    private mutating func monitor(_ event: ShortcutEvent, index: Int, pressed: Bool, hold: Bool, _ run: WalkRun) {
        flushHeld(run)
        if hold { held = Held(event, index: index, pressed: pressed) }
        else { feed(.key(event, at: now), .key, run, key: (index, pressed)) }
    }

    private mutating func toggle(_ index: Int, hold: Bool, _ run: WalkRun) {
        let bit = UInt16(1) << UInt16(index)
        let key = run.keys[index]
        let pressing = down & bit == 0
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

    private mutating func advance(_ run: WalkRun) {
        step += 1
        let confirmSteps = Int((run.configs[cfg].confirm / 0.05).rounded())
        if checker.ownWasDown, confirmSteps > 0 { checker.pressAge = min(checker.pressAge + 1, confirmSteps) }
        drainWakes(run)
    }

    /// Delivers every tick that is due, as the adapter would: each with the modifiers that are really down.
    private mutating func drainWakes(_ run: WalkRun) {
        var guardCount = 0
        while let due = wakes.filter({ $0 <= step }).min(), guardCount < 100 {
            guardCount += 1
            wakes.remove(due)
            feed(.tick(at: now, live: liveModifiers(run)), .tick, run)
        }
    }

    private mutating func feed(_ event: VoiceKeyMachine.Event, _ kind: Kind, _ run: WalkRun, key: (Int, Bool)? = nil) {
        edge = Edge()
        if let (index, pressed) = key {
            let bit = UInt16(1) << UInt16(index)
            if pressed { seen |= bit } else { seen &= ~bit }
            seenChanged(run)
        }
        let config = run.configs[cfg]
        let wasLatched = machine.isLatched
        let before = machine.phase
        let effects = machine.handle(event, config: config)
        log += effects
        // A wake belongs to the phase that asked for it. Once the phase has changed the old ones are dropped, so a
        // phase that forgets to ask for its own wake is caught, not covered by a stale one.
        if machine.phase != before { wakes.removeAll() }
        for effect in effects {
            if case .wake(let after) = effect { wakes.insert(step + Int((after / 0.05).rounded())) }
        }
        check(effects, wasLatched: wasLatched, kind: kind, config: config, run)
        if kind != .tick { drainWakes(run) }
    }

    // MARK: The rules

    private mutating func seenChanged(_ run: WalkRun) {
        let phys = Phys(seen, run)
        let wasOwn = checker.ownWasDown
        if phys.ownAll, !wasOwn {
            checker.pressAge = 0
            checker.pressForeign = phys.foreignAny
            edge.cameDown = true
        } else if phys.ownAll {
            checker.pressForeign = checker.pressForeign || phys.foreignAny
        }
        if !phys.ownAll {
            checker.presses = 0
            checker.pressAge = 0
        }
        if wasOwn, !phys.ownAll { edge.released = true }
        if checker.turnOpen, phys.foreignAny {
            if run.configs[0].role == .dictation, phys.onlyShift { checker.shiftSeen = true } else { checker.foreign = true }
        }
        if phys.ownAll, phys.foreignAny { checker.bigger = true }
        if !phys.anyDown {
            checker.cancelled = false
            checker.bigger = false
        }
        checker.ownWasDown = phys.ownAll
    }

    private mutating func check(_ effects: [VoiceKeyMachine.Effect], wasLatched: Bool, kind: Kind,
                                config: VoiceKeyMachine.Config, _ run: WalkRun) {
        let phys = Phys(seen, run)
        let dictation = config.role == .dictation
        let confirmSteps = Int((config.confirm / 0.05).rounded())
        for effect in effects {
            switch effect {
            case .start:
                if checker.cancelled { found.append("I2: start after a cancel, before every key was up") }
                if checker.bigger { found.append("I6: start after the own set was down with something foreign, before every key was up") }
                if phys.ownAll, phys.foreignAny { found.append("I3: start on a larger chord") }
                if config.mode == .toggle {
                    checker.presses += 1
                    if checker.presses > 1 { found.append("I7: a toggle fired twice in one press") }
                } else {
                    if checker.turnOpen { found.append("I4: start while a turn is open") }
                    checker.turnOpen = true
                    checker.foreign = false
                    checker.shiftSeen = false
                    if phys.foreignAny {
                        if dictation, phys.onlyShift { checker.shiftSeen = true } else { checker.foreign = true }
                    }
                }
            case .send:
                if !checker.turnOpen {
                    found.append("I4: send without an open turn")
                } else if wasLatched {
                    let atPress = confirmSteps == 0 && edge.cameDown && phys.exactOwn
                    let stayedAlone = confirmSteps > 0 && kind == .tick && phys.exactOwn && !checker.pressForeign
                        && checker.pressAge >= confirmSteps
                    let cleanRelease = confirmSteps > 0 && edge.released && !checker.pressForeign
                    if !(atPress || stayedAlone || cleanRelease) {
                        found.append("I1: a hands-free turn was sent by something other than a clean press of exactly the own set")
                    }
                } else {
                    if checker.foreign { found.append("I1: a turn was sent after something foreign was down") }
                    if checker.shiftSeen, phys.ownAll { found.append("I1: a Shift press was sent while its key was still down") }
                }
                checker.turnOpen = false
            case .cancel:
                if !checker.turnOpen { found.append("I4: cancel without an open turn") }
                if wasLatched, kind != .interrupt, kind != .flip, kind != .abandon {
                    found.append("I1: a hands-free turn was cancelled by typing or a larger chord")
                }
                checker.turnOpen = false
                checker.cancelled = phys.anyDown
            case .refused, .wake: break
            }
        }
        if kind == .abandon { checker.turnOpen = false }
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

/// The rest check of one state, on a copy: let go of everything, wait 0.5 s, press the own set (I8, last clause of I4).
private func restCheck(_ sim: Sim, _ run: WalkRun) -> [String] {
    var base = sim
    base.found = []
    base.apply(.deliver, run)
    for index in run.keys.indices where base.down & (UInt16(1) << UInt16(index)) != 0 { base.apply(.toggle(index), run) }
    base.apply(.deliver, run)
    for _ in 0..<10 { base.apply(.wait, run) }
    var out = base.found
    base.found = []
    if base.checker.turnOpen != base.machine.isLatched {
        out.append("I4: with every key up and every timer run out, a turn is open and the machine is not hands-free (or the reverse)")
    }
    let config = run.configs[base.cfg]
    guard config.key != nil, !config.voiceOverHoldsKey else { return out }
    let ownIndices = run.keys.indices.filter { run.ownMask & (UInt16(1) << UInt16($0)) != 0 }
    for order in [ownIndices, ownIndices.reversed()] {
        var sim = base
        sim.log = []
        let wasLatched = sim.machine.isLatched
        func tap(_ sim: inout Sim) {
            for index in order { sim.apply(.toggle(index), run) }
            sim.apply(.wait, run); sim.apply(.wait, run)
            for index in order.reversed() { sim.apply(.toggle(index), run) }
            sim.apply(.wait, run); sim.apply(.wait, run)
        }
        if config.mode == .shared, config.role == .talk, !wasLatched {
            tap(&sim); tap(&sim)
        } else {
            for index in order { sim.apply(.toggle(index), run) }
            let steps = config.mode == .shared ? 7 : Int((config.confirm / 0.05).rounded()) + 2
            for _ in 0..<steps { sim.apply(.wait, run) }
        }
        let acted: Bool = wasLatched ? sim.log.contains(.send) : sim.log.contains(.start)
        if !acted {
            let names = order.map { run.keys[$0].name }.joined(separator: ", ")
            out.append("I8: after letting go of everything and waiting 0.5 s, pressing \(names) did not act (latched \(wasLatched))")
        }
        out += sim.found
    }
    return out
}

private func search(_ run: WalkRun) -> Report {
    let start = Date()
    var report = Report()
    var seen: [Int: Int] = [:]
    var parents = [0], via: [Move] = [.wait]
    var frontier: [Sim?] = []
    let root = Sim()
    seen[root.key(run).hashValue] = 0
    frontier.append(root)
    var seenRules: Set<String> = []

    func record(_ messages: [String], at index: Int, move: Move?) {
        for message in messages {
            let rule = String(message.prefix(while: { $0 != ":" }))
            guard seenRules.insert(rule + message).inserted, report.violations.count < 16 else { continue }
            var text = path(run, to: index, parents: parents, via: via)
            if let move { text += (text.isEmpty ? "" : ", ") + move.text(run) }
            report.violations.append("\(message) [after: \(text)]")
        }
    }

    var cursor = 0
    while cursor < frontier.count {
        guard let sim = frontier[cursor] else { cursor += 1; continue }
        frontier[cursor] = nil
        record(restCheck(sim, run), at: cursor, move: nil)
        for move in sim.moves(run) {
            var next = sim
            next.found = []
            next.apply(move, run)
            report.moves += 1
            record(next.found, at: cursor, move: move)
            let key = next.key(run).hashValue
            if seen[key] == nil {
                seen[key] = frontier.count
                parents.append(cursor)
                via.append(move)
                frontier.append(next)
            }
        }
        cursor += 1
    }
    report.states = seen.count
    report.seconds = Date().timeIntervalSince(start)
    report.visited = Set(seen.keys)
    return report
}

/// Replays one order of moves through the harness and returns what the checker found.
private func replay(_ run: WalkRun, _ names: [String]) -> [String] {
    var sim = Sim()
    var out: [String] = []
    for name in names {
        let move: Move
        switch name {
        case "wait": move = .wait
        case "wait 0.5": move = .waitHalfSecond
        case "deliver": move = .deliver
        default:
            guard let index = run.keys.firstIndex(where: { $0.name == name }) else { return ["unknown move \(name)"] }
            move = .toggle(index)
        }
        sim.found = []
        sim.apply(move, run)
        out += sim.found
    }
    return out + restCheck(sim, run)
}

@Suite struct VoiceKeyWalkTests {
    @Test(arguments: WalkRun.all)
    fileprivate func everyOrderOfPressesKeepsTheRules(run: WalkRun) {
        let report = search(run)
        print("voice key walk \(run.name): \(report.states) states, \(report.moves) moves, \(String(format: "%.2f", report.seconds)) s")
        #expect(report.violations.isEmpty, "\(run.name): \(report.violations.joined(separator: "\n"))")
        #expect(report.states > 100, "the search found too few states to be a search")
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

    /// As a check on the state key: run A walked plainly from rest, every order up to five steps over eight moves.
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
        walk(Sim(), depth: 0, trail: [])
        print("voice key walk, plain: \(sequences) sequences")
        #expect(sequences == 37_448)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }
}
