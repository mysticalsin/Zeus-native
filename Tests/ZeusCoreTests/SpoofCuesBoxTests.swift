import Foundation
import Testing
@testable import ZeusCore

@Suite("Spoof cues box")
struct SpoofCuesBoxTests {
    private func glare(width: Double = 130, fraction: Float, cluster: Float) -> SpoofCuesBox.Frame {
        SpoofCuesBox.Frame(
            glare: SpoofCuesBox.Glare(cropPixelWidth: width, specularFraction: fraction, specularClusterRatio: cluster),
            deviceOverlapFraction: nil)
    }

    private func device(_ overlap: Float?) -> SpoofCuesBox.Frame {
        SpoofCuesBox.Frame(glare: nil, deviceOverlapFraction: overlap)
    }

    private func both() -> SpoofCuesBox.Frame {
        SpoofCuesBox.Frame(
            glare: SpoofCuesBox.Glare(cropPixelWidth: 130, specularFraction: 0.08, specularClusterRatio: 1),
            deviceOverlapFraction: 0.5)
    }

    private var glass: SpoofCuesBox.Frame { glare(fraction: 0.08, cluster: 1) }
    private var clean: SpoofCuesBox.Frame { SpoofCuesBox.Frame(glare: nil, deviceOverlapFraction: nil) }

    @Test func thresholdsMatchTheGlanceFloors() {
        #expect(SpoofCuesBox.glareLevel == 0.04)
        #expect(SpoofCuesBox.deviceLevel == 0.15)
        #expect(SpoofCuesBox.Window.size == 6)
        #expect(SpoofCuesBox.Window.latchCount == 3)
        #expect(SpoofCuesBox.Reading.none == SpoofCuesBox.Reading(level: 0, confidence: 0))
        #expect(Set(SpoofCuesBox.Cue.allCases) == [.glossGlare, .deviceBezel])
    }

    @Test func glareNeedsConcentrationNotJustBrightness() {
        let scattered = SpoofCuesBox.glossGlare(glare(fraction: 0.015, cluster: 0.1))
        let blob = SpoofCuesBox.glossGlare(glare(fraction: 0.015, cluster: 1))
        #expect(blob.level > scattered.level * 2)
        #expect(SpoofCuesBox.counted(in: glare(fraction: 0.015, cluster: 0.1)).isEmpty)
        #expect(SpoofCuesBox.counted(in: glare(fraction: 0.015, cluster: 1)) == [.glossGlare])
        #expect(SpoofCuesBox.glossGlare(glare(fraction: 0.01, cluster: 1)).level == 0)
        #expect(SpoofCuesBox.counted(in: glare(fraction: 0.005, cluster: 1)).isEmpty)
        let extreme = SpoofCuesBox.glossGlare(glare(fraction: 5, cluster: 9))
        #expect(extreme.level == 1)
        #expect(extreme.confidence == 1)
    }

    @Test func smallCropLowersGlareConfidence() {
        func confidence(_ width: Double) -> Float {
            SpoofCuesBox.glossGlare(glare(width: width, fraction: 0.08, cluster: 1)).confidence
        }
        #expect(confidence(50) == 0)
        #expect(confidence(30) == 0)
        #expect(confidence(130) == 1)
        #expect(confidence(400) == 1)
        #expect(confidence(90) == 0.5)
        #expect(confidence(70) < confidence(90))
        #expect(confidence(60) > 0)
        #expect(confidence(-10) == 0)
        let tiny = SpoofCuesBox.glossGlare(glare(width: 40, fraction: 0.5, cluster: 1))
        #expect(tiny.confidence == 0)
        #expect(tiny.level == 1)
        #expect(SpoofCuesBox.counted(in: glare(width: 40, fraction: 0.5, cluster: 1)).isEmpty)
        #expect(SpoofCuesBox.counted(in: glare(width: 50, fraction: 0.08, cluster: 1)).isEmpty)
        #expect(SpoofCuesBox.counted(in: glare(width: 60, fraction: 0.08, cluster: 1)) == [.glossGlare])
    }

    @Test func unreadableGlareAbstains() {
        #expect(SpoofCuesBox.glossGlare(clean) == .none)
        #expect(SpoofCuesBox.glossGlare(glare(width: .nan, fraction: 0.08, cluster: 1)) == .none)
        #expect(SpoofCuesBox.glossGlare(glare(width: .infinity, fraction: 0.08, cluster: 1)) == .none)
        #expect(SpoofCuesBox.glossGlare(glare(fraction: .nan, cluster: 1)) == .none)
        #expect(SpoofCuesBox.glossGlare(glare(fraction: .infinity, cluster: 1)) == .none)
        #expect(SpoofCuesBox.glossGlare(glare(fraction: 0.08, cluster: .nan)) == .none)
        #expect(SpoofCuesBox.glossGlare(glare(fraction: 0.08, cluster: -.infinity)) == .none)
        #expect(SpoofCuesBox.counted(in: glare(fraction: .nan, cluster: 1)).isEmpty)
    }

