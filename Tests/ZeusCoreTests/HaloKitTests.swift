import Foundation
import Testing
@testable import ZeusCore

@Suite struct HaloKitTests {
    // MARK: halo.style migration

    @Test func oldNotchKeyWinsOverThePickerKey() {
        #expect(HaloMigration.unified(haloStyle: "Classic halo", legacyTopBar: "Aurora") == .aurora)
        #expect(HaloMigration.unified(haloStyle: "Wet rays", legacyTopBar: nil) == .rayons)
        #expect(HaloMigration.unified(haloStyle: nil, legacyTopBar: nil) == .classic)
        #expect(HaloMigration.unified(haloStyle: "garbage", legacyTopBar: "") == .classic)
    }

    @Test func everyNameEverUsedResolves() {
        for style in HaloStyle.allCases {
            #expect(HaloStyle.resolve(style.rawValue) == style)
            #expect(HaloStyle.resolve(style.title) == style)
        }
        #expect(HaloStyle.resolve("Crystal prism") == .prisme)
        #expect(HaloStyle.resolve("Realistic nimbus") == .nimbus)
        #expect(HaloStyle.resolve("Pixelated halo") == .pixelated)
        #expect(HaloStyle.resolve("Classic glow") == .classic)
        #expect(HaloStyle.resolve("Lumière") == .lumiere)
    }

    @Test func runRewritesBothKeysIntoOne() throws {
        let name = "zeus.halo.migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("Storm", forKey: HaloMigration.legacyKey)
        defaults.set("Pixelated halo", forKey: HaloMigration.styleKey)
        #expect(HaloMigration.run(defaults: defaults) == .storm)
        #expect(defaults.string(forKey: HaloMigration.styleKey) == "storm")
        #expect(defaults.object(forKey: HaloMigration.legacyKey) == nil)
        #expect(HaloMigration.run(defaults: defaults) == nil)
    }

    @Test func runNormalizesAnOldPickerValueAndLeavesIdsAlone() throws {
        let name = "zeus.halo.migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(HaloMigration.run(defaults: defaults) == nil)
        defaults.set("Wet rays", forKey: HaloMigration.styleKey)
        #expect(HaloMigration.run(defaults: defaults) == .rayons)
        #expect(defaults.string(forKey: HaloMigration.styleKey) == "rayons")
        defaults.set("nimbus", forKey: HaloMigration.styleKey)
        #expect(HaloMigration.run(defaults: defaults) == nil)
    }

    // MARK: Renderer selection

    @Test func everyStyleHasItsOwnRenderer() {
        let renderers = HaloStyle.allCases.map(\.renderer)
        #expect(Set(renderers).count == HaloStyle.allCases.count)
        #expect(HaloStyle.off.renderer == .none)
        #expect(HaloStyle.classic.renderer == .line)
    }

