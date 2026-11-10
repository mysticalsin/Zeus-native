import Testing
@testable import ZeusCore

/// P0 item F, QA7 (Tony: "maybe an orb animation instead of the red dot"). Pure geometry, no
/// rendering surface, so every claim here holds regardless of how `Canvas` paints it.
@Suite("Thinking orb geometry")
struct ThinkingOrbMathTests {
    @Test func fibonacciDirectionsAreUnitVectors() {
        for n in [1, 2, 18, 46] {
            for i in 0..<n {
                let d = ThinkingOrbMath.fibonacciDirection(i, n)
                let magnitude = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
                #expect(abs(magnitude - 1) < 0.0001, "n=\(n) i=\(i)")
            }
        }
    }

    @Test func listeningUsesTheDefaultDotCount() {
        #expect(ThinkingOrbMath.dots(mode: .listening(level: 0.5), time: 0).count == 46)
        #expect(ThinkingOrbMath.dots(mode: .listening(level: 0.5), time: 0, listeningCount: 10).count == 10)
    }

    @Test func workingUsesItsOwnSmallerDotCount() {
        #expect(ThinkingOrbMath.dots(mode: .working, time: 0).count == 18)
    }

    @Test func everyDotIsInBoundsWithPositiveRadiusAndClampedOpacity() {
        for mode: ThinkingOrbMath.Mode in [.listening(level: 0), .listening(level: 1), .working] {
            for dot in ThinkingOrbMath.dots(mode: mode, time: 1.23) {
                #expect(abs(dot.x) <= 1.05, "\(dot)")
                #expect(abs(dot.y) <= 1.05, "\(dot)")
                #expect(dot.depth >= 0 && dot.depth <= 1, "\(dot)")
                #expect(dot.radius > 0, "\(dot)")
                #expect(dot.opacity >= 0 && dot.opacity <= 1, "\(dot)")
            }
        }
    }

    @Test func louderLevelsMakeTheWaveReachFurtherThanSilence() {
        func radiusSpread(level: Double) -> Double {
            let radii = ThinkingOrbMath.dots(mode: .listening(level: level), time: 2.0).map(\.radius)
            return (radii.max() ?? 0) - (radii.min() ?? 0)
        }
        #expect(radiusSpread(level: 1) > radiusSpread(level: 0))
    }

    @Test func listeningIsNeverFullyFlatEvenInSilence() {
        // A gentle idle ripple keeps the orb looking alive while Zeus is still listening for
        // speech, even before anyone has said anything.
        let radii = ThinkingOrbMath.dots(mode: .listening(level: 0), time: 2.0).map(\.radius)
        #expect((radii.max() ?? 0) - (radii.min() ?? 0) > 0)
    }

    @Test func theFrameMovesOverTime() {
        let a = ThinkingOrbMath.dots(mode: .listening(level: 0.5), time: 0)
        let b = ThinkingOrbMath.dots(mode: .listening(level: 0.5), time: 3)
        #expect(a != b)
        let workingA = ThinkingOrbMath.dots(mode: .working, time: 0)
        let workingB = ThinkingOrbMath.dots(mode: .working, time: 3)
        #expect(workingA != workingB)
    }

    @Test func workingAndListeningAreVisiblyDifferentPatterns() {
        #expect(ThinkingOrbMath.dots(mode: .working, time: 0).count != ThinkingOrbMath.dots(mode: .listening(level: 0.5), time: 0).count)
    }
}