    @Test func deviceOverlapCountsAtItsLevel() {
        #expect(SpoofCuesBox.counted(in: device(0.14)).isEmpty)
        #expect(SpoofCuesBox.counted(in: device(0.15)) == [.deviceBezel])
        #expect(SpoofCuesBox.counted(in: device(0.9)) == [.deviceBezel])
        #expect(SpoofCuesBox.deviceBezel(device(0.4)) == SpoofCuesBox.Reading(level: 0.4, confidence: 1))
        #expect(SpoofCuesBox.deviceBezel(device(3)).level == 1)
        #expect(SpoofCuesBox.deviceBezel(device(-2)).level == 0)
        #expect(SpoofCuesBox.counted(in: device(-2)).isEmpty)
        #expect(SpoofCuesBox.deviceBezel(device(.nan)) == .none)
        #expect(SpoofCuesBox.deviceBezel(device(.infinity)) == .none)
        #expect(SpoofCuesBox.deviceBezel(device(nil)) == .none)
        #expect(SpoofCuesBox.counted(in: device(nil)).isEmpty)
    }

    @Test func readingsNameBothDenyCues() {
        #expect(SpoofCuesBox.readings(glass) == [
            .glossGlare: SpoofCuesBox.Reading(level: 1, confidence: 1),
            .deviceBezel: .none,
        ])
        #expect(SpoofCuesBox.readings(device(0.4)) == [
            .glossGlare: .none,
            .deviceBezel: SpoofCuesBox.Reading(level: 0.4, confidence: 1),
        ])
        #expect(SpoofCuesBox.counted(in: both()) == [.glossGlare, .deviceBezel])
    }

    @Test func threeCountedFramesLatch() {
        var window = SpoofCuesBox.Window()
        #expect(!window.isSpoofed)
        #expect(window.observe(glass).isEmpty)
        #expect(window.observe(glass).isEmpty)
        #expect(window.observe(glass) == [.glossGlare])
        #expect(window.latched == [.glossGlare])
        #expect(window.isSpoofed)
        var twin = SpoofCuesBox.Window()
        for _ in 0..<3 { _ = twin.observe(glass) }
        #expect(twin == window)
        _ = window.observe(clean)
        #expect(window != twin)
    }

    @Test func agingOutClearsAndCuesStaySeparate() {
        var window = SpoofCuesBox.Window()
        _ = window.observe(glass)
        _ = window.observe(glass)
        #expect(window.observe(glass) == [.glossGlare])
        for _ in 0..<3 { #expect(window.observe(clean) == [.glossGlare]) }
        #expect(window.observe(clean).isEmpty)
        #expect(!window.isSpoofed)

        window.reset()
        #expect(window.observe(glass).isEmpty)
        #expect(window.observe(clean).isEmpty)
        #expect(window.observe(glass).isEmpty)
        #expect(window.observe(clean).isEmpty)
        #expect(window.observe(glass) == [.glossGlare])

        window.reset()
        let far: [SpoofCuesBox.Frame] = [glass, clean, clean, clean, clean, clean, glass, clean, clean, clean, clean, clean, glass]
        for frame in far { #expect(window.observe(frame).isEmpty) }

        window.reset()
        for frame in [glass, device(0.5), glass, device(0.5)] {
            #expect(window.observe(frame).isEmpty)
        }
        #expect(window.observe(device(0.5)) == [.deviceBezel])

        window.reset()
        #expect(window.observe(both()).isEmpty)
        #expect(window.observe(both()).isEmpty)
        #expect(window.observe(both()) == [.glossGlare, .deviceBezel])
    }

    @Test func resetForgetsEveryFrame() {
        var window = SpoofCuesBox.Window()
        _ = window.observe(glass)
        _ = window.observe(glass)
        #expect(window.observe(glass) == [.glossGlare])
        window.reset()
        #expect(window.latched.isEmpty)
        #expect(!window.isSpoofed)
        #expect(window == SpoofCuesBox.Window())
        #expect(window.observe(glass).isEmpty)
    }

    @Test func aCleanRunNeverLatches() {
        var window = SpoofCuesBox.Window()
        for _ in 0..<20 {
            #expect(window.observe(clean).isEmpty)
            #expect(!window.isSpoofed)
        }
        let skin = glare(fraction: 0, cluster: 0)
        #expect(SpoofCuesBox.glossGlare(skin).level == 0)
        #expect(SpoofCuesBox.counted(in: skin).isEmpty)
        for _ in 0..<20 { #expect(window.observe(skin).isEmpty) }
    }
}
