import Foundation

/// Which art stands for ZEUS's voice orb. Stored in UserDefaults under `defaultsKey`.
public enum VoiceOrbStyle: String, CaseIterable, Sendable {
    case mascot, ring, mono

    public static let defaultsKey = "voice.orbStyle"

    public var title: String {
        switch self {
        case .mascot: "Mascot"
        case .ring: "Ring"
        case .mono: "Mono ring"
        }
    }

    /// Anything unknown or missing is the mascot.
    public static func resolve(_ raw: String?) -> VoiceOrbStyle {
        raw.flatMap(VoiceOrbStyle.init(rawValue:)) ?? .mascot
    }
}

/// The two drawings: a glassy ribbon with a spectrum, or two loops of grey tube a voice opens into a globe.
public enum VoiceRingType: String, CaseIterable, Sendable {
    case ring, mono
}

public enum VoiceRingState: String, CaseIterable, Sendable {
    case idle, listening, speaking, processing
}

/// Tints the spectrum. nil (no emotion) is Zeus's own purple, blue, teal and pink.
public enum VoiceRingEmotion: String, CaseIterable, Sendable {
    case positive, negative, calm
}

public struct VoiceRingPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct VoiceRingRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
}

/// Where a pointer near the rim pulls it: `amount` 0...1, `angle` toward the pointer (radians).
public struct VoiceRingHover: Equatable, Sendable {
    public var amount: Double
    public var angle: Double
    public init(amount: Double, angle: Double) { self.amount = amount; self.angle = angle }
}

/// How much of each state is showing. Always sums to 1; moves linearly, `eased` is what is drawn.
public struct VoiceRingWeights: Equatable, Sendable {
    public var idle: Double
    public var listening: Double
    public var speaking: Double
    public var processing: Double

    public init(idle: Double = 0, listening: Double = 0, speaking: Double = 0, processing: Double = 0) {
        self.idle = idle; self.listening = listening; self.speaking = speaking; self.processing = processing
    }

    public static func pure(_ state: VoiceRingState) -> VoiceRingWeights {
        var weights = VoiceRingWeights()
        weights[state] = 1
        return weights
    }

    public subscript(state: VoiceRingState) -> Double {
        get {
            switch state {
            case .idle: idle
            case .listening: listening
            case .speaking: speaking
            case .processing: processing
            }
        }
        set {
            switch state {
            case .idle: idle = newValue
            case .listening: listening = newValue
            case .speaking: speaking = newValue
            case .processing: processing = newValue
            }
        }
    }

    /// The share of the calm states, where a pointer bends the rim.
    public var calm: Double { idle + processing }

    public var normalized: VoiceRingWeights {
        let sum = idle + listening + speaking + processing
        guard sum > 0.000_001 else { return .pure(.idle) }
        return VoiceRingWeights(idle: idle / sum, listening: listening / sum, speaking: speaking / sum, processing: processing / sum)
    }

    /// Smoothstep on each weight, so a change of state starts and ends gently.
    public var eased: VoiceRingWeights {
        func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
        return VoiceRingWeights(idle: smooth(idle), listening: smooth(listening),
                                speaking: smooth(speaking), processing: smooth(processing)).normalized
    }

    /// Moves toward `target`, finishing a full change in `duration` seconds.
    public mutating func advance(toward target: VoiceRingState, dt: Double, duration: Double = 0.5) {
        let step = duration <= 0 ? 1 : max(0, dt) / duration
        for state in VoiceRingState.allCases {
            let goal: Double = state == target ? 1 : 0
            let current = self[state]
            self[state] = current < goal ? min(goal, current + step) : max(goal, current - step)
        }
        self = normalized
    }
}

/// Everything the geometry needs for one frame. `weights` are the weights as drawn (eased).
public struct VoiceRingInput: Equatable, Sendable {
    public var time: Double
    public var level: Double
    public var weights: VoiceRingWeights
    public var lean: Double
    public var bend: Double
    public var bendAngle: Double

    public init(time: Double = 0, level: Double = 0, weights: VoiceRingWeights = .pure(.idle),
                lean: Double = 0, bend: Double = 0, bendAngle: Double = 0) {
        self.time = time
        self.level = min(1, max(0, level))
        self.weights = weights.normalized
        self.lean = min(1, max(-1, lean))
        self.bend = min(1, max(0, bend))
        self.bendAngle = bendAngle
    }

