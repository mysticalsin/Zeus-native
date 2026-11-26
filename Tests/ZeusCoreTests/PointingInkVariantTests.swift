import Testing
@testable import ZeusCore

/// Phase 2 ink and listen-marker variants (docs/POINTING-ASSISTANT-PLAN.md).
/// Reduce Motion holds the ring still: no spring. Reduce Transparency drops the
/// translucent halo and the ring glow. The numbers are the ink `MarkOverlay`
/// already draws and the companion spring the marker already follows.
@Suite("Pointing ink variants")
struct PointingInkVariantTests {
    @Test func theDefaultMarkerUsesTheCompanionSpringAndRestsAtTheCompanionGlow() {
        let appearance = PointingInkVariant.resolve(reduceMotion: false, reduceTransparency: false)
        #expect(appearance.marker.motion == .spring(response: 0.2, damping: 0.6))
        #expect(appearance.marker.ringWidth == 2)
        #expect(appearance.marker.ringOpacity == 1)
        #expect(appearance.marker.glowRadius == 8)
        #expect(appearance.marker.glowPulses)
        #expect(appearance.marker.glowPeak == 14)
    }

    @Test func theDefaultStrokeMatchesTheOverlayHaloAndCore() {
        let stroke = PointingInkVariant.resolve(reduceMotion: false, reduceTransparency: false).stroke
        #expect(stroke.haloOpacity == 0.35)
        #expect(stroke.haloWidth == 12)
        #expect(stroke.coreOpacity == 1)
        #expect(stroke.coreWidth == 4)
        #expect(stroke.haloWidth > stroke.coreWidth)
        #expect(stroke.haloOpacity < stroke.coreOpacity)
    }

    @Test func theDefaultTrailMatchesTheOverlayFade() {
        let tail = PointingInkVariant.trail(place: 0, reduceMotion: false, reduceTransparency: false)
        let mid = PointingInkVariant.trail(place: 0.5, reduceMotion: false, reduceTransparency: false)
        let head = PointingInkVariant.trail(place: 1, reduceMotion: false, reduceTransparency: false)
        #expect(tail.opacity == 0.15 + 0.75 * 0)
        #expect(tail.width == 2 + 4 * 0)
        #expect(mid.opacity == 0.15 + 0.75 * 0.5)
        #expect(mid.width == 2 + 4 * 0.5)
        #expect(head.opacity == 0.15 + 0.75 * 1)
        #expect(head.width == 2 + 4 * 1)
        #expect(tail.opacity < mid.opacity && mid.opacity < head.opacity)
        #expect(tail.width < mid.width && mid.width < head.width)
    }

    @Test func reduceMotionHoldsTheMarkerStillAndStopsTheGlowPulse() {
        let appearance = PointingInkVariant.resolve(reduceMotion: true, reduceTransparency: false)
        #expect(appearance.marker.motion == .still)
        if case .spring = appearance.marker.motion {
            Issue.record("Reduce Motion kept a spring on the listen ring")
        }
        #expect(appearance.marker.glowPulses == false)
        #expect(appearance.marker.glowRadius == 8)
        #expect(appearance.marker.glowPeak == appearance.marker.glowRadius)
        #expect(appearance.marker.glowPeak != 14)
        #expect(appearance.marker.ringWidth == 2)
        #expect(appearance.marker.ringOpacity == 1)
    }

    @Test func reduceMotionKeepsTheTranslucentHalo() {
        let stroke = PointingInkVariant.resolve(reduceMotion: true, reduceTransparency: false).stroke
        #expect(stroke.haloOpacity == 0.35)
        #expect(stroke.haloWidth == 12)
        #expect(stroke.coreOpacity == 1)
        #expect(stroke.coreWidth == 4)
    }

    @Test func reduceMotionHoldsTheTrailAtTheHead() {
        let tail = PointingInkVariant.trail(place: 0, reduceMotion: true, reduceTransparency: false)
        let head = PointingInkVariant.trail(place: 1, reduceMotion: true, reduceTransparency: false)
        let headInk = 0.15 + 0.75 * 1
        let headWidth = 2.0 + 4.0 * 1
        #expect(tail.opacity == headInk)
        #expect(head.opacity == headInk)
        #expect(tail.width == headWidth)
        #expect(head.width == headWidth)
        #expect(tail == head)
    }

