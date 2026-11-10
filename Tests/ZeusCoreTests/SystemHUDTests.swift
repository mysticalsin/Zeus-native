import Foundation
import Testing
@testable import ZeusCore

@Suite struct SystemHUDTests {
    @Test func segmentIndexMapsSixteenSteps() {
        #expect(SystemHUDMath.segmentIndex(for: 0) == 0)
        #expect(SystemHUDMath.segmentIndex(for: 1) == 15)
        #expect(SystemHUDMath.filledSegmentCount(for: 0.5) == 9)
    }

    @Test func deltaThresholdIgnoresNoise() {
        #expect(!SystemHUDMath.shouldReport(previous: 0.5, next: 0.502))
        #expect(SystemHUDMath.shouldReport(previous: 0.5, next: 0.51))
    }

    @Test func stepMathUsesSixteenthAndSixtyFourth() {
        #expect(abs(SystemHUDMath.stepDelta(fine: false) - 1.0 / 16.0) < 0.0001)
        #expect(abs(SystemHUDMath.stepDelta(fine: true) - 1.0 / 64.0) < 0.0001)
        #expect(abs(SystemHUDMath.steppedValue(0.5, direction: 1, fine: false) - 0.5625) < 0.0001)
    }

    @Test func coalesceTimesMergeBursts() {
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        let merged = SystemHUDMath.coalesceTimes([t0, t0.addingTimeInterval(0.005), t0.addingTimeInterval(0.01), t0.addingTimeInterval(0.2)])
        #expect(merged.count == 2)
    }

    @Test func coalescerSkipsTinyVolumeJitter() {
        var gate = SystemHUDCoalescer()
        let initial = gate.accept(value: 0.4, muted: false)
        let tiny = gate.accept(value: 0.401, muted: false)
        let bigger = gate.accept(value: 0.42, muted: false)
        let muted = gate.accept(value: 0.42, muted: true)
        #expect(initial)
        #expect(!tiny)
        #expect(bigger)
        #expect(muted)
    }

    // H1: reading the current hardware level at launch (or when a monitor starts) must never
    // itself trigger a HUD -- only a real change after that should.
    @Test func firstSampleNeverPresentsAfterSeeding() {
        var gate = SystemHUDCoalescer()
        gate.seed(value: 0.4, muted: false)
        let sameAsSeed = gate.accept(value: 0.401, muted: false)
        #expect(!sameAsSeed) // same as the seeded reading: no HUD
        let realChange = gate.accept(value: 0.6, muted: false)
        #expect(realChange) // a real change: HUD fires
    }

    // H4/H5/H6: the media-key -> action table, independent of CGEvent/AppKit.
    @Test func mediaKeyActionTable() {
        #expect(SystemHUDKeys.action(for: 0) == .volumeUp(fine: false))
        #expect(SystemHUDKeys.action(for: 1) == .volumeDown(fine: false))
        #expect(SystemHUDKeys.action(for: 7) == .toggleMute) // H4: was a no-op
        #expect(SystemHUDKeys.action(for: 2) == .brightnessUp(fine: false)) // H5: was mapped to down
        #expect(SystemHUDKeys.action(for: 3) == .brightnessDown(fine: false))
        #expect(SystemHUDKeys.action(for: 21) == .illuminationUp(fine: false)) // H6: real code
        #expect(SystemHUDKeys.action(for: 22) == .illuminationDown(fine: false)) // H6: real code
        #expect(SystemHUDKeys.action(for: 23) == .illuminationToggle)
        // H6: Caps Lock (4) and Help (5) are never ours -- always pass through, never consumed.
        #expect(SystemHUDKeys.action(for: 4) == .passThrough)
        #expect(SystemHUDKeys.action(for: 5) == .passThrough)
        #expect(SystemHUDKeys.action(for: 99) == .passThrough)
    }

    @Test func mediaKeyActionCarriesTheFineFlag() {
        #expect(SystemHUDKeys.action(for: 2, fine: true) == .brightnessUp(fine: true))
    }

    @Test func settingsGateEachEffect() {
        var flags = [String: Bool]()
        flags[SystemHUDSettings.settingID(for: .volume)] = false
        flags[SystemHUDSettings.settingID(for: .brightness)] = true
        #expect(!SystemHUDSettings.isEnabled(.volume) { flags[$0] ?? true })
        #expect(SystemHUDSettings.isEnabled(.brightness) { flags[$0] ?? true })
    }

    @Test func migrationTurnsAllHudOffWhenLegacyVolumeOff() throws {
        let suite = "zeus.hud.migrate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("false", forKey: "opt.\(SystemHUDSettings.legacyVolumeID)")
        SystemHUDMigration.run(defaults: defaults)
        #expect(defaults.string(forKey: "opt.lights.hud.volume") == "false")
        #expect(defaults.string(forKey: "opt.lights.hud.brightness") == "false")
        #expect(defaults.string(forKey: "opt.lights.hud.keyboard") == "false")
        #expect(defaults.string(forKey: "opt.lights.hud.mute") == "false")
    }

    @Test func notchHudLightSegmentsFillToValue() {
        let segments = NotchLightMath.segments(.hudLevel(.volume, value: 0.75, previousLevel: 0.75, muted: false), progress: 0.5, shoulder: 0.4)
        #expect(segments.first?.to ?? 0 > 0.3)
    }

    @Test func degradePathWhenReplaceSystemNeedsAccessibility() {
        #expect(SystemHUDSettings.replaceSystemEnabled { _ in true })
        #expect(!SystemHUDSettings.replaceSystemEnabled { _ in false })
    }
}