    /// A state held still: no time, no level (Reduce Motion).
    public static func still(_ state: VoiceRingState, lean: Double = 0) -> VoiceRingInput {
        VoiceRingInput(weights: .pure(state), lean: lean)
    }
}

public struct VoiceRingRibbonSample: Equatable, Sendable {
    public var angle: Double
    public var center: VoiceRingPoint
    public var outer: VoiceRingPoint
    public var inner: VoiceRingPoint
}

/// Pure ring maths. Coordinates are unit space: the drawing circle is radius 1, y grows downward
/// (screen space), angle 0 points right. Nothing here reads a clock or draws.
public enum VoiceRingModel {
    /// The level gain that counts as 1: sensitivity 0.85 (the default) passes the level through.
    public static let referenceSensitivity = 0.85
    public static let defaultSensitivity = 0.85
    /// Where the rim sits, and how far from it a pointer still bends it.
    public static let hoverRim = 0.62
    public static let hoverReach = 0.4

    static let leanReach = 0.05
    static let leanShift = 0.03
    static let bendReach = 0.07

    struct Shape {
        let radius: Double
        let thickness: Double
        let amplitude: Double
        let levelGain: Double
        let lobes: Int
        let spin: Double
        /// How fast the shared clock runs in this state.
        let rate: Double
    }

    static func shape(_ state: VoiceRingState) -> Shape {
        switch state {
        case .idle: Shape(radius: 0.62, thickness: 0.060, amplitude: 0.012, levelGain: 0, lobes: 3, spin: 0.25, rate: 1)
        case .listening: Shape(radius: 0.60, thickness: 0.070, amplitude: 0.020, levelGain: 0.08, lobes: 5, spin: 0.5, rate: 1.4)
        case .speaking: Shape(radius: 0.58, thickness: 0.080, amplitude: 0.030, levelGain: 0.12, lobes: 6, spin: 0.8, rate: 1.8)
        case .processing: Shape(radius: 0.62, thickness: 0.055, amplitude: 0.010, levelGain: 0, lobes: 4, spin: 1.6, rate: 2.6)
        }
    }

    // MARK: Level

    public static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// The mic level scaled by sensitivity (0.85 is unity), kept in 0...1.
    public static func shapedLevel(raw: Double, sensitivity: Double) -> Double {
        clamp01(raw * max(0, sensitivity) / referenceSensitivity)
    }

    /// Fast to rise, slower to fall, frame-rate independent.
    public static func smoothLevel(previous: Double, target: Double, dt: Double, attack: Double = 18, release: Double = 6) -> Double {
        let rate = target > previous ? attack : release
        let alpha = 1 - exp(-rate * max(0, dt))
        return clamp01(previous + (target - previous) * alpha)
    }

    /// A stand-in voice level when no real meter is reachable: layered sines, 0...1, deterministic.
    public static func proceduralLevel(time t: Double, state: VoiceRingState) -> Double {
        switch state {
        case .listening:
            clamp01(0.32 + 0.22 * sin(t * 2.3) + 0.16 * sin(t * 5.1 + 1) + 0.10 * sin(t * 9.7 + 2))
        case .speaking:
            clamp01(0.45 + 0.28 * sin(t * 3.4) + 0.18 * sin(t * 7.3 + 1.3) + 0.09 * sin(t * 12.1 + 0.4))
        case .idle, .processing:
            0
        }
    }

    /// The shared clock's speed for the current mix of states.
    public static func timeRate(_ weights: VoiceRingWeights) -> Double {
        VoiceRingState.allCases.reduce(0) { $0 + weights[$1] * shape($1).rate }
    }

    // MARK: Pointer

    /// How strongly a pointer at unit-space (x, y) pulls the rim: strongest on the rim, none far from it.
    public static func hover(x: Double, y: Double) -> VoiceRingHover {
        let distance = hypot(x, y)
        let amount = clamp01(1 - abs(distance - hoverRim) / hoverReach)
        return VoiceRingHover(amount: amount, angle: atan2(y, x))
    }

    /// The angle difference folded into -pi...pi.
    public static func wrapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    /// 1 facing the pointer, falling to 0 away from it.
    static func bump(_ angle: Double, toward target: Double) -> Double {
        let base = (1 + cos(angle - target)) / 2
        return pow(base, 6)
    }

    // MARK: Ring

