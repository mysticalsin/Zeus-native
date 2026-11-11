import Foundation

/// Canvas uses logical points; capture uses the delivered image's pixel grid
/// (after app-owned crop/resize), both top-left and y down. World is right-handed,
/// Y-up and illustrative. Capture/display transforms are app-issued context;
/// a model cannot change a display, crop, backing scale or capture rectangle.
public enum ExplanationSpace: String, Codable, CaseIterable, Sendable { case canvas, world, capture }

public struct ExplanationVector3: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double = 0) { self.x = x; self.y = y; self.z = z }
    public static let zero = Self(x: 0, y: 0, z: 0)
    public static let one = Self(x: 1, y: 1, z: 1)
}

public struct ExplanationSize2: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct ExplanationRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct ExplanationTransform: Codable, Equatable, Sendable {
    public var position: ExplanationVector3
    /// Euler angles in radians. No code, arbitrary matrix, or callback is accepted.
    public var rotation: ExplanationVector3
    public var scale: ExplanationVector3
    public init(position: ExplanationVector3 = .zero, rotation: ExplanationVector3 = .zero,
                scale: ExplanationVector3 = .one) {
        self.position = position; self.rotation = rotation; self.scale = scale
    }
    public static let identity = Self()
}

public enum ExplanationColor: String, Codable, CaseIterable, Sendable {
    case ink, secondary, white, blue, green, orange, red, purple, cyan, clear
}

public enum ExplanationMaterial: String, Codable, CaseIterable, Sendable { case matte, metal, glass, emissive }

public struct ExplanationStyle: Codable, Equatable, Sendable {
    public var fill: ExplanationColor
    public var stroke: ExplanationColor
    public var lineWidth: Double
    public var opacity: Double
    public var dashed: Bool
    public var material: ExplanationMaterial
    public init(fill: ExplanationColor = .blue, stroke: ExplanationColor = .ink,
                lineWidth: Double = 2, opacity: Double = 1, dashed: Bool = false,
                material: ExplanationMaterial = .matte) {
        self.fill = fill; self.stroke = stroke; self.lineWidth = lineWidth
        self.opacity = opacity; self.dashed = dashed; self.material = material
    }
}

/// A finite geometry vocabulary. Only parameters admitted for `kind` may be set.
/// Curves/meshes are data with strict vertex/index limits, never generated shaders.
public struct ExplanationGeometry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case group, point, ring, roundedRectangle, region, arrow, connector, underline, highlight
        case badge, label, card, chart, timeline, path, image
        case box, sphere, cylinder, cone, tube, extrusion, mesh
    }
    public var kind: Kind
    public var size: ExplanationVector3?
    public var radius: Double?
    public var secondaryRadius: Double?
    public var depth: Double?
    public var points: [ExplanationVector3]?
    public var vertices: [ExplanationVector3]?
    public var indices: [Int]?
    public var values: [Double]?
    public var labels: [String]?
    public var fromID: String?
    public var toID: String?
    /// Protocol v3 only, chart and timeline only: scale, domain, units and data provenance.
    public var axis: ExplanationChartAxis?
    public init(kind: Kind, size: ExplanationVector3? = nil, radius: Double? = nil,
                secondaryRadius: Double? = nil, depth: Double? = nil,
                points: [ExplanationVector3]? = nil, vertices: [ExplanationVector3]? = nil,
                indices: [Int]? = nil, values: [Double]? = nil, labels: [String]? = nil,
                fromID: String? = nil, toID: String? = nil, axis: ExplanationChartAxis? = nil) {
        self.kind = kind; self.size = size; self.radius = radius; self.secondaryRadius = secondaryRadius
        self.depth = depth; self.points = points; self.vertices = vertices; self.indices = indices
        self.values = values; self.labels = labels; self.fromID = fromID; self.toID = toID; self.axis = axis
    }
}

/// Where a chart's numbers came from. A chart without an axis spec is treated as `.example`.
public enum ExplanationDataSource: String, Codable, CaseIterable, Sendable {
    case userProvided, onScreen, live, example
}

/// How positions are spaced. A chart's value axis is `linear` (bars are always evenly spaced
/// categories). A timeline is `time` (position proportional to its values) or `categorical`
/// (evenly spaced, explicitly not to scale).
public enum ExplanationScaleKind: String, Codable, CaseIterable, Sendable { case linear, categorical, time }

