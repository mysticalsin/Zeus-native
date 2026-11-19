import Foundation

/// Slice S3 scene model: named parts, paths, flows, callouts and one cutaway. It is data only.
/// Every field is bounded, no field carries code, URLs or shaders, and a part is addressed by its
/// stable id so a follow-up edits the same scene instead of stacking a second copy.
public enum ExplanationAxis: String, Codable, CaseIterable, Sendable {
    case x, y, z
    public var unit: ExplanationVector3 {
        switch self {
        case .x: .init(x: 1, y: 0, z: 0)
        case .y: .init(x: 0, y: 1, z: 0)
        case .z: .init(x: 0, y: 0, z: 1)
        }
    }
}

public enum ExplanationPartRecipe: String, Codable, CaseIterable, Sendable {
    case batteryPack, inverterBox, motor, reductionGear, halfShafts, wheel, carShell
}

/// Nil colour, metalness or roughness means "use the part's own look": the recipe's colours for a
/// recipe part, steel grey for a plain primitive. A value overrides it for the whole part.
public struct ExplanationPartMaterial: Codable, Equatable, Sendable {
    public var color: ExplanationColor?
    public var metalness: Double?
    public var roughness: Double?
    public var opacity: Double
    public init(color: ExplanationColor? = nil, metalness: Double? = nil, roughness: Double? = nil, opacity: Double = 1) {
        self.color = color; self.metalness = metalness; self.roughness = roughness; self.opacity = opacity
    }
    private enum CodingKeys: String, CodingKey { case color, metalness, roughness, opacity }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(color: try c.decodeIfPresent(ExplanationColor.self, forKey: .color),
                  metalness: try c.decodeIfPresent(Double.self, forKey: .metalness),
                  roughness: try c.decodeIfPresent(Double.self, forKey: .roughness),
                  opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1)
    }
}

/// `count` copies, copy `i` offset by `offset * i` in the part's local frame.
public struct ExplanationPartRepeat: Codable, Equatable, Sendable {
    public var count: Int
    public var offset: ExplanationVector3
    public init(count: Int, offset: ExplanationVector3) { self.count = count; self.offset = offset }
}

/// Continuous rotation of the rotating primitives of a recipe part, in radians per second of
/// animation time (never per frame). Axis is in the part's local frame.
public struct ExplanationPartSpin: Codable, Equatable, Sendable {
    public var radiansPerSecond: Double
    public var axis: ExplanationAxis
    public init(radiansPerSecond: Double, axis: ExplanationAxis = .z) {
        self.radiansPerSecond = radiansPerSecond; self.axis = axis
    }
    private enum CodingKeys: String, CodingKey { case radiansPerSecond, axis }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(radiansPerSecond: try c.decode(Double.self, forKey: .radiansPerSecond),
                  axis: try c.decodeIfPresent(ExplanationAxis.self, forKey: .axis) ?? .z)
    }
}

public struct ExplanationPart: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case group, box, cylinder, sphere, recipe }
    public var id: String
    public var parentID: String?
    public var kind: Kind
    public var recipe: ExplanationPartRecipe?
    public var size: ExplanationVector3?
    public var radius: Double?
    public var depth: Double?
    public var transform: ExplanationTransform
    public var material: ExplanationPartMaterial
    /// A shell can be hidden or made transparent by a cutaway.
    public var isShell: Bool
    public var repeats: ExplanationPartRepeat?
    public var spin: ExplanationPartSpin?
    public var visible: Bool
    public var accessibleDescription: String

    public init(id: String, parentID: String? = nil, kind: Kind, recipe: ExplanationPartRecipe? = nil,
                size: ExplanationVector3? = nil, radius: Double? = nil, depth: Double? = nil,
                transform: ExplanationTransform = .identity, material: ExplanationPartMaterial = .init(),
                isShell: Bool = false, repeats: ExplanationPartRepeat? = nil, spin: ExplanationPartSpin? = nil,
                visible: Bool = true, accessibleDescription: String) {
        self.id = id; self.parentID = parentID; self.kind = kind; self.recipe = recipe; self.size = size
        self.radius = radius; self.depth = depth; self.transform = transform; self.material = material
        self.isShell = isShell; self.repeats = repeats; self.spin = spin; self.visible = visible
        self.accessibleDescription = accessibleDescription
    }

    private enum CodingKeys: String, CodingKey {
        case id, parentID, kind, recipe, size, radius, depth, transform, material
        case isShell = "shell"
        case repeats = "repeat"
        case spin, visible, accessibleDescription
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  parentID: try c.decodeIfPresent(String.self, forKey: .parentID),
                  kind: try c.decode(Kind.self, forKey: .kind),
                  recipe: try c.decodeIfPresent(ExplanationPartRecipe.self, forKey: .recipe),
                  size: try c.decodeIfPresent(ExplanationVector3.self, forKey: .size),
                  radius: try c.decodeIfPresent(Double.self, forKey: .radius),
                  depth: try c.decodeIfPresent(Double.self, forKey: .depth),
                  transform: try c.decodeIfPresent(ExplanationTransform.self, forKey: .transform) ?? .identity,
                  material: try c.decodeIfPresent(ExplanationPartMaterial.self, forKey: .material) ?? .init(),
                  isShell: try c.decodeIfPresent(Bool.self, forKey: .isShell) ?? false,
                  repeats: try c.decodeIfPresent(ExplanationPartRepeat.self, forKey: .repeats),
                  spin: try c.decodeIfPresent(ExplanationPartSpin.self, forKey: .spin),
                  visible: try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true,
                  accessibleDescription: try c.decode(String.self, forKey: .accessibleDescription))
    }
}