    @Test func formerlyClassicLookalikesAreDrawnForReal() {
        #expect(HaloStyle.rayons.renderer == .rays)
        #expect(HaloStyle.prisme.renderer == .prism)
        #expect(HaloStyle.nimbus.renderer == .cloud)
        #expect(HaloStyle.lumiere.renderer == .core)
        #expect(HaloStyle.pixelated.renderer == .grid)
        #expect(HaloStyle.volumetric.renderer == .depth)
        #expect(HaloStyle.bioluminescent.renderer == .dots)
        for style in [HaloStyle.rayons, .prisme, .nimbus, .lumiere] { #expect(style.renderer != .line) }
    }

    // MARK: Entrances

    @Test func entranceIdsRoundTrip() {
        for e in HaloEntrance.allCases {
            #expect(HaloEntrance(rawValue: e.id) == e)
            #expect(HaloEntrance.resolve(e.id) == e)
            #expect(HaloEntrance.resolve(e.title) == e)
        }
        // What older builds saved and what the picker used to offer.
        #expect(HaloEntrance.resolve("Trace") == .trace)
        #expect(HaloEntrance.resolve("Trace (sleek)") == .trace)
        #expect(HaloEntrance.resolve("Big bang") == .bigBang)
        #expect(HaloEntrance.resolve("Big Bang") == .bigBang)
        #expect(HaloEntrance.resolve("White flash") == .whiteFlash)
        #expect(HaloEntrance.resolve("Hue slide") == .hueSlide)
        #expect(HaloEntrance.resolve("nonsense") == .sweep)
        #expect(HaloEntrance.resolve(nil) == .sweep)
    }

    @Test func everyEntranceHasADistinctChoreography() {
        let all = HaloEntrance.allCases
        #expect(all.count == 13)
        let signatures = all.map { $0.choreography.signature }
        #expect(Set(signatures).count == all.count)
        // And they really move differently: sample each at several moments.
        var seen: Set<String> = []
        for e in all {
            var fingerprint = ""
            for p in [0.1, 0.3, 0.5, 0.7, 0.9] {
                let frame = NotchLightMath.entranceFrame(e, progress: p, shoulder: 0.4)
                fingerprint += frame.layers.map { layer in
                    layer.segments.map { String(format: "%.2f,%.2f,%.2f", $0.from, $0.to, $0.opacity) }.joined(separator: ";")
                        + String(format: "|w%.2f|x%.2f|b%.2f", layer.white, layer.width, layer.bloom)
                }.joined(separator: "/") + String(format: "h%.2f#", frame.hueShift)
            }
            #expect(seen.insert(fingerprint).inserted, "\(e) repeats another entrance")
        }
    }

    @Test func entranceTimingStaysBetweenFourTenthsAndOnePointTwoSeconds() {
        for e in HaloEntrance.allCases {
            let d = NotchLightKind.entrance(e, .sky).duration
            #expect(d >= 0.4 && d <= 1.2, "\(e) lasts \(d)")
            #expect(d == e.choreography.duration)
        }
    }

    @Test func strobeNeverFlashesFasterThanThreeHertz() {
        let strobe = NotchLightKind.entrance(.strobe, .sky)
        for speed in [50.0, 100, 150, 200, 1000] {
            let d = strobe.duration(speedPercent: speed)
            #expect(Double(HaloEntrance.strobe.choreography.pulses) / d <= 3.0001, "speed \(speed)")
        }
        #expect(HaloEntrance.strobe.choreography.flashRate <= 3)
        // Count the flashes in a run: rising edges of the opacity.
        var flashes = 0, wasOn = false
        for i in 0...400 {
            let on = (NotchLightMath.entranceFrame(.strobe, progress: Double(i) / 400, shoulder: 0.4).flat.first?.opacity ?? 0) > 0.5
            if on && !wasOn { flashes += 1 }
            wasOn = on
        }
        #expect(flashes == 3)
    }

    @Test func hueSlideActuallyAnimatesTheHue() {
        let early = NotchLightMath.entranceFrame(.hueSlide, progress: 0.1, shoulder: 0.4).hueShift
        let mid = NotchLightMath.entranceFrame(.hueSlide, progress: 0.5, shoulder: 0.4).hueShift
        let late = NotchLightMath.entranceFrame(.hueSlide, progress: 0.95, shoulder: 0.4).hueShift
        #expect(early < mid && mid < late)
        #expect(late > 0.3)
        #expect(NotchLightMath.entranceFrame(.sweep, progress: 0.5, shoulder: 0.4).hueShift == 0)
    }

    @Test func entranceFramesStayInsideTheArm() {
        for e in HaloEntrance.allCases {
            for i in 0...20 {
                for s in NotchLightMath.entranceFrame(e, progress: Double(i) / 20, shoulder: 0.35).flat {
                    #expect(s.from >= 0 && s.to <= 1 && s.opacity >= 0 && s.opacity <= 1)
                }
            }
        }
    }

    // MARK: Wallpaper blend

    @Test func wallpaperBlendGrowsWithBrightness() {
        #expect(WallpaperBlend.whiteAmount(luminance: 0) == 0)
        #expect(WallpaperBlend.whiteAmount(luminance: 0.4) == 0)
        #expect(WallpaperBlend.whiteAmount(luminance: 0.7) > 0.1)
        #expect(WallpaperBlend.whiteAmount(luminance: 0.7) < WallpaperBlend.whiteAmount(luminance: 0.8))
        #expect(WallpaperBlend.whiteAmount(luminance: 1) <= 0.8 + 1e-9)
        #expect(WallpaperBlend.whiteAmount(luminance: 5) == WallpaperBlend.whiteAmount(luminance: 1))
    }

    @Test func wallpaperBlendMovesColourTowardWhiteOnlyOnLightWallpapers() {
        let dark = WallpaperBlend.blend(red: 0.2, green: 0.4, blue: 0.9, luminance: 0.2)
        #expect(dark.red == 0.2 && dark.green == 0.4 && dark.blue == 0.9)
        let light = WallpaperBlend.blend(red: 0.2, green: 0.4, blue: 0.9, luminance: 0.95)
        #expect(light.red > 0.6 && light.green > 0.7 && light.blue > 0.95)
        #expect(WallpaperBlend.luminance(red: 1, green: 1, blue: 1) > 0.999)
        #expect(WallpaperBlend.luminance(red: 0, green: 0, blue: 0) == 0)
        #expect(WallpaperBlend.luminance(red: 0, green: 1, blue: 0) > WallpaperBlend.luminance(red: 0, green: 0, blue: 1))
    }

    // MARK: Edge wave

    @Test func edgeWaveFrontsRunAroundAndFade() {
        var lastHead = -1.0
        for i in 0...20 {
            let f = EdgeWaveMath.fronts(progress: Double(i) / 20)
            #expect(f.head >= lastHead && f.tail <= f.head && f.opacity >= 0 && f.opacity <= 1)
            lastHead = f.head
        }
        #expect(EdgeWaveMath.fronts(progress: 1).head == 1)
        #expect(EdgeWaveMath.fronts(progress: 1).opacity == 0)
    }
}
