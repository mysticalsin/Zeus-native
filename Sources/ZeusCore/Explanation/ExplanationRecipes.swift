import Foundation

/// One solid in a part recipe, in the recipe's local frame (metres, right-handed, Y up).
/// Rotations are limited to what the recipes need: a cylinder lies along one axis, and a box can
/// roll about Z. That keeps the geometry checkable without a matrix library, and the app layer
/// turns each primitive into one SceneKit node.
public struct ExplanationRecipePrimitive: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case box(ExplanationVector3)
        case cylinder(radius: Double, length: Double, axis: ExplanationAxis)
        case sphere(radius: Double)
    }
    /// A rotating primitive turns about the part's spin axis through `pivot`, at `factor` times
    /// the part's spin rate. A negative factor turns the other way (a meshing gear).
    public struct Spin: Equatable, Sendable {
        public var pivot: ExplanationVector3
        public var factor: Double
        public init(pivot: ExplanationVector3 = .zero, factor: Double = 1) { self.pivot = pivot; self.factor = factor }
    }
    public var name: String
    public var shape: Shape
    public var position: ExplanationVector3
    public var roll: Double
    public var color: ExplanationColor
    public var metalness: Double
    public var roughness: Double
    public var opacity: Double
    public var spin: Spin?
    public init(name: String, shape: Shape, position: ExplanationVector3 = .zero, roll: Double = 0,
                color: ExplanationColor = .secondary, metalness: Double = 0.2, roughness: Double = 0.6,
                opacity: Double = 1, spin: Spin? = nil) {
        self.name = name; self.shape = shape; self.position = position; self.roll = roll
        self.color = color; self.metalness = metalness; self.roughness = roughness
        self.opacity = opacity; self.spin = spin
    }

    /// Axis-aligned extent of this primitive in the recipe frame.
    public var bounds: (min: ExplanationVector3, max: ExplanationVector3) {
        let half: ExplanationVector3
        switch shape {
        case .box(let size):
            let c = abs(cos(roll)), s = abs(sin(roll))
            half = .init(x: (c * size.x + s * size.y) / 2, y: (s * size.x + c * size.y) / 2, z: size.z / 2)
        case .cylinder(let radius, let length, let axis):
            switch axis {
            case .x: half = .init(x: length / 2, y: radius, z: radius)
            case .y: half = .init(x: radius, y: length / 2, z: radius)
            case .z: half = .init(x: radius, y: radius, z: length / 2)
            }
        case .sphere(let radius):
            half = .init(x: radius, y: radius, z: radius)
        }
        return (.init(x: position.x - half.x, y: position.y - half.y, z: position.z - half.z),
                .init(x: position.x + half.x, y: position.y + half.y, z: position.z + half.z))
    }
}

/// Pure geometry recipes. Dimensions are plausible for a mid-size passenger car and are
/// illustrative, not the specification of any real vehicle. Frame: +X forward, +Y up, +Z right.
public enum ExplanationRecipes {
    public static func primitives(_ recipe: ExplanationPartRecipe) -> [ExplanationRecipePrimitive] {
        switch recipe {
        case .batteryPack: batteryPack
        case .inverterBox: inverterBox
        case .motor: motor
        case .reductionGear: reductionGear
        case .halfShafts: halfShafts
        case .wheel: wheel
        case .carShell: carShell
        }
    }

    public static func bounds(_ recipe: ExplanationPartRecipe) -> (min: ExplanationVector3, max: ExplanationVector3) {
        let all = primitives(recipe).map(\.bounds)
        guard let first = all.first else { return (.zero, .zero) }
        return all.dropFirst().reduce(first) { acc, b in
            (.init(x: min(acc.min.x, b.min.x), y: min(acc.min.y, b.min.y), z: min(acc.min.z, b.min.z)),
             .init(x: max(acc.max.x, b.max.x), y: max(acc.max.y, b.max.y), z: max(acc.max.z, b.max.z)))
        }
    }

