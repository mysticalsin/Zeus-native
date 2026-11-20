import Foundation
import Testing
@testable import ZeusCore

@Suite struct SensorySettingsTests {
    @Test func existingOverlayKeysStayTheOnesAlreadyStored() {
        #expect(SensorySettings.volumeKey == "lights.hud.volume")
        #expect(SensorySettings.volumeKey == SystemHUDSettings.settingID(for: .volume))
        #expect(SensorySettings.brightnessKey == "lights.hud.brightness")
        #expect(SensorySettings.brightnessKey == SystemHUDSettings.settingID(for: .brightness))
        #expect(SensorySettings.replaceSystemKey == "lights.hud.replaceSystem")
        #expect(SensorySettings.replaceSystemKey == SystemHUDSettings.replaceSystemID)
        #expect(SensorySettings.holdKey == "lights.hud.hold")
        #expect(SensorySettings.labelKey == "lights.hud.label")
    }

    @Test func missingValuesUseTheCatalogDefaults() {
        let settings = SensorySettings.read { _ in nil }
        #expect(settings.volume)
        #expect(settings.brightness)
        #expect(settings.replaceSystem)
        #expect(settings.hold == 1.2)
        #expect(settings.label == .icon)
    }

    @Test func storedValuesRoundTrip() {
        let original = SensorySettings(volume: false, brightness: true, replaceSystem: false, hold: 2.5, label: .words)
        var stored: [String: String] = [:]
        original.write { stored[$0] = $1 }
        let read = SensorySettings.read { stored[$0] }
        #expect(read == original)
        #expect(stored[SensorySettings.volumeKey] == "false")
        #expect(stored[SensorySettings.brightnessKey] == "true")
        #expect(stored[SensorySettings.replaceSystemKey] == "false")
        #expect(stored[SensorySettings.holdKey] == "2.5")
        #expect(stored[SensorySettings.labelKey] == "words")
    }

    @Test func anUnknownToggleTokenIsOffAndABlankTokenKeepsTheDefault() {
        #expect(SensorySettings.read { $0 == SensorySettings.volumeKey ? "yes" : nil }.volume == false)
        #expect(SensorySettings.read { $0 == SensorySettings.volumeKey ? "  " : nil }.volume)
        #expect(SensorySettings.read { $0 == SensorySettings.volumeKey ? "FALSE" : nil }.volume == false)
        #expect(SensorySettings.read { $0 == SensorySettings.replaceSystemKey ? "TRUE" : nil }.replaceSystem)
    }

    @Test func labelFallsBackToIcon() {
        #expect(SensoryHUDLabel.parse(nil) == .icon)
        #expect(SensoryHUDLabel.parse("  ") == .icon)
        #expect(SensoryHUDLabel.parse("ICON") == .icon)
        #expect(SensoryHUDLabel.parse("words") == .words)
        #expect(SensoryHUDLabel.parse("text") == .icon)
        let settings = SensorySettings.read { $0 == SensorySettings.labelKey ? "nope" : nil }
        #expect(settings.label == .icon)
    }

    @Test func replaceSystemFailsClosedWithoutTrust() {
        #expect(SensoryReplace.decision(enabled: false, accessibilityTrusted: true) == .leaveSystemOverlay)
        #expect(SensoryReplace.decision(enabled: false, accessibilityTrusted: false) == .leaveSystemOverlay)
        #expect(SensoryReplace.decision(enabled: true, accessibilityTrusted: true) == .replaceSystemOverlay)
        #expect(SensoryReplace.decision(enabled: true, accessibilityTrusted: false) == .blockedUntilTrusted)
    }

    @Test func onlyVolumeAndBrightnessAreAccepted() {
        let both = SensorySettings()
        #expect(SensoryHUDLifecycle.accepts(.volume, both))
        #expect(SensoryHUDLifecycle.accepts(.brightness, both))
        #expect(!SensoryHUDLifecycle.accepts(.keyboardBacklight, both))
        let volumeOnly = SensorySettings(volume: true, brightness: false)
        #expect(SensoryHUDLifecycle.accepts(.volume, volumeOnly))
        #expect(!SensoryHUDLifecycle.accepts(.brightness, volumeOnly))
    }
}