/// A named world-space polyline that markers travel along. Order defines "forward".
public struct ExplanationFlowPath: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var points: [ExplanationVector3]
    public init(id: String, points: [ExplanationVector3]) { self.id = id; self.points = points }
}

/// Markers travelling along a named path. Direction is defined against the path's point order in
/// world space, so no camera orientation can change what "forward" or "reverse" means.
public struct ExplanationFlow: Codable, Equatable, Sendable, Identifiable {
    public enum Direction: String, Codable, CaseIterable, Sendable {
        case forward, reverse
        public var sign: Double { self == .forward ? 1 : -1 }
    }
    public var id: String
    public var pathID: String
    /// World units per second of animation time.
    public var speed: Double
    public var direction: Direction
    public var count: Int
    public var color: ExplanationColor
    public var active: Bool
    public var markerSize: Double
    public init(id: String, pathID: String, speed: Double, direction: Direction = .forward, count: Int = 4,
                color: ExplanationColor = .cyan, active: Bool = true, markerSize: Double = 0.08) {
        self.id = id; self.pathID = pathID; self.speed = speed; self.direction = direction; self.count = count
        self.color = color; self.active = active; self.markerSize = markerSize
    }
    private enum CodingKeys: String, CodingKey { case id, pathID, speed, direction, count, color, active, markerSize }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), pathID: try c.decode(String.self, forKey: .pathID),
                  speed: try c.decode(Double.self, forKey: .speed),
                  direction: try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .forward,
                  count: try c.decodeIfPresent(Int.self, forKey: .count) ?? 4,
                  color: try c.decodeIfPresent(ExplanationColor.self, forKey: .color) ?? .cyan,
                  active: try c.decodeIfPresent(Bool.self, forKey: .active) ?? true,
                  markerSize: try c.decodeIfPresent(Double.self, forKey: .markerSize) ?? 0.08)
    }
}

/// A text label anchored to a world point. With `partID`, `anchor` is an offset (world axes)
/// from that part's origin, so the label follows the part when it moves.
public struct ExplanationCallout: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var partID: String?
    public var anchor: ExplanationVector3
    public var visible: Bool
    public init(id: String, text: String, partID: String? = nil, anchor: ExplanationVector3 = .zero, visible: Bool = true) {
        self.id = id; self.text = text; self.partID = partID; self.anchor = anchor; self.visible = visible
    }
    private enum CodingKeys: String, CodingKey { case id, text, partID, anchor, visible }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text),
                  partID: try c.decodeIfPresent(String.self, forKey: .partID),
                  anchor: try c.decodeIfPresent(ExplanationVector3.self, forKey: .anchor) ?? .zero,
                  visible: try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true)
    }
}

public struct ExplanationCutaway: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable { case none, hide, transparent }
    public var style: Style
    public var partIDs: [String]
    public var opacity: Double
    public static let none = Self(style: .none, partIDs: [], opacity: 0.15)
    public init(style: Style, partIDs: [String], opacity: Double = 0.15) {
        self.style = style; self.partIDs = partIDs; self.opacity = opacity
    }
}

