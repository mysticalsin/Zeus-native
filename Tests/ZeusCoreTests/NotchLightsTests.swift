import Foundation
import Testing
@testable import ZeusCore

@Suite struct NotchLightsTests {
    @Test func armWidths() {
        #expect(NotchLightMath.armLength("Narrow") == 76)
        #expect(NotchLightMath.armLength("Medium") == 130)
        #expect(NotchLightMath.armLength("Extra wide") == 440)
    }

    @Test func entranceSpeedScalesOnlyEntranceDuration() {
        let entrance = NotchLightKind.entrance(.sweep, .sky)
        #expect(entrance.duration(speedPercent: 100) == entrance.duration)
        #expect(entrance.duration(speedPercent: 50) == entrance.duration * 2)
        #expect(entrance.duration(speedPercent: 200) == entrance.duration / 2)
        #expect(entrance.duration(speedPercent: 10) == entrance.duration * 2)
        #expect(NotchLightKind.copySweep.duration(speedPercent: 200) == NotchLightKind.copySweep.duration)
    }

    @Test func copySweepCrossesLeftThenRight() {
        let early = NotchLightMath.segments(.copySweep, progress: 0.1, shoulder: 0.4)
        let late = NotchLightMath.segments(.copySweep, progress: 0.4, shoulder: 0.4)
        #expect(early.first?.side == -1)
        #expect(late.first?.side == 1)
    }

    @Test func timerGaugeShrinks() {
        #expect(NotchLightMath.timerGauge(remainingFraction: 0.5).to == 0.5)
        #expect(NotchLightMath.timerGauge(remainingFraction: 0).to > 0)
    }

    @Test func batteryFillMatchesLevel() {
        let segments = NotchLightMath.segments(.battery(level: 0.62, charging: false), progress: 0.5, shoulder: 0.4)
        #expect(segments.count == 1)
        #expect(abs(segments[0].to - 0.62) < 0.001)
    }

    @Test func shiftPeekNeedsHalfASecondAlone() {
        var gate = ShiftPeekGate()
        let start = Date()
        gate.shift(down: true, at: start)
        let tooSoon = gate.fire(at: start.addingTimeInterval(0.3))
        #expect(!tooSoon)
        let fired = gate.fire(at: start.addingTimeInterval(0.6))
        #expect(fired)
        gate.shift(down: true, at: start)
        gate.otherKey()
        let typed = gate.fire(at: start.addingTimeInterval(0.6))
        #expect(!typed)
    }

    @Test func shortcutsMapToMotions() {
        #expect(ShortcutPeek.lookup("x", shift: false)?.motion == .breach)
        #expect(ShortcutPeek.lookup("z", shift: false)?.motion == .rewind)
        #expect(ShortcutPeek.lookup("Z", shift: true)?.title == "Redo")
        #expect(ShortcutPeek.lookup("c", shift: false) == nil)
    }

    @Test func hudLevelKindDurationMatchesHold() {
        let kind = NotchLightKind.hudLevel(.brightness, value: 0.5, previousLevel: 0.5, muted: false)
        #expect(abs(kind.duration - (SystemHUDMath.holdAfterChange + SystemHUDMath.easeOut)) < 0.001)
    }

    // H2/H3: repeated changes continue the same arm (spring from the previous level, not zero),
    // and a lower value visibly retracts instead of regrowing from nothing.
    @Test func segmentsSpringFromThePreviousLevelNotZero() {
        let rising = NotchLightMath.segments(.hudLevel(.volume, value: 0.8, previousLevel: 0.2, muted: false), progress: 0, shoulder: 0.4)
        #expect(abs((rising.first?.to ?? -1) - 0.2) < 0.001) // starts where the arm already was
        let settled = NotchLightMath.segments(.hudLevel(.volume, value: 0.8, previousLevel: 0.2, muted: false), progress: 0.5, shoulder: 0.4)
        #expect(abs((settled.first?.to ?? -1) - 0.8) < 0.001) // springs on to the new target
    }

