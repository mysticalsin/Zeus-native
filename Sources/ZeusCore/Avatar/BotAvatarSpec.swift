import Foundation

// Bot avatars: a roster of rounded little heads, one shape per Zeus agent. Everything here is pure
// geometry and timing math; the SwiftUI view (Zeus/Avatar/BotAvatarView.swift) only draws it.
// Outlines are generated from polar, rounded-polygon and superellipse formulas (Zeus' own shapes).

// MARK: Geometry

public struct BotPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

public enum BotPathCommand: Equatable, Sendable {
    case move(BotPoint)
    case line(BotPoint)
    case quad(control: BotPoint, to: BotPoint)
    case cubic(control1: BotPoint, control2: BotPoint, to: BotPoint)
    case close
}

public struct BotBounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    public func contains(_ p: BotPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}

/// A path in a 100 x 100 box: move / line / quadratic / cubic / close.
public struct BotPath: Equatable, Sendable {
    public var commands: [BotPathCommand]

    public init(commands: [BotPathCommand] = []) {
        self.commands = commands
    }

    /// A closed polyline.
    public init(polygon points: [BotPoint]) {
        var list: [BotPathCommand] = []
        for (index, point) in points.enumerated() {
            list.append(index == 0 ? .move(point) : .line(point))
        }
        if !points.isEmpty { list.append(.close) }
        self.commands = list
    }

    public var isClosed: Bool { commands.last == .close }

    /// Every end point and control point (a control polygon always contains the curve).
    public var points: [BotPoint] {
        var all: [BotPoint] = []
        for command in commands {
            switch command {
            case .move(let a), .line(let a): all.append(a)
            case .quad(let c, let a): all.append(c); all.append(a)
            case .cubic(let c1, let c2, let a): all.append(c1); all.append(c2); all.append(a)
            case .close: break
            }
        }
        return all
    }

    public var bounds: BotBounds? {
        let pts = points
        guard let first = pts.first else { return nil }
        var b = BotBounds(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in pts {
            b.minX = min(b.minX, p.x)
            b.minY = min(b.minY, p.y)
            b.maxX = max(b.maxX, p.x)
            b.maxY = max(b.maxY, p.y)
        }
        return b
    }

    public func fits(inBox box: Double = 100) -> Bool {
        guard let b = bounds else { return false }
        return b.minX >= 0 && b.minY >= 0 && b.maxX <= box && b.maxY <= box
    }

    /// Parses the SVG path subset M, L, C, Q, Z (absolute coordinates). Numbers may be separated by
    /// spaces or commas, and extra coordinate groups repeat the last command (an extra M becomes L).
    /// Returns nil for anything else, for a path that does not start with M, or for missing numbers.
    public static func parse(_ svg: String) -> BotPath? {
        var scanner = BotPathScanner(Array(svg.utf8))
        var commands: [BotPathCommand] = []
        var current: UInt8 = 0
        let (M, L, C, Q, Z) = (UInt8(ascii: "M"), UInt8(ascii: "L"), UInt8(ascii: "C"), UInt8(ascii: "Q"), UInt8(ascii: "Z"))
        scanner.skipSeparators()
        while !scanner.atEnd {
            if let letter = scanner.takeLetter() {
                guard letter == M || letter == L || letter == C || letter == Q || letter == Z else { return nil }
                if letter == Z {
                    commands.append(.close)
                    current = 0
                    scanner.skipSeparators()
                    continue
                }
                current = letter
            } else if current == 0 {
                return nil
            }
            switch current {
            case M:
                guard let p = scanner.point() else { return nil }
                commands.append(.move(p))
                // A further coordinate pair after M is an implicit L.
                current = L
            case L:
                guard let p = scanner.point() else { return nil }
                commands.append(.line(p))
            case Q:
                guard let c = scanner.point(), let p = scanner.point() else { return nil }
                commands.append(.quad(control: c, to: p))
            case C:
                guard let c1 = scanner.point(), let c2 = scanner.point(), let p = scanner.point() else { return nil }
                commands.append(.cubic(control1: c1, control2: c2, to: p))
            default:
                return nil
            }
            scanner.skipSeparators()
        }
        guard case .move? = commands.first else { return nil }
        return BotPath(commands: commands)
    }
}

private struct BotPathScanner {
    let bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { index >= bytes.count }

