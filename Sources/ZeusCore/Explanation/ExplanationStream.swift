import Foundation

/// The only model-data entry point. Codable is also used for app-owned history;
/// raw model bytes must pass this closed-schema, duplicate-key rejecting decoder.
public enum ExplanationWire {
    public static func decode(_ data: Data, profile: ExplanationWireProfile = .v1) throws -> ExplanationEvent {
        guard !data.isEmpty, data.count <= ExplanationLimits.frameBytes else {
            throw ExplanationFailure.limitExceeded("event bytes")
        }
        do {
            var scanner = ExplanationJSONScanner(bytes: Array(data))
            let value = try scanner.parse()
            try schema(value, profile: profile)
            let event = try JSONDecoder().decode(ExplanationEvent.self, from: data)
            try ExplanationSceneReducer.validate(event, profile: profile)
            return event
        } catch let failure as ExplanationFailure { throw failure }
        catch { throw ExplanationFailure.invalid("malformed event JSON") }
    }

    /// A canonical compact event, without the NDJSON newline delimiter.
    public static func encode(_ event: ExplanationEvent) throws -> Data {
        try ExplanationSceneReducer.validate(event)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(event)
        guard data.count <= ExplanationLimits.frameBytes else { throw ExplanationFailure.limitExceeded("event bytes") }
        return data
    }

    public static let modelInstructions = """
    Return only compact NDJSON: one version-1 ExplanationEvent per line, ending each line with LF.
    Copy app-issued sessionID, turnID and sceneID exactly. Start sequence at zero, increment by one.
    baseRevision is the supplied current revision for the first beat; revision = baseRevision + 1.
    Later beats use the previous revision. Every beatID and speech.chunkID must be unique in this turn.
    Required event fields: version, sessionID, turnID, sceneID, sequence, baseRevision, revision,
    beatID, speech:{chunkID,text}, cues:[{id,anchor,operations}], isFinal. Mark only the final beat isFinal:true.
    Anchors are {kind:"start"}, {kind:"end"}, or {kind:"word",wordIndex:integer}; word indices refer to
    actual provider alignment when available. Do not invent timestamps, audio references or durations of speech.
    Cues must be ordered by anchor and contain operations; use cues:[] for a spoken-only beat.
    Closed operations: create/connect {object}, update {id,patch}, remove {id}, move {id,position},
    recolor {id,color}, highlight {id,highlighted}, group {id,members}, label {id,text}, camera {camera},
    animate {id,animation}, clear {}. Every operation also requires its "op" string.
    Objects require id, geometry:{kind,...}, accessibleDescription; optional parentID, space, captureID,
    transform, style, text, assetID, sourceIDs, provenance, highlighted, reveal. IDs: 1..64 ASCII letters,
    digits, hyphens or underscores. Geometry and operations are finite data, never JavaScript, Swift,
    shell commands, native actions, HTML, callbacks, URLs or shaders. Use only app-approved asset/source IDs.
    canvas = logical top-left points, capture = delivered image pixels bound to the supplied captureID,
    world = illustrative right-handed Y-up units. Never invent or modify capture/display transforms.
    Geometry: group/label(no parameters); point/ring/badge(radius); roundedRectangle/region/highlight/card/image
    (size,optional radius); arrow/underline/path(points); connector(fromID,toID); chart/timeline(size,values,labels);
    box(size); sphere(radius); cylinder(radius,depth); cone(radius,depth,optional secondaryRadius);
    tube(radius,points); extrusion(planar points,depth); mesh(vertices,triangle indices).
    label/card/badge require nonempty text. Chart/timeline require equal-length values and labels;
    timeline values must be nondecreasing. Paths need at least two points; extrusions need at least three.
    3D primitives must use space:"world"; groups and labels may use world or a 2D space.
    Images require an approved assetID and provenance userProvided, retrievedPhoto or generatedImage;
    all other geometry uses proceduralIllustration. No source/asset ID is approved unless the app lists it.
    Vectors are {x,y,z}; 2D sizes and points use z:0. World primitives use positive dimensions.
    Transform is {position,rotation,scale}, rotation in radians. For canvas/capture, position.z=0,
    rotation.x=rotation.y=0, scale.z=1. Style is {fill,stroke,lineWidth,opacity,dashed,material}.
    Keep combined parent/child scales between 0.000001 and 1000; avoid extreme nested transforms.
    Colors: ink,secondary,white,blue,green,orange,red,purple,cyan,clear. Materials: matte,metal,glass,emissive.
    Camera is {position,target,fieldOfView}. Animation is {property,to,duration,curve}, duration 0..30 seconds
    relative to its semantic cue; properties position,rotation,scale,opacity,strokeReveal; curves linear,easeInOut.
    Scalar animation targets use x:0..1,y:0,z:0. No automatic independent animation loop.
    Limits: 64 events/turn, 16 cues/event, 128 operations/event, 256 scene objects, 1024 points/path,
    4096 mesh vertices, 12288 triangle indices, 1024 text bytes/object, 1600 speech bytes/beat, 65536 bytes/line.
    Unknown fields and operations are rejected. Keep the scene small and accessible.
    """

