import Foundation

/// Pure maths for the "voice glow": a soft, colourful glow along the bottom edge of a view that
/// rises and blooms with the voice, and gathers into a narrow beam that sweeps back and forth
/// while the app is processing. No UI here; `VoiceGlowView` only paints what this describes.

/// A palette colour as plain numbers (0...1), so ZeusCore stays free of SwiftUI.
public struct VoiceGlowRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Colour sets. A palette holds one to seven colours; lobes cycle through them left to right.
public enum VoiceGlowVariant: String, CaseIterable, Sendable {
    case colorful, mono, ocean, sunset, forest, candy, ice, gold

    public static let maxColors = 7

    public var title: String {
        switch self {
        case .colorful: "Colorful"
        case .mono: "Mono"
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .candy: "Candy"
        case .ice: "Ice"
        case .gold: "Gold"
        }
    }

    public var palette: [VoiceGlowRGB] {
        let hexes: [UInt32]
        switch self {
        case .colorful: hexes = [0x8B5CF6, 0x6366F1, 0x3B82F6, 0x22D3EE, 0x34D399, 0xF472B6, 0xFB923C]
        case .mono: hexes = [0xF5F5F7, 0xC7CAD1, 0xE4E6EB]
        case .ocean: hexes = [0x0EA5E9, 0x06B6D4, 0x2563EB, 0x14B8A6, 0x38BDF8]
        case .sunset: hexes = [0xF97316, 0xEF4444, 0xEC4899, 0xA855F7, 0xFBBF24, 0xFB7185]
        case .forest: hexes = [0x22C55E, 0x16A34A, 0x84CC16, 0x10B981, 0x65A30D]
        case .candy: hexes = [0xF472B6, 0xC084FC, 0x60A5FA, 0x5EEAD4, 0xFDE68A, 0xFCA5A5, 0xA5B4FC]
        case .ice: hexes = [0xE0F2FE, 0xBAE6FD, 0xA5F3FC, 0xC7D2FE]
        case .gold: hexes = [0xFBBF24, 0xF59E0B, 0xFDE68A, 0xD97706, 0xFCD34D]
        }
        return hexes.map(VoiceGlowRGB.init(hex:))
    }

    /// Unknown or missing stored values fall back to `.colorful`.
    public static func resolve(_ raw: String?) -> VoiceGlowVariant {
        raw.flatMap(VoiceGlowVariant.init(rawValue:)) ?? .colorful
    }

    /// The colours to draw: custom colours (first seven) when given, else this variant's palette.
    public static func colors(variant: VoiceGlowVariant, custom: [VoiceGlowRGB] = []) -> [VoiceGlowRGB] {
        custom.isEmpty ? variant.palette : Array(custom.prefix(maxColors))
    }
}

/// The input chain: gain, gate, then an attack/release smoother.
public struct VoiceGlowInput: Equatable, Sendable {
    /// Gain applied to the raw 0...1 level before the gate.
    public var sensitivity: Double
    /// Level (after gain) below which the glow stays at rest.
    public var threshold: Double
    /// Seconds to rise about 63% of the way to a louder level.
    public var attack: Double
    /// Seconds to fall about 63% of the way to a quieter level.
    public var release: Double

    public init(sensitivity: Double = 1.6, threshold: Double = 0.04, attack: Double = 0.05, release: Double = 0.28) {
        self.sensitivity = sensitivity
        self.threshold = threshold
        self.attack = attack
        self.release = release
    }

    public static let standard = VoiceGlowInput()

    /// Gain, then gate: 0 at or under the threshold, rescaled to reach 1 at full gain.
    public func gated(_ level: Double) -> Double {
        guard level.isFinite else { return 0 }
        let amplified = max(0, level) * max(0, sensitivity)
        let gate = min(max(threshold, 0), 0.99)
        guard amplified > gate else { return 0 }
        return min(1, (amplified - gate) / (1 - gate))
    }
}

/// The per-frame smoother: fast attack, slow release, frame-rate independent.
public struct VoiceGlowEnvelope: Equatable, Sendable {
    public var input: VoiceGlowInput
    public private(set) var value: Double = 0

