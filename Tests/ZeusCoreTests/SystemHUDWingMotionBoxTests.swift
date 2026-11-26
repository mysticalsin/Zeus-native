import Foundation
import Testing
@testable import ZeusCore

/// HUD wing expansion as plain numbers. The caller supplies the spring remainder and the idle
/// and final widths. The type does not read a screen, a pointer, or a clock.
@Suite("System HUD wing motion box")
struct SystemHUDWingMotionBoxTests {
    private func sample(_ time: Double, _ width: Double, opacity: Double = 0) -> SystemHUDWingMotionBox.Sample {
        .init(time: time, width: width, height: 32, opacity: opacity)
    }

    @Test func cueExtraWidthIsFiftyEightExceptCapsLock() {
        for kind in SystemHUDWingMotionBox.Kind.allCases {
            let expected: Double = kind == .capsLock ? 30 : 58
            #expect(kind.extraWidth == expected)
        }
    }

    @Test func ratesAndReferenceSizesStayFixed() {
        #expect(SystemHUDWingMotionBox.sampleFPS == 120)
        #expect(SystemHUDWingMotionBox.frameStep == 1.0 / 60.0)
        #expect(SystemHUDWingMotionBox.referenceNotchWidth == 185)
        #expect(SystemHUDWingMotionBox.referenceBarHeight == 32)
    }

    @Test func expansionInvertsAnOpeningRemainderAndClampsBothDirections() {
        #expect(SystemHUDWingMotionBox.expansion(remaining: 1, opening: true) == 0)
        #expect(SystemHUDWingMotionBox.expansion(remaining: 0, opening: true) == 1)
        #expect(SystemHUDWingMotionBox.expansion(remaining: 0.25, opening: true) == 0.75)
        #expect(SystemHUDWingMotionBox.expansion(remaining: -0.1, opening: true) == 1.06)
        #expect(SystemHUDWingMotionBox.expansion(remaining: 2, opening: true) == 0)
        #expect(SystemHUDWingMotionBox.expansion(remaining: 0, opening: false) == 0)
        #expect(SystemHUDWingMotionBox.expansion(remaining: 0.4, opening: false) == 0.4)
        #expect(SystemHUDWingMotionBox.expansion(remaining: 1.2, opening: false) == 1.06)
        #expect(SystemHUDWingMotionBox.expansion(remaining: -0.2, opening: false) == 0)
    }

    @Test func samplePlacesWidthFromTheExpansionAndClampsOpacityOnClose() {
        let open = SystemHUDWingMotionBox.sample(
            time: 0.25, opening: true, expansion: 0.5, idle: 100, target: 180, height: 32)
        #expect(open.time == 0.25)
        #expect(open.width == 140)
        #expect(open.height == 32)
        #expect(open.opacity == 0.5)

        let over = SystemHUDWingMotionBox.sample(
            time: 0.3, opening: true, expansion: 1.06, idle: 100, target: 180, height: 32)
        #expect(over.width == 184.8)
        #expect(over.opacity == 1)

        let closing = SystemHUDWingMotionBox.sample(
            time: 0.3, opening: false, expansion: 1.06, idle: 100, target: 180, height: 32)
        #expect(closing.width == 184.8)
        #expect(closing.opacity == 1)

        let below = SystemHUDWingMotionBox.sample(
            time: 0.1, opening: true, expansion: -0.2, idle: 100, target: 180, height: 32)
        #expect(below.width == 84)
        #expect(below.opacity == -0.2)

        let closedBelow = SystemHUDWingMotionBox.sample(
            time: 0.1, opening: false, expansion: -0.2, idle: 100, target: 180, height: 32)
        #expect(closedBelow.width == 84)
        #expect(closedBelow.opacity == 0)
    }

    @Test func timelineFollowsTheInjectedRemainderAtOneHundredTwentyFrames() {
        var seen: [Double] = []
        let held = SystemHUDWingMotionBox.timeline(seconds: 0.35, opening: true, idle: 100, target: 180) { time in
            seen.append(time)
            return 1
        }
        let step = 1 / SystemHUDWingMotionBox.sampleFPS
        let limit = 0.35 + step * 0.5
        #expect(held.count > 2)
        #expect(held.first?.time == 0)
        #expect(held.dropFirst().first?.time == step)
        #expect(held.last?.time ?? -1 <= limit)
        #expect((held.last?.time ?? 0) + step > limit)
        #expect(seen == held.map(\.time))
        #expect(held.allSatisfy { $0.width == 100 && $0.opacity == 0 && $0.height == 32 })

        let released = SystemHUDWingMotionBox.timeline(seconds: 0, opening: true, idle: 100, target: 180) { _ in 0 }
        #expect(released.count == 1)
        #expect(released.first?.time == 0)
        #expect(released.first?.width == 180)
        #expect(released.first?.opacity == 1)
    }

    @Test func openNeedsTwoSamplesAndADeltaAboveOne() {
        #expect(SystemHUDWingMotionBox.validateOpen(samples: [], finalSize: 200) == ["need samples"])
        #expect(SystemHUDWingMotionBox.validateOpen(samples: [sample(0, 100)], finalSize: 200) == ["need samples"])
        let flat = [sample(0, 100), sample(0.01, 100)]
        #expect(SystemHUDWingMotionBox.validateOpen(samples: flat, finalSize: 101) == ["final size must exceed idle"])
    }