public struct ExplanationAxisDomain: Codable, Equatable, Sendable {
    public var lower: Double
    public var upper: Double
    public init(lower: Double, upper: Double) { self.lower = lower; self.upper = upper }
}

/// Protocol v3 chart axis specification. Every field is finite data; the app, not the model,
/// computes ticks and pixel positions.
public struct ExplanationChartAxis: Codable, Equatable, Sendable {
    public var scale: ExplanationScaleKind
    /// Explicit value domain. Omitted: derived from the data. Never narrower than the data.
    public var domain: ExplanationAxisDomain?
    public var units: String?
    /// Approximate tick count, 2...12.
    public var tickHint: Int?
    /// Charts only. Omitted means true: a magnitude bar chart includes zero. False is allowed and
    /// is labelled on the chart as a truncated axis.
    public var includeZero: Bool?
    public var source: ExplanationDataSource
    /// ISO 8601 date-time. Required for `live`, forbidden otherwise.
    public var asOf: String?
    public init(scale: ExplanationScaleKind, domain: ExplanationAxisDomain? = nil, units: String? = nil,
                tickHint: Int? = nil, includeZero: Bool? = nil, source: ExplanationDataSource = .example,
                asOf: String? = nil) {
        self.scale = scale; self.domain = domain; self.units = units; self.tickHint = tickHint
        self.includeZero = includeZero; self.source = source; self.asOf = asOf
    }
}

public enum ExplanationProvenance: String, Codable, Sendable {
    case proceduralIllustration, userProvided, retrievedPhoto, generatedImage
}

public struct ExplanationObject: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var parentID: String?
    public var space: ExplanationSpace
    public var captureID: UUID?
    public var geometry: ExplanationGeometry
    public var transform: ExplanationTransform
    public var style: ExplanationStyle
    public var text: String?
    public var accessibleDescription: String
    public var assetID: String?
    public var sourceIDs: [String]
    public var provenance: ExplanationProvenance
    public var highlighted: Bool
    public var reveal: Double
    /// Protocol v2 only: names an app-issued pointing candidate ("t0".."t15"). The app
    /// replaces model geometry with the candidate's rectangle and clears this field.
    public var targetID: String?

    public init(id: String, parentID: String? = nil, space: ExplanationSpace = .canvas,
                captureID: UUID? = nil, geometry: ExplanationGeometry,
                transform: ExplanationTransform = .identity, style: ExplanationStyle = .init(),
                text: String? = nil, accessibleDescription: String, assetID: String? = nil,
                sourceIDs: [String] = [], provenance: ExplanationProvenance = .proceduralIllustration,
                highlighted: Bool = false, reveal: Double = 1, targetID: String? = nil) {
        self.targetID = targetID
        self.id = id; self.parentID = parentID; self.space = space; self.captureID = captureID
        self.geometry = geometry; self.transform = transform; self.style = style; self.text = text
        self.accessibleDescription = accessibleDescription; self.assetID = assetID
        self.sourceIDs = sourceIDs; self.provenance = provenance; self.highlighted = highlighted; self.reveal = reveal
    }

    private enum CodingKeys: String, CodingKey {
        case id, parentID, space, captureID, geometry, transform, style, text, accessibleDescription
        case assetID, sourceIDs, provenance, highlighted, reveal, targetID
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), parentID: try c.decodeIfPresent(String.self, forKey: .parentID),
                  space: try c.decodeIfPresent(ExplanationSpace.self, forKey: .space) ?? .canvas,
                  captureID: try c.decodeIfPresent(UUID.self, forKey: .captureID),
                  geometry: try c.decode(ExplanationGeometry.self, forKey: .geometry),
                  transform: try c.decodeIfPresent(ExplanationTransform.self, forKey: .transform) ?? .identity,
                  style: try c.decodeIfPresent(ExplanationStyle.self, forKey: .style) ?? .init(),
                  text: try c.decodeIfPresent(String.self, forKey: .text),
                  accessibleDescription: try c.decode(String.self, forKey: .accessibleDescription),
                  assetID: try c.decodeIfPresent(String.self, forKey: .assetID),
                  sourceIDs: try c.decodeIfPresent([String].self, forKey: .sourceIDs) ?? [],
                  provenance: try c.decodeIfPresent(ExplanationProvenance.self, forKey: .provenance) ?? .proceduralIllustration,
                  highlighted: try c.decodeIfPresent(Bool.self, forKey: .highlighted) ?? false,
                  reveal: try c.decodeIfPresent(Double.self, forKey: .reveal) ?? 1,
                  targetID: try c.decodeIfPresent(String.self, forKey: .targetID))
    }
}

