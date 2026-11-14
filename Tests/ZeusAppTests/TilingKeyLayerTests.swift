import Foundation
import Testing
import ZeusCore
@testable import Zeus

// MARK: Fakes

/// A tap that never touches the system. It records every call the layer makes.
@MainActor
private final class FakeTap: TilingKeyTapping {
    let sink: TilingKeyTap.Sink
    let onFailure: TilingKeyTap.Failure
    var startSucceeds: Bool
    private(set) var started = 0
    private(set) var stopped = 0
    private(set) var updates: [(enabled: Bool, paused: Bool, keymap: TileKeymap)] = []

    init(sink: @escaping TilingKeyTap.Sink, onFailure: @escaping TilingKeyTap.Failure, startSucceeds: Bool) {
        self.sink = sink
        self.onFailure = onFailure
        self.startSucceeds = startSucceeds
    }

    func update(keymap: TileKeymap, enabled: Bool, paused: Bool) { updates.append((enabled, paused, keymap)) }
    func start() -> Bool {
        started += 1
        return startSucceeds
    }
    func stop() { stopped += 1 }
}

/// The permission and the tap factory, with the wait that `AccessibilityGate` keeps by key.
@MainActor
private final class Rig {
    var trusted: Bool
    var nextStartSucceeds = true
    private(set) var taps: [FakeTap] = []
    private(set) var waits: [String: () -> Void] = [:]
    private(set) var waitRegistrations = 0
    private(set) var cancels: [String] = []
    private(set) var unavailable = 0
    let layer: TilingKeyLayer

    init(trusted: Bool) {
        self.trusted = trusted
        let holder = Holder()
        layer = TilingKeyLayer(environment: TilingKeyLayer.Environment(
            isTrusted: { holder.rig?.trusted ?? false },
            whenTrusted: { key, work in
                guard let rig = holder.rig else { return }
                rig.waitRegistrations += 1
                if rig.trusted { work() } else { rig.waits[key] = work }
            },
            cancelWaiting: { key in
                holder.rig?.cancels.append(key)
                holder.rig?.waits[key] = nil
            },
            makeTap: { sink, onFailure in
                let tap = FakeTap(sink: sink, onFailure: onFailure, startSucceeds: holder.rig?.nextStartSucceeds ?? true)
                holder.rig?.taps.append(tap)
                return tap
            }))
        holder.rig = self
        layer.onUnavailable = { [weak self] in self?.unavailable += 1 }
    }

    /// Breaks the cycle between the rig and the closures the layer keeps.
    @MainActor private final class Holder { weak var rig: Rig? }

    let keymap = TileKeymap.defaults(base: .standard)

    func apply(enabled: Bool = true, paused: Bool = false) { layer.apply(enabled: enabled, paused: paused, keymap: keymap) }

    /// Accessibility is granted and the poll fires the waiting work.
    func grant() {
        trusted = true
        let pending = waits
        waits = [:]
        for work in pending.values { work() }
    }
}

// MARK: Tests

/// The tap owner's rules: never installed while tiling is off, never without Accessibility, gone the moment either
/// goes, and stopped for good after a failure until tiling is turned off and on again.
@Suite("Tiling key layer", .serialized) @MainActor
struct TilingKeyLayerTests {
    private let key = TilingKeyLayer.gateKey

    @Test func offMeansNoTapAndNoWait() {
        let rig = Rig(trusted: true)
        rig.apply(enabled: false)
        #expect(!rig.layer.isInstalled && rig.taps.isEmpty)
        #expect(rig.waits.isEmpty && rig.waitRegistrations == 0)
        #expect(rig.cancels == [key], "a stale wait for the tap is cancelled")
    }

    @Test func withoutAccessibilityNoTapExistsAndOneWaitIsRegistered() {
        let rig = Rig(trusted: false)
        rig.apply()
        #expect(!rig.layer.isInstalled && rig.taps.isEmpty, "no tap is created before the permission")
        #expect(rig.waits.keys.sorted() == [key])
        rig.apply(paused: true)
        #expect(rig.taps.isEmpty && rig.waits.keys.sorted() == [key], "a second call replaces the wait and still creates nothing")
    }