    /// Total solids a part expands to, counting its repeats. Used for the object budget.
    public static func primitiveCount(of part: ExplanationPart) -> Int {
        let copies = max(1, part.repeats?.count ?? 1)
        switch part.kind {
        case .recipe: return (part.recipe.map { primitives($0).count } ?? 0) * copies
        case .group: return 0
        default: return copies
        }
    }

    private static func v(_ x: Double, _ y: Double, _ z: Double) -> ExplanationVector3 { .init(x: x, y: y, z: z) }

    /// Tray 2.0 x 1.4 m with eight modules in two rows and a busbar down the middle.
    static let batteryPack: [ExplanationRecipePrimitive] = {
        var result: [ExplanationRecipePrimitive] = [
            .init(name: "tray", shape: .box(v(2.0, 0.03, 1.4)), position: v(0, -0.055, 0), color: .secondary, metalness: 0.7, roughness: 0.45),
            .init(name: "wall-front", shape: .box(v(0.03, 0.10, 1.4)), position: v(0.985, -0.005, 0), color: .secondary, metalness: 0.7, roughness: 0.45),
            .init(name: "wall-rear", shape: .box(v(0.03, 0.10, 1.4)), position: v(-0.985, -0.005, 0), color: .secondary, metalness: 0.7, roughness: 0.45),
            .init(name: "wall-left", shape: .box(v(1.94, 0.10, 0.03)), position: v(0, -0.005, -0.685), color: .secondary, metalness: 0.7, roughness: 0.45),
            .init(name: "wall-right", shape: .box(v(1.94, 0.10, 0.03)), position: v(0, -0.005, 0.685), color: .secondary, metalness: 0.7, roughness: 0.45)
        ]
        for column in 0..<4 {
            for row in 0..<2 {
                result.append(.init(name: "module-\(column)-\(row)", shape: .box(v(0.44, 0.08, 0.62)),
                                    position: v(-0.72 + 0.48 * Double(column), 0, row == 0 ? -0.33 : 0.33),
                                    color: .blue, metalness: 0.15, roughness: 0.55))
            }
        }
        result.append(.init(name: "busbar", shape: .box(v(1.6, 0.012, 0.05)), position: v(0, 0.046, 0),
                            color: .orange, metalness: 0.8, roughness: 0.35))
        return result
    }()

    /// Power electronics housing with cooling fins and three phase connectors on the motor side.
    static let inverterBox: [ExplanationRecipePrimitive] = {
        var result: [ExplanationRecipePrimitive] = [
            .init(name: "housing", shape: .box(v(0.52, 0.18, 0.34)), color: .secondary, metalness: 0.75, roughness: 0.4)
        ]
        for index in 0..<6 {
            result.append(.init(name: "fin-\(index)", shape: .box(v(0.03, 0.04, 0.30)), position: v(-0.2 + 0.08 * Double(index), 0.11, 0),
                                color: .secondary, metalness: 0.8, roughness: 0.35))
        }
        for index in 0..<3 {
            result.append(.init(name: "phase-\(index)", shape: .cylinder(radius: 0.025, length: 0.08, axis: .x),
                                position: v(-0.30, 0, -0.08 + 0.08 * Double(index)), color: .orange, metalness: 0.7, roughness: 0.4))
        }
        return result
    }()

