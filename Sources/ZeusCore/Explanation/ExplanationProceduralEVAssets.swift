import Foundation

/// Phase 4 procedural EV assets (`docs/POINTING-ASSISTANT-PLAN.md`).
///
/// The battery is a grid of boxes in a group. The inverter is a box with a label.
/// The motor is a stator cylinder and a rotor cylinder. The drivetrain is two gear
/// cylinders plus an axle tube. The wheels are cylinders. Propulsion names the path
/// battery, inverter, motor, wheels as `forward`. Regeneration keeps that order and
/// names `reverse`. Dimensions are metres in a local frame (+X forward, +Y up,
/// +Z right) and are illustrative, not a real vehicle.
///
/// This type does not draw, does not build a scene, and does not open a connection.
public enum ExplanationProceduralEVAssets {
    public static let batteryID = "battery"
    public static let inverterID = "inverter"
    public static let motorID = "motor"
    public static let drivetrainID = "drivetrain"
    public static let wheelsID = "wheels"

    public static let batteryColumns = 4
    public static let batteryRows = 2
    public static let batteryPitchX = 0.5
    public static let batteryPitchZ = 0.375
    public static let cellWidth = 0.5
    public static let cellHeight = 0.125
    public static let cellDepth = 0.25

    public static let inverterWidth = 0.5
    public static let inverterHeight = 0.25
    public static let inverterDepth = 0.375
    public static let inverterLabel = "Inverter"
    /// Gap from the top face of the inverter box to the label, along +Y.
    public static let labelLift = 0.0625

    public static let statorRadius = 0.25
    public static let statorLength = 0.5
    public static let rotorRadius = 0.125
    public static let rotorLength = 0.25
    public static let rotorSpin = 1.0

    public static let inputGearRadius = 0.125
    public static let outputGearRadius = 0.25
    public static let gearLength = 0.125
    public static let inputGearX = -0.1875
    public static let outputGearX = 0.1875
    public static let inputGearSpin = 1.0
    public static let outputGearSpin = -0.5
    public static let axleRadius = 0.0625
    public static let axleLength = 1.0

    public static let wheelRadius = 0.375
    public static let wheelLength = 0.25
    public static let wheelZ = 0.75
    public static let wheelSpin = 1.0

    /// `ExplanationLimits.objects`.
    public static let objectBudget = 256
    /// `ExplanationLimits.coordinate`.
    public static let coordinateLimit = 16_384.0
    /// `ExplanationLimits.text`.
    public static let labelByteBudget = 1_024

    public enum Energy: String, Equatable, Sendable {
        case propulsion
        case regeneration
    }

    public enum Direction: String, Equatable, Sendable {
        case forward
        case reverse
    }

    public enum Axis: String, Equatable, Sendable {
        case x, y, z
    }

    public enum PartKind: String, Equatable, Sendable {
        /// Several solids that belong to one part. The battery grid is the group.
        case group
        case part
    }

    public enum Shape: Equatable, Sendable {
        case box(width: Double, height: Double, depth: Double)
        case cylinder(radius: Double, length: Double, axis: Axis)
    }

    public struct Solid: Equatable, Sendable {
        public var name: String
        public var shape: Shape
        public var x: Double
        public var y: Double
        public var z: Double
        /// Turn about this solid's own axis, relative to the part. Nil stays fixed.
        public var spin: Double?

        public init(name: String, shape: Shape, x: Double, y: Double, z: Double, spin: Double?) {
            self.name = name
            self.shape = shape
            self.x = x
            self.y = y
            self.z = z
            self.spin = spin
        }
    }

    public struct Label: Equatable, Sendable {
        public var text: String
        public var x: Double
        public var y: Double
        public var z: Double

        public init(text: String, x: Double, y: Double, z: Double) {
            self.text = text
            self.x = x
            self.y = y
            self.z = z
        }
    }

    public struct Part: Equatable, Sendable {
        public var id: String
        public var kind: PartKind
        public var solids: [Solid]
        public var label: Label?

        public init(id: String, kind: PartKind, solids: [Solid], label: Label?) {
            self.id = id
            self.kind = kind
            self.solids = solids
            self.label = label
        }
    }

    public struct Flow: Equatable, Sendable {
        public var partIDs: [String]
        public var direction: Direction

        public init(partIDs: [String], direction: Direction) {
            self.partIDs = partIDs
            self.direction = direction
        }
    }

    public struct Assembly: Equatable, Sendable {
        public var parts: [Part]
        public var flow: Flow

        public init(parts: [Part], flow: Flow) {
            self.parts = parts
            self.flow = flow
        }
    }

    public static let flowPartIDs = [batteryID, inverterID, motorID, wheelsID]

    public static func assembly(for energy: Energy) -> Assembly {
        Assembly(
            parts: catalog(),
            flow: Flow(partIDs: flowPartIDs, direction: energy == .propulsion ? .forward : .reverse)
        )
    }

    private static func catalog() -> [Part] {
        [battery(), inverter(), motor(), drivetrain(), wheels()]
    }

    private static func battery() -> Part {
        var solids: [Solid] = []
        solids.reserveCapacity(batteryColumns * batteryRows)
        for column in 0..<batteryColumns {
            for row in 0..<batteryRows {
                solids.append(box(
                    name: "cell-\(column)-\(row)",
                    width: cellWidth, height: cellHeight, depth: cellDepth,
                    x: (Double(column) - 1.5) * batteryPitchX,
                    z: (Double(row) - 0.5) * batteryPitchZ
                ))
            }
        }
        return Part(id: batteryID, kind: .group, solids: solids, label: nil)
    }

    private static func inverter() -> Part {
        Part(
            id: inverterID,
            kind: .part,
            solids: [box(name: "housing", width: inverterWidth, height: inverterHeight, depth: inverterDepth)],
            label: Label(text: inverterLabel, x: 0, y: inverterHeight / 2 + labelLift, z: 0)
        )
    }

    private static func motor() -> Part {
        Part(id: motorID, kind: .part, solids: [
            tube(name: "stator", radius: statorRadius, length: statorLength),
            tube(name: "rotor", radius: rotorRadius, length: rotorLength, spin: rotorSpin),
        ], label: nil)
    }

    private static func drivetrain() -> Part {
        Part(id: drivetrainID, kind: .part, solids: [
            tube(name: "input-gear", radius: inputGearRadius, length: gearLength, x: inputGearX, spin: inputGearSpin),
            tube(name: "output-gear", radius: outputGearRadius, length: gearLength, x: outputGearX, spin: outputGearSpin),
            tube(name: "axle", radius: axleRadius, length: axleLength, x: outputGearX, spin: outputGearSpin),
        ], label: nil)
    }

    private static func wheels() -> Part {
        Part(id: wheelsID, kind: .part, solids: [
            tube(name: "wheel-left", radius: wheelRadius, length: wheelLength, z: wheelZ, spin: wheelSpin),
            tube(name: "wheel-right", radius: wheelRadius, length: wheelLength, z: -wheelZ, spin: wheelSpin),
        ], label: nil)
    }

    private static func box(name: String, width: Double, height: Double, depth: Double,
                            x: Double = 0, y: Double = 0, z: Double = 0) -> Solid {
        Solid(name: name, shape: .box(width: width, height: height, depth: depth), x: x, y: y, z: z, spin: nil)
    }

    private static func tube(name: String, radius: Double, length: Double,
                             x: Double = 0, y: Double = 0, z: Double = 0, spin: Double? = nil) -> Solid {
        Solid(name: name, shape: .cylinder(radius: radius, length: length, axis: .z), x: x, y: y, z: z, spin: spin)
    }
}