    mutating func skipSeparators() {
        while index < bytes.count {
            let b = bytes[index]
            if b == 0x20 || b == 0x2C || b == 0x0A || b == 0x09 || b == 0x0D { index += 1 } else { break }
        }
    }

    /// A command letter, or nil when the next thing is not a letter.
    mutating func takeLetter() -> UInt8? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        let b = bytes[index]
        let isLetter = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
        guard isLetter else { return nil }
        index += 1
        return b
    }

    mutating func number() -> Double? {
        skipSeparators()
        let start = index
        var i = index
        func digits() -> Int {
            var count = 0
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 { i += 1; count += 1 }
            return count
        }
        if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D { i += 1 }
        var total = digits()
        if i < bytes.count, bytes[i] == 0x2E {
            i += 1
            total += digits()
        }
        guard total > 0 else { return nil }
        if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {
            var j = i + 1
            if j < bytes.count, bytes[j] == 0x2B || bytes[j] == 0x2D { j += 1 }
            if j < bytes.count, bytes[j] >= 0x30, bytes[j] <= 0x39 {
                i = j
                _ = digits()
            }
        }
        guard let value = Double(String(decoding: bytes[start..<i], as: UTF8.self)), value.isFinite else { return nil }
        index = i
        return value
    }

    mutating func point() -> BotPoint? {
        guard let x = number(), let y = number() else { return nil }
        return BotPoint(x, y)
    }
}

// MARK: Roster

public enum BotAvatarType: String, CaseIterable, Sendable {
    case clover, flower, triangle, square, blob, ghost, circle, drop, star
    case droid, mech, alien, hexagon, cat, cloud, pill, pebble, puddle
}

/// `.eyes` draws eyes only; `.mouth` draws eyes and a mouth.
public enum BotFace: String, CaseIterable, Sendable {
    case eyes, mouth
}

public enum BotAvatarState: String, CaseIterable, Sendable {
    case `default`, working, sleeping

    /// Running sessions work; a session that has sat idle for `sleepAfter` seconds sleeps.
    public static func forActivity(running: Bool, idleFor: TimeInterval, sleepAfter: TimeInterval = 600) -> BotAvatarState {
        if running { return .working }
        return idleFor >= sleepAfter ? .sleeping : .default
    }

    public var spokenName: String {
        switch self {
        case .default: "idle"
        case .working: "working"
        case .sleeping: "sleeping"
        }
    }
}

public enum BotHat: String, CaseIterable, Sendable { case none, beret, beanie, party, crown }
public enum BotGlasses: String, CaseIterable, Sendable { case none, round, square, shades }

public struct BotAccessories: Equatable, Sendable {
    public var hat: BotHat
    public var glasses: BotGlasses
    public var headphones: Bool
    public var bowTie: Bool

    public init(hat: BotHat = .none, glasses: BotGlasses = .none, headphones: Bool = false, bowTie: Bool = false) {
        self.hat = hat
        self.glasses = glasses
        self.headphones = headphones
        self.bowTie = bowTie
    }

    public static let none = BotAccessories()
}

/// One roster entry: the body outline, its default colour, and where the face sits.
public struct BotAvatarSpec: Equatable, Sendable {
    public let type: BotAvatarType
    public let outline: BotPath
    public let defaultColorHex: UInt32
    /// Centre of the eyes, in the 100 x 100 box.
    public let faceAnchor: BotPoint
    /// Half the distance between the eyes.
    public let eyeSpacing: Double
    public let bounds: BotBounds