    /// Three-phase motor on the Z axis: translucent housing, eight stator teeth, rotor and shaft.
    static let motor: [ExplanationRecipePrimitive] = {
        let turning = ExplanationRecipePrimitive.Spin()
        var result: [ExplanationRecipePrimitive] = [
            .init(name: "housing", shape: .cylinder(radius: 0.21, length: 0.30, axis: .z), color: .secondary,
                  metalness: 0.6, roughness: 0.3, opacity: 0.35)
        ]
        for index in 0..<8 {
            let angle = Double(index) * Double.pi / 4
            result.append(.init(name: "stator-tooth-\(index)", shape: .box(v(0.07, 0.05, 0.26)),
                                position: v(0.165 * cos(angle), 0.165 * sin(angle), 0), roll: angle,
                                color: .orange, metalness: 0.6, roughness: 0.4))
        }
        result.append(.init(name: "rotor", shape: .cylinder(radius: 0.12, length: 0.36, axis: .z), color: .secondary,
                            metalness: 0.85, roughness: 0.3, spin: turning))
        result.append(.init(name: "rotor-mark", shape: .box(v(0.04, 0.06, 0.37)), position: v(0, 0.085, 0),
                            color: .white, metalness: 0.1, roughness: 0.5, spin: turning))
        result.append(.init(name: "shaft", shape: .cylinder(radius: 0.03, length: 0.56, axis: .z), color: .secondary,
                            metalness: 0.9, roughness: 0.25, spin: turning))
        result.append(.init(name: "cap-front", shape: .cylinder(radius: 0.215, length: 0.02, axis: .z), position: v(0, 0, 0.16),
                            color: .secondary, metalness: 0.7, roughness: 0.4))
        result.append(.init(name: "cap-rear", shape: .cylinder(radius: 0.215, length: 0.02, axis: .z), position: v(0, 0, -0.16),
                            color: .secondary, metalness: 0.7, roughness: 0.4))
        return result
    }()

    static let reductionInputTeeth = 8
    static let reductionOutputTeeth = 20
    /// Output turns this many times the input rate, with the opposite sense (8 teeth driving 20).
    public static let reductionOutputFactor = -Double(reductionInputTeeth) / Double(reductionOutputTeeth)

    /// Single-stage reduction: an 8 tooth input gear driving a 20 tooth output gear, in a
    /// translucent case. Real units use two stages and a differential; this is simplified.
    static let reductionGear: [ExplanationRecipePrimitive] = {
        let inputCentre = v(-0.14, 0, 0), outputCentre = v(0.14, 0, 0)
        let inputPitch = 0.08, outputPitch = 0.20
        let input = ExplanationRecipePrimitive.Spin(pivot: inputCentre, factor: 1)
        let output = ExplanationRecipePrimitive.Spin(pivot: outputCentre, factor: reductionOutputFactor)
        var result: [ExplanationRecipePrimitive] = [
            .init(name: "case", shape: .box(v(0.78, 0.50, 0.12)), position: v(0.04, 0, 0), color: .secondary,
                  metalness: 0.5, roughness: 0.3, opacity: 0.25),
            .init(name: "input-gear", shape: .cylinder(radius: inputPitch - 0.012, length: 0.05, axis: .z), position: inputCentre,
                  color: .secondary, metalness: 0.85, roughness: 0.3, spin: input),
            .init(name: "output-gear", shape: .cylinder(radius: outputPitch - 0.012, length: 0.05, axis: .z), position: outputCentre,
                  color: .secondary, metalness: 0.85, roughness: 0.3, spin: output),
            .init(name: "input-shaft", shape: .cylinder(radius: 0.03, length: 0.3, axis: .z), position: inputCentre,
                  color: .secondary, metalness: 0.9, roughness: 0.25, spin: input),
            .init(name: "output-shaft", shape: .cylinder(radius: 0.03, length: 0.3, axis: .z), position: outputCentre,
                  color: .secondary, metalness: 0.9, roughness: 0.25, spin: output)
        ]
        for index in 0..<reductionInputTeeth {
            let angle = Double(index) * 2 * Double.pi / Double(reductionInputTeeth)
            result.append(.init(name: "input-tooth-\(index)", shape: .box(v(0.024, 0.028, 0.05)),
                                position: v(inputCentre.x + inputPitch * cos(angle), inputPitch * sin(angle), 0), roll: angle,
                                color: .white, metalness: 0.8, roughness: 0.35, spin: input))
        }
        for index in 0..<reductionOutputTeeth {
            let angle = Double(index) * 2 * Double.pi / Double(reductionOutputTeeth)
            result.append(.init(name: "output-tooth-\(index)", shape: .box(v(0.024, 0.028, 0.05)),
                                position: v(outputCentre.x + outputPitch * cos(angle), outputPitch * sin(angle), 0), roll: angle,
                                color: .white, metalness: 0.8, roughness: 0.35, spin: output))
        }
        return result
    }()