public struct ExplanationObjectPatch: Codable, Equatable, Sendable {
    public var geometry: ExplanationGeometry?
    public var transform: ExplanationTransform?
    public var style: ExplanationStyle?
    public var text: String?
    public var accessibleDescription: String?
    public init(geometry: ExplanationGeometry? = nil, transform: ExplanationTransform? = nil,
                style: ExplanationStyle? = nil, text: String? = nil, accessibleDescription: String? = nil) {
        self.geometry = geometry; self.transform = transform; self.style = style
        self.text = text; self.accessibleDescription = accessibleDescription
    }
}

public struct ExplanationCamera: Codable, Equatable, Sendable {
    public var position: ExplanationVector3
    public var target: ExplanationVector3
    public var fieldOfView: Double
    public init(position: ExplanationVector3 = .init(x: 0, y: 3, z: 8),
                target: ExplanationVector3 = .zero, fieldOfView: Double = 45) {
        self.position = position; self.target = target; self.fieldOfView = fieldOfView
    }
}

public struct ExplanationAnimation: Codable, Equatable, Sendable {
    public enum Property: String, Codable, Sendable { case position, rotation, scale, opacity, strokeReveal }
    public enum Curve: String, Codable, Sendable { case linear, easeInOut }
    public var property: Property
    public var to: ExplanationVector3
    /// Bounded relative transition length, not an invented audio timestamp.
    public var duration: Double
    public var curve: Curve
    public init(property: Property, to: ExplanationVector3, duration: Double, curve: Curve = .easeInOut) {
        self.property = property; self.to = to; self.duration = duration; self.curve = curve
    }
}

/// Each operation has a closed set of fields. The wire decoder rejects extra fields,
/// including URLs, callbacks, native actions, code, and model-issued audio references.
public enum ExplanationOperation: Equatable, Sendable, Codable {
    case create(ExplanationObject)
    case update(id: String, patch: ExplanationObjectPatch)
    case remove(id: String)
    case move(id: String, position: ExplanationVector3)
    case recolor(id: String, color: ExplanationColor)
    case highlight(id: String, highlighted: Bool)
    case group(id: String, members: [String])
    case label(id: String, text: String)
    case connect(ExplanationObject)
    case camera(ExplanationCamera)
    case animate(id: String, animation: ExplanationAnimation)
    case clear

