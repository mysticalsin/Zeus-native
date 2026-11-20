import Foundation
import Testing
@testable import ZeusCore

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// The ring budget written down for the presenter: 24 px at scale 1 and under 3840 px, otherwise 48.
private func spec(scale: Double, pixelWidth: Int) -> (pixels: Double, points: Double) {
    let pixels = (scale >= 2 || pixelWidth >= 3840) ? 48.0 : 24.0
    let safe = scale > 0 ? scale : 1
    return (pixels, pixels / safe)
}

@Suite("Present ring tolerance")
struct PresentToleranceTests {
    @Test func standardAndFineBandsMeetTheWrittenThresholds() {
        let hd = PresentTolerance.decide(scale: 1, pixelWidth: 1920)
        #expect(hd.band == .standard)
        #expect(hd.pixels == 24)
        #expect(hd.points == 24)
        let retina = PresentTolerance.decide(scale: 2, pixelWidth: 2560)
        #expect(retina.band == .fine)
        #expect(retina.pixels == 48)
        #expect(retina.points == 24)
        let panel = PresentTolerance.decide(scale: 1, pixelWidth: 3840)
        #expect(panel.band == .fine)
        #expect(panel.pixels == 48)
        #expect(panel.points == 48)
    }

    @Test func theBoundariesAreClosedOnTheHighSide() {
        #expect(PresentTolerance.decide(scale: 2, pixelWidth: 0).band == .fine)
        #expect(PresentTolerance.decide(scale: 1.999, pixelWidth: 3839).band == .standard)
        #expect(PresentTolerance.decide(scale: 1.999, pixelWidth: 3839).pixels == 24)
        #expect(PresentTolerance.decide(scale: 0, pixelWidth: 3840).pixels == 48)
        #expect(PresentTolerance.decide(scale: 0, pixelWidth: 3840).points == 48)
        #expect(PresentTolerance.decide(scale: -1, pixelWidth: 100).pixels == 24)
        #expect(PresentTolerance.decide(scale: -1, pixelWidth: 100).points == 24)
        #expect(PresentTolerance.decide(scale: .nan, pixelWidth: 1920).pixels == 24)
        #expect(PresentTolerance.decide(scale: .nan, pixelWidth: 1920).points == 24)
        #expect(PresentTolerance.decide(scale: .infinity, pixelWidth: 1).pixels == 48)
        #expect(PresentTolerance.decide(scale: .infinity, pixelWidth: 1).points == 0)
        #expect(PresentTolerance.decide(scale: -.infinity, pixelWidth: 1).pixels == 24)
        #expect(PresentTolerance.decide(scale: -.infinity, pixelWidth: 1).points == 24)
        #expect(PresentTolerance.decide(scale: 1, pixelWidth: .min).band == .standard)
        #expect(PresentTolerance.decide(scale: 1, pixelWidth: .max).band == .fine)
    }

    @Test func productionReadersGoThroughTheDecision() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mapper = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/Present/CoordinateMapper.swift"), encoding: .utf8)
        let mapping = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/Present/PresentPointMapping.swift"), encoding: .utf8)
        #expect(mapper.contains("PresentTolerance.decide("))
        #expect(mapping.contains("PresentTolerance.decide("))
        #expect(!mapper.contains("PresentTolerance.ringPixels("))
        #expect(!mapper.contains("PresentTolerance.ringPoints("))
        #expect(!mapping.contains("PresentTolerance.ringPoints("))
        #expect(!mapping.contains("PresentTolerance.ringPixels("))
    }

    @Test func theExistingReadersFollowTheDecision() {
        for (scale, width) in [(1.0, 1920), (2.0, 2560), (1.0, 3840), (0.0, 100), (-3.0, 4000)] {
            let decision = PresentTolerance.decide(scale: scale, pixelWidth: width)
            #expect(PresentTolerance.ringPixels(scale: scale, pixelWidth: width) == decision.pixels)
            #expect(PresentTolerance.ringPoints(scale: scale, pixelWidth: width) == decision.points)
        }
    }

    @Test func randomScalesStayOnTheSpec() {
        var rng = SplitMix(state: 42)
        let widths = [Int.min, -1, 0, 1, 1919, 1920, 3839, 3840, 3841, Int.max]
        for _ in 0..<300 {
            let scale = (rng.unit() * 8) - 2
            let width = widths[Int(rng.next() % UInt64(widths.count))]
            let expected = spec(scale: scale, pixelWidth: width)
            let decision = PresentTolerance.decide(scale: scale, pixelWidth: width)
            #expect(decision.pixels == expected.pixels)
            #expect(decision.points == expected.points)
            #expect(decision.pixels == 24 || decision.pixels == 48)
            #expect(decision.band == (decision.pixels == 48 ? .fine : .standard))
        }
    }
}