    @Test func theTapStartsOnceAccessibilityArrivesWithTheKeymapAndThePauseThatWasAskedFor() {
        let rig = Rig(trusted: false)
        rig.apply(paused: true)
        rig.grant()
        #expect(rig.layer.isInstalled && rig.taps.count == 1)
        let tap = rig.taps[0]
        #expect(tap.started == 1)
        #expect(tap.updates.last?.enabled == true && tap.updates.last?.paused == true && tap.updates.last?.keymap == rig.keymap)
        #expect(rig.waits.isEmpty && rig.unavailable == 0)
    }

    @Test func withAccessibilityOnTheTapIsInstalledAtOnceAndLaterCallsOnlyUpdateIt() {
        let rig = Rig(trusted: true)
        rig.apply()
        #expect(rig.layer.isInstalled && rig.taps.count == 1 && rig.taps[0].started == 1)
        rig.apply(paused: true)
        rig.apply(paused: false)
        #expect(rig.taps.count == 1, "one tap for the whole run")
        #expect(rig.taps[0].updates.map(\.paused) == [false, true, false])
        #expect(rig.taps[0].stopped == 0)
    }

    @Test func turningTilingOffRemovesTheTapAndCancelsTheWait() {
        let rig = Rig(trusted: true)
        rig.apply()
        rig.apply(enabled: false)
        #expect(!rig.layer.isInstalled)
        #expect(rig.taps[0].stopped == 1)
        #expect(rig.cancels == [key])
    }

    @Test func aWaitThatFiresAfterTilingWasTurnedOffInstallsNothing() {
        let rig = Rig(trusted: false)
        rig.apply()
        let stale = rig.waits[key]
        rig.apply(enabled: false)
        rig.trusted = true
        stale?()
        #expect(!rig.layer.isInstalled && rig.taps.isEmpty)
    }

    @Test func revokedAccessibilityRemovesTheTapAndWaitsForItAgain() {
        let rig = Rig(trusted: true)
        rig.apply()
        rig.trusted = false
        rig.apply()
        #expect(!rig.layer.isInstalled, "no tap stays installed without the permission")
        #expect(rig.taps[0].stopped == 1)
        #expect(rig.waits.keys.sorted() == [key])
        rig.grant()
        #expect(rig.layer.isInstalled && rig.taps.count == 2 && rig.taps[1].started == 1, "a fresh tap once it is back")
    }

    @Test func aTapThatCannotStartReportsOnceAndStaysOffUntilTilingIsToggled() {
        let rig = Rig(trusted: true)
        rig.nextStartSucceeds = false
        rig.apply()
        #expect(!rig.layer.isInstalled)
        #expect(rig.unavailable == 1)
        rig.nextStartSucceeds = true
        rig.apply()
        rig.apply(paused: true)
        #expect(rig.taps.count == 1 && rig.unavailable == 1, "no retry and no second report")
        rig.apply(enabled: false)
        rig.apply()
        #expect(rig.layer.isInstalled && rig.taps.count == 2, "turning tiling off and on again tries once more")
        #expect(rig.unavailable == 1)
    }

    @Test func aTapTheSystemKeepsDisablingIsRemovedAndReportedOnce() {
        let rig = Rig(trusted: true)
        rig.apply()
        let tap = rig.taps[0]
        tap.onFailure()
        #expect(!rig.layer.isInstalled)
        #expect(tap.stopped == 1)
        #expect(rig.unavailable == 1)
        rig.apply()
        #expect(!rig.layer.isInstalled && rig.taps.count == 1, "it stays off")
        tap.onFailure()
        #expect(rig.unavailable == 1, "a late failure from the removed tap reports nothing")
    }

    @Test func stopRemovesTheTapAndCancelsTheWaitWhateverTheState() {
        let installed = Rig(trusted: true)
        installed.apply()
        installed.layer.stop()
        #expect(!installed.layer.isInstalled && installed.taps[0].stopped == 1 && installed.cancels == [key])

        let waiting = Rig(trusted: false)
        waiting.apply()
        waiting.layer.stop()
        #expect(waiting.waits.isEmpty)
        waiting.grant()
        #expect(waiting.taps.isEmpty && !waiting.layer.isInstalled)
    }

    @Test func aChordTheTapMatchedReachesTheOwnerOnTheMainActor() {
        let rig = Rig(trusted: true)
        var got: [TileAction] = []
        rig.layer.onAction = { got.append($0) }
        rig.apply()
        rig.taps[0].sink(.retile)
        #expect(got == [.retile])
    }
}
