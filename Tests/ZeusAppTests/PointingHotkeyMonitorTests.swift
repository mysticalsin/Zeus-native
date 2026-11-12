import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Production monitor, synthetic keyboard events. No event tap, no permission, no real keys.
@MainActor
@Suite("Pointing hotkey monitor", .serialized)
struct PointingHotkeyMonitorTests {
    private final class Log { var signals: [PointingHotkeyMonitor.Signal] = [] }

    private func monitor(voiceOver: Bool = false, shortcut: Shortcut = .controlOption,
                         startsTurns: Bool = true) -> (PointingHotkeyMonitor, Log) {
        let monitor = PointingHotkeyMonitor()
        let log = Log()
        monitor.shortcutProvider = { shortcut }
        monitor.startsTurnsProvider = { startsTurns }
        monitor.voiceOverProvider = { voiceOver }
        monitor.onSignal = { log.signals.append($0) }
        return (monitor, log)
    }

    private func press(_ monitor: PointingHotkeyMonitor, at time: Double = 0) {
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]), at: time)
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: time + 0.01)
    }

    @Test func controlOptionBeginsAndReleaseEnds() {
        let (monitor, log) = monitor()
        press(monitor)
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]), at: 1)
        monitor.feed(.flags(keyCode: 59, modifiers: []), at: 1.1)
        #expect(log.signals == [.began, .ended])
    }

    @Test func anotherKeyJoiningCancelsAndNeverEnds() {
        let (monitor, log) = monitor()
        press(monitor)
        monitor.feed(.keyDown(keyCode: 49, modifiers: [.control, .option]), at: 0.5)
        monitor.feed(.keyUp(keyCode: 49), at: 0.6)
        monitor.feed(.flags(keyCode: 58, modifiers: []), at: 0.7)
        // Listening starts the moment the exact hold forms (owner spec), so a spoil cancels a begun turn.
        #expect(log.signals == [.began, .cancelled])
    }

    @Test func voiceOverBlocksControlOptionWithOneVisibleMessage() {
        let (monitor, log) = monitor(voiceOver: true)
        press(monitor)
        press(monitor, at: 2)
        #expect(log.signals.count == 1)
        guard case .blocked(let message)? = log.signals.first else { Issue.record("expected a block"); return }
        #expect(message.contains("VoiceOver") && !message.contains("—"))
    }

    /// Control+Option is the talk key too: the talk turn owns the hold, so pointing starts nothing,
    /// shows no VoiceOver notice, and Esc still passes through.
    @Test func theTalkKeyHoldStartsNoPointingTurn() {
        let (monitor, log) = monitor(startsTurns: false)
        press(monitor)
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]), at: 1)
        monitor.feed(.flags(keyCode: 59, modifiers: []), at: 1.1)
        #expect(log.signals.isEmpty)
        monitor.feed(.keyDown(keyCode: 53, modifiers: []), at: 2)
        #expect(log.signals == [.escape])
        let (blocked, blockedLog) = self.monitor(voiceOver: true, startsTurns: false)
        press(blocked)
        #expect(blockedLog.signals.isEmpty)
    }

    @Test func aConfiguredShortcutIsHonoured() {
        let (monitor, log) = monitor(shortcut: .rightOption)
        monitor.feed(.flags(keyCode: 61, modifiers: [.option]), at: 0)
        monitor.feed(.flags(keyCode: 61, modifiers: []), at: 1)
        #expect(log.signals == [.began, .ended])
    }

    @Test func escapeOutsideAHoldIsReported() {
        let (monitor, log) = monitor()
        monitor.feed(.keyDown(keyCode: 53, modifiers: []), at: 0)
        #expect(log.signals == [.escape])
    }
}