    private static func schema(_ value: ExplanationJSONValue, profile: ExplanationWireProfile) throws {
        let allowTarget: Bool
        if case .v2 = profile { allowTarget = true } else { allowTarget = false }
        let root = try object(value, required: ["version", "sessionID", "turnID", "sceneID", "sequence", "baseRevision", "revision", "beatID", "speech", "cues", "isFinal"])
        _ = try object(root["speech"]!, required: ["chunkID", "text"])
        for cue in try array(root["cues"]!, maximum: ExplanationLimits.cuesPerEvent) {
            let c = try object(cue, required: ["id", "anchor", "operations"])
            _ = try object(c["anchor"]!, required: ["kind"], optional: ["wordIndex"])
            for operation in try array(c["operations"]!, maximum: ExplanationLimits.operationsPerEvent) { try operationSchema(operation, allowTarget: allowTarget) }
        }
    }

    private static func operationSchema(_ value: ExplanationJSONValue, allowTarget: Bool) throws {
        guard case .object(let raw) = value, case .string(let name) = raw["op"] else { throw ExplanationFailure.invalid("operation discriminator") }
        let fields: Set<String>
        switch name {
        case "create", "connect": fields = ["object"]
        case "update": fields = ["id", "patch"]
        case "remove": fields = ["id"]
        case "move": fields = ["id", "position"]
        case "recolor": fields = ["id", "color"]
        case "highlight": fields = ["id", "highlighted"]
        case "group": fields = ["id", "members"]
        case "label": fields = ["id", "text"]
        case "camera": fields = ["camera"]
        case "animate": fields = ["id", "animation"]
        case "clear": fields = []
        default: throw ExplanationFailure.invalid("unknown operation")
        }
        let op = try object(value, required: fields.union(["op"]))
        if let v = op["object"] { try objectSchema(v, allowTarget: allowTarget) }
        if let v = op["patch"] {
            let p = try object(v, required: [], optional: ["geometry", "transform", "style", "text", "accessibleDescription"])
            try components(p)
        }
        if let v = op["position"] { try vectorSchema(v) }
        if let v = op["members"] { _ = try array(v, maximum: ExplanationLimits.objects) }
        if let v = op["camera"] {
            let camera = try object(v, required: ["position", "target", "fieldOfView"])
            try vectorSchema(camera["position"]!); try vectorSchema(camera["target"]!)
        }
        if let v = op["animation"] {
            let animation = try object(v, required: ["property", "to", "duration", "curve"])
            try vectorSchema(animation["to"]!)
        }
    }

    private static func objectSchema(_ value: ExplanationJSONValue, allowTarget: Bool) throws {
        var optionalKeys: Set<String> = ["parentID", "space", "captureID", "transform", "style", "text", "assetID", "sourceIDs", "provenance", "highlighted", "reveal"]
        if allowTarget { optionalKeys.insert("targetID") }
        let o = try object(value, required: ["id", "geometry", "accessibleDescription"], optional: optionalKeys)
        try components(o)
        if let v = o["sourceIDs"] { _ = try array(v, maximum: 8) }
    }

