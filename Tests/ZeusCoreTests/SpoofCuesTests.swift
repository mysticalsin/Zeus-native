import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Spoof cues")
struct SpoofCuesTests {
    private func glareFrame(width: CGFloat = 130, fraction: Float, cluster: Float) -> SpoofFrame {
        SpoofFrame(glare: GlareSample(cropPixelWidth: width, specularFraction: fraction, specularClusterRatio: cluster),
                   deviceOverlapFraction: nil)
    }

    private func deviceFrame(_ overlap: Float?) -> SpoofFrame {
        SpoofFrame(glare: nil, deviceOverlapFraction: overlap)
    }

    /// A frame the glare cue counts: a large, concentrated highlight on a crop with enough detail.
    private var glassGlare: SpoofFrame { glareFrame(fraction: 0.08, cluster: 1.0) }
    private var clean: SpoofFrame { SpoofFrame(glare: nil, deviceOverlapFraction: nil) }

    @Test func zeroConfidenceNeverCounts() {
        // A 40 px crop has no detail to judge: confidence 0, whatever the level says.
        let tiny = glareFrame(width: 40, fraction: 0.5, cluster: 1.0)
        let reading = SpoofCues.glossGlare(tiny)
        #expect(reading.confidence == 0)
        #expect(reading.level > 0.5)
        #expect(SpoofCues.counted(in: tiny).isEmpty)

        // A frame with no measurement at all abstains: it neither convicts nor acquits.
        #expect(SpoofCues.glossGlare(clean) == .none)
        #expect(SpoofCues.deviceBezel(clean) == .none)
        #expect(CueReading.none.confidence == 0)

        // Six frames of zero-confidence evidence never latch.
        var window = SpoofCues.Window()
        for _ in 0..<12 { _ = window.observe(tiny) }
        #expect(window.latched.isEmpty)
        #expect(!window.isSpoofed)
    }

    @Test func glareNeedsConcentrationNotJustBrightness() {
        // The same share of bright pixels: scattered like skin shine, or one flat blob like glass.
        let scattered = SpoofCues.glossGlare(glareFrame(fraction: 0.015, cluster: 0.1))
        let blob = SpoofCues.glossGlare(glareFrame(fraction: 0.015, cluster: 1.0))
        #expect(blob.level > scattered.level * 2)
        #expect(SpoofCues.counted(in: glareFrame(fraction: 0.015, cluster: 0.1)).isEmpty)
        #expect(SpoofCues.counted(in: glareFrame(fraction: 0.015, cluster: 1.0)) == [.glossGlare])

        // A bright forehead below the fraction floor reads as nothing, however concentrated.
        #expect(SpoofCues.glossGlare(glareFrame(fraction: 0.01, cluster: 1.0)).level == 0)
        #expect(SpoofCues.counted(in: glareFrame(fraction: 0.005, cluster: 1.0)).isEmpty)

        // Level never leaves 0...1.
        let extreme = SpoofCues.glossGlare(glareFrame(fraction: 5, cluster: 9))
        #expect(extreme.level == 1)
    }

    @Test func smallCropLowersGlareConfidence() {
        func confidence(_ width: CGFloat) -> Float {
            SpoofCues.glossGlare(glareFrame(width: width, fraction: 0.08, cluster: 1.0)).confidence
        }
        #expect(confidence(50) == 0)
        #expect(confidence(30) == 0)
        #expect(confidence(130) == 1)
        #expect(confidence(400) == 1)
        let middle = confidence(90)
        #expect(middle > 0.45 && middle < 0.55)
        #expect(confidence(70) < confidence(90))
        // Just above the floor the crop is trusted a little, and the frame counts.
        #expect(confidence(60) > 0)
        #expect(SpoofCues.counted(in: glareFrame(width: 60, fraction: 0.08, cluster: 1.0)) == [.glossGlare])
    }

