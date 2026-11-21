import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The real monitor, driven as the adapter of the voice key machine (docs/VOICE-KEY-MACHINE-PLAN.md, 4.4): it turns
/// events, consumed keys and timer firings into machine events and runs the effects. The press orders here are the ones
/// the reviews of the tiling branch found. Everything the monitor decides, the machine decides, so these tests read
/// only the callbacks.
@Suite("Hotkey monitor as the voice key machine's adapter", .serialized) @MainActor
struct HotkeyMonitorMachineTests {
    private let all: ShortcutModifiers = [.control, .option, .command]
    private let leftArrow: UInt16 = 123
    private let letterT: UInt16 = 17

    private final class Calls {
        var presses = 0, releases = 0, cancels = 0, blocked = 0
        var log: [String] = []
        /// What `onPress` answers: false means the owner refused the press.
        var takes = true
    }

    private func make(key: Shortcut = .controlOption, role: HotkeyMonitor.Role = .talk, shared: Bool = false,
                      toggle: Bool = false, voiceOver: Bool = false, confirm: TimeInterval = 0,
                      live: ShortcutModifiers? = nil, chord: UInt16? = nil, second: Shortcut? = nil) -> (HotkeyMonitor, Calls) {
        let monitor = HotkeyMonitor()
        monitor.secondKeyProvider = { second }
        let calls = Calls()
        monitor.role = role
        monitor.keyProvider = { key }
        monitor.sharedProvider = { shared }
        monitor.directPressProvider = { toggle }
        monitor.voiceOverProvider = { voiceOver }
        monitor.confirmProvider = { confirm }
        monitor.liveModifiers = { live }
        monitor.chordProvider = { chord }
        monitor.onPress = { calls.presses += 1; calls.log.append("press"); return calls.takes }
        monitor.onRelease = { calls.releases += 1; calls.log.append("release") }
        monitor.onCancel = { calls.cancels += 1; calls.log.append("cancel") }
        monitor.onBlocked = { _ in calls.blocked += 1; calls.log.append("blocked") }
        return (monitor, calls)
    }

    private func wait(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }

    private func controlOption(_ monitor: HotkeyMonitor) {
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
    }

