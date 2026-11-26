// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): Liveness/LivenessCues.swift, GlareCue.swift, LivenessFeatures.swift, DeviceBezelDetector.swift.
import CoreGraphics

/// The two things that make a frame look like a photo or a screen instead of a person. They are deny cues
/// only: firing pushes a match toward absent, and there is no cue that can argue for a real face.
public enum SpoofCue: String, CaseIterable, Hashable, Sendable {
    /// A large flat specular highlight, as from glass or a screen, rather than the small scattered shine of skin.
    case glossGlare
    /// A phone or tablet shaped rectangle around the face.
    case deviceBezel
}

/// One cue's reading of one frame. A confidence of 0 is always an abstention, never a reading of zero: a cue
/// that cannot see anything must not be able to convict or acquit.
public struct CueReading: Equatable, Sendable {
    /// 0 to 1 strength of the evidence of a spoof.
    public let level: Float
    /// 0 to 1 trust in that evidence. 0 means the frame is ignored by this cue.
    public let confidence: Float

    public init(level: Float, confidence: Float) {
        self.level = level
        self.confidence = confidence
    }

    public static let none = CueReading(level: 0, confidence: 0)
}

/// Pixel statistics of one face crop, measured by the Vision side. No image is kept; these are three numbers.
public struct GlareSample: Equatable, Sendable {
    /// Native pixel width of the measured crop. Only ever downsampled, so it is an honest measure of detail.
    public let cropPixelWidth: CGFloat
    /// Fraction of crop pixels that are near saturated and low in colour: direct specular reflection.
    public let specularFraction: Float
    /// How concentrated those pixels are in one region (the densest cell's share of them), as against scattered.
    public let specularClusterRatio: Float

    public init(cropPixelWidth: CGFloat, specularFraction: Float, specularClusterRatio: Float) {
        self.cropPixelWidth = cropPixelWidth
        self.specularFraction = specularFraction
        self.specularClusterRatio = specularClusterRatio
    }
}

/// What the Vision side measured on one analyzed frame. A field is nil when it could not be measured.
public struct SpoofFrame: Equatable, Sendable {
    public let glare: GlareSample?
    /// Fraction of the face box that falls inside the largest device shaped rectangle in the frame.
    public let deviceOverlapFraction: Float?

    public init(glare: GlareSample?, deviceOverlapFraction: Float?) {
        self.glare = glare
        self.deviceOverlapFraction = deviceOverlapFraction
    }
}

/// Pure spoof rules: readings per frame, and a rolling window that latches a cue seen often enough.
/// The arithmetic lives in `SpoofCuesBox`.
public enum SpoofCues {
    /// A glare frame counts at or above this level. Seeded from Glance's real device observation.
    public static let glareLevel: Float = SpoofCuesBox.glareLevel
    /// A device frame counts at or above this overlap, lower than the glare level because the rectangle
    /// detector was the more reliable signal in Glance's device tests.
    public static let deviceLevel: Float = SpoofCuesBox.deviceLevel

    /// Every cue's reading for one frame.
    public static func readings(_ frame: SpoofFrame) -> [SpoofCue: CueReading] {
        Dictionary(uniqueKeysWithValues: SpoofCuesBox.readings(boxFrame(frame)).map { cue, reading in
            (spoofCue(cue), cueReading(reading))
        })
    }

    /// The cues that count this frame: confident, and at or above their level.
    public static func counted(in frame: SpoofFrame) -> Set<SpoofCue> {
        Set(SpoofCuesBox.counted(in: boxFrame(frame)).map(spoofCue))
    }

    /// Skin gives many small scattered specular points; glass gives one big flat blob. The bright pixel fraction
    /// alone would fire on a shiny forehead, so how concentrated the glare is scales it. Confidence follows the
    /// crop width: under 50 px there is too little detail to tell a blob from a bright patch, full trust at 130.
    public static func glossGlare(_ frame: SpoofFrame) -> CueReading {
        cueReading(SpoofCuesBox.glossGlare(boxFrame(frame)))
    }

    /// The overlap as measured, clamped to 0 to 1, at full confidence. An unreadable value abstains.
    public static func deviceBezel(_ frame: SpoofFrame) -> CueReading {
        cueReading(SpoofCuesBox.deviceBezel(boxFrame(frame)))
    }

    /// Rolling window over the last analyzed frames. A cue latches when it counted in at least `latchCount` of
    /// them, not necessarily in a row, and clears as those frames age out. No clock: one `observe` is one frame.
    public struct Window: Equatable, Sendable {
        /// Frames kept.
        public static let size = SpoofCuesBox.Window.size
        /// Counted frames of one cue that latch it.
        public static let latchCount = SpoofCuesBox.Window.latchCount

        private var box = SpoofCuesBox.Window()

        public init() {}

        /// Adds one analyzed frame and returns the cues latched afterwards.
        @discardableResult
        public mutating func observe(_ frame: SpoofFrame) -> Set<SpoofCue> {
            Set(box.observe(SpoofCues.boxFrame(frame)).map(SpoofCues.spoofCue))
        }

        /// The cues counted in at least `latchCount` of the kept frames.
        public var latched: Set<SpoofCue> {
            Set(box.latched.map(SpoofCues.spoofCue))
        }

        /// True when any cue is latched.
        public var isSpoofed: Bool { box.isSpoofed }

        /// Forgets every frame, for a new watch or a new enrollment.
        public mutating func reset() { box.reset() }
    }

    private static func boxFrame(_ frame: SpoofFrame) -> SpoofCuesBox.Frame {
        SpoofCuesBox.Frame(
            glare: frame.glare.map {
                SpoofCuesBox.Glare(cropPixelWidth: Double($0.cropPixelWidth),
                                   specularFraction: $0.specularFraction,
                                   specularClusterRatio: $0.specularClusterRatio)
            },
            deviceOverlapFraction: frame.deviceOverlapFraction)
    }

    private static func cueReading(_ reading: SpoofCuesBox.Reading) -> CueReading {
        CueReading(level: reading.level, confidence: reading.confidence)
    }

    private static func spoofCue(_ cue: SpoofCuesBox.Cue) -> SpoofCue {
        switch cue {
        case .glossGlare: .glossGlare
        case .deviceBezel: .deviceBezel
        }
    }
}