@Suite struct SensoryHUDHoldTests {
    @Test func boundsMatchTheSpec() {
        #expect(SensoryHUDHold.minimum == 0.4)
        #expect(SensoryHUDHold.maximum == 6)
        #expect(SensoryHUDHold.defaultHold == 1.2)
        #expect(SensoryHUDHold.step == 0.1)
        #expect(SensoryHUDTiming.fadeIn == 0.12)
        #expect(SensoryHUDTiming.fadeOut == 0.25)
    }

    @Test func finiteValuesClampAndNonFiniteValuesUseTheDefault() {
        #expect(SensoryHUDHold.clamp(0.4) == 0.4)
        #expect(SensoryHUDHold.clamp(6) == 6)
        #expect(SensoryHUDHold.clamp(1.2) == 1.2)
        #expect(SensoryHUDHold.clamp(1.25) == 1.25)
        #expect(SensoryHUDHold.clamp(0.39) == 0.4)
        #expect(SensoryHUDHold.clamp(0) == 0.4)
        #expect(SensoryHUDHold.clamp(-4) == 0.4)
        #expect(SensoryHUDHold.clamp(6.01) == 6)
        #expect(SensoryHUDHold.clamp(100) == 6)
        #expect(SensoryHUDHold.clamp(.nan) == 1.2)
        #expect(SensoryHUDHold.clamp(.infinity) == 1.2)
        #expect(SensoryHUDHold.clamp(-.infinity) == 1.2)
    }

    @Test func parsingUsesTheSameBounds() {
        #expect(SensoryHUDHold.parse(nil) == 1.2)
        #expect(SensoryHUDHold.parse("  ") == 1.2)
        #expect(SensoryHUDHold.parse("nope") == 1.2)
        #expect(SensoryHUDHold.parse("1.25") == 1.25)
        #expect(SensoryHUDHold.parse("0.2") == 0.4)
        #expect(SensoryHUDHold.parse("9") == 6)
        #expect(SensoryHUDHold.store(1.2) == "1.2")
        #expect(SensoryHUDHold.store(0.4) == "0.4")
        #expect(SensoryHUDHold.store(6) == "6")
        #expect(SensoryHUDHold.store(1.25) == "1.25")
        #expect(SensoryHUDHold.store(.nan) == "1.2")
        #expect(SensoryHUDHold.store(9) == "6")
        #expect(SensoryHUDHold.store(0) == "0.4")
        #expect(SensoryHUDHold.parse(SensoryHUDHold.store(1.2)) == 1.2)
        #expect(SensoryHUDHold.parse(SensoryHUDHold.store(1.25)) == 1.25)
    }

    @Test func theStepperStaysInsideTheBoundsAndOnTheGrid() {
        #expect(SensoryHUDHold.step(1.25, direction: 1) == 1.4)
        #expect(SensoryHUDHold.step(1.25, direction: -1) == 1.2)
        #expect(SensoryHUDHold.step(1.25, direction: 0) == 1.3)
        #expect(SensoryHUDHold.step(0.4, direction: -1) == 0.4)
        #expect(SensoryHUDHold.step(6, direction: 1) == 6)
        #expect(SensoryHUDHold.step(1.2, direction: 0) == 1.2)
        var value = SensoryHUDHold.minimum
        for _ in 0..<80 {
            let next = SensoryHUDHold.step(value, direction: 1)
            #expect(next <= SensoryHUDHold.maximum)
            #expect(next >= value)
            value = next
        }
        #expect(value == SensoryHUDHold.maximum)
        value = SensoryHUDHold.maximum
        for _ in 0..<80 {
            value = SensoryHUDHold.step(value, direction: -1)
            #expect(value >= SensoryHUDHold.minimum)
        }
        #expect(value == SensoryHUDHold.minimum)
    }

