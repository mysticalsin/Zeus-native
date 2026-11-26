import Foundation

/// How the pointing listen marker and its ink draw for one combination of
/// Reduce Motion and Reduce Transparency.
///
/// The plan asks for a static ring with no spring under Reduce Motion, and for
/// Reduce Transparency variants of the marker and the ink. The caller passes
/// those two facts. This type does not read the system settings and does not draw.
///
/// The stroke and trail numbers are the ink `MarkOverlay` already paints: a 12 pt
/// halo at 35% under a 4 pt opaque core, and a cursor trail of
/// `0.15 + 0.75 * fade` by `2 + 4 * fade`. The spring is `CompanionSpring`
/// (response 0.2 s, damping 0.6). The glow rest and peak are `CompanionFlight`
/// (8 and 14). The ring stroke is the 2 pt line in `BuddyOverlayView`.
public enum PointingInkVariant {
    /// `CompanionSpring.response` and `CompanionSpring.damping`.
    public static let markerSpringResponse = 0.2
    public static let markerSpringDamping = 0.6
    /// Ring stroke width in `BuddyOverlayView`.
    public static let markerRingWidth = 2.0
    public static let markerRingOpacity = 1.0
    /// `CompanionFlight.glowRest` and `CompanionFlight.glowPeak`.
    public static let markerGlowRest = 8.0
    public static let markerGlowPeak = 14.0
    /// Halo under the pointing stroke in `MarkOverlay`.
    public static let strokeHaloOpacity = 0.35
    public static let strokeHaloWidth = 12.0
    /// Opaque core of the pointing stroke in `MarkOverlay`.
    public static let strokeCoreOpacity = 1.0
    public static let strokeCoreWidth = 4.0
    /// Cursor-trail fade in `MarkOverlay`: opacity `base + gain * fade`, width the same way.
    public static let trailBaseOpacity = 0.15
    public static let trailOpacityGain = 0.75
    public static let trailBaseWidth = 2.0
    public static let trailWidthGain = 4.0

    public struct Appearance: Equatable, Sendable {
        public var marker: Marker
        public var stroke: Stroke

        public init(marker: Marker, stroke: Stroke) {
            self.marker = marker
            self.stroke = stroke
        }
    }

    public enum MarkerMotion: Equatable, Sendable {
        /// The listen ring holds still. No spring.
        case still
        /// Response is seconds. Damping is a fraction, 1 being critically damped.
        case spring(response: Double, damping: Double)
    }

    public struct Marker: Equatable, Sendable {
        public var motion: MarkerMotion
        public var ringWidth: Double
        public var ringOpacity: Double
        /// 0 when Reduce Transparency is on. Otherwise the resting glow.
        public var glowRadius: Double
        /// True only when the glow may travel from rest to peak.
        public var glowPulses: Bool
        /// Equal to `glowRadius` when the glow does not pulse.
        public var glowPeak: Double

        public init(motion: MarkerMotion, ringWidth: Double, ringOpacity: Double,
                    glowRadius: Double, glowPulses: Bool, glowPeak: Double) {
            self.motion = motion
            self.ringWidth = ringWidth
            self.ringOpacity = ringOpacity
            self.glowRadius = glowRadius
            self.glowPulses = glowPulses
            self.glowPeak = glowPeak
        }
    }

    public struct Stroke: Equatable, Sendable {
        public var coreOpacity: Double
        public var coreWidth: Double
        public var haloOpacity: Double
        public var haloWidth: Double

        public init(coreOpacity: Double, coreWidth: Double, haloOpacity: Double, haloWidth: Double) {
            self.coreOpacity = coreOpacity
            self.coreWidth = coreWidth
            self.haloOpacity = haloOpacity
            self.haloWidth = haloWidth
        }
    }

    /// One place on the cursor trail. `place` 0 is the tail and 1 is the head.
    public struct TrailSample: Equatable, Hashable, Sendable {
        public var opacity: Double
        public var width: Double

        public init(opacity: Double, width: Double) {
            self.opacity = opacity
            self.width = width
        }
    }

    public static func resolve(reduceMotion: Bool, reduceTransparency: Bool) -> Appearance {
        let motion: MarkerMotion = reduceMotion
            ? .still
            : .spring(response: markerSpringResponse, damping: markerSpringDamping)
        let glow = reduceTransparency ? 0 : markerGlowRest
        let pulses = !reduceMotion && !reduceTransparency
        let peak = pulses ? markerGlowPeak : glow
        let haloOpacity = reduceTransparency ? 0 : strokeHaloOpacity
        let haloWidth = reduceTransparency ? 0 : strokeHaloWidth
        return Appearance(
            marker: Marker(motion: motion, ringWidth: markerRingWidth, ringOpacity: markerRingOpacity,
                           glowRadius: glow, glowPulses: pulses, glowPeak: peak),
            stroke: Stroke(coreOpacity: strokeCoreOpacity, coreWidth: strokeCoreWidth,
                           haloOpacity: haloOpacity, haloWidth: haloWidth)
        )
    }

    /// `place` runs from 0 at the tail to 1 at the head. A non-finite place is the tail
    /// when the trail tapers. Reduce Transparency draws the opaque core at every place.
    /// Reduce Motion holds the head of the taper at every place, so the line does not fade.
    public static func trail(place: Double, reduceMotion: Bool, reduceTransparency: Bool) -> TrailSample {
        if reduceTransparency {
            return TrailSample(opacity: strokeCoreOpacity, width: strokeCoreWidth)
        }
        if reduceMotion {
            return TrailSample(opacity: taperedOpacity(1), width: taperedWidth(1))
        }
        let fade = finitePlace(place)
        return TrailSample(opacity: taperedOpacity(fade), width: taperedWidth(fade))
    }

    private static func finitePlace(_ place: Double) -> Double {
        guard place.isFinite else { return 0 }
        return min(max(place, 0), 1)
    }

    private static func taperedOpacity(_ fade: Double) -> Double {
        trailBaseOpacity + trailOpacityGain * fade
    }

    private static func taperedWidth(_ fade: Double) -> Double {
        trailBaseWidth + trailWidthGain * fade
    }
}