    @Test func reduceTransparencyDropsTheHaloAndTheGlowButKeepsTheSpring() {
        let appearance = PointingInkVariant.resolve(reduceMotion: false, reduceTransparency: true)
        #expect(appearance.marker.motion == .spring(response: 0.2, damping: 0.6))
        #expect(appearance.marker.glowRadius == 0)
        #expect(appearance.marker.glowPeak == 0)
        #expect(appearance.marker.glowPulses == false)
        #expect(appearance.marker.ringWidth == 2)
        #expect(appearance.marker.ringOpacity == 1)
        #expect(appearance.stroke.haloOpacity == 0)
        #expect(appearance.stroke.haloWidth == 0)
        #expect(appearance.stroke.coreOpacity == 1)
        #expect(appearance.stroke.coreWidth == 4)
    }

    @Test func reduceTransparencyMakesTheTrailOpaqueAndUniform() {
        let places = [0.0, 0.25, 1.0]
        let samples = places.map {
            PointingInkVariant.trail(place: $0, reduceMotion: false, reduceTransparency: true)
        }
        #expect(samples.allSatisfy { $0.opacity == 1 && $0.width == 4 })
        #expect(Set(samples).count == 1)
    }

    @Test func bothPreferencesHoldStillAndDrawOpaqueInk() {
        let appearance = PointingInkVariant.resolve(reduceMotion: true, reduceTransparency: true)
        #expect(appearance.marker.motion == .still)
        #expect(appearance.marker.glowRadius == 0)
        #expect(appearance.marker.glowPeak == 0)
        #expect(appearance.marker.glowPulses == false)
        #expect(appearance.marker.ringOpacity == 1)
        #expect(appearance.marker.ringWidth == 2)
        #expect(appearance.stroke.haloOpacity == 0)
        #expect(appearance.stroke.haloWidth == 0)
        #expect(appearance.stroke.coreOpacity == 1)
        #expect(appearance.stroke.coreWidth == 4)
        let trail = PointingInkVariant.trail(place: 0.2, reduceMotion: true, reduceTransparency: true)
        #expect(trail.opacity == 1)
        #expect(trail.width == 4)
        let other = PointingInkVariant.trail(place: 0.8, reduceMotion: true, reduceTransparency: true)
        #expect(trail == other)
    }

    @Test func theSameFactsResolveTheSameAppearance() {
        let first = PointingInkVariant.resolve(reduceMotion: false, reduceTransparency: true)
        let second = PointingInkVariant.resolve(reduceMotion: false, reduceTransparency: true)
        #expect(first == second)
        let moving = PointingInkVariant.resolve(reduceMotion: false, reduceTransparency: false)
        #expect(first != moving)
    }

    @Test func aNonFiniteTrailPlaceDoesNotProduceANonFiniteSample() {
        for place in [Double.nan, Double.infinity, -Double.infinity] {
            let tapered = PointingInkVariant.trail(place: place, reduceMotion: false, reduceTransparency: false)
            #expect(tapered.opacity.isFinite)
            #expect(tapered.width.isFinite)
            #expect(tapered.opacity == 0.15 + 0.75 * 0)
            #expect(tapered.width == 2 + 4 * 0)
            let still = PointingInkVariant.trail(place: place, reduceMotion: true, reduceTransparency: false)
            #expect(still.opacity.isFinite && still.width.isFinite)
            #expect(still.opacity == 0.15 + 0.75 * 1)
            let opaque = PointingInkVariant.trail(place: place, reduceMotion: true, reduceTransparency: true)
            #expect(opaque.opacity == 1 && opaque.width == 4)
        }
    }

    @Test func aTrailPlaceOutsideZeroToOneIsClamped() {
        let below = PointingInkVariant.trail(place: -2, reduceMotion: false, reduceTransparency: false)
        let above = PointingInkVariant.trail(place: 3, reduceMotion: false, reduceTransparency: false)
        let tail = PointingInkVariant.trail(place: 0, reduceMotion: false, reduceTransparency: false)
        let head = PointingInkVariant.trail(place: 1, reduceMotion: false, reduceTransparency: false)
        #expect(below == tail)
        #expect(above == head)
    }

    @Test func everyVariantKeepsTheRingVisible() {
        let flags = [(false, false), (true, false), (false, true), (true, true)]
        for (motion, transparency) in flags {
            let marker = PointingInkVariant.resolve(reduceMotion: motion, reduceTransparency: transparency).marker
            #expect(marker.ringOpacity == 1)
            #expect(marker.ringWidth == 2)
            #expect(marker.ringOpacity.isFinite && marker.ringWidth.isFinite)
        }
    }
}