    public init(input: VoiceGlowInput = .standard) {
        self.input = input
    }

    @discardableResult
    public mutating func step(level: Double, dt: Double) -> Double {
        guard dt.isFinite, dt > 0 else { return value }
        let target = input.gated(level)
        let tau = target > value ? input.attack : input.release
        let alpha = tau <= 0 ? 1 : 1 - exp(-min(dt, 0.25) / tau)
        value += (target - value) * alpha
        value = min(1, max(0, value))
        return value
    }

    public mutating func reset() { value = 0 }
}

/// Shape parameters. Distances are points; the rest are fractions or rates.
public struct VoiceGlowGeometry: Equatable, Sendable {
    /// Tallest the glow rises from the bottom edge, in points.
    public var reach: Double
    /// Share of the edge width the lobes spread over, 0...1.
    public var spread: Double
    /// How fast the lobes drift and breathe (cycles per second).
    public var flow: Double
    /// 0 = lobes all the same height, 1 = outer lobes fall away strongly (a bowed, centred glow).
    public var bend: Double
    /// Resting glow while silent, 0...1 of reach.
    public var idle: Double
    /// Soft blur radius in points.
    public var blur: Double
    /// Number of lobes along the edge.
    public var lobeCount: Int
    /// Width of the processing beam as a fraction of the edge.
    public var beamWidth: Double
    /// Height of the processing beam, 0...1 of reach.
    public var beamHeight: Double
    /// Seconds for the beam to travel out and back.
    public var beamPeriod: Double

    public init(reach: Double, spread: Double, flow: Double, bend: Double, idle: Double, blur: Double,
                lobeCount: Int, beamWidth: Double, beamHeight: Double, beamPeriod: Double) {
        self.reach = reach
        self.spread = spread
        self.flow = flow
        self.bend = bend
        self.idle = idle
        self.blur = blur
        self.lobeCount = lobeCount
        self.beamWidth = beamWidth
        self.beamHeight = beamHeight
        self.beamPeriod = beamPeriod
    }

    /// About a 350 pt wide chat input.
    public static let `default` = VoiceGlowGeometry(reach: 70, spread: 0.82, flow: 0.3, bend: 0.55, idle: 0.14, blur: 18,
                                                    lobeCount: 7, beamWidth: 0.22, beamHeight: 0.7, beamPeriod: 2.4)
    /// About 150x44, and the 292x48 recorder pill: the glow stays inside the pill's height.
    public static let pill = VoiceGlowGeometry(reach: 22, spread: 0.9, flow: 0.45, bend: 0.35, idle: 0.2, blur: 7,
                                               lobeCount: 7, beamWidth: 0.3, beamHeight: 0.8, beamPeriod: 1.8)
    public static let mobile = VoiceGlowGeometry(reach: 46, spread: 0.95, flow: 0.35, bend: 0.5, idle: 0.16, blur: 12,
                                                 lobeCount: 5, beamWidth: 0.3, beamHeight: 0.7, beamPeriod: 2.0)

    /// Level drawn (0...1 of reach) when Reduce Motion asks for a still, low glow.
    public var reducedMotionLevel: Double { min(0.35, max(idle, 0.2)) }
}

/// One soft lobe, ready to paint as an ellipse standing on the bottom edge.
public struct VoiceGlowLobe: Equatable, Sendable {
    /// Horizontal centre, 0...1 along the edge.
    public var center: Double
    /// Half width as a fraction of the edge.
    public var halfWidth: Double
    /// Height, 0...1 of the geometry's reach.
    public var height: Double
    public var colorIndex: Int
}

/// The glow's state: the envelope, the beam gather and the clocks. Step it once per frame.
public struct VoiceGlowModel: Equatable, Sendable {
    public var geometry: VoiceGlowGeometry
    public private(set) var envelope: VoiceGlowEnvelope
    /// 0 = voice lobes, 1 = a single narrow beam.
    public private(set) var gather = 0.0
    public private(set) var clock = 0.0
    public private(set) var beamClock = 0.0
    public private(set) var reduceMotion = false

    /// Seconds for the lobes to gather into the beam (and spread back out).
    public static let gatherTime = 0.35