public struct ExplanationModel3D: Codable, Equatable, Sendable {
    public var parts: [String: ExplanationPart]
    public var paths: [String: ExplanationFlowPath]
    public var flows: [String: ExplanationFlow]
    public var callouts: [String: ExplanationCallout]
    public var cutaway: ExplanationCutaway
    /// Multiplier on every part spin and flow speed. 1 is normal; "slow it down" lowers it.
    public var animationRate: Double
    public var caption: String?
    public static let empty = Self()
    public init(parts: [String: ExplanationPart] = [:], paths: [String: ExplanationFlowPath] = [:],
                flows: [String: ExplanationFlow] = [:], callouts: [String: ExplanationCallout] = [:],
                cutaway: ExplanationCutaway = .none, animationRate: Double = 1, caption: String? = nil) {
        self.parts = parts; self.paths = paths; self.flows = flows; self.callouts = callouts
        self.cutaway = cutaway; self.animationRate = animationRate; self.caption = caption
    }
    public var isEmpty: Bool { parts.isEmpty && flows.isEmpty && callouts.isEmpty }
    /// True when something moves on its own, so a render loop is worth running.
    public var hasMotion: Bool {
        guard animationRate > 0 else { return false }
        return parts.values.contains { $0.visible && ($0.spin?.radiansPerSecond ?? 0) != 0 }
            || flows.values.contains { $0.active && $0.speed > 0 }
    }
}

extension ExplanationScene {
    /// True when the scene carries S3 model parts that the 3D view should show.
    public var hasModel3D: Bool { model?.isEmpty == false }
}

// MARK: - Operations

public enum ExplanationCameraPreset: String, Codable, CaseIterable, Sendable {
    case overview, front, rear, side, top, inside
}

public struct ExplanationViewChange: Codable, Equatable, Sendable {
    public var preset: ExplanationCameraPreset?
    /// Degrees about the world Y axis through the camera target. Positive moves the camera around to its right.
    public var orbit: Double?
    /// Multiplier on the camera distance. Below 1 moves closer.
    public var zoom: Double?
    public init(preset: ExplanationCameraPreset? = nil, orbit: Double? = nil, zoom: Double? = nil) {
        self.preset = preset; self.orbit = orbit; self.zoom = zoom
    }
}

public struct ExplanationCutawayChange: Codable, Equatable, Sendable {
    public var expectedRevision: Int
    public var style: ExplanationCutaway.Style
    public var partIDs: [String]
    public var opacity: Double?
    public init(expectedRevision: Int, style: ExplanationCutaway.Style, partIDs: [String], opacity: Double? = nil) {
        self.expectedRevision = expectedRevision; self.style = style; self.partIDs = partIDs; self.opacity = opacity
    }
}

public struct ExplanationModelSettings: Codable, Equatable, Sendable {
    public var caption: String?
    public var animationRate: Double?
    public init(caption: String? = nil, animationRate: Double? = nil) {
        self.caption = caption; self.animationRate = animationRate
    }
}

/// The fields an `edit` may change. A field that does not apply to the target kind is rejected.
/// Parts: opacity, visible, color, metalness, roughness, position, rotation, scale, spin.
/// Flows: speed, direction, active, color. Callouts: text, visible.
public struct ExplanationPartChange: Codable, Equatable, Sendable {
    public var opacity: Double?
    public var visible: Bool?
    public var color: ExplanationColor?
    public var metalness: Double?
    public var roughness: Double?
    public var position: ExplanationVector3?
    public var rotation: ExplanationVector3?
    public var scale: ExplanationVector3?
    public var spin: Double?
    public var speed: Double?
    public var direction: ExplanationFlow.Direction?
    public var active: Bool?
    public var text: String?
    public init(opacity: Double? = nil, visible: Bool? = nil, color: ExplanationColor? = nil,
                metalness: Double? = nil, roughness: Double? = nil, position: ExplanationVector3? = nil,
                rotation: ExplanationVector3? = nil, scale: ExplanationVector3? = nil, spin: Double? = nil,
                speed: Double? = nil, direction: ExplanationFlow.Direction? = nil, active: Bool? = nil,
                text: String? = nil) {
        self.opacity = opacity; self.visible = visible; self.color = color; self.metalness = metalness
        self.roughness = roughness; self.position = position; self.rotation = rotation; self.scale = scale
        self.spin = spin; self.speed = speed; self.direction = direction; self.active = active; self.text = text
    }
    public var isEmpty: Bool { self == Self() }
}

public struct ExplanationPartEdit: Codable, Equatable, Sendable {
    public var id: String
    public var expectedRevision: Int
    public var change: ExplanationPartChange
    public init(id: String, expectedRevision: Int, change: ExplanationPartChange) {
        self.id = id; self.expectedRevision = expectedRevision; self.change = change
    }
}