    /// `customPath` replaces the generated outline (it should already sit in the 100 x 100 box).
    public init(type: BotAvatarType, customPath: BotPath? = nil) {
        self.type = type
        let path = customPath ?? BotShapes.outline(for: type)
        self.outline = path
        self.bounds = path.bounds ?? BotBounds(minX: 6, minY: 6, maxX: 94, maxY: 94)
        self.defaultColorHex = BotShapes.colorHex(for: type)
        let face = BotShapes.face(for: type)
        self.faceAnchor = face.anchor
        self.eyeSpacing = face.spacing
    }

    private static let catalog: [BotAvatarType: BotAvatarSpec] = {
        var table: [BotAvatarType: BotAvatarSpec] = [:]
        for type in BotAvatarType.allCases { table[type] = BotAvatarSpec(type: type) }
        return table
    }()

    /// The shared, precomputed spec for a type.
    public static func spec(for type: BotAvatarType) -> BotAvatarSpec {
        catalog[type] ?? BotAvatarSpec(type: type)
    }

    // MARK: Agents

    /// FNV-1a over the trimmed, lowercased name, finished with a splitmix mix so near-identical
    /// names ("agent-1", "agent-2") still land on different shapes.
    static func hash(_ name: String) -> UInt64 {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        h ^= h >> 30
        h = h &* 0xbf58_476d_1ce4_e5b9
        h ^= h >> 27
        h = h &* 0x94d0_49bb_1331_11eb
        h ^= h >> 31
        return h
    }

    /// A stable shape for an agent name (same name, same shape, on every launch).
    public static func type(forAgent name: String) -> BotAvatarType {
        let all = BotAvatarType.allCases
        return all[Int(hash(name) % UInt64(all.count))]
    }

    /// A stable 0...1 seed for an agent, so two agents never blink or hop in unison.
    public static func seed(forAgent name: String) -> Double {
        Double((hash(name) >> 11) & 0xFFFF) / 65536
    }

    public static func accessibilityLabel(agent: String?, state: BotAvatarState) -> String {
        let trimmed = agent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(trimmed.isEmpty ? "Agent" : trimmed) avatar, \(state.spokenName)"
    }
}

// MARK: Shape generation

enum BotShapes {
    static func colorHex(for type: BotAvatarType) -> UInt32 {
        switch type {
        case .clover: 0x3CCB7F
        case .flower: 0xFF7AB6
        case .triangle: 0xFF8A3D
        case .square: 0x4DA3FF
        case .blob: 0x9B6BFF
        case .ghost: 0xE9EDF2
        case .circle: 0xFF6B6B
        case .drop: 0x2EC4E6
        case .star: 0xFFD84D
        case .droid: 0x7C8CFF
        case .mech: 0x8A94A0
        case .alien: 0x7BE04A
        case .hexagon: 0x2ED3C6
        case .cat: 0xF2C79B
        case .cloud: 0xA9D6FF
        case .pill: 0xB46BFF
        case .pebble: 0xC2A383
        case .puddle: 0x3D8BFF
        }
    }

    static func face(for type: BotAvatarType) -> (anchor: BotPoint, spacing: Double) {
        switch type {
        case .clover: (BotPoint(50, 50), 15)
        case .flower: (BotPoint(50, 50), 14)
        case .triangle: (BotPoint(50, 60), 12)
        case .square: (BotPoint(50, 52), 17)
        case .blob: (BotPoint(50, 52), 16)
        case .ghost: (BotPoint(50, 42), 15)
        case .circle: (BotPoint(50, 52), 16)
        case .drop: (BotPoint(50, 60), 13)
        case .star: (BotPoint(50, 54), 11)
        case .droid: (BotPoint(50, 56), 15)
        case .mech: (BotPoint(50, 52), 17)
        case .alien: (BotPoint(50, 46), 15)
        case .hexagon: (BotPoint(50, 50), 15)
        case .cat: (BotPoint(50, 56), 16)
        case .cloud: (BotPoint(50, 50), 17)
        case .pill: (BotPoint(50, 50), 16)
        case .pebble: (BotPoint(50, 50), 15)
        case .puddle: (BotPoint(50, 50), 17)
        }
    }