    /// Pointer bend that actually applies: only in the calm states (idle, processing).
    public static func effectiveBend(_ input: VoiceRingInput) -> Double {
        input.bend * input.weights.calm
    }

    public static func center(_ input: VoiceRingInput) -> VoiceRingPoint {
        VoiceRingPoint(x: input.lean * leanShift, y: 0)
    }

    /// The ribbon's centre-line radius at `angle`. Every wobble is a whole number of lobes, so it closes.
    public static func radius(at angle: Double, input: VoiceRingInput) -> Double {
        var r = 0.0
        for state in VoiceRingState.allCases {
            let weight = input.weights[state]
            if weight <= 0 { continue }
            let s = shape(state)
            let amplitude = s.amplitude + s.levelGain * input.level
            r += weight * (s.radius + amplitude * sin(Double(s.lobes) * angle + input.time * s.spin))
        }
        r += input.lean * leanReach * cos(angle)
        r += effectiveBend(input) * bendReach * bump(angle, toward: input.bendAngle)
        return r
    }

    /// Half the ribbon's width at `angle`: wider when loud, with a slow two-lobe swell.
    public static func halfThickness(at angle: Double, input: VoiceRingInput) -> Double {
        var t = 0.0
        for state in VoiceRingState.allCases {
            let weight = input.weights[state]
            if weight <= 0 { continue }
            let s = shape(state)
            t += weight * s.thickness * (1 + 0.25 * sin(2 * angle + input.time * s.spin * 0.5))
        }
        let loud = input.weights.listening + input.weights.speaking
        return t * (1 + 0.4 * input.level * loud)
    }

    /// Points around the ribbon. The last sample is not a repeat of the first: the path closes by itself.
    public static func ribbon(_ input: VoiceRingInput, samples: Int = 96) -> [VoiceRingRibbonSample] {
        let count = max(8, samples)
        let c = center(input)
        return (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            let r = radius(at: angle, input: input)
            let h = halfThickness(at: angle, input: input)
            let dx = cos(angle), dy = sin(angle)
            return VoiceRingRibbonSample(
                angle: angle,
                center: VoiceRingPoint(x: c.x + dx * r, y: c.y + dy * r),
                outer: VoiceRingPoint(x: c.x + dx * (r + h), y: c.y + dy * (r + h)),
                inner: VoiceRingPoint(x: c.x + dx * (r - h), y: c.y + dy * (r - h)))
        }
    }

    // MARK: Mono

    /// 0 = two thin flat loops, 1 = fully open into a globe.
    public static func monoOpenness(_ input: VoiceRingInput) -> Double {
        let w = input.weights
        return clamp01(w.listening * (0.25 + 0.75 * input.level) + w.speaking * (0.55 + 0.45 * input.level))
    }

    static let monoFlat = 0.14

    /// One of the two loops (0 or 1) as a closed polyline. Open loops turn like meridians of a globe.
    public static func monoLoop(_ loop: Int, samples: Int = 96, input: VoiceRingInput) -> [VoiceRingPoint] {
        let count = max(8, samples)
        let open = monoOpenness(input)
        let turn = input.time * 0.9 + (loop == 0 ? 0 : Double.pi / 2)
        let squash = monoFlat + (max(monoFlat, abs(cos(turn))) - monoFlat) * open
        let a = 0.74 + 0.04 * input.level * open
        let tilt = (loop == 0 ? 0.6 : -0.6) + input.lean * 0.4
        let c = center(input)
        let bend = effectiveBend(input)
        return (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            var x = a * cos(angle)
            var y = a * sin(angle)
            if loop == 0 { x *= squash } else { y *= squash }
            let rx = x * cos(tilt) - y * sin(tilt)
            let ry = x * sin(tilt) + y * cos(tilt)
            var scale = 1.0
            if bend > 0 { scale += bend * 0.08 * bump(atan2(ry, rx), toward: input.bendAngle) }
            return VoiceRingPoint(x: c.x + rx * scale, y: c.y + ry * scale)
        }
    }

    // MARK: Palette

    /// Four spectrum stops per emotion, as Zeus colours (purple, blue, teal, pink for none).
    public static func spectrum(_ emotion: VoiceRingEmotion?) -> [UInt32] {
        switch emotion {
        case nil: [0xB46BFF, 0x3D8BFF, 0x2EE6D0, 0xFF4FB8]
        case .positive?: [0xFF4FB8, 0xFF8A3D, 0xFFC27A, 0xB46BFF]
        case .negative?: [0xFF5A5F, 0xFF8A3D, 0x7A3DB8, 0x3D5BFF]
        case .calm?: [0x4DA3FF, 0x2EE6D0, 0x7AE7C7, 0xB46BFF]
        }
    }