    /// Left and right drive shafts along Z with a stripe so their turning is visible.
    static let halfShafts: [ExplanationRecipePrimitive] = {
        let turning = ExplanationRecipePrimitive.Spin()
        var result: [ExplanationRecipePrimitive] = []
        for (name, side) in [("left", 1.0), ("right", -1.0)] {
            result.append(.init(name: "\(name)-shaft", shape: .cylinder(radius: 0.022, length: 0.7, axis: .z), position: v(0, 0, 0.45 * side),
                                color: .secondary, metalness: 0.9, roughness: 0.25, spin: turning))
            result.append(.init(name: "\(name)-stripe", shape: .box(v(0.02, 0.02, 0.4)), position: v(0, 0.026, 0.45 * side),
                                color: .white, metalness: 0.1, roughness: 0.5, spin: turning))
            result.append(.init(name: "\(name)-joint-inner", shape: .sphere(radius: 0.045), position: v(0, 0, 0.08 * side),
                                color: .secondary, metalness: 0.8, roughness: 0.35))
            result.append(.init(name: "\(name)-joint-outer", shape: .sphere(radius: 0.045), position: v(0, 0, 0.82 * side),
                                color: .secondary, metalness: 0.8, roughness: 0.35))
        }
        return result
    }()

    /// Wheel with tyre, 0.33 m outer radius and 0.22 m tread, axle on Z, five spokes.
    static let wheel: [ExplanationRecipePrimitive] = {
        let turning = ExplanationRecipePrimitive.Spin()
        var result: [ExplanationRecipePrimitive] = [
            .init(name: "tyre", shape: .cylinder(radius: 0.33, length: 0.22, axis: .z), color: .ink, metalness: 0.0, roughness: 0.92, spin: turning),
            .init(name: "rim", shape: .cylinder(radius: 0.23, length: 0.20, axis: .z), color: .secondary, metalness: 0.85, roughness: 0.3, spin: turning),
            .init(name: "hub", shape: .cylinder(radius: 0.06, length: 0.22, axis: .z), color: .secondary, metalness: 0.9, roughness: 0.25, spin: turning)
        ]
        for index in 0..<5 {
            let angle = Double(index) * 2 * Double.pi / 5
            result.append(.init(name: "spoke-\(index)", shape: .box(v(0.17, 0.035, 0.215)),
                                position: v(0.15 * cos(angle), 0.15 * sin(angle), 0), roll: angle,
                                color: index == 0 ? .orange : .white, metalness: 0.7, roughness: 0.35, spin: turning))
        }
        return result
    }()

    /// A simplified shell: lower body, glass cabin, roof and two bumpers, 4.6 m long and 1.6 m wide
    /// at the body. Origin at ground level, centred. It is the part a cutaway hides or fades.
    static let carShell: [ExplanationRecipePrimitive] = [
        .init(name: "lower-body", shape: .box(v(4.5, 0.5, 1.6)), position: v(0, 0.52, 0), color: .secondary, metalness: 0.5, roughness: 0.35),
        .init(name: "cabin", shape: .box(v(2.3, 0.5, 1.45)), position: v(-0.15, 1.02, 0), color: .cyan, metalness: 0.1, roughness: 0.15, opacity: 0.55),
        .init(name: "roof", shape: .box(v(1.7, 0.06, 1.4)), position: v(-0.15, 1.30, 0), color: .secondary, metalness: 0.5, roughness: 0.35),
        .init(name: "bumper-front", shape: .box(v(0.1, 0.28, 1.6)), position: v(2.3, 0.4, 0), color: .ink, metalness: 0.1, roughness: 0.8),
        .init(name: "bumper-rear", shape: .box(v(0.1, 0.28, 1.6)), position: v(-2.3, 0.4, 0), color: .ink, metalness: 0.1, roughness: 0.8)
    ]
}