    private static func components(_ o: [String: ExplanationJSONValue]) throws {
        if let v = o["geometry"] {
            let g = try object(v, required: ["kind"], optional: ["size", "radius", "secondaryRadius", "depth", "points", "vertices", "indices", "values", "labels", "fromID", "toID"])
            if let v = g["size"] { try vectorSchema(v) }
            for (key, limit) in [("points", ExplanationLimits.points), ("vertices", ExplanationLimits.vertices)] {
                if let v = g[key] { for point in try array(v, maximum: limit) { try vectorSchema(point) } }
            }
            for (key, limit) in [("indices", ExplanationLimits.indices), ("values", 64), ("labels", 64)] {
                if let v = g[key] { _ = try array(v, maximum: limit) }
            }
        }
        if let v = o["transform"] {
            let transform = try object(v, required: ["position", "rotation", "scale"])
            for value in transform.values { try vectorSchema(value) }
        }
        if let v = o["style"] {
            _ = try object(v, required: ["fill", "stroke", "lineWidth", "opacity", "dashed", "material"])
        }
    }

    private static func vectorSchema(_ v: ExplanationJSONValue) throws { _ = try object(v, required: ["x", "y", "z"]) }
    private static func object(_ v: ExplanationJSONValue, required: Set<String>, optional: Set<String> = []) throws -> [String: ExplanationJSONValue] {
        guard case .object(let fields) = v else { throw ExplanationFailure.invalid("expected JSON object") }
        let keys = Set(fields.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
            throw ExplanationFailure.invalid("unknown or missing JSON field")
        }
        return fields
    }
    private static func array(_ v: ExplanationJSONValue, maximum: Int) throws -> [ExplanationJSONValue] {
        guard case .array(let values) = v, values.count <= maximum else { throw ExplanationFailure.invalid("JSON array budget") }
        return values
    }
}

/// One app-issued turn. No incomplete frame escapes. A malformed append rejects
/// its whole batch and permanently fails the stream, so callers cannot skip a bad
/// event and silently continue with an apparently valid suffix.
public struct ExplanationEventStream: Sendable {
    private let sessionID: UUID
    private let turnID: UUID
    private let sceneID: UUID
    private let profile: ExplanationWireProfile
    private var expectedRevision: Int
    private var pending = Data()
    private var receivedBytes = 0
    private var accepted: [ExplanationEvent] = []
    private var finalSeen = false
    private enum State: Sendable { case active, failed, cancelled, finished }
    private var state: State = .active

    public init(sessionID: UUID, turnID: UUID, sceneID: UUID, baseRevision: Int,
                profile: ExplanationWireProfile = .v1) throws {
        guard (0..<ExplanationLimits.revision).contains(baseRevision) else { throw ExplanationFailure.revisionConflict }
        self.profile = profile
        self.sessionID = sessionID; self.turnID = turnID; self.sceneID = sceneID; expectedRevision = baseRevision
    }

    public mutating func append(_ data: Data) throws -> [ExplanationEvent] {
        try requireActive()
        var candidate = self
        do {
            let result = try candidate.appendBatch(data)
            self = candidate
            return result
        } catch {
            pending.removeAll(); state = .failed
            throw error
        }
    }

    public mutating func finish() throws {
        try requireActive()
        guard pending.isEmpty, finalSeen else {
            pending.removeAll(); state = .failed
            throw ExplanationFailure.invalid("truncated explanation stream")
        }
        state = .finished
    }

    public mutating func cancel() {
        pending.removeAll(); accepted.removeAll(); state = .cancelled
    }

    private func requireActive() throws {
        switch state {
        case .active: return
        case .cancelled: throw ExplanationFailure.cancelled
        case .finished: throw ExplanationFailure.streamFinished
        case .failed: throw ExplanationFailure.invalid("explanation stream already rejected")
        }
    }

