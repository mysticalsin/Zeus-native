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

    // MARK: Talk and dictation on one key

    private final class Dictation { var starts = 0; var ends = 0; var cancels = 0 }

    /// The talk key and the dictation key are one key (the shared gesture): dictation starts on a hold.
    private func sharedDictationMonitor(key: Shortcut = .controlOption) -> (HotkeyMonitor, Dictation) {
        let monitor = HotkeyMonitor()
        let seen = Dictation()
        monitor.role = .dictation
        monitor.keyProvider = { key }
        monitor.sharedProvider = { true }
        monitor.onPress = { seen.starts += 1 }
        monitor.onRelease = { seen.ends += 1 }
        monitor.onCancel = { seen.cancels += 1 }
        monitor.observeConsumedKeys()
        return (monitor, seen)
    }

    private func hold(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }

    /// The default tiling pair holds Command as well. The owner presses Command first, then Control and Option, and keeps
    /// them down past the hold delay before the first arrow. The hold is for exactly Control-Option, so it must not begin.
    @Test func aSharedHoldOfAPairInsideTheTilingPairDoesNotStartDictationWhenCommandComesFirst() async throws {
        let (monitor, seen) = sharedDictationMonitor()
        monitor.feed(.flags(keyCode: 55, modifiers: [.command]))
        monitor.feed(.flags(keyCode: 59, modifiers: [.command, .control]))
        monitor.feed(.flags(keyCode: 58, modifiers: all))
        try await hold(0.45)
        #expect(seen.starts == 0, "the microphone must stay closed while the larger pair is held")
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        try await hold(0.45)
        #expect(seen.starts == 0 && seen.cancels == 0, "nothing started, so nothing is cancelled")
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
        try await hold(0.45)
        #expect(seen.starts == 0, "letting go of Command first must not form the smaller hold after a consumed chord")
    }

    @Test func aSharedHoldOfExactlyItsOwnKeyStillStartsDictationAndExtraModifiersDoNotEndIt() async throws {
        let (monitor, seen) = sharedDictationMonitor()
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        try await hold(0.45)
        #expect(seen.starts == 1, "a plain hold begins dictation")
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]))
        #expect(seen.ends == 0, "Shift joining a running dictation means Return, it does not end the hold")
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        #expect(seen.ends == 1, "letting go of the key ends it")
    }

    // MARK: The natural press order: the smaller pair first, then the rest of the tiling pair

    private final class Turns { var starts = 0; var releases = 0; var cancels = 0 }

    /// A hold-style monitor on `key` that counts how its turn ends: a release sends the question, a cancel does not.
    private func turnMonitor(key: Shortcut = .controlOption, role: HotkeyMonitor.Role = .talk) -> (HotkeyMonitor, Turns) {
        let monitor = HotkeyMonitor()
        let turns = Turns()
        monitor.role = role
        monitor.keyProvider = { key }
        monitor.sharedProvider = { false }
        monitor.onPress = { turns.starts += 1 }
        monitor.onRelease = { turns.releases += 1 }
        monitor.onCancel = { turns.cancels += 1 }
        monitor.cancelsWhenSpoiled = role == .talk
        monitor.observeConsumedKeys()
        return (monitor, turns)
    }

    /// Control, then Option, then Command, then the consumed Left arrow and its release, then everything let go.
    private func controlOptionCommandThenArrow(_ monitor: HotkeyMonitor) {
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 59, modifiers: []))
    }

    @Test func aTalkTurnThatTheRestOfTheTilingPairEndsIsCancelledNotSent() async throws {
        let (monitor, turns) = turnMonitor()
        controlOptionCommandThenArrow(monitor)
        try await hold(0.6) // a quick tap would wait for a second tap before it stops
        #expect(turns.releases == 0, "a tiling chord must never send a talk turn: \(turns.releases) sent")
        #expect(turns.cancels == turns.starts, "every turn it opened is cancelled: started \(turns.starts), cancelled \(turns.cancels)")
    }

    @Test func aSlowPressOfTheSameOrderIsCancelledToo() async throws {
        let (monitor, turns) = turnMonitor()
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        try await hold(0.5)
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 58, modifiers: []))
        #expect(turns.releases == 0 && turns.cancels == turns.starts, "\(turns.starts) \(turns.releases) \(turns.cancels)")
    }

    @Test func aDedicatedDictationHoldThatTheRestOfThePairEndsIsCancelledNotInserted() async throws {
        let (monitor, turns) = turnMonitor(role: .dictation)
        controlOptionCommandThenArrow(monitor)
        try await hold(0.6)
        #expect(turns.releases == 0, "\(turns.releases) dictation turns finished")
        #expect(turns.cancels == turns.starts)
    }

    @Test func aSingleModifierHoldThatAnotherModifierEndsIsCancelledToo() {
        let (monitor, turns) = turnMonitor(key: .rightCommand, role: .dictation)
        monitor.feed(.flags(keyCode: 54, modifiers: [.command]))
        monitor.feed(.flags(keyCode: 59, modifiers: [.command, .control]))
        monitor.feed(.flags(keyCode: 58, modifiers: all))
        #expect(turns.starts == 1 && turns.cancels == 1 && turns.releases == 0, "\(turns.starts) \(turns.releases) \(turns.cancels)")
    }

    /// Shift joining a hold is how the owner asks for Return after dictation, so it ends the hold as before.
    /// Pressed as a plain modifier chord with no key, then Command let go first: the smaller pair is held again, but the
    /// turn was cancelled, so it stays cancelled until every modifier is up, as the pointing hold does.
    @Test func aCancelledHoldDoesNotRestartWhenTheExtraModifierIsLetGo() {
        let (monitor, turns) = turnMonitor()
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
        #expect(turns.starts == 1 && turns.cancels == 1 && turns.releases == 0, "no second turn: \(turns.starts) \(turns.cancels)")
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 59, modifiers: []))
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        #expect(turns.starts == 2, "a fresh hold works again")
    }

    @Test func shiftJoiningAHoldStillEndsItTheNormalWay() async throws {
        let (monitor, turns) = turnMonitor(role: .dictation)
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 56, modifiers: [.control, .option, .shift]))
        try await hold(0.55) // a quick tap waits for a possible second tap before it ends
        #expect(turns.starts == 1 && turns.releases == 1 && turns.cancels == 0, "\(turns.starts) \(turns.releases) \(turns.cancels)")
    }

    @Test func aPlainHoldAndReleaseStillSendsTheTurn() async throws {
        let (monitor, turns) = turnMonitor()
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 59, modifiers: []))
        try await hold(0.55)
        #expect(turns.starts == 1 && turns.releases == 1 && turns.cancels == 0)
    }

    @Test func aSharedHoldInTheSameOrderStartsNothingWhenTheRestOfThePairArrivesInTime() async throws {
        let (monitor, seen) = sharedDictationMonitor()
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]))
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]))
        monitor.feed(.flags(keyCode: 55, modifiers: all))
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        try await hold(0.5)
        #expect(seen.starts == 0 && seen.ends == 0, "the hold timer never fires: \(seen.starts) \(seen.ends)")
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]))
        try await hold(0.45)
        #expect(seen.starts == 0, "and letting go of Command does not form the smaller hold after a consumed chord")
    }

    /// The tap hands its consumed keys over through the main queue while the modifier changes reach the monitors from
    /// the window server, so the owner letting go of Command can be heard before the forwarded key. The outcome stays
    /// bounded: a smaller hold that forms in that gap is cancelled the moment the key arrives, and nothing is sent.
    @Test func aModifierChangeHeardBeforeTheForwardedKeyOnlyCostsACancelledTurn() {
        let (monitor, turns) = turnMonitor()
        monitor.feed(.flags(keyCode: 55, modifiers: [.command]))
        monitor.feed(.flags(keyCode: 59, modifiers: [.command, .control]))
        monitor.feed(.flags(keyCode: 58, modifiers: all))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option])) // heard first
        tell(.keyDown(keyCode: leftArrow, modifiers: all)) // the forwarded key arrives late
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 58, modifiers: []))
        #expect(turns.releases == 0, "nothing is sent")
        #expect(turns.cancels == turns.starts, "\(turns.starts) \(turns.cancels)")
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

    @Test func aPointingHoldThatTheRestOfTheTilingPairEndsIsCancelledNotEnded() {
        let monitor = PointingHotkeyMonitor()
        var signals: [PointingHotkeyMonitor.Signal] = []
        monitor.shortcutProvider = { .controlOption }
        monitor.voiceOverProvider = { false }
        monitor.startsTurnsProvider = { true }
        monitor.onSignal = { signals.append($0) }
        monitor.observeConsumedKeys()
        defer { monitor.stop() }
        monitor.feed(.flags(keyCode: 59, modifiers: [.control]), at: 0)
        monitor.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 0.1)
        monitor.feed(.flags(keyCode: 55, modifiers: all), at: 0.2)
        tell(.keyDown(keyCode: leftArrow, modifiers: all))
        tell(.keyUp(keyCode: leftArrow))
        monitor.feed(.flags(keyCode: 55, modifiers: [.control, .option]), at: 0.4)
        monitor.feed(.flags(keyCode: 58, modifiers: []), at: 0.5)
        #expect(!signals.contains(.ended), "\(signals)")
        #expect(signals.filter { $0 == .began }.count == signals.filter { $0 == .cancelled }.count, "\(signals)")
    }
}