    private func allUp(_ monitor: HotkeyMonitor) {
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 59, modifiers: []))
    }

    /// Control, Option, Shift, Command, then Left: the swap chord pressed in the order that sent a turn.
    private func swapChord(_ monitor: HotkeyMonitor, consumed: Bool) {
        controlOption(monitor)
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option, .shift, .command]))
        let down = ShortcutEvent.keyDown(keyCode: leftArrow, modifiers: [.control, .option, .shift, .command])
        if consumed { TilingConsumedKey.post(down) } else { monitor.feed(down) }
        if consumed { TilingConsumedKey.post(.keyUp(keyCode: leftArrow)) } else { monitor.feed(.keyUp(keyCode: leftArrow)) }
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option, .shift]))
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option]))
        allUp(monitor)
    }

    // MARK: F1

    @Test func theSwapChordPressedControlOptionShiftCommandSendsAndLatchesNothing() async throws {
        let (monitor, calls) = make()
        for _ in 0..<3 {
            swapChord(monitor, consumed: false)
        }
        try await wait(0.6)
        #expect(calls.releases == 0, "no tiling chord sends a talk turn: \(calls.log)")
        #expect(calls.cancels == calls.presses, "every turn is cancelled, none is left open: \(calls.log)")
        controlOption(monitor)
        #expect(calls.log.last == "press", "a plain hold afterwards starts a turn, so nothing latched: \(calls.log)")
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.releases == 1, "and its release sends: \(calls.log)")
    }

    @Test func aConsumedKeyAndTheSameKeyFedDirectlyGiveTheSameCallbacks() async throws {
        let (viaTap, tapCalls) = make()
        viaTap.observeConsumedKeys()
        let (direct, directCalls) = make()
        swapChord(viaTap, consumed: true)
        swapChord(direct, consumed: false)
        try await wait(0.6)
        #expect(tapCalls.log == directCalls.log, "\(tapCalls.log) against \(directCalls.log)")
    }

    // MARK: The second talk key (docs/RIGHT-OPTION-TALK-PLAN.md)

    /// Right Option goes down or up, with `held` modifiers already down.
    private func rightOptionDown(_ monitor: HotkeyMonitor, beside held: ShortcutModifiers = []) {
        monitor.feed(.flags(keyCode: 61, modifiers: held.union(.option)))
    }

    private func rightOptionUp(_ monitor: HotkeyMonitor, beside held: ShortcutModifiers = []) {
        monitor.feed(.flags(keyCode: 61, modifiers: held))
    }

    @Test func theSecondKeyCallsPressOnceAndReleaseOnce() async throws {
        let (monitor, calls) = make(second: .rightOption)
        rightOptionDown(monitor)
        try await wait(0.1)
        #expect(calls.presses == 0, "Right Option waits a quarter second: \(calls.log)")
        try await wait(0.4)
        #expect(calls.presses == 1, "\(calls.log)")
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "release"], "\(calls.log)")
    }

    @Test func aSecondKeyPressDuringAPrimaryTurnCallsNothing() async throws {
        let (monitor, calls) = make(second: .rightOption)
        controlOption(monitor)
        #expect(calls.presses == 1, "the primary key starts at once with no confirm: \(calls.log)")
        rightOptionDown(monitor, beside: [.control])
        try await wait(0.6)
        #expect(calls.log == ["press"], "the second key's start never reaches the owner: \(calls.log)")
        rightOptionUp(monitor, beside: [.control, .option])
        try await wait(0.1)
        allUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "release"], "one turn, ended by its own key: \(calls.log)")
    }

    @Test func aRefusedSecondKeyPressIsAbandonedAndTheNextPressStarts() async throws {
        let (monitor, calls) = make(second: .rightOption)
        calls.takes = false
        rightOptionDown(monitor)
        try await wait(0.5)
        #expect(calls.log == ["press"], "\(calls.log)")
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press"], "a turn the owner refused is never sent: \(calls.log)")
        calls.takes = true
        rightOptionDown(monitor)
        try await wait(0.5)
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "press", "release"], "\(calls.log)")
    }

    /// The clock the monitor reads, set by the test, so keys can be fed at times the real timers have not reached (a busy main thread).
    private final class FakeClock { var seconds = 0.0 }

    @Test func aSecondStartDueBeforeTheControlKeyActsBeforeItWhenTheTimerIsLate() async throws {
        let (monitor, calls) = make(second: .rightOption)
        let clock = FakeClock()
        monitor.now = { clock.seconds }
        rightOptionDown(monitor)
        clock.seconds = 0.3
        monitor.feed(.flags(keyCode: 59, modifiers: [.control, .option]), at: 0.3)
        #expect(calls.log == ["press", "cancel"], "Right Option started at 0.25, Control cancelled it, and the primary start is swallowed: \(calls.log)")
        try await wait(0.4)
        monitor.feed(.flags(keyCode: 59, modifiers: [.option]), at: 0.8)
        monitor.feed(.flags(keyCode: 61, modifiers: []), at: 0.8)
        try await wait(0.1)
        #expect(calls.log == ["press", "cancel"], "\(calls.log)")
    }

    @Test func aGapSendDueBeforeASecondKeyReleaseIsOneSendWhenTheTimerIsLate() async throws {
        let (monitor, calls) = make(second: .rightOption)
        let clock = FakeClock()
        monitor.now = { clock.seconds }
        controlOption(monitor)
        clock.seconds = 0.1
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]), at: 0.1)
        monitor.feed(.flags(keyCode: 59, modifiers: []), at: 0.1)
        clock.seconds = 0.2
        rightOptionDown(monitor)
        clock.seconds = 0.6
        monitor.feed(.flags(keyCode: 61, modifiers: []), at: 0.6)
        #expect(calls.log == ["press", "release"], "one turn, sent once, no second start: \(calls.log)")
    }

    @Test func aSpaceDownAtTheReleaseOfASecondKeyTurnCancelsItInsteadOfSendingIt() async throws {
        // Space may be held by a launcher on Option-Space that Zeus cannot see; the system's own key state says it is down.
        let (monitor, calls) = make(second: .rightOption)
        var spaceDown = false
        monitor.keysStillDown = { spaceDown ? $0.intersection([49]) : [] }
        rightOptionDown(monitor)
        try await wait(0.5)
        spaceDown = true
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "cancel"], "\(calls.log)")
        spaceDown = false
        rightOptionDown(monitor)
        try await wait(0.5)
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "cancel", "press", "release"], "a plain release still sends: \(calls.log)")
    }

    @Test func aMouseDownWhileTheSecondKeyIsHeldCancelsItAndNeverSendsIt() async throws {
        let (monitor, calls) = make(second: .rightOption)
        rightOptionDown(monitor)
        try await wait(0.5)
        monitor.mouseDown()
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "cancel"], "\(calls.log)")
    }

    @Test func aMouseClickHeardLateIsReadAtTheTimeItHappened() async throws {
        // Right Option down at 0, the click at 0.2, the main thread busy until 0.3: the 0.25 confirm has not passed at the click, so
        // the press is dropped, and onPress is never called.
        let (monitor, calls) = make(second: .rightOption)
        let clock = FakeClock()
        monitor.now = { clock.seconds }
        rightOptionDown(monitor)
        clock.seconds = 0.3
        monitor.mouseDown(at: 0.2)
        #expect(calls.log == [], "the click came inside the confirm: \(calls.log)")
        try await wait(0.4)
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == [], "nothing started, nothing sent: \(calls.log)")
    }

    @Test func aLauncherSpaceTappedDuringTheHoldCancelsItAtTheRelease() async throws {
        // Option-Space tapped and let go inside the hold, between two looks at the keyboard, is never in the picture at the release.
        let (monitor, calls) = make(second: .rightOption)
        var spaceDown = false
        monitor.keysStillDown = { spaceDown ? $0.intersection([49]) : [] }
        rightOptionDown(monitor)
        try await wait(0.4)
        spaceDown = true
        monitor.feed(.flags(keyCode: 61, modifiers: [.option]))
        spaceDown = false
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "cancel"], "a Space seen during the hold means the person was not talking: \(calls.log)")
    }

    @Test func aMouseDownDuringTheControlOptionKeyChangesNothing() async throws {
        let (monitor, calls) = make(second: .rightOption)
        controlOption(monitor)
        try await wait(0.3)
        monitor.mouseDown()
        allUp(monitor)
        try await wait(0.1)
        #expect(calls.log == ["press", "release"], "\(calls.log)")
    }

    @Test func aSecondKeyTurnedOffDuringAHandsFreeTurnIsCancelledAtOnce() async throws {
        let (monitor, calls) = make(second: .rightOption)
        var second: Shortcut? = .rightOption
        monitor.secondKeyProvider = { second }
        rightOptionDown(monitor); rightOptionUp(monitor)
        rightOptionDown(monitor); rightOptionUp(monitor)
        #expect(calls.log == ["press"], "a double tap goes hands-free: \(calls.log)")
        second = nil
        monitor.configChanged()
        #expect(calls.log == ["press", "cancel"], "the next sync point applies the change at once: \(calls.log)")
    }

    @Test func theDictationMonitorNeverHearsTheSecondKey() async throws {
        let (monitor, calls) = make(key: .rightCommand, role: .dictation, second: .rightOption)
        rightOptionDown(monitor)
        try await wait(0.6)
        rightOptionUp(monitor)
        try await wait(0.1)
        #expect(calls.log.isEmpty, "only the talk monitor has a second key: \(calls.log)")
    }

    /// Sentinel L-1 #112. A stale hardware read must not hold Right Option past the key-up,
    /// and a flags repeat of that key must not ask the hardware at all.
    @Test func aRightOptionReleaseStopsAtTheKeyUpAndNeverTakesTheRepeatDropPath() {
        let (monitor, calls) = make(second: .rightOption)
        let clock = FakeClock()
        monitor.now = { clock.seconds }
        var releaseAt: TimeInterval?
        monitor.onRelease = {
            calls.releases += 1
            calls.log.append("release")
            releaseAt = clock.seconds
        }
        monitor.modifierIsDown = { $0 == 61 || $0 == 58 }
        rightOptionDown(monitor)
        clock.seconds = VoiceKey.secondKeyConfirm
        monitor.configChanged()
        #expect(calls.log == ["press"], "the hold starts at the confirm: \(calls.log)")
        let keyUp = VoiceKey.secondKeyConfirm + 0.20
        clock.seconds = keyUp
        rightOptionUp(monitor)
        #expect(releaseAt == keyUp, "the release stops the turn at the key-up")
        clock.seconds = keyUp + 0.30
        monitor.configChanged()
        #expect(releaseAt == keyUp, "a later tick is not what stops Right Option: \(calls.log)")

        var asked: [UInt16] = []
        monitor.modifierIsDown = { code in
            asked.append(code)
            return true
        }
        monitor.feed(.flags(keyCode: 58, modifiers: [.option]), at: clock.seconds)
        clock.seconds += 0.01
        monitor.feed(.flags(keyCode: 61, modifiers: [.option]), at: clock.seconds)
        asked.removeAll()
        clock.seconds += 0.01
        monitor.feed(.flags(keyCode: 61, modifiers: [.option]), at: clock.seconds)
        #expect(asked.isEmpty, "Right Option never takes the repeat-drop path")
    }

    // MARK: The talk chord (docs/ULTRON-CHORD-PLAN.md)

    private let space: UInt16 = 49

    /// Control and Option held, Space down for a while and up again, then the pair let go.
    private func chordHold(_ monitor: HotkeyMonitor) async throws {
        controlOption(monitor)
        try await wait(0.1)
        monitor.feed(.keyDown(keyCode: space, modifiers: [.control, .option]))
        try await wait(0.35)
        monitor.feed(.keyUp(keyCode: space))
        try await wait(0.05)
        allUp(monitor)
        try await wait(0.6)
    }

    @Test func theTalkChordCallsPressOnceAndReleaseOnce() async throws {
        let (monitor, calls) = make(chord: space)
        try await chordHold(monitor)
        #expect(calls.presses == 1 && calls.releases == 1 && calls.cancels == 0, "\(calls.log)")
        #expect(calls.log == ["press", "release"], "\(calls.log)")
    }

    @Test func theTalkChordWithTheChordOffCancelsAsBefore() async throws {
        let (monitor, calls) = make(chord: nil)
        try await chordHold(monitor)
        #expect(calls.presses == 1 && calls.cancels == 1 && calls.releases == 0, "\(calls.log)")
    }

    @Test func aSpaceTypedAloneCallsNothing() async throws {
        let (monitor, calls) = make(chord: space)
        monitor.feed(.keyDown(keyCode: space, modifiers: []))
        monitor.feed(.keyUp(keyCode: space))
        try await wait(0.6)
        #expect(calls.log.isEmpty, "\(calls.log)")
    }

    // MARK: A Space no monitor heard (Carbon holds the talk chord, so its key-down never reaches the monitors)

    private final class LiveSpace { var down = false }

    private func swallowing(_ live: LiveSpace) -> (HotkeyMonitor, Calls) {
        let (monitor, calls) = make(chord: space)
        monitor.keysStillDown = { $0.filter { $0 == 49 && live.down } }
        return (monitor, calls)
    }

    @Test func aSwallowedSpaceHeldBeforeTheSetKeepsTheSetFromStarting() async throws {
        let live = LiveSpace()
        let (monitor, calls) = swallowing(live)
        live.down = true // Space went down first and no event said so
        controlOption(monitor)
        try await wait(0.1)
        #expect(calls.presses == 0, "Space came before the set: not the chord: \(calls.log)")
        allUp(monitor)
        live.down = false
        try await wait(0.1)
        controlOption(monitor)
        #expect(calls.presses == 1, "everything was up in between: \(calls.log)")
        allUp(monitor)
        try await wait(0.6)
    }

    @Test func aSwallowedSpaceHeldPastTheSendDoesNotLetTheSetStartAgain() async throws {
        let live = LiveSpace()
        let (monitor, calls) = swallowing(live)
        controlOption(monitor)
        try await wait(0.1)
        live.down = true // the chord Space, swallowed
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.log == ["press", "release"], "the clean chord sends: \(calls.log)")
        controlOption(monitor)
        try await wait(0.1)
        #expect(calls.presses == 1, "Space is still down: the set is not alone, nothing starts (I6): \(calls.log)")
        allUp(monitor)
        live.down = false
        try await wait(0.1)
        controlOption(monitor)
        #expect(calls.presses == 2, "Space is up and so is everything else: \(calls.log)")
        allUp(monitor)
        try await wait(0.6)
    }

    /// The pair at 0.00 and 0.01 arms a press that waits 0.15 s. Control comes up at 0.05, Space goes down with no event, and
    /// the main thread is busy until 0.30. The Space is found on the flags event of Control, which is read at its own time
    /// and not at the time it is heard: the pair never stood for the confirm, so nothing starts.
    @Test func aSwallowedSpaceFoundOnALateFlagsEventIsReadAtThatEventsTime() {
        let live = LiveSpace()
        let (monitor, calls) = swallowing(live)
        monitor.confirmProvider = { 0.15 }
        let clock = Clock()
        armedThenBusy(monitor, clock)
        live.down = true
        monitor.feed(.flags(keyCode: 59, modifiers: [.option]), at: 0.05)
        #expect(calls.log.isEmpty, "a tap shorter than the confirm does nothing, Space or not: \(calls.log)")
    }

    // MARK: Cancel and release

    @Test func aKeyJoiningADedicatedDictationHoldCancelsIt() async throws {
        let (monitor, calls) = make(role: .dictation)
        controlOption(monitor)
        monitor.feed(.keyDown(keyCode: letterT, modifiers: [.control, .option]))
        monitor.feed(.keyUp(keyCode: letterT))
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.presses == 1 && calls.cancels == 1 && calls.releases == 0, "\(calls.log)")
    }

    @Test func aCancelNeverCallsOnRelease() async throws {
        let (monitor, calls) = make()
        monitor.onCancel = nil
        controlOption(monitor)
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.presses == 1 && calls.releases == 0, "\(calls.log)")
    }

    // MARK: Toggle

    @Test func aToggleFiresOncePerPress() async throws {
        let (monitor, calls) = make(role: .dictation, toggle: true)
        controlOption(monitor)
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]))
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        #expect(calls.presses == 1, "a foreign modifier tapped during one press does not toggle again: \(calls.log)")
        allUp(monitor)
        controlOption(monitor)
        #expect(calls.presses == 2, "the next press toggles: \(calls.log)")
        #expect(calls.cancels == 0 && calls.releases == 0)
    }

    // MARK: VoiceOver

    @Test func theVoiceOverRefusalComesOncePerPressInEveryMode() {
        for (shared, toggle) in [(false, false), (true, false), (false, true)] {
            let (monitor, calls) = make(role: .dictation, shared: shared, toggle: toggle, voiceOver: true)
            controlOption(monitor)
            monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]))
            monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option]))
            #expect(calls.blocked == 1 && calls.presses == 0, "shared \(shared), toggle \(toggle): \(calls.log)")
            allUp(monitor)
            controlOption(monitor)
            #expect(calls.blocked == 2 && calls.presses == 0, "shared \(shared), toggle \(toggle): \(calls.log)")
        }
    }

    // MARK: The owner and the machine

    @Test func aRefusedPressFollowedByAForeignKeyCallsNeitherReleaseNorCancel() async throws {
        let (monitor, calls) = make()
        calls.takes = false
        controlOption(monitor)
        monitor.feed(.keyDown(keyCode: letterT, modifiers: [.control, .option]))
        monitor.feed(.keyUp(keyCode: letterT))
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.presses == 1 && calls.releases == 0 && calls.cancels == 0, "\(calls.log)")
    }

    @Test func aRefusedPressIsNotSentWhenTheKeyIsLetGo() async throws {
        let (monitor, calls) = make()
        calls.takes = false
        controlOption(monitor)
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.presses == 1 && calls.releases == 0 && calls.cancels == 0, "\(calls.log)")
    }

    /// Right Command pressed twice quickly: a hands-free turn is running.
    private func latchHandsFree(_ monitor: HotkeyMonitor) {
        for _ in 0..<2 {
            monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
            monitor.feed(.flags(keyCode: 54, modifiers: []))
        }
    }

    @Test func turnEndedWhileLatchedLetsTheNextPressStart() {
        let (monitor, calls) = make(key: .rightCommand, role: .dictation)
        latchHandsFree(monitor)
        #expect(calls.presses == 1 && calls.releases == 0, "\(calls.log)")
        monitor.turnEnded()
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        #expect(calls.presses == 2 && calls.releases == 0, "the press starts a turn, it does not end a gone one: \(calls.log)")
    }

    @Test func turnEndedAfterTheMachinesOwnSendChangesNothing() {
        let (monitor, calls) = make(key: .rightCommand, role: .dictation)
        latchHandsFree(monitor)
        monitor.feed(.flags(keyCode: 54, modifiers: [.command])) // the press that ends it: sent
        monitor.turnEnded()
        monitor.feed(.flags(keyCode: 54, modifiers: []))
        #expect(calls.presses == 1 && calls.releases == 1 && calls.cancels == 0, "\(calls.log)")
    }

    /// A quick tap leaves its turn waiting out the gap. The tick that would send it is late, so the next press is handled
    /// first: one call sends the old turn and opens the new one. The owner stops listening the moment it is sent and says
    /// so from inside `onRelease`, which must not end the turn that the same call opened.
    @Test func anOwnersEchoOfASendDoesNotEndTheTurnTheSameCallOpens() {
        let (monitor, calls) = make(key: .rightCommand, role: .dictation)
        var clock: TimeInterval = 0
        monitor.now = { clock }
        monitor.onRelease = { [weak monitor] in
            calls.releases += 1
            calls.log.append("release")
            monitor?.turnEnded()
        }
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        clock = 0.1
        monitor.feed(.flags(keyCode: 54, modifiers: []))
        clock = 0.55 // the 0.4 s gap is over (the tap ended at 0.1) and its tick has not run
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        #expect(calls.log == ["press", "release", "press"], "the old turn is sent, the new one opens: \(calls.log)")
        clock = 1.0
        monitor.feed(.flags(keyCode: 54, modifiers: []))
        #expect(calls.log == ["press", "release", "press", "release"], "the release sends the second turn: \(calls.log)")
    }

    // MARK: A key-up nobody saw

    private let tab: UInt16 = 48

    /// Tab into a password field: secure input turns on before Tab comes up, so the key-up never reaches a monitor.
    @Test func anOrdinaryKeyWhoseKeyUpNoMonitorSawDoesNotKillTheKey() {
        let (monitor, calls) = make(key: .rightCommand, role: .dictation)
        var clock: TimeInterval = 0
        monitor.now = { clock }
        monitor.keysStillDown = { _ in [] } // the system says Tab is up
        monitor.feed(.keyDown(keyCode: tab, modifiers: []))
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        #expect(calls.log == ["press"], "the first press of the key acts: \(calls.log)")
        clock = 1
        monitor.feed(.flags(keyCode: 54, modifiers: []))
        clock = 2
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        #expect(calls.log == ["press", "release", "press"], "and so does the next, nothing is stuck: \(calls.log)")
    }

    @Test func anOrdinaryKeyTheSystemStillReportsDownStaysForeign() {
        let (monitor, calls) = make(key: .rightCommand, role: .dictation)
        var clock: TimeInterval = 0
        monitor.now = { clock }
        monitor.keysStillDown = { $0 }
        monitor.feed(.keyDown(keyCode: tab, modifiers: []))
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        #expect(calls.log.isEmpty, "Tab is held: a larger chord, not the key: \(calls.log)")
        monitor.feed(.keyUp(keyCode: tab))
        monitor.feed(.flags(keyCode: 54, modifiers: []))
        clock = 1
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        #expect(calls.log == ["press"], "everything was up in between: \(calls.log)")
    }

    // MARK: Time

    @Test func aReleaseNoEventReportedEndsTheTurnWithinAMoment() async throws {
        let (monitor, calls) = make(live: [])
        controlOption(monitor)
        #expect(calls.presses == 1)
        try await wait(0.9) // the first look is at 0.25 s, a quick tap then waits out its 0.4 s gap
        #expect(calls.releases == 1 && calls.cancels == 0, "the live modifiers say it was let go: \(calls.log)")
    }

    /// A monitor whose owner sets no confirm asks tiling for it, by the key it listens for.
    @Test func aMonitorWithNoConfirmOfItsOwnAsksTilingForOne() {
        let saved = HotkeyMonitor.tilingConfirm
        defer { HotkeyMonitor.tilingConfirm = saved }
        HotkeyMonitor.tilingConfirm = { $0 == .controlOption ? 0.15 : 0 }
        let (monitor, calls) = make()
        monitor.confirmProvider = nil
        controlOption(monitor)
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        monitor.feed(.keyDown(keyCode: leftArrow, modifiers: all))
        monitor.feed(.keyUp(keyCode: leftArrow))
        allUp(monitor)
        #expect(calls.log.isEmpty, "the chord pressed as a chord opens nothing: \(calls.log)")
    }

    /// Control at 0.00 and Option at 0.01 arm a talk press that waits 0.15 s. The main thread is then busy, and the
    /// monitor handles at 0.30 an event that happened at 0.05, before the wake that was due at 0.16 has run.
    private func armedThenBusy(_ monitor: HotkeyMonitor, _ clock: Clock) {
        monitor.now = { clock.time }
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]), at: 0)
        clock.time = 0.01
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 0.01)
        clock.time = 0.30
    }

    private final class Clock { var time: TimeInterval = 0 }

    @Test func aFlagsEventHandledLateIsReadAtTheTimeItHappened() async throws {
        let (monitor, calls) = make(confirm: 0.15)
        armedThenBusy(monitor, Clock())
        monitor.feed(.flags(keyCode: 55, modifiers: all), at: 0.05)
        try await wait(0.3) // the wake arrives and finds nothing
        #expect(calls.log.isEmpty, "Command came 0.04 s after the pair: a chord, nothing opens: \(calls.log)")
    }

    @Test func aConsumedKeyHandledLateIsReadAtTheTimeItHappened() async throws {
        let (monitor, calls) = make(confirm: 0.15)
        monitor.observeConsumedKeys()
        armedThenBusy(monitor, Clock())
        // The key reports no modifier beyond the pair, so only its own time can say it came before the confirm elapsed.
        TilingConsumedKey.post(.keyDown(keyCode: leftArrow, modifiers: [.control, .option]), at: 0.06)
        try await wait(0.3)
        #expect(calls.log.isEmpty, "the key came 0.05 s after the pair: \(calls.log)")
    }

    @Test func aKeyThatCameAfterTheConfirmStillStartsTheTurnWhateverTheHandlingTime() async throws {
        let (monitor, calls) = make(confirm: 0.15)
        armedThenBusy(monitor, Clock())
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]), at: 0.2)
        #expect(calls.log == ["press", "cancel"], "a slow press is a start and then a cancel, as always: \(calls.log)")
    }

    // MARK: Sleep and wake

    @Test func sleepCancelsAnOpenTurnAndNothingStartsUntilEveryKeyIsUp() {
        let center = NotificationCenter()
        let (monitor, calls) = make()
        monitor.observeSleep(center: center)
        monitor.observeSleep(center: center)
        controlOption(monitor)
        #expect(calls.log == ["press"])
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(calls.log == ["press", "cancel"], "one cancel, never a send: \(calls.log)")
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(calls.log == ["press", "cancel"], "nothing is open to cancel on wake: \(calls.log)")
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]))
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option]))
        #expect(calls.presses == 1, "the keys are still down: \(calls.log)")
    }

    @Test func aHoldKeyInsideATilingChordActsOnlyAfterItsConfirm() async throws {
        let (monitor, calls) = make(confirm: 0.15)
        controlOption(monitor)
        #expect(calls.presses == 0, "nothing at the key-down: \(calls.log)")
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        try await wait(0.3)
        #expect(calls.presses == 0 && calls.cancels == 0, "the larger chord came in time: \(calls.log)")
        allUp(monitor)
        controlOption(monitor)
        try await wait(0.45)
        #expect(calls.presses == 1, "held alone past the confirm, it starts: \(calls.log)")
        allUp(monitor)
        try await wait(0.6)
        #expect(calls.releases == 1 && calls.cancels == 0, "\(calls.log)")
    }
}