    static func outline(for type: BotAvatarType) -> BotPath {
        let top = Double.pi / 2
        let points: [BotPoint]
        switch type {
        case .clover:
            points = polar { 1 + 0.30 * cos(4 * ($0 + top)) }
        case .flower:
            points = polar { 1 + 0.17 * cos(6 * ($0 + top)) }
        case .triangle:
            points = roundedPolygon(sides: 3, round: 0.5)
        case .square:
            points = superellipse(power: 4.2, scaleY: 1)
        case .blob:
            points = polar { (a: Double) -> Double in
                let w1: Double = 0.09 * cos(2 * a + 0.6)
                let w2: Double = 0.08 * cos(3 * a + 1.9)
                let w3: Double = 0.05 * cos(5 * a)
                return 1 + w1 + w2 + w3
            }
        case .ghost:
            points = ghost()
        case .circle:
            points = polar { _ in 1 }
        case .drop:
            points = drop()
        case .star:
            points = polar { 0.5 + 0.5 * pow(0.5 + 0.5 * cos(5 * ($0 + top)), 1.4) }
        case .droid:
            points = superellipse(power: 5, scaleY: 0.86, extra: { 0.32 * bump($0, center: -top, width: 0.09) })
        case .mech:
            points = superellipse(power: 7, scaleY: 0.88, extra: { (a: Double) -> Double in
                let right: Double = bump(a, center: 0, width: 0.22)
                let left: Double = bump(a, center: Double.pi, width: 0.22)
                return 0.14 * (right + left)
            })
        case .alien:
            points = polar { _ in 1 }.map { BotPoint($0.x * (1 - 0.32 * max(0, $0.y)), $0.y) }
        case .hexagon:
            points = roundedPolygon(sides: 6, round: 0.3)
        case .cat:
            points = polar(scaleY: 0.86) { (a: Double) -> Double in
                let leftEar: Double = bump(a, center: -top - 0.78, width: 0.2)
                let rightEar: Double = bump(a, center: -top + 0.78, width: 0.2)
                return 1 + 0.5 * (leftEar + rightEar)
            }
        case .cloud:
            points = polar(scaleY: 0.74) { 0.8 + 0.2 * abs(cos(3 * $0)) }
        case .pill:
            points = pill()
        case .pebble:
            points = polar(scaleY: 0.82) { (a: Double) -> Double in
                let w1: Double = 0.06 * cos(a + 0.4)
                let w2: Double = 0.05 * cos(2 * a + 2)
                let w3: Double = 0.04 * cos(3 * a + 1)
                return 1 + w1 + w2 + w3
            }
        case .puddle:
            points = polar(scaleY: 0.55) { 1 + 0.12 * cos(3 * $0) + 0.07 * cos(5 * $0 + 1) }
        }
        return BotPath(polygon: fitted(points))
    }

    /// Scales and centres a shape so its longer side is 88 units, leaving a 6 unit margin.
    static func fitted(_ points: [BotPoint]) -> [BotPoint] {
        guard let first = points.first else { return [] }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let scale = 88 / max(maxX - minX, maxY - minY, 0.0001)
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        return points.map { BotPoint(50 + ($0.x - cx) * scale, 50 + ($0.y - cy) * scale) }
    }

    /// r(angle) sampled all the way round, starting at the top and going clockwise on screen.
    static func polar(count: Int = 96, scaleY: Double = 1, radius: (Double) -> Double) -> [BotPoint] {
        (0..<count).map { i in
            let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(count)
            let r = radius(a)
            return BotPoint(r * cos(a), scaleY * r * sin(a))
        }
    }