public enum ExplanationModelOperation: Equatable, Sendable, Codable {
    case part(ExplanationPart)
    case path(ExplanationFlowPath)
    case flow(ExplanationFlow)
    case callout(ExplanationCallout)
    case view(ExplanationViewChange)
    case cutaway(ExplanationCutawayChange)
    case settings(ExplanationModelSettings)
    case edit(ExplanationPartEdit)

    /// Wire `op` names. `settings` is spelled "model" on the wire.
    public static let wireNames: Set<String> = ["part", "path", "flow", "callout", "view", "cutaway", "model", "edit"]

    private enum CodingKeys: String, CodingKey {
        case op, part, path, flow, callout, preset, orbit, zoom, expectedRevision, style, partIDs, opacity
        case caption, animationRate, id, change
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .op) {
        case "part": self = .part(try c.decode(ExplanationPart.self, forKey: .part))
        case "path": self = .path(try c.decode(ExplanationFlowPath.self, forKey: .path))
        case "flow": self = .flow(try c.decode(ExplanationFlow.self, forKey: .flow))
        case "callout": self = .callout(try c.decode(ExplanationCallout.self, forKey: .callout))
        case "view":
            self = .view(.init(preset: try c.decodeIfPresent(ExplanationCameraPreset.self, forKey: .preset),
                               orbit: try c.decodeIfPresent(Double.self, forKey: .orbit),
                               zoom: try c.decodeIfPresent(Double.self, forKey: .zoom)))
        case "cutaway":
            self = .cutaway(.init(expectedRevision: try c.decode(Int.self, forKey: .expectedRevision),
                                  style: try c.decode(ExplanationCutaway.Style.self, forKey: .style),
                                  partIDs: try c.decode([String].self, forKey: .partIDs),
                                  opacity: try c.decodeIfPresent(Double.self, forKey: .opacity)))
        case "model":
            self = .settings(.init(caption: try c.decodeIfPresent(String.self, forKey: .caption),
                                   animationRate: try c.decodeIfPresent(Double.self, forKey: .animationRate)))
        case "edit":
            self = .edit(.init(id: try c.decode(String.self, forKey: .id),
                               expectedRevision: try c.decode(Int.self, forKey: .expectedRevision),
                               change: try c.decode(ExplanationPartChange.self, forKey: .change)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "unknown model operation")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .part(let value): try c.encode("part", forKey: .op); try c.encode(value, forKey: .part)
        case .path(let value): try c.encode("path", forKey: .op); try c.encode(value, forKey: .path)
        case .flow(let value): try c.encode("flow", forKey: .op); try c.encode(value, forKey: .flow)
        case .callout(let value): try c.encode("callout", forKey: .op); try c.encode(value, forKey: .callout)
        case .view(let value):
            try c.encode("view", forKey: .op)
            try c.encodeIfPresent(value.preset, forKey: .preset)
            try c.encodeIfPresent(value.orbit, forKey: .orbit)
            try c.encodeIfPresent(value.zoom, forKey: .zoom)
        case .cutaway(let value):
            try c.encode("cutaway", forKey: .op)
            try c.encode(value.expectedRevision, forKey: .expectedRevision)
            try c.encode(value.style, forKey: .style)
            try c.encode(value.partIDs, forKey: .partIDs)
            try c.encodeIfPresent(value.opacity, forKey: .opacity)
        case .settings(let value):
            try c.encode("model", forKey: .op)
            try c.encodeIfPresent(value.caption, forKey: .caption)
            try c.encodeIfPresent(value.animationRate, forKey: .animationRate)
        case .edit(let value):
            try c.encode("edit", forKey: .op)
            try c.encode(value.id, forKey: .id)
            try c.encode(value.expectedRevision, forKey: .expectedRevision)
            try c.encode(value.change, forKey: .change)
        }
    }
}

/// Why an edit was refused. The scene is unchanged and the turn is marked failed.
public enum ExplanationEditRejection: Equatable, Sendable {
    case missingTarget(String)
    case staleRevision(expected: Int, actual: Int)
    case inapplicableChange(String)
}

public enum ExplanationModelLimits {
    public static let parts = 96
    public static let repeatCount = 16
    public static let instances = 160
    public static let primitives = 1200
    public static let paths = 12
    public static let pathPoints = 32
    public static let flows = 12
    public static let markersPerFlow = 24
    public static let markers = 96
    public static let callouts = 24
    public static let calloutText = 60
    public static let caption = 160
    public static let hierarchyDepth = 6
    public static let spinRate = 60.0
    public static let flowSpeed = 20.0
    public static let animationRate = 4.0
    public static let minimumAnimationRate = 0.05
    public static let dimension = 1000.0
}