    @Test func everyFiniteSampleClampsIntoTheClosedInterval() {
        var generator = SensoryRNG(state: 0x5E45_0001)
        let specials = [Double.nan, .infinity, -.infinity, -10, 0, 0.4, 0.4000000001, 1.2, 1.25, 6, 6.0000000001, 40]
        for value in specials {
            let clamped = SensoryHUDHold.clamp(value)
            #expect(clamped.isFinite)
            #expect(clamped >= SensoryHUDHold.minimum)
            #expect(clamped <= SensoryHUDHold.maximum)
            if value.isFinite, value >= SensoryHUDHold.minimum, value <= SensoryHUDHold.maximum {
                #expect(clamped == value)
            }
        }
        for _ in 0..<400 {
            let sample = generator.unit() * 20 - 4
            let clamped = SensoryHUDHold.clamp(sample)
            #expect(clamped >= SensoryHUDHold.minimum && clamped <= SensoryHUDHold.maximum)
            if sample >= SensoryHUDHold.minimum, sample <= SensoryHUDHold.maximum {
                #expect(clamped == sample)
            }
            let stepped = SensoryHUDHold.step(sample, direction: generator.bool() ? 1 : -1)
            #expect(stepped >= SensoryHUDHold.minimum && stepped <= SensoryHUDHold.maximum)
            let tenths = (stepped * 10).rounded()
            #expect(abs(stepped * 10 - tenths) < 0.000_001)
        }
    }
}