    /// A gaussian bump around `center` (angles wrap).
    static func bump(_ angle: Double, center: Double, width: Double) -> Double {
        let d = atan2(sin(angle - center), cos(angle - center))
        return exp(-(d / width) * (d / width))
    }

    static func superellipse(power p: Double, scaleY: Double, extra: (Double) -> Double = { _ in 0 }) -> [BotPoint] {
        polar(scaleY: scaleY) { a in
            pow(pow(abs(cos(a)), p) + pow(abs(sin(a)), p), -1 / p) * (1 + extra(a))
        }
    }

    /// A polygon with a vertex at the top; `round` 0 is sharp, 1 is a circle.
    static func roundedPolygon(sides n: Int, round: Double) -> [BotPoint] {
        let segment = 2 * Double.pi / Double(n)
        return polar { a in
            let t = a + Double.pi / 2
            let local = t - (t / segment).rounded(.down) * segment - segment / 2
            let sharp = cos(Double.pi / Double(n)) / cos(local)
            return sharp + (1 - sharp) * round
        }
    }

    static func ghost() -> [BotPoint] {
        var pts: [BotPoint] = []
        let steps = 40
        for i in 0...steps {
            let a = Double.pi + Double.pi * Double(i) / Double(steps)
            pts.append(BotPoint(0.5 * cos(a), -0.05 + 0.5 * sin(a)))
        }
        pts.append(BotPoint(0.5, 0.4))
        let wave = 36
        for i in 0...wave {
            let u = Double(i) / Double(wave)
            pts.append(BotPoint(0.5 - u, 0.5 - 0.1 * abs(sin(3 * Double.pi * u))))
        }
        pts.append(BotPoint(-0.5, 0.4))
        return pts
    }

    static func drop() -> [BotPoint] {
        let n = 96
        return (0..<n).map { i in
            let t = 2 * Double.pi * Double(i) / Double(n)
            return BotPoint(sin(t) * sin(t / 2), -cos(t))
        }
    }

    static func pill() -> [BotPoint] {
        var pts: [BotPoint] = []
        let steps = 24
        for i in 0...steps {
            let a = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            pts.append(BotPoint(0.2 + 0.3 * cos(a), 0.3 * sin(a)))
        }
        for i in 0...steps {
            let a = Double.pi / 2 + Double.pi * Double(i) / Double(steps)
            pts.append(BotPoint(-0.2 + 0.3 * cos(a), 0.3 * sin(a)))
        }
        return pts
    }
}

// MARK: Colour and shading