    @Test func segmentsRetractWhenLowering() {
        let start = NotchLightMath.segments(.hudLevel(.volume, value: 0.2, previousLevel: 0.9, muted: false), progress: 0, shoulder: 0.4)
        let end = NotchLightMath.segments(.hudLevel(.volume, value: 0.2, previousLevel: 0.9, muted: false), progress: 0.5, shoulder: 0.4)
        #expect((start.first?.to ?? 0) > (end.first?.to ?? 0)) // the arm shrinks, not grows
    }

    @Test func limitEchoAtBoundsAddsATipPulseEarlyThenFades() {
        let withEcho = NotchLightMath.segments(.hudLevel(.volume, value: 1, previousLevel: 1, muted: false, limitEcho: true), progress: 0.02, shoulder: 0.4)
        #expect(withEcho.count == 2)
        #expect((withEcho.last?.opacity ?? 0) > 0)
        let afterEcho = NotchLightMath.segments(.hudLevel(.volume, value: 1, previousLevel: 1, muted: false, limitEcho: true), progress: 0.5, shoulder: 0.4)
        #expect(afterEcho.count == 1) // the pulse is only in its own short window
        let withoutEcho = NotchLightMath.segments(.hudLevel(.volume, value: 1, previousLevel: 1, muted: false), progress: 0.02, shoulder: 0.4)
        #expect(withoutEcho.count == 1)
    }

    @Test func tabHoldGateNeedsFourTenthsOfASecondAlone() {
        var gate = TabHoldGate()
        let start = Date()
        gate.tabDown(at: start, modifiersHeld: false)
        let tooSoon = gate.fire(at: start.addingTimeInterval(0.3))
        #expect(!tooSoon)
        let fired = gate.fire(at: start.addingTimeInterval(0.45))
        #expect(fired)
    }

    @Test func tabHoldGateCancelsOnAnyOtherKey() {
        var gate = TabHoldGate()
        let start = Date()
        gate.tabDown(at: start, modifiersHeld: false)
        gate.otherKey()
        let fired = gate.fire(at: start.addingTimeInterval(0.5))
        #expect(!fired)
    }

    @Test func tabHoldGateIgnoresTabWithModifiersHeld() {
        var gate = TabHoldGate()
        let start = Date()
        gate.tabDown(at: start, modifiersHeld: true)
        let fired = gate.fire(at: start.addingTimeInterval(0.5))
        #expect(!fired)
    }

    @Test func tabHoldGateReleaseReportsWhetherItWasRevealed() {
        var gate = TabHoldGate()
        let start = Date()
        gate.tabDown(at: start, modifiersHeld: false)
        let earlyRelease = gate.tabUp()
        #expect(!earlyRelease) // released before the threshold: nothing to fade
        gate.tabDown(at: start, modifiersHeld: false)
        let fired = gate.fire(at: start.addingTimeInterval(0.45))
        #expect(fired)
        let release = gate.tabUp()
        #expect(release) // was revealed: the caller starts its 250 ms fade now
    }

    @Test func shiftPeekHoldsUntilReleaseNotAFixedDuration() {
        var gate = ShiftPeekGate()
        let start = Date()
        gate.shift(down: true, at: start)
        let fired = gate.fire(at: start.addingTimeInterval(0.6))
        #expect(fired)
        let secondFire = gate.fire(at: start.addingTimeInterval(0.7))
        #expect(!secondFire) // already revealed: no second fire
        let release = gate.release()
        #expect(release) // keyUp: tell the caller to start the fade now
        let secondRelease = gate.release()
        #expect(!secondRelease) // calling again (no peek showing) reports nothing to fade
    }

    @Test func rainAlertOncePerShower() {
        let now = Date()
        let hour = WeatherSnapshot.Hour(time: now.addingTimeInterval(1800), temperature: 20, sky: .rain, rainChance: 80)
        let weather = WeatherSnapshot(temperature: 20, apparent: 20, high: 22, low: 15, sky: .cloudy, isDay: true, humidity: 60, wind: 5, hours: [hour])
        var gate = RainAlertGate()
        let first = gate.minutesUntilRain(weather, now: now)
        let second = gate.minutesUntilRain(weather, now: now.addingTimeInterval(60))
        #expect(first == 30)
        #expect(second == nil)
    }
}
