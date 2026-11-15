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
                      live: ShortcutModifiers? = nil) -> (HotkeyMonitor, Calls) {
        let monitor = HotkeyMonitor()
        let calls = Calls()
        monitor.role = role
        monitor.keyProvider = { key }
        monitor.sharedProvider = { shared }
        monitor.directPressProvider = { toggle }
        monitor.voiceOverProvider = { voiceOver }
        monitor.confirmProvider = { confirm }
        monitor.liveModifiers = { live }
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