    private enum CodingKeys: String, CodingKey { case op, object, id, patch, position, color, highlighted, members, text, camera, animation }
    private enum Name: String, Codable { case create, update, remove, move, recolor, highlight, group, label, connect, camera, animate, clear }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Name.self, forKey: .op) {
        case .create: self = .create(try c.decode(ExplanationObject.self, forKey: .object))
        case .connect: self = .connect(try c.decode(ExplanationObject.self, forKey: .object))
        case .update: self = .update(id: try c.decode(String.self, forKey: .id), patch: try c.decode(ExplanationObjectPatch.self, forKey: .patch))
        case .remove: self = .remove(id: try c.decode(String.self, forKey: .id))
        case .move: self = .move(id: try c.decode(String.self, forKey: .id), position: try c.decode(ExplanationVector3.self, forKey: .position))
        case .recolor: self = .recolor(id: try c.decode(String.self, forKey: .id), color: try c.decode(ExplanationColor.self, forKey: .color))
        case .highlight: self = .highlight(id: try c.decode(String.self, forKey: .id), highlighted: try c.decode(Bool.self, forKey: .highlighted))
        case .group: self = .group(id: try c.decode(String.self, forKey: .id), members: try c.decode([String].self, forKey: .members))
        case .label: self = .label(id: try c.decode(String.self, forKey: .id), text: try c.decode(String.self, forKey: .text))
        case .camera: self = .camera(try c.decode(ExplanationCamera.self, forKey: .camera))
        case .animate: self = .animate(id: try c.decode(String.self, forKey: .id), animation: try c.decode(ExplanationAnimation.self, forKey: .animation))
        case .clear: self = .clear
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .create(let object): try c.encode(Name.create, forKey: .op); try c.encode(object, forKey: .object)
        case .connect(let object): try c.encode(Name.connect, forKey: .op); try c.encode(object, forKey: .object)
        case .update(let id, let patch): try c.encode(Name.update, forKey: .op); try c.encode(id, forKey: .id); try c.encode(patch, forKey: .patch)
        case .remove(let id): try c.encode(Name.remove, forKey: .op); try c.encode(id, forKey: .id)
        case .move(let id, let position): try c.encode(Name.move, forKey: .op); try c.encode(id, forKey: .id); try c.encode(position, forKey: .position)
        case .recolor(let id, let color): try c.encode(Name.recolor, forKey: .op); try c.encode(id, forKey: .id); try c.encode(color, forKey: .color)
        case .highlight(let id, let highlighted): try c.encode(Name.highlight, forKey: .op); try c.encode(id, forKey: .id); try c.encode(highlighted, forKey: .highlighted)
        case .group(let id, let members): try c.encode(Name.group, forKey: .op); try c.encode(id, forKey: .id); try c.encode(members, forKey: .members)
        case .label(let id, let text): try c.encode(Name.label, forKey: .op); try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
        case .camera(let camera): try c.encode(Name.camera, forKey: .op); try c.encode(camera, forKey: .camera)
        case .animate(let id, let animation): try c.encode(Name.animate, forKey: .op); try c.encode(id, forKey: .id); try c.encode(animation, forKey: .animation)
        case .clear: try c.encode(Name.clear, forKey: .op)
        }
    }
}

public struct ExplanationAnchor: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case start, end, word }
    public var kind: Kind
    /// Index into actual provider alignment marks. Absent alignment falls back to
    /// beat start; it must never be replaced by a word-count timing estimate.
    public var wordIndex: Int?
    public init(kind: Kind, wordIndex: Int? = nil) { self.kind = kind; self.wordIndex = wordIndex }
    public static let start = Self(kind: .start)
    public static let end = Self(kind: .end)
    public static func word(_ index: Int) -> Self { .init(kind: .word, wordIndex: index) }
}

public struct ExplanationCue: Codable, Equatable, Sendable {
    public var id: String
    public var anchor: ExplanationAnchor
    public var operations: [ExplanationOperation]
    public init(id: String, anchor: ExplanationAnchor = .start, operations: [ExplanationOperation]) {
        self.id = id; self.anchor = anchor; self.operations = operations
    }
}

public struct ExplanationSpeech: Codable, Equatable, Sendable {
    public var chunkID: String
    public var text: String
    public init(chunkID: String, text: String) { self.chunkID = chunkID; self.text = text }
}

public struct ExplanationEvent: Codable, Equatable, Sendable {
    public var version: Int
    public var sessionID: UUID
    public var turnID: UUID
    public var sceneID: UUID
    public var sequence: Int
    public var baseRevision: Int
    public var revision: Int
    public var beatID: String
    public var speech: ExplanationSpeech
    public var cues: [ExplanationCue]
    public var isFinal: Bool
    public init(version: Int = 1, sessionID: UUID, turnID: UUID, sceneID: UUID, sequence: Int,
                baseRevision: Int, revision: Int, beatID: String, speech: ExplanationSpeech,
                cues: [ExplanationCue], isFinal: Bool = false) {
        self.version = version; self.sessionID = sessionID; self.turnID = turnID; self.sceneID = sceneID
        self.sequence = sequence; self.baseRevision = baseRevision; self.revision = revision
        self.beatID = beatID; self.speech = speech; self.cues = cues; self.isFinal = isFinal
    }
}