    @Test func openNamesAFirstFramePastFifteenPercent() {
        let samples = [sample(0, 100), sample(0.01, 120), sample(0.10, 196), sample(0.20, 200)]
        let firstExpansion = (120.0 - 100.0) / 100.0
        #expect(SystemHUDWingMotionBox.validateOpen(samples: samples, finalSize: 200) == [
            "first frame expansion \(firstExpansion) > 0.15"
        ])
    }

    @Test func openNamesAStepInsideOneFrameAndIgnoresAWiderGap() {
        let stepTime = 2.0 / 120.0
        let stepped = [
            sample(0, 100),
            sample(1.0 / 120.0, 110),
            sample(stepTime, 180),
            sample(0.10, 196),
            sample(0.20, 200),
        ]
        #expect(SystemHUDWingMotionBox.validateOpen(samples: stepped, finalSize: 200) == [
            "step at \(stepTime)s delta \(70.0) > 25% final"
        ])

        let gapped = [
            sample(0, 100),
            sample(0.01, 110),
            sample(0.03, 180),
            sample(0.10, 196),
            sample(0.20, 200),
        ]
        #expect(SystemHUDWingMotionBox.validateOpen(samples: gapped, finalSize: 200) == [])
    }

    @Test func openNamesAMissedReachAndAnOvershootPastSixPercent() {
        let missed = [sample(0, 100), sample(0.01, 110), sample(0.079, 200), sample(0.10, 190), sample(0.151, 200)]
        #expect(SystemHUDWingMotionBox.validateOpen(samples: missed, finalSize: 200) == [
            "did not reach 95% between 80 and 150 ms"
        ])

        let over = [sample(0, 100), sample(0.01, 110), sample(0.10, 196), sample(0.12, 210)]
        #expect(SystemHUDWingMotionBox.validateOpen(samples: over, finalSize: 200) == [
            "overshoot \(10.0) > 6% of delta"
        ])
    }

    @Test func openAcceptsACurveInsideEveryBar() {
        let samples = [sample(0, 100), sample(0.01, 110), sample(0.08, 195), sample(0.20, 206)]
        #expect(SystemHUDWingMotionBox.validateOpen(samples: samples, finalSize: 200) == [])
    }

    @Test func closeNeedsASampleAndADeltaAboveOne() {
        #expect(SystemHUDWingMotionBox.validateClose(samples: [], idle: 100, finalSize: 200) == ["need samples"])
        let flat = [sample(0, 200, opacity: 1)]
        #expect(SystemHUDWingMotionBox.validateClose(samples: flat, idle: 100, finalSize: 101) == [
            "final size must exceed idle"
        ])
    }

    @Test func closeNamesAStartThatIsNotFinalAndAFirstFrameThatShrinksTooFar() {
        let started = [
            sample(0, 150, opacity: 1),
            sample(0.01, 190, opacity: 0.9),
            sample(0.10, 104, opacity: 0.2),
            sample(0.20, 100, opacity: 0),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: started, idle: 100, finalSize: 200) == [
            "close must start at final width"
        ])

        let shrunk = [
            sample(0, 200, opacity: 1),
            sample(0.01, 184, opacity: 0.9),
            sample(0.10, 104, opacity: 0.2),
            sample(0.20, 100, opacity: 0),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: shrunk, idle: 100, finalSize: 200) == [
            "first close frame shrank past 15% in one step"
        ])
    }

    @Test func closeNamesAStepInsideOneFrame() {
        let stepTime = 0.01 + 1.0 / 120.0
        let samples = [
            sample(0, 200, opacity: 1),
            sample(0.01, 190, opacity: 0.9),
            sample(stepTime, 120, opacity: 0.4),
            sample(0.10, 104, opacity: 0.2),
            sample(0.20, 100, opacity: 0),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: samples, idle: 100, finalSize: 200) == [
            "close step at \(stepTime)s delta \(70.0) > 25% final"
        ])
    }

    @Test func closeNamesAMissedSettleALingeringOpacityAndAWidthBelowIdle() {
        let missed = [
            sample(0, 200, opacity: 1),
            sample(0.01, 190, opacity: 0.9),
            sample(0.16, 100, opacity: 0),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: missed, idle: 100, finalSize: 200) == [
            "did not reach 5% expansion within 150 ms on close"
        ])

        let faded = [
            sample(0, 200, opacity: 1),
            sample(0.01, 190, opacity: 0.9),
            sample(0.10, 104, opacity: 0.2),
            sample(0.20, 100, opacity: 0.02),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: faded, idle: 100, finalSize: 200) == [
            "opacity jumped before width on close"
        ])

        let under = [
            sample(0, 200, opacity: 1),
            sample(0.01, 190, opacity: 0.9),
            sample(0.10, 104, opacity: 0.2),
            sample(0.20, 98, opacity: 0),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: under, idle: 100, finalSize: 200) == [
            "width jumped below idle"
        ])
    }

    @Test func closeAcceptsACurveInsideEveryBar() {
        let samples = [
            sample(0, 200, opacity: 1),
            sample(0.01, 190, opacity: 0.9),
            sample(0.15, 105, opacity: 0.05),
            sample(0.30, 100, opacity: 0),
        ]
        #expect(SystemHUDWingMotionBox.validateClose(samples: samples, idle: 100, finalSize: 200) == [])
    }
}
