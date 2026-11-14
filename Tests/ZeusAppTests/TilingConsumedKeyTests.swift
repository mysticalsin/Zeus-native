import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The tiling tap consumes a bound chord before the other monitors' event streams see it. Each monitor is told about
/// the consumed key instead, so a smaller modifier-only hold the chord was made on stays spoiled until every modifier
/// is up. Here the real monitors take the forwarded events through the same notification the tap posts.
@Suite("Tiling consumed keys reach the monitors", .serialized) @MainActor
struct TilingConsumedKeyTests {
    private let all: ShortcutModifiers = [.control, .option, .command]
    private let leftArrow: UInt16 = 123

    private func tell(_ event: ShortcutEvent) { TilingConsumedKey.post(event) }

    @Test func theNotificationCarriesTheEventAndNothingElse() {
        let note = Notification(name: TilingConsumedKey.notification, object: nil,
                                userInfo: ["event": ShortcutEvent.keyDown(keyCode: 123, modifiers: [.control])])
        #expect(TilingConsumedKey.event(in: note) == .keyDown(keyCode: 123, modifiers: [.control]))
        #expect(TilingConsumedKey.event(in: Notification(name: TilingConsumedKey.notification)) == nil)
    }

    // MARK: Talk and dictation

    private final class Presses { var count = 0; var cancels = 0 }

    private func talkMonitor(key: Shortcut = .controlOption) -> (HotkeyMonitor, Presses) {
        let monitor = HotkeyMonitor()
        let presses = Presses()
        monitor.keyProvider = { key }
        monitor.onPress = { presses.count += 1 }
        monitor.observeConsumedKeys()
        return (monitor, presses)
    }

    /// Command, Control and Option down, Left consumed, Command released first.
    private func chordThenReleaseCommandFirst(_ monitor: HotkeyMonitor, keys: [ShortcutModifiers] = [[.command], [.command, .control]]) {
        monitor.feed(.flags(keyCode: 55, modifiers: [.command]))
        monitor.feed(.flags(keyCode: 59, modifiers: [.command, .control]))
        monitor.feed(.flags(keyCode: 58, modifiers: all))
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
    }

    @Test func aTalkHoldDoesNotStartWhenCommandIsReleasedFirstAfterAConsumedChord() {
        let (monitor, presses) = talkMonitor()
        chordThenReleaseCommandFirst(monitor)
        #expect(presses.count == 0, "the smaller pair must not open the microphone")
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 59, modifiers: []))
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        #expect(presses.count == 1, "a plain hold afterwards works again")
    }

    @Test func aDictationKeyOnRightCommandDoesNotStartWhenTheOthersAreReleasedFirst() {
        let (monitor, presses) = talkMonitor(key: .rightCommand)
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 54, modifiers: all))
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .command]))
        monitor.feed(.flags(keyCode: 59, modifiers: [.command]))
        #expect(presses.count == 0)
    }

    // MARK: Pointing

    @Test func aPointingHoldDoesNotBeginWhenCommandIsReleasedFirstAfterAConsumedChord() {
        let monitor = PointingHotkeyMonitor()
        var signals: [PointingHotkeyMonitor.Signal] = []
        monitor.shortcutProvider = { .controlOption }
        monitor.voiceOverProvider = { false }
        monitor.startsTurnsProvider = { true }
        monitor.onSignal = { signals.append($0) }
        monitor.observeConsumedKeys()
        defer { monitor.stop() }
        monitor.feed(.flags(keyCode: 55, modifiers: [.command]), at: 0)
        monitor.feed(.flags(keyCode: 59, modifiers: [.command, .control]), at: 0.1)
        monitor.feed(.flags(keyCode: 58, modifiers: all), at: 0.2)
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]), at: 0.4)
        #expect(!signals.contains(.began), "\(signals)")
    }
}
