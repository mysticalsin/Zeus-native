import Foundation
import Testing
@testable import ZeusCore

@Suite struct TopBarVisibleLightsTests {
    @Test func volumeMarkStaysLitAfterTheTransientHold() {
        let early = VolumeSteadyLightMath.frame(level: 0.4, muted: false, elapsed: 0)
        let later = VolumeSteadyLightMath.frame(level: 0.4, muted: false, elapsed: 30)
        #expect(early.opacity == 1)
        #expect(later.opacity == 1)
        #expect(early.fraction == 0.4)
        #expect(later.fraction == early.fraction)
    }

    @Test func aQuietVolumeStillShowsAVisibleMark() {
        let quiet = VolumeSteadyLightMath.frame(level: 0.02, muted: false, elapsed: 5)
        #expect(quiet.fraction >= VolumeSteadyLightMath.minimumVisibleFraction)
        #expect(quiet.opacity == 1)
        #expect(VolumeSteadyLightMath.lineWidth >= 3)
    }

    @Test func muteKeepsADimMarkThatDoesNotDisappear() {
        let mute = VolumeSteadyLightMath.frame(level: 0.8, muted: true, elapsed: 10)
        #expect(mute.fraction == VolumeSteadyLightMath.minimumVisibleFraction)
        #expect(mute.opacity == 0.7)
        let later = VolumeSteadyLightMath.frame(level: 0.8, muted: true, elapsed: 60)
        #expect(later == mute)
    }

    @Test func litWidthFollowsTheBarAndStaysInsideIt() {
        #expect(VolumeSteadyLightMath.litWidth(span: 200, level: 0.5, muted: false) == 100)
        #expect(VolumeSteadyLightMath.litWidth(span: 200, level: 0, muted: false) == 200 * VolumeSteadyLightMath.minimumVisibleFraction)
        #expect(VolumeSteadyLightMath.litWidth(span: 0, level: 1, muted: false) == 0)
        #expect(VolumeSteadyLightMath.litWidth(span: .nan, level: 1, muted: false) == 0)
        let full = VolumeSteadyLightMath.litWidth(span: 80, level: 4, muted: false)
        #expect(full == 80)
    }

    @Test func spokenVolumeNamesTheLevel() {
        #expect(VolumeSteadyLightMath.spoken(level: 0.4, muted: false) == "Volume 40 percent")
        #expect(VolumeSteadyLightMath.spoken(level: 0, muted: false) == "Volume muted")
        #expect(VolumeSteadyLightMath.spoken(level: 0.9, muted: true) == "Volume muted")
        #expect(VolumeSteadyLightMath.spoken(level: .infinity, muted: false) == "Volume muted")
    }

    @Test func capsLockShiftAndCommandPeeksTravelTheScreenEdge() {
        #expect(ScreenEdgeKeyLight.tint(for: .capsLock(true)) == .amber)
        #expect(ScreenEdgeKeyLight.tint(for: .capsLock(false)) == .white)
        #expect(ScreenEdgeKeyLight.tint(for: .shiftCrest) == .white)
        let keys = [("x", false), ("v", false), ("z", false), ("z", true), ("s", false), ("r", false),
                    ("p", false), ("a", false), ("f", false), ("t", false), ("w", false), ("n", false), ("q", false)]
        for (characters, shift) in keys {
            let peek = ShortcutPeek.lookup(characters, shift: shift)
            #expect(peek != nil)
            #expect(ScreenEdgeKeyLight.tint(for: .shortcut(peek?.motion ?? .sweep)) == .white)
        }
        #expect(ShortcutPeek.lookup("c", shift: false) == nil)
    }

    @Test func otherNotchLightsDoNotTravelTheScreenEdge() {
        #expect(ScreenEdgeKeyLight.tint(for: .copySweep) == nil)
        #expect(ScreenEdgeKeyLight.tint(for: .hudLevel(.volume, value: 0.5, previousLevel: 0.2, muted: false)) == nil)
        #expect(ScreenEdgeKeyLight.tint(for: .battery(level: 0.5, charging: true)) == nil)
        #expect(ScreenEdgeKeyLight.tint(for: .edgeWave(.cyan)) == nil)
    }
}