    @Test func deviceOverlapCountsAtItsLevel() {
        #expect(SpoofCues.counted(in: deviceFrame(0.14)).isEmpty)
        #expect(SpoofCues.counted(in: deviceFrame(0.15)) == [.deviceBezel])
        #expect(SpoofCues.counted(in: deviceFrame(0.9)) == [.deviceBezel])
        // The overlap is used as measured and always at full confidence.
        #expect(SpoofCues.deviceBezel(deviceFrame(0.4)) == CueReading(level: 0.4, confidence: 1))
        // Out-of-range and unreadable values are clamped or abstain; they never crash or convict.
        #expect(SpoofCues.deviceBezel(deviceFrame(3)).level == 1)
        #expect(SpoofCues.deviceBezel(deviceFrame(-2)).level == 0)
        #expect(SpoofCues.deviceBezel(deviceFrame(.nan)) == .none)
        #expect(SpoofCues.deviceBezel(deviceFrame(.infinity)) == .none)
        #expect(SpoofCues.deviceBezel(deviceFrame(nil)) == .none)
    }

    @Test func threeOfSixLatchesAndAgingOutClears() {
        var window = SpoofCues.Window()
        #expect(SpoofCues.Window.size == 6)
        #expect(SpoofCues.Window.latchCount == 3)

        // Two spoof frames are not enough, however close together.
        #expect(window.observe(glassGlare).isEmpty)
        #expect(window.observe(glassGlare).isEmpty)
        // The third latches, and the frames between need not be consecutive.
        #expect(window.observe(glassGlare) == [.glossGlare])
        #expect(window.isSpoofed)

        // Three clean frames: the window is S S S c c c, still latched.
        for _ in 0..<3 { #expect(window.observe(clean) == [.glossGlare]) }
        // One more clean frame pushes the first spoof frame out: 2 of 6, cleared.
        #expect(window.observe(clean).isEmpty)
        #expect(!window.isSpoofed)

        // Spread out: S c S c S latches on the fifth frame.
        window.reset()
        #expect(window.latched.isEmpty)
        #expect(window.observe(glassGlare).isEmpty)
        #expect(window.observe(clean).isEmpty)
        #expect(window.observe(glassGlare).isEmpty)
        #expect(window.observe(clean).isEmpty)
        #expect(window.observe(glassGlare) == [.glossGlare])

        // Three spoof frames more than six apart never latch.
        window.reset()
        for frame in [glassGlare, clean, clean, clean, clean, clean, glassGlare, clean, clean, clean, clean, clean, glassGlare] {
            #expect(window.observe(frame).isEmpty)
        }

        // Each cue is counted on its own: two glare and two bezel frames do not add up to three.
        window.reset()
        for frame in [glassGlare, deviceFrame(0.5), glassGlare, deviceFrame(0.5)] {
            #expect(window.observe(frame).isEmpty)
        }
        #expect(window.observe(deviceFrame(0.5)) == [.deviceBezel])
    }

    @Test func cuesNeverReportLiveness() {
        // The only cues are deny cues.
        #expect(Set(SpoofCue.allCases) == [.glossGlare, .deviceBezel])

        // A spotless run of frames only ever reports no spoof; there is no positive "live" result to read.
        var window = SpoofCues.Window()
        for _ in 0..<20 {
            #expect(window.observe(clean).isEmpty)
            #expect(!window.isSpoofed)
        }
        // A near-perfect face (no glare, no device) still reads as nothing at all.
        let skin = glareFrame(fraction: 0.0, cluster: 0.0)
        #expect(SpoofCues.glossGlare(skin).level == 0)
        #expect(SpoofCues.counted(in: skin).isEmpty)
        for _ in 0..<20 { #expect(window.observe(skin).isEmpty) }

        // The window exposes no field that talks about liveness, confirmation or a pass.
        let names = Mirror(reflecting: window).children.compactMap(\.label).map { $0.lowercased() }
        #expect(names.allSatisfy { !$0.contains("live") && !$0.contains("confirm") && !$0.contains("pass") })
        #expect(Mirror(reflecting: SpoofFrame(glare: nil, deviceOverlapFraction: nil)).children.compactMap(\.label)
            .allSatisfy { !$0.lowercased().contains("blink") && !$0.lowercased().contains("pose") })
    }
}
