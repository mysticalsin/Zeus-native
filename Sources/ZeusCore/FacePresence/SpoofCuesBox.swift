// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): Liveness/LivenessCues.swift, GlareCue.swift, LivenessFeatures.swift, DeviceBezelDetector.swift.
import Foundation

/// Spoof scoring as `Float`s, with the crop width as a `Double`. The cues are deny cues only.
/// This type does not read a camera, an image, or a clock.
public enum SpoofCuesBox {
    public enum Cue: String, CaseIterable, Hashable, Sendable {
        case glossGlare
        case deviceBezel
    }

    /// 0 to 1 strength and 0 to 1 trust. A confidence of 0 is an abstention, never a reading of zero.
    public struct Reading: Equatable, Sendable {
        public var level: Float
        public var confidence: Float

        public init(level: Float, confidence: Float) {
            self.level = level
            self.confidence = confidence
        }

        public static let none = Reading(level: 0, confidence: 0)
    }

    /// Three numbers from one face crop. No image is kept.
    public struct Glare: Equatable, Sendable {
        public var cropPixelWidth: Double
        public var specularFraction: Float
        public var specularClusterRatio: Float

        public init(cropPixelWidth: Double, specularFraction: Float, specularClusterRatio: Float) {
            self.cropPixelWidth = cropPixelWidth
            self.specularFraction = specularFraction
            self.specularClusterRatio = specularClusterRatio
        }
    }

    /// What one analyzed frame measured. A field is nil when it could not be measured.
    public struct Frame: Equatable, Sendable {
        public var glare: Glare?
        public var deviceOverlapFraction: Float?

        public init(glare: Glare?, deviceOverlapFraction: Float?) {
            self.glare = glare
            self.deviceOverlapFraction = deviceOverlapFraction
        }
    }

    /// A glare frame counts at or above this level.
    public static let glareLevel: Float = 0.04
    /// A device frame counts at or above this overlap.
    public static let deviceLevel: Float = 0.15

    /// Every cue's reading for one frame.
    public static func readings(_ frame: Frame) -> [Cue: Reading] {
        [.glossGlare: glossGlare(frame), .deviceBezel: deviceBezel(frame)]
    }

    /// The cues that count this frame: confident, and at or above their level.
    public static func counted(in frame: Frame) -> Set<Cue> {
        var result: Set<Cue> = []
        let glare = glossGlare(frame)
        if glare.confidence > 0, glare.level >= glareLevel { result.insert(.glossGlare) }
        let device = deviceBezel(frame)
        if device.confidence > 0, device.level >= deviceLevel { result.insert(.deviceBezel) }
        return result
    }

    /// Scattered shine stays weak. One flat blob scales the bright-pixel fraction up.
    /// Confidence follows the crop width: none at 50 px, full at 130.
    public static func glossGlare(_ frame: Frame) -> Reading {
        guard let glare = frame.glare, glare.specularFraction.isFinite, glare.specularClusterRatio.isFinite,
              glare.cropPixelWidth.isFinite
        else { return .none }
        let fractionScore = ramp(glare.specularFraction, floor: 0.01, ceiling: 0.08)
        let clusterFactor = ramp(glare.specularClusterRatio, floor: 0.3, ceiling: 1.0)
        let level = fractionScore * (0.3 + 0.7 * clusterFactor)
        let confidence = ramp(Float(glare.cropPixelWidth), floor: 50, ceiling: 130)
        return Reading(level: level, confidence: confidence)
    }

    /// The overlap as measured, clamped to 0 to 1, at full confidence. An unreadable value abstains.
    public static func deviceBezel(_ frame: Frame) -> Reading {
        guard let overlap = frame.deviceOverlapFraction, overlap.isFinite else { return .none }
        return Reading(level: min(max(overlap, 0), 1), confidence: 1)
    }

    /// Rolling window over the last analyzed frames. A cue latches when it counted in at least `latchCount`
    /// of them, not necessarily in a row, and clears as those frames age out. One `observe` is one frame.
    public struct Window: Equatable, Sendable {
        public static let size = 6
        public static let latchCount = 3

        private var recent: [Set<Cue>] = []

        public init() {}

        @discardableResult
        public mutating func observe(_ frame: Frame) -> Set<Cue> {
            recent.append(SpoofCuesBox.counted(in: frame))
            if recent.count > Self.size { recent.removeFirst(recent.count - Self.size) }
            return latched
        }

        public var latched: Set<Cue> {
            Set(Cue.allCases.filter { cue in recent.filter { $0.contains(cue) }.count >= Self.latchCount })
        }

        public var isSpoofed: Bool { !latched.isEmpty }

        public mutating func reset() { recent = [] }
    }

    private static func ramp(_ value: Float, floor: Float, ceiling: Float) -> Float {
        min(max((value - floor) / max(ceiling - floor, 0.0001), 0), 1)
    }
}