@Suite struct SensorySectionPresentationTests {
    @Test func everyControlHasAHelperAVoiceOverLabelAndAKeyboardPath() {
        let rows = SensoryControls.rows(SensorySettings(), trusted: true)
        #expect(rows.map(\.id) == [
            SensorySettings.volumeKey,
            SensorySettings.brightnessKey,
            SensorySettings.replaceSystemKey,
            SensorySettings.holdKey,
            SensorySettings.labelKey,
            SensoryControls.previewID,
        ])
        var seen: Set<String> = []
        for row in rows {
            #expect(seen.insert(row.id).inserted)
            #expect(!row.title.isEmpty)
            #expect(!row.helper.isEmpty)
            #expect(row.accessibilityLabel.contains(row.title))
            #expect(!row.accessibilityValue.isEmpty)
            #expect(row.keyboardReachable)
        }
    }

    @Test func theHoldHelperNamesTheTestedBounds() {
        let rows = SensoryControls.rows(SensorySettings(hold: 1.2), trusted: true)
        let hold = rows.first { $0.id == SensorySettings.holdKey }
        #expect(hold?.helper.contains("0.4") == true)
        #expect(hold?.helper.contains("6") == true)
        #expect(hold?.accessibilityValue == "1.2 seconds")
        let label = rows.first { $0.id == SensorySettings.labelKey }
        #expect(label?.accessibilityValue == "Icon")
        let words = SensoryControls.rows(SensorySettings(label: .words), trusted: true)
        #expect(words.first { $0.id == SensorySettings.labelKey }?.accessibilityValue == "Words")
    }

    @Test func replaceSystemExplainsAMissingPermission() {
        let blocked = SensoryControls.rows(SensorySettings(replaceSystem: true), trusted: false)
        let row = blocked.first { $0.id == SensorySettings.replaceSystemKey }
        #expect(row?.helper.contains("Accessibility") == true)
        #expect(row?.accessibilityValue.contains("Accessibility") == true)
        let trusted = SensoryControls.rows(SensorySettings(replaceSystem: true), trusted: true)
        let open = trusted.first { $0.id == SensorySettings.replaceSystemKey }
        #expect(open?.accessibilityValue == "On")
        #expect(open?.helper.contains("Accessibility") == true)
        let off = SensoryControls.rows(SensorySettings(replaceSystem: false), trusted: false)
        #expect(off.first { $0.id == SensorySettings.replaceSystemKey }?.accessibilityValue == "Off")
    }

    @Test func metricsMatchTheGlassSection() {
        #expect(SensoryLayout.rowHeight == 52)
        #expect(SensoryLayout.panelPadding == 32)
        #expect(SensoryLayout.cardSpacing == 28)
        #expect(SensoryLayout.animationDuration(reduceMotion: true) == 0)
        #expect(SensoryLayout.animationDuration(reduceMotion: false) == 0.22)
    }

    @Test func previewShowsLoadingEmptyAndThePermissionError() {
        let now = Date(timeIntervalSinceReferenceDate: 20)
        let idle = SensoryHUDSnapshot.hidden
        let loading = SensoryPreview.frame(settings: SensorySettings(), trusted: true, reading: true, snapshot: idle, now: now, reduceMotion: false)
        #expect(loading.status == .loading)
        #expect(loading.title == "Reading the current level")
        #expect(loading.error == nil)

        let empty = SensoryPreview.frame(
            settings: SensorySettings(volume: false, brightness: false),
            trusted: true, reading: false, snapshot: idle, now: now, reduceMotion: false)
        #expect(empty.status == .empty)
        #expect(!empty.detail.isEmpty)

        let blocked = SensoryPreview.frame(
            settings: SensorySettings(replaceSystem: true),
            trusted: false, reading: false, snapshot: idle, now: now, reduceMotion: true)
        #expect(blocked.status == .live)
        #expect(blocked.error?.contains("Accessibility") == true)
        #expect(blocked.hudPhase == .hidden)

        let both = SensoryPreview.frame(
            settings: SensorySettings(volume: false, brightness: false, replaceSystem: true),
            trusted: false, reading: true, snapshot: idle, now: now, reduceMotion: false)
        #expect(both.status == .empty)
        #expect(both.error?.contains("Accessibility") == true)
    }

    @Test func captionsUseAnIconOrWordsAndAlwaysSpeakTheLevel() {
        let icon = SensoryHUDCaptioning.caption(kind: .volume, level: 0.42, muted: false, style: .icon)
        #expect(icon.symbol == "speaker.wave.2.fill")
        #expect(icon.words == nil)
        #expect(icon.accessibilityLabel == "Volume 42 percent")

        let words = SensoryHUDCaptioning.caption(kind: .volume, level: 0.42, muted: false, style: .words)
        #expect(words.symbol == nil)
        #expect(words.words == "Volume 42%")
        #expect(words.accessibilityLabel == "Volume 42 percent")

        let muted = SensoryHUDCaptioning.caption(kind: .volume, level: 0.8, muted: true, style: .icon)
        #expect(muted.symbol == "speaker.slash.fill")
        #expect(muted.accessibilityLabel == "Muted")
        let mutedWords = SensoryHUDCaptioning.caption(kind: .volume, level: 0.8, muted: true, style: .words)
        #expect(mutedWords.words == "Muted")

        #expect(SensoryHUDCaptioning.caption(kind: .volume, level: 0, muted: false, style: .icon).symbol == "speaker.slash.fill")
        #expect(SensoryHUDCaptioning.caption(kind: .volume, level: 0.2, muted: false, style: .icon).symbol == "speaker.wave.1.fill")
        #expect(SensoryHUDCaptioning.caption(kind: .volume, level: 0.9, muted: false, style: .icon).symbol == "speaker.wave.3.fill")
        #expect(SensoryHUDCaptioning.caption(kind: .brightness, level: 0.2, muted: false, style: .icon).symbol == "sun.min.fill")
        #expect(SensoryHUDCaptioning.caption(kind: .brightness, level: 0.5, muted: false, style: .icon).symbol == "sun.max.fill")
        let brightness = SensoryHUDCaptioning.caption(kind: .brightness, level: 1, muted: false, style: .words)
        #expect(brightness.words == "Brightness 100%")
        #expect(brightness.accessibilityLabel == "Brightness 100 percent")
        #expect(SensoryHUDCaptioning.caption(kind: .volume, level: 0.005, muted: false, style: .words).words == "Volume 1%")
        #expect(SensoryHUDCaptioning.caption(kind: .volume, level: 1.4, muted: false, style: .words).accessibilityLabel == "Volume 100 percent")
        #expect(SensoryHUDCaptioning.caption(kind: .keyboardBacklight, level: 0.5, muted: false, style: .words).words == nil)
    }

    @Test func aSampleChangeUsesTheFirstEnabledKind() {
        let at = Date(timeIntervalSinceReferenceDate: 5)
        #expect(SensoryHUDLifecycle.sampleChange(settings: SensorySettings(), at: at) == .changed(.volume, level: 0.6, muted: false, at: at))
        #expect(SensoryHUDLifecycle.sampleChange(settings: SensorySettings(volume: false), at: at) == .changed(.brightness, level: 0.6, muted: false, at: at))
        #expect(SensoryHUDLifecycle.sampleChange(settings: SensorySettings(volume: false, brightness: false), at: at) == nil)
    }
}

/// A fixed generator so the property cases are the same on every run.
struct SensoryRNG: Sendable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func unit() -> Double { Double(next() % 10_000) / 9_999 }

    mutating func bool() -> Bool { next() & 1 == 0 }
}