    private mutating func appendBatch(_ data: Data) throws -> [ExplanationEvent] {
        guard data.count <= ExplanationLimits.turnBytes - receivedBytes else { throw ExplanationFailure.limitExceeded("turn bytes") }
        receivedBytes += data.count
        var emitted: [ExplanationEvent] = []
        for byte in data {
            if byte == 10 {
                if pending.last == 13 { pending.removeLast() }
                let event = try ExplanationWire.decode(pending, profile: profile)
                pending.removeAll(keepingCapacity: true)
                guard event.sessionID == sessionID, event.turnID == turnID, event.sceneID == sceneID else { throw ExplanationFailure.staleIdentity }
                if event.sequence < accepted.count {
                    guard accepted[event.sequence] == event else { throw ExplanationFailure.conflictingDuplicate }
                    continue
                }
                guard !finalSeen else { throw ExplanationFailure.streamFinished }
                guard event.sequence == accepted.count else { throw ExplanationFailure.sequenceGap }
                guard event.baseRevision == expectedRevision else { throw ExplanationFailure.revisionConflict }
                guard !accepted.contains(where: { $0.beatID == event.beatID || $0.speech.chunkID == event.speech.chunkID }) else {
                    throw ExplanationFailure.invalid("reused beat or speech identity")
                }
                accepted.append(event); emitted.append(event)
                expectedRevision = event.revision; finalSeen = event.isFinal
            } else {
                guard pending.count < ExplanationLimits.frameBytes + 1 else { throw ExplanationFailure.limitExceeded("event bytes") }
                pending.append(byte)
            }
        }
        return emitted
    }
}

private indirect enum ExplanationJSONValue {
    case object([String: ExplanationJSONValue]), array([ExplanationJSONValue]), string(String), scalar
}

/// A bounded lexical pass retains object keys before Foundation can discard
/// duplicates. JSONDecoder subsequently validates complete JSON and scalar types.
private struct ExplanationJSONScanner {
    let bytes: [UInt8]
    var offset = 0
    var nodes = 0
    mutating func parse() throws -> ExplanationJSONValue {
        let result = try value(depth: 0)
        whitespace()
        guard offset == bytes.count else { throw ExplanationFailure.invalid("trailing JSON data") }
        return result
    }
    private mutating func value(depth: Int) throws -> ExplanationJSONValue {
        nodes += 1
        guard depth <= 24, nodes <= 32_768 else { throw ExplanationFailure.limitExceeded("JSON complexity") }
        whitespace()
        guard offset < bytes.count else { throw ExplanationFailure.invalid("incomplete JSON") }
        switch bytes[offset] {
        case 123:
            offset += 1; whitespace(); var result: [String: ExplanationJSONValue] = [:]
            if take(125) { return .object(result) }
            while true {
                whitespace(); let key = try string()
                guard result[key] == nil else { throw ExplanationFailure.invalid("duplicate JSON key") }
                whitespace(); guard take(58) else { throw ExplanationFailure.invalid("JSON colon") }
                result[key] = try value(depth: depth + 1)
                whitespace(); if take(125) { return .object(result) }
                guard take(44) else { throw ExplanationFailure.invalid("JSON object delimiter") }
            }
        case 91:
            offset += 1; whitespace(); var result: [ExplanationJSONValue] = []
            if take(93) { return .array(result) }
            while true {
                result.append(try value(depth: depth + 1))
                whitespace(); if take(93) { return .array(result) }
                guard take(44) else { throw ExplanationFailure.invalid("JSON array delimiter") }
            }
        case 34: return .string(try string())
        default:
            let start = offset
            while offset < bytes.count && ![UInt8(9), 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            guard offset > start else { throw ExplanationFailure.invalid("JSON scalar") }
            return .scalar
        }
    }
    private mutating func string() throws -> String {
        let start = offset
        guard take(34) else { throw ExplanationFailure.invalid("JSON string") }
        while offset < bytes.count {
            let byte = bytes[offset]; offset += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) }
            if byte == 92 {
                guard offset < bytes.count else { throw ExplanationFailure.invalid("JSON string escape") }
                offset += 1
            }
        }
        throw ExplanationFailure.invalid("unterminated JSON string")
    }
    private mutating func whitespace() { while offset < bytes.count && [UInt8(9), 10, 13, 32].contains(bytes[offset]) { offset += 1 } }
    private mutating func take(_ byte: UInt8) -> Bool {
        guard offset < bytes.count, bytes[offset] == byte else { return false }
        offset += 1; return true
    }
}