    public init(geometry: VoiceGlowGeometry = .default, input: VoiceGlowInput = .standard) {
        self.geometry = geometry
        self.envelope = VoiceGlowEnvelope(input: input)
    }

    public var input: VoiceGlowInput {
        get { envelope.input }
        set { envelope.input = newValue }
    }

    /// Smoothed level mapped over the resting glow, 0...1 of reach.
    public var drive: Double {
        if reduceMotion { return geometry.reducedMotionLevel }
        let idle = min(1, max(0, geometry.idle))
        return idle + (1 - idle) * envelope.value
    }

    public static func clampStrength(_ strength: Double) -> Double {
        strength.isFinite ? min(1, max(0, strength)) : 1
    }

    /// Advances one frame. Reduce Motion freezes everything at a static low glow: no envelope,
    /// no drift, no beam travel.
    public mutating func step(level: Double, processing: Bool, dt: Double, reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
        if reduceMotion {
            envelope.reset()
            gather = 0
            clock = 0
            beamClock = 0
            return
        }
        let dt = dt.isFinite ? min(max(dt, 0), 0.1) : 0
        envelope.step(level: level, dt: dt)
        clock += dt
        let alpha = 1 - exp(-dt / Self.gatherTime)
        gather += ((processing ? 1 : 0) - gather) * alpha
        if processing {
            beamClock += dt
        } else if gather < 0.002 {
            gather = 0
            beamClock = 0
        }
    }

    /// Beam centre, 0...1 along the edge: a smooth sweep out and back that starts in the middle and
    /// never lets the beam cross either end.
    public static func beamPosition(clock: Double, period: Double, halfWidth: Double) -> Double {
        let margin = min(0.45, max(0, halfWidth))
        guard clock.isFinite, period > 0 else { return 0.5 }
        let swing = 0.5 + 0.5 * sin(2 * Double.pi * clock / period)
        return margin + (1 - 2 * margin) * swing
    }

    public var beamPosition: Double {
        Self.beamPosition(clock: beamClock, period: geometry.beamPeriod, halfWidth: geometry.beamWidth / 2)
    }

    /// The lobes to paint now. Colours cycle through `paletteCount` entries.
    public func lobes(paletteCount: Int) -> [VoiceGlowLobe] {
        let count = min(max(geometry.lobeCount, 1), 16)
        let colors = max(paletteCount, 1)
        let spread = min(1, max(0.1, geometry.spread))
        let bend = min(1, max(0, geometry.bend))
        let drive = self.drive
        let blend = gather * gather * (3 - 2 * gather)
        let beamHalf = min(0.5, max(0.02, geometry.beamWidth / 2))
        let beamCenter = beamPosition
        let beamHeight = min(1, max(0, geometry.beamHeight))
        let motion = reduceMotion ? 0.0 : 1.0

        return (0..<count).map { index in
            let offset = count == 1 ? 0 : Double(index) / Double(count - 1) * 2 - 1
            let spacing = spread / Double(count)
            let phase = clock * 2 * Double.pi * geometry.flow
            let drift = motion * sin(phase + Double(index) * 1.9) * spacing * 0.35
            let breathe = 1 - motion * 0.2 * (0.5 - 0.5 * sin(phase * 1.7 + Double(index) * 2.3))

            let voiceCenter = 0.5 + offset * spread / 2 + drift
            let voiceHalf = min(0.5, max(spacing * 1.6, 0.06) * (0.8 + 0.6 * drive))
            let voiceHeight = drive * (1 - bend * offset * offset) * breathe

            let beamLobeCenter = beamCenter + offset * beamHalf * 0.6
            let beamLobeHalf = beamHalf * 0.7
            let beamLobeHeight = beamHeight * (1 - 0.35 * offset * offset)

            return VoiceGlowLobe(
                center: min(1, max(0, voiceCenter + (beamLobeCenter - voiceCenter) * blend)),
                halfWidth: min(0.5, max(0, voiceHalf + (beamLobeHalf - voiceHalf) * blend)),
                height: min(1, max(0, voiceHeight + (beamLobeHeight - voiceHeight) * blend)),
                colorIndex: index % colors)
        }
    }
}