public struct ExplanationScene: Codable, Equatable, Sendable {
    public var version: Int
    public var sessionID: UUID
    public var sceneID: UUID
    public var revision: Int
    public var canvasSize: ExplanationSize2
    public var captureID: UUID?
    public var objects: [String: ExplanationObject]
    public var camera: ExplanationCamera
    public init(version: Int = 1, sessionID: UUID, sceneID: UUID, revision: Int = 0,
                canvasSize: ExplanationSize2 = .init(width: 1024, height: 768), captureID: UUID? = nil,
                objects: [String: ExplanationObject] = [:], camera: ExplanationCamera = .init()) {
        self.version = version; self.sessionID = sessionID; self.sceneID = sceneID; self.revision = revision
        self.canvasSize = canvasSize; self.captureID = captureID; self.objects = objects; self.camera = camera
    }
}

/// These are app-issued references, never fields admitted from model wire data.
public struct ExplanationAlignmentMark: Codable, Equatable, Sendable {
    public var wordIndex: Int
    public var start: Double
    public var end: Double
    public init(wordIndex: Int, start: Double, end: Double) { self.wordIndex = wordIndex; self.start = start; self.end = end }
}

public struct ExplanationAudioChunk: Codable, Equatable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var turnID: UUID
    public var sceneID: UUID
    public var beatID: String
    public var chunkID: String
    public var duration: Double
    public var sampleRate: Double
    public var alignment: [ExplanationAlignmentMark]
    public init(id: UUID = UUID(), sessionID: UUID, turnID: UUID, sceneID: UUID, beatID: String,
                chunkID: String, duration: Double, sampleRate: Double, alignment: [ExplanationAlignmentMark] = []) {
        self.id = id; self.sessionID = sessionID; self.turnID = turnID; self.sceneID = sceneID
        self.beatID = beatID; self.chunkID = chunkID; self.duration = duration
        self.sampleRate = sampleRate; self.alignment = alignment
    }
}

/// A trusted app resolver populates IDs after checking bytes, licensing/provenance
/// and network policy. IDs alone do not authorize arbitrary retrieval or execution.
public struct ExplanationRegistry: Equatable, Sendable {
    public var assetIDs: Set<String>
    public var sourceIDs: Set<String>
    public init(assetIDs: Set<String> = [], sourceIDs: Set<String> = []) { self.assetIDs = assetIDs; self.sourceIDs = sourceIDs }
    public static let empty = Self()
}

/// Which wire version a turn may use. v1 is the Chat protocol. v2 (pointing turns only)
/// additionally admits `targetID`, limited to the candidate IDs the app issued for this turn.
/// v3 (pointing turns) is v2 plus the chart `axis` specification on chart/timeline geometry.
public enum ExplanationWireProfile: Equatable, Sendable {
    case v1
    case v2(candidateIDs: Set<String>)
    case v3(candidateIDs: Set<String>)

    /// The app-issued candidate IDs, or nil for a profile that admits no `targetID`.
    public var candidateIDs: Set<String>? {
        switch self {
        case .v1: nil
        case .v2(let ids), .v3(let ids): ids
        }
    }
}

public enum ExplanationFailure: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    case staleIdentity
    case revisionConflict
    case sequenceGap
    case conflictingDuplicate
    case streamFinished
    case cancelled
    case limitExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .invalid: "The explanation contained an invalid or unsupported scene."
        case .staleIdentity: "This response belongs to an earlier explanation."
        case .revisionConflict: "The scene changed while this response was being prepared. Try again."
        case .sequenceGap: "Part of the explanation is missing. Try again."
        case .conflictingDuplicate: "The provider returned conflicting explanation updates."
        case .streamFinished: "This explanation has already finished."
        case .cancelled: "Explanation stopped."
        case .limitExceeded: "This explanation is too large. Try a smaller step."
        }
    }
}

public enum ExplanationLimits {
    public static let frameBytes = 65_536
    public static let turnBytes = 524_288
    public static let events = 64
    public static let cuesPerEvent = 16
    public static let operationsPerEvent = 128
    public static let objects = 256
    public static let points = 1024
    public static let vertices = 4096
    public static let indices = 12_288
    public static let text = 1024
    public static let speech = 1600
    public static let revision = 1_000_000_000
    public static let coordinate = 16_384.0
    public static let animationSeconds = 30.0
    public static let chartUnitsBytes = 24
    public static let chartAsOfBytes = 40
    public static let chartTickHint = 2...12
}