public struct BotRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    public static let white = BotRGB(r: 1, g: 1, b: 1)
    public static let black = BotRGB(r: 0, g: 0, b: 0)

    /// Moves `amount` (0...1) of the way to `other`.
    public func mixed(with other: BotRGB, _ amount: Double) -> BotRGB {
        let t = min(max(amount, 0), 1)
        return BotRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

public enum BotShading: String, CaseIterable, Sendable {
    /// Soft fuzzy edge. Plastic: gloss hot spot and a rim. Crisp: a lit rim. Smooth: gradient only. Flat: one colour.
    case plush, plastic, crisp, smooth, flat
}

public struct BotShadingParams: Equatable, Sendable {
    /// 0 = one flat colour, 1 = full light-to-shadow gradient.
    public let contrast: Double
    /// Opacity of the white hot spot on the lit side.
    public let gloss: Double
    /// Opacity of the lit rim, and its width in box units.
    public let rim: Double
    public let rimWidth: Double
    /// Width in box units of the soft edge drawn outside the body (plush).
    public let fuzz: Double

    public static func params(for shading: BotShading) -> BotShadingParams {
        switch shading {
        case .plush: BotShadingParams(contrast: 0.75, gloss: 0, rim: 0.18, rimWidth: 3, fuzz: 2.4)
        case .plastic: BotShadingParams(contrast: 1, gloss: 0.55, rim: 0.35, rimWidth: 2.2, fuzz: 0)
        case .crisp: BotShadingParams(contrast: 0.6, gloss: 0.1, rim: 0.85, rimWidth: 2.4, fuzz: 0)
        case .smooth: BotShadingParams(contrast: 0.8, gloss: 0, rim: 0, rimWidth: 0, fuzz: 0)
        case .flat: BotShadingParams(contrast: 0, gloss: 0, rim: 0, rimWidth: 0, fuzz: 0)
        }
    }
}

public enum BotLight {
    /// Up and to the left, in degrees (screen y points down, so -135 is up-left).
    public static let defaultAngleDegrees = -135.0

    /// Unit vector pointing towards the light, in screen coordinates.
    public static func direction(degrees: Double) -> (x: Double, y: Double) {
        let a = degrees * Double.pi / 180
        return (cos(a), sin(a))
    }
}

// MARK: Timeline math

public enum BotEase: String, CaseIterable, Sendable {
    case sharp, pulse, soft, bouncy
}

public struct BotJump: Equatable, Sendable {
    /// Peak height as a fraction of the avatar's size.
    public var height: Double
    public var duration: Double
    public var stretch: Double
    public var squash: Double
    public var ease: BotEase

    public init(height: Double, duration: Double, stretch: Double, squash: Double, ease: BotEase) {
        self.height = height
        self.duration = duration
        self.stretch = stretch
        self.squash = squash
        self.ease = ease
    }

    public static let idle = BotJump(height: 0.14, duration: 0.7, stretch: 0.12, squash: 0.14, ease: .soft)
    public static let working = BotJump(height: 0.12, duration: 0.62, stretch: 0.10, squash: 0.12, ease: .bouncy)
    public static let click = BotJump(height: 0.18, duration: 0.8, stretch: 0.16, squash: 0.18, ease: .pulse)
}

/// What the avatar looks like at one instant. Lift and sink are fractions of the avatar's size.
public struct BotPose: Equatable, Sendable {
    public var lift = 0.0
    public var sink = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    /// Radians; a full spin ends at 2 pi, which looks the same as 0.
    public var rotation = 0.0
    public var lookX = 0.0
    public var lookY = 0.0
    /// 0 = eyes open, 1 = lids shut.
    public var lid = 0.0
    /// 0...1 happy squint (laughing).
    public var squint = 0.0
    public var mouthOpen = 0.0
    public var breath = 1.0

    public init() {}

    public static let still = BotPose()
}

public enum BotTimeline {
    public static let idleJumpPeriod = 8.0

    static func wrap(_ x: Double, _ period: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }

    static func fraction(_ x: Double) -> Double {
        x - x.rounded(.down)
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Jump height curve: 0 at both ends, never above 1, and 0 outside 0...1.
    public static func arc(_ progress: Double, ease: BotEase) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        let p = progress
        let s = sin(Double.pi * p)
        switch ease {
        case .sharp: return pow(s, 0.7)
        case .pulse: return s * s
        case .soft: return s
        case .bouncy:
            // One big hop, then a small rebound.
            if p < 0.75 {
                let q = p / 0.75
                return 4 * q * (1 - q)
            }
            let q = (p - 0.75) / 0.25
            return 0.18 * 4 * q * (1 - q)
        }
    }

    /// Squash on the way in and out of a jump, stretch in the air; width follows to keep the volume.
    /// Both are exactly 1 at progress 0 and 1, so a jump joins the rest pose without a pop.
    public static func squashStretch(progress p: Double, jump: BotJump) -> (x: Double, y: Double) {
        guard p > 0, p < 1 else { return (1, 1) }
        let anticipation = p < 0.12 ? sin(Double.pi * p / 0.12) : 0
        let landing = p > 0.82 ? sin(Double.pi * (p - 0.82) / 0.18) : 0
        let y = 1 + jump.stretch * arc(p, ease: jump.ease) - jump.squash * (0.5 * anticipation + landing)
        let clamped = min(max(y, 0.6), 1.4)
        return (1 / clamped, clamped)
    }

    /// Blink amount, 0...1. Each seed has its own interval (3.2 to 4.8 s) and its own offset.
    public static func blink(time t: Double, seed: Double) -> Double {
        let s = fraction(seed)
        let interval = 3.2 + 1.6 * fraction(s * 7.31)
        let phase = wrap(t + s * interval, interval)
        let length = 0.16
        guard phase < length else { return 0 }
        return sin(Double.pi * phase / length)
    }

    /// Chest scale: about 1, a slow swell.
    public static func breath(time t: Double, state: BotAvatarState) -> Double {
        switch state {
        case .default: 1 + 0.02 * sin(2 * Double.pi * t / 4.2)
        case .working: 1
        case .sleeping: 1 + 0.04 * sin(2 * Double.pi * t / 5.5)
        }
    }

    private static func apply(jump: BotJump, progress p: Double, to pose: inout BotPose) {
        pose.lift = arc(p, ease: jump.ease) * jump.height
        let s = squashStretch(progress: p, jump: jump)
        pose.scaleX = s.x
        pose.scaleY = s.y
    }

    /// The avatar at time `t` seconds. `seed` (0...1) offsets blinks, hops and glances.
    /// With `reduceMotion` the pose never changes: eyes open (or shut when sleeping), no hop, no spin.
    public static func pose(state: BotAvatarState, time t: Double, seed: Double = 0, reduceMotion: Bool = false) -> BotPose {
        var pose = BotPose.still
        if reduceMotion {
            switch state {
            case .default: break
            case .working:
                pose.squint = 0.6
                pose.mouthOpen = 0.5
            case .sleeping:
                pose.sink = 0.07
                pose.rotation = 0.2
                pose.lid = 1
                pose.mouthOpen = 0.1
            }
            return pose
        }
        let s = fraction(seed)
        switch state {
        case .default:
            let local = wrap(t + s * idleJumpPeriod, idleJumpPeriod)
            let p = local / BotJump.idle.duration
            if p < 1 { apply(jump: .idle, progress: p, to: &pose) }
            pose.lookX = 0.8 * sin(0.55 * t + s * 6.2832) * cos(0.21 * t + 1.3 * s)
            pose.lookY = 0.45 * sin(0.37 * t + s * 4.1)
            pose.lid = blink(time: t, seed: s)
        case .working:
            let hopPeriod = 0.9
            let p = wrap(t + s * hopPeriod, hopPeriod) / BotJump.working.duration
            if p < 1 { apply(jump: .working, progress: p, to: &pose) }
            let spinCycle = 3.6
            let spinProgress = wrap(t + s * spinCycle, spinCycle) / 0.8
            let spin = spinProgress < 1 ? 2 * Double.pi * smoothstep(spinProgress) : 0
            pose.rotation = spin + 0.08 * sin(t * 7)
            pose.squint = 0.6
            pose.mouthOpen = 0.5 + 0.5 * sin(t * 13)
        case .sleeping:
            pose.sink = 0.07
            pose.rotation = 0.2 + 0.03 * sin(t * 0.8 + s * 6.2832)
            pose.lid = 1
            pose.mouthOpen = 0.1 + 0.08 * sin(2 * Double.pi * t / 5.5)
        }
        pose.breath = breath(time: t, state: state)
        return pose
    }

    /// A click: one hop with a full spin over `BotJump.click.duration`. Nil before and after it.
    /// The result keeps the face of `base` and replaces lift, squash and rotation.
    public static func clickPose(elapsed: Double, over base: BotPose) -> BotPose? {
        let jump = BotJump.click
        let p = elapsed / jump.duration
        guard p >= 0, p < 1 else { return nil }
        var pose = base
        apply(jump: jump, progress: p, to: &pose)
        pose.rotation = 2 * Double.pi * smoothstep(p)
        pose.lid = 0
        return pose
    }
}