    public static func rgb(_ hex: UInt32) -> VoiceRingRGB {
        VoiceRingRGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    /// The four stops while `from` fades into `to` (`mix` 0 = from, 1 = to).
    public static func stops(from: VoiceRingEmotion?, to: VoiceRingEmotion?, mix: Double) -> [VoiceRingRGB] {
        let m = clamp01(mix)
        let eased = m * m * (3 - 2 * m)
        let a = spectrum(from).map(rgb), b = spectrum(to).map(rgb)
        return zip(a, b).map { x, y in
            VoiceRingRGB(r: x.r + (y.r - x.r) * eased, g: x.g + (y.g - x.g) * eased, b: x.b + (y.b - x.b) * eased)
        }
    }
}

/// The frame-to-frame side of the ring: eases state, level, lean, bend and emotion, and keeps the clock.
public struct VoiceRingEngine: Sendable {
    public private(set) var weights = VoiceRingWeights.pure(.idle)
    public private(set) var level = 0.0
    public private(set) var time = 0.0
    public private(set) var lean = 0.0
    public private(set) var bend = 0.0
    public private(set) var bendAngle = 0.0
    public private(set) var emotionFrom: VoiceRingEmotion?
    public private(set) var emotionTo: VoiceRingEmotion?
    public private(set) var emotionMix = 1.0

    public static let transitionSeconds = 0.5
    public static let emotionSeconds = 0.6

    public init() {}

    public init(snappedTo state: VoiceRingState, emotion: VoiceRingEmotion? = nil) {
        weights = .pure(state)
        emotionFrom = emotion
        emotionTo = emotion
    }

    /// `rawLevel` is the live 0...1 meter; `direction` -1...1 leans the ring; `hover` is the pointer
    /// pull, scaled by `hoverBend` (0...1). Reduce Motion snaps to the state and freezes the clock.
    public mutating func advance(dt rawDT: Double, state: VoiceRingState, rawLevel: Double,
                                 sensitivity: Double = VoiceRingModel.defaultSensitivity,
                                 emotion: VoiceRingEmotion? = nil, direction: Double = 0,
                                 hover: VoiceRingHover? = nil, hoverBend: Double = 1,
                                 speed: Double = 1, reduceMotion: Bool = false) {
        let dt = min(0.1, max(0, rawDT))
        let leanTarget = min(1, max(-1, direction))
        if reduceMotion {
            weights = .pure(state)
            level = 0
            bend = 0
            lean = leanTarget
            emotionFrom = emotion
            emotionTo = emotion
            emotionMix = 1
            return
        }
        weights.advance(toward: state, dt: dt, duration: Self.transitionSeconds)

        let loud = weights.listening + weights.speaking
        let target = VoiceRingModel.shapedLevel(raw: rawLevel, sensitivity: sensitivity) * loud
        level = VoiceRingModel.smoothLevel(previous: level, target: target, dt: dt)

        let leanAlpha = 1 - exp(-6 * dt)
        lean += (leanTarget - lean) * leanAlpha

        let bendTarget = VoiceRingModel.clamp01(hoverBend) * (hover?.amount ?? 0)
        if let hover { bendAngle = hover.angle }
        bend += (bendTarget - bend) * (1 - exp(-10 * dt))

        if emotion != emotionTo {
            emotionFrom = emotionTo
            emotionTo = emotion
            emotionMix = 0
        }
        emotionMix = min(1, emotionMix + dt / Self.emotionSeconds)

        time += dt * min(3, max(0.25, speed)) * VoiceRingModel.timeRate(weights.eased)
    }

    /// The geometry input for now. Reduce Motion draws the held state: no time, no level.
    public func input(reduceMotion: Bool = false) -> VoiceRingInput {
        if reduceMotion {
            return VoiceRingInput(time: 0, level: 0, weights: weights, lean: lean)
        }
        return VoiceRingInput(time: time, level: level, weights: weights.eased, lean: lean, bend: bend, bendAngle: bendAngle)
    }

    public var stops: [VoiceRingRGB] {
        VoiceRingModel.stops(from: emotionFrom, to: emotionTo, mix: emotionMix)
    }
}
