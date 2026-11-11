import Foundation

/// Pure transactional scene mutations. Callers must keep projected future scenes
/// separate from the canonical graph of cues actually admitted by playback.
public enum ExplanationSceneReducer {
    public static func validate(_ scene: ExplanationScene, registry: ExplanationRegistry = .empty) throws {
        try check(scene.version == 1, "unsupported scene version")
        try revision(scene.revision)
        try check(scene.canvasSize.width.isFinite && scene.canvasSize.height.isFinite
                  && (1...8192).contains(scene.canvasSize.width) && (1...8192).contains(scene.canvasSize.height), "canvas bounds")
        try check(scene.objects.count <= ExplanationLimits.objects, "object budget")
        try check(registry.assetIDs.count <= 256 && registry.sourceIDs.count <= 256, "registry budget")
        for id in registry.assetIDs.union(registry.sourceIDs) { try identifier(id) }
        try camera(scene.camera)
        if let model = scene.model { try ExplanationModelValidator.validate(model) }
        var pointCount = 0, vertexCount = 0, textBytes = 0
        for (key, object) in scene.objects {
            try check(key == object.id, "object dictionary identity")
            try validate(object, scene: scene, registry: registry)
            pointCount += object.geometry.points?.count ?? 0
            vertexCount += object.geometry.vertices?.count ?? 0
            textBytes += (object.text?.utf8.count ?? 0) + object.accessibleDescription.utf8.count
            textBytes += object.geometry.labels?.reduce(0, { $0 + $1.utf8.count }) ?? 0
        }
        try check(pointCount <= 8192 && vertexCount <= 16_384 && textBytes <= 65_536, "aggregate scene budget")
        for object in scene.objects.values {
            var cursor = object.parentID, seen: Set<String> = [object.id]
            var maximumScale = max(object.transform.scale.x, object.transform.scale.y, object.transform.scale.z)
            var minimumScale = min(object.transform.scale.x, object.transform.scale.y, object.transform.scale.z)
            var translationRadius = length(object.transform.position)
            while let parentID = cursor {
                try check(seen.insert(parentID).inserted, "parent cycle")
                try check(seen.count <= 17, "parent depth")
                guard let parent = scene.objects[parentID] else { throw ExplanationFailure.invalid("missing parent") }
                try check(parent.geometry.kind == .group && parent.space == object.space
                          && parent.captureID == object.captureID, "incompatible parent")
                let parentScale = max(parent.transform.scale.x, parent.transform.scale.y, parent.transform.scale.z)
                maximumScale *= parentScale
                minimumScale *= min(parent.transform.scale.x, parent.transform.scale.y, parent.transform.scale.z)
                translationRadius = length(parent.transform.position) + parentScale * translationRadius
                // Individually finite transforms can overflow Float matrices when
                // nested. Bound their composition before either native renderer.
                try check(maximumScale <= 1000 && minimumScale >= 0.000001
                          && translationRadius <= 1_000_000, "composed transform bounds")
                cursor = parent.parentID
            }
            if object.geometry.kind == .connector {
                guard let from = object.geometry.fromID.flatMap({ scene.objects[$0] }),
                      let to = object.geometry.toID.flatMap({ scene.objects[$0] }) else {
                    throw ExplanationFailure.invalid("missing connector reference")
                }
                try check(from.id != object.id && to.id != object.id && from.id != to.id
                          && from.geometry.kind != .connector && to.geometry.kind != .connector,
                          "invalid connector reference")
                try check(from.space == object.space && to.space == object.space
                          && from.captureID == object.captureID && to.captureID == object.captureID,
                          "connector coordinate mismatch")
            }
        }
    }

    /// Structural bounds independent of the current scene. Still mandatory for
    /// trusted Codable records: direct Swift construction also can contain NaN.
    public static func validate(_ event: ExplanationEvent) throws {
        try validate(event, profile: .v1)
    }

    /// v1 events never carry `targetID`. v2 events (pointing turns) may reference only the
    /// candidate IDs the app issued for this turn, and only on capture-space objects.
    public static func validate(_ event: ExplanationEvent, profile: ExplanationWireProfile) throws {
        switch profile {
        case .v1: try check(event.version == 1, "unsupported event version")
        case .v2: try check(event.version == 1 || event.version == 2, "unsupported event version")
        }
        for cue in event.cues {
            for operation in cue.operations {
                guard case .create(let object) = operation else { continue }
                guard let target = object.targetID else { continue }
                guard case .v2(let candidates) = profile, event.version == 2 else {
                    throw ExplanationFailure.invalid("targetID requires protocol version 2")
                }
                try check(isTargetID(target) && candidates.contains(target), "unknown targetID")
                try check(object.space == .capture, "targetID needs capture space")
            }
        }
        try check((0..<ExplanationLimits.events).contains(event.sequence), "event sequence budget")
        try revision(event.baseRevision)
        try check(event.baseRevision < ExplanationLimits.revision && event.revision == event.baseRevision + 1,
                  "event revision increment")
        try identifier(event.beatID); try identifier(event.speech.chunkID)
        try text(event.speech.text, maximum: ExplanationLimits.speech, empty: false)
        try check(event.cues.count <= ExplanationLimits.cuesPerEvent, "cue budget")
        var identifiers = Set<String>(), operationCount = 0, previousAnchor = -1
        for cue in event.cues {
            try identifier(cue.id)
            try check(identifiers.insert(cue.id).inserted, "duplicate cue")
            let order: Int
            switch cue.anchor.kind {
            case .start: try check(cue.anchor.wordIndex == nil, "start anchor index"); order = -1
            case .end: try check(cue.anchor.wordIndex == nil, "end anchor index"); order = 4097
            case .word:
                guard let index = cue.anchor.wordIndex, (0...4096).contains(index) else { throw ExplanationFailure.invalid("word anchor index") }
                order = index
            }
            try check(order >= previousAnchor, "cue anchors must be ordered")
            previousAnchor = order
            try check(!cue.operations.isEmpty, "empty visual cue")
            operationCount += cue.operations.count
            try check(operationCount <= ExplanationLimits.operationsPerEvent, "operation budget")
            for operation in cue.operations { try validate(operation) }
        }
        // No cues is an intentional spoken-only beat. Its revision is reserved
        // by the coordinator at actual audio start (or explicit caption advance).
    }

    public static func applying(_ event: ExplanationEvent, to scene: ExplanationScene,
                                activeTurn: UUID, registry: ExplanationRegistry = .empty) throws -> ExplanationScene {
        try validate(event)
        guard event.sessionID == scene.sessionID, event.sceneID == scene.sceneID, event.turnID == activeTurn else {
            throw ExplanationFailure.staleIdentity
        }
        guard event.baseRevision == scene.revision else { throw ExplanationFailure.revisionConflict }
        var projected = scene
        if event.cues.isEmpty {
            return try applyingOperations([], to: scene, resultingRevision: event.revision, registry: registry)
        }
        for cue in event.cues {
            // Every admitted cue must leave a valid graph. A future cue cannot
            // repair a missing reference in an earlier visible checkpoint.
            projected = try applyingOperations(cue.operations, to: projected,
                                                resultingRevision: event.revision, registry: registry)
        }
        return projected
    }

    /// App-only primitive used for an admitted cue or manual edit. Same revision
    /// is allowed for later cues of an already reserved beat; the scheduler owns
    /// the transient turn/beat/cue admission token. Never call from raw model data.
    public static func applyingOperations(_ operations: [ExplanationOperation], to scene: ExplanationScene,
                                          resultingRevision: Int, registry: ExplanationRegistry = .empty) throws -> ExplanationScene {
        try validate(scene, registry: registry)
        try revision(resultingRevision)
        guard resultingRevision == scene.revision
                || (scene.revision < ExplanationLimits.revision && resultingRevision == scene.revision + 1) else {
            throw ExplanationFailure.revisionConflict
        }
        try check(operations.count <= ExplanationLimits.operationsPerEvent, "operation budget")
        var candidate = scene
        for operation in operations {
            try validate(operation)
            // A later clear/remove must not conceal an unauthorized reference.
            switch operation {
            case .create(let object), .connect(let object):
                try validate(object, scene: candidate, registry: registry)
            default: break
            }
            // The revision the model last saw: an edit's expectedRevision must equal it.
            try apply(operation, to: &candidate, baseRevision: resultingRevision - 1)
            switch operation {
            case .update(let id, _), .move(let id, _), .animate(let id, _):
                if let object = candidate.objects[id] { try validate(object, scene: candidate, registry: registry) }
            default: break
            }
            // Reference integrity is checked at the transaction boundary: a
            // group/connector and its members may be created in the same cue.
            try check(candidate.objects.count <= ExplanationLimits.objects, "object budget")
        }
        candidate.revision = resultingRevision
        try validate(candidate, registry: registry)
        return candidate
    }

    public static func restoring(_ snapshot: ExplanationScene, atRevision newRevision: Int,
                                  registry: ExplanationRegistry = .empty) throws -> ExplanationScene {
        try validate(snapshot, registry: registry)
        guard newRevision >= snapshot.revision else { throw ExplanationFailure.revisionConflict }
        try revision(newRevision)
        var restored = snapshot; restored.revision = newRevision
        return restored
    }

    public static func restoring(_ snapshot: ExplanationScene, over current: ExplanationScene,
                                  registry: ExplanationRegistry = .empty) throws -> ExplanationScene {
        try validate(current, registry: registry)
        guard snapshot.sessionID == current.sessionID, snapshot.sceneID == current.sceneID else { throw ExplanationFailure.staleIdentity }
        guard current.revision < ExplanationLimits.revision else { throw ExplanationFailure.revisionConflict }
        return try restoring(snapshot, atRevision: current.revision + 1, registry: registry)
    }

    public static func validate(_ audio: ExplanationAudioChunk) throws {
        try identifier(audio.beatID); try identifier(audio.chunkID)
        try check(audio.duration.isFinite && audio.duration > 0 && audio.duration <= 300, "audio duration")
        try check(audio.sampleRate.isFinite && (8000...192_000).contains(audio.sampleRate), "audio sample rate")
        try check(audio.alignment.count <= 4096, "alignment budget")
        var previousIndex = -1, previousEnd = 0.0
        for mark in audio.alignment {
            try check(mark.wordIndex > previousIndex && mark.wordIndex <= 4096
                      && mark.start.isFinite && mark.end.isFinite && mark.start >= previousEnd
                      && mark.end >= mark.start && mark.end <= audio.duration, "invalid alignment")
            previousIndex = mark.wordIndex; previousEnd = mark.end
        }
    }

    public static func validate(_ operation: ExplanationOperation) throws {
        switch operation {
        case .create(let object), .connect(let object):
            try intrinsicObject(object)
            if case .connect = operation { try check(object.geometry.kind == .connector, "connect geometry") }
        case .update(let id, let patch):
            try identifier(id)
            try check(patch.geometry != nil || patch.transform != nil || patch.style != nil
                      || patch.text != nil || patch.accessibleDescription != nil, "empty patch")
            if let transform = patch.transform { try self.transform(transform) }
            if let style = patch.style { try self.style(style) }
            if let geometry = patch.geometry {
                let world: [ExplanationGeometry.Kind] = [.box, .sphere, .cylinder, .cone, .tube, .extrusion, .mesh]
                try self.geometry(geometry, space: world.contains(geometry.kind) ? .world : .canvas)
            }
            if let value = patch.text { try text(value, maximum: ExplanationLimits.text, empty: true) }
            if let value = patch.accessibleDescription { try text(value, maximum: 512, empty: false) }
        case .remove(let id): try identifier(id)
        case .move(let id, let position): try identifier(id); try vector(position)
        case .recolor(let id, _), .highlight(let id, _): try identifier(id)
        case .label(let id, let value): try identifier(id); try text(value, maximum: ExplanationLimits.text, empty: false)
        case .group(let id, let members):
            try identifier(id)
            try check(!members.isEmpty && members.count <= ExplanationLimits.objects
                      && Set(members).count == members.count && !members.contains(id), "group members")
            for member in members { try identifier(member) }
        case .camera(let camera): try self.camera(camera)
        case .animate(let id, let animation):
            try identifier(id); try vector(animation.to)
            try check(animation.duration.isFinite && (0...ExplanationLimits.animationSeconds).contains(animation.duration), "animation duration")
            switch animation.property {
            case .position: break
            case .rotation: try vector(animation.to, maximum: 100 * Double.pi)
            case .scale: try scale(animation.to)
            case .opacity, .strokeReveal:
                try check((0...1).contains(animation.to.x) && animation.to.y == 0 && animation.to.z == 0, "scalar animation target")
            }
        case .clear: break
        case .model(let model): try ExplanationModelValidator.validate(model)
        }
    }

    private static func apply(_ operation: ExplanationOperation, to scene: inout ExplanationScene, baseRevision: Int) throws {
        switch operation {
        case .create(let object), .connect(let object):
            try check(scene.objects[object.id] == nil, "duplicate object")
            scene.objects[object.id] = object
        case .update(let id, let patch):
            var object = try existing(id, in: scene)
            if let value = patch.geometry { object.geometry = value }
            if let value = patch.transform { object.transform = value }
            if let value = patch.style { object.style = value }
            if let value = patch.text { object.text = value }
            if let value = patch.accessibleDescription { object.accessibleDescription = value }
            scene.objects[id] = object
        case .remove(let id):
            _ = try existing(id, in: scene)
            var removed: Set<String> = [id]
            var changed = true
            while changed {
                changed = false
                for object in scene.objects.values where !removed.contains(object.id) {
                    if object.parentID.map(removed.contains) == true
                        || object.geometry.fromID.map(removed.contains) == true
                        || object.geometry.toID.map(removed.contains) == true {
                        removed.insert(object.id); changed = true
                    }
                }
            }
            for removedID in removed { scene.objects.removeValue(forKey: removedID) }
        case .move(let id, let position):
            var object = try existing(id, in: scene); object.transform.position = position; scene.objects[id] = object
        case .recolor(let id, let color):
            var object = try existing(id, in: scene); object.style.fill = color; object.style.stroke = color; scene.objects[id] = object
        case .highlight(let id, let highlighted):
            var object = try existing(id, in: scene); object.highlighted = highlighted; scene.objects[id] = object
        case .label(let id, let text):
            var object = try existing(id, in: scene); object.text = text; scene.objects[id] = object
        case .group(let id, let members):
            let parent = try existing(id, in: scene)
            try check(parent.geometry.kind == .group, "group target")
            for member in members {
                var object = try existing(member, in: scene); object.parentID = id; scene.objects[member] = object
            }
        case .camera(let camera): scene.camera = camera
        case .animate(let id, let animation):
            var object = try existing(id, in: scene)
            switch animation.property {
            case .position: object.transform.position = animation.to
            case .rotation: object.transform.rotation = animation.to
            case .scale: object.transform.scale = animation.to
            case .opacity: object.style.opacity = animation.to.x
            case .strokeReveal: object.reveal = animation.to.x
            }
            scene.objects[id] = object
        case .clear: scene.objects.removeAll(); scene.camera = .init(); scene.model = nil
        case .model(let model): try ExplanationModelReducer.apply(model, to: &scene, baseRevision: baseRevision)
        }
    }

    private static func existing(_ id: String, in scene: ExplanationScene) throws -> ExplanationObject {
        guard let object = scene.objects[id] else { throw ExplanationFailure.invalid("unknown object") }
        return object
    }

    private static func validate(_ object: ExplanationObject, scene: ExplanationScene, registry: ExplanationRegistry) throws {
        try intrinsicObject(object)
        try check(object.space != .capture || object.captureID == scene.captureID, "capture coordinate identity")
        for id in object.sourceIDs { try check(registry.sourceIDs.contains(id), "unapproved source") }
        if let id = object.assetID { try check(registry.assetIDs.contains(id), "unapproved asset") }
    }

    private static func intrinsicObject(_ object: ExplanationObject) throws {
        try identifier(object.id)
        if let id = object.parentID { try identifier(id) }
        try check(object.space == .capture ? object.captureID != nil : object.captureID == nil,
                  "capture coordinate identity")
        try transform(object.transform); try style(object.style)
        if object.space != .world {
            try check(object.transform.position.z == 0 && object.transform.rotation.x == 0
                      && object.transform.rotation.y == 0 && object.transform.scale.z == 1,
                      "planar object transform")
        }
        try text(object.accessibleDescription, maximum: 512, empty: false)
        if let value = object.text { try text(value, maximum: ExplanationLimits.text, empty: true) }
        try check(object.reveal.isFinite && (0...1).contains(object.reveal), "stroke reveal")
        try check(object.sourceIDs.count <= 8 && Set(object.sourceIDs).count == object.sourceIDs.count, "source budget")
        for id in object.sourceIDs { try identifier(id) }
        if let id = object.assetID { try identifier(id) }
        if object.geometry.kind == .image {
            try check(object.assetID != nil && object.provenance != .proceduralIllustration, "image provenance")
        } else {
            try check(object.assetID == nil && object.provenance == .proceduralIllustration, "procedural provenance")
        }
        try geometry(object.geometry, space: object.space)
        if [.label, .card, .badge].contains(object.geometry.kind) {
            try text(object.text ?? "", maximum: ExplanationLimits.text, empty: false)
        }
    }

    private static func geometry(_ g: ExplanationGeometry, space: ExplanationSpace) throws {
        var allowed = Set<String>(), required = Set<String>()
        func fields(_ names: [String], optional: [String] = []) { required = Set(names); allowed = required.union(optional) }
        switch g.kind {
        case .group: fields([])
        case .point, .ring: fields(["radius"])
        case .roundedRectangle, .region, .highlight, .card, .image: fields(["size"], optional: ["radius"])
        case .badge: fields(["radius"])
        case .label: fields([])
        case .arrow, .underline, .path: fields(["points"])
        case .connector: fields(["fromID", "toID"])
        case .chart, .timeline: fields(["size", "values", "labels"])
        case .box: fields(["size"])
        case .sphere: fields(["radius"])
        case .cylinder: fields(["radius", "depth"])
        case .cone: fields(["radius", "depth"], optional: ["secondaryRadius"])
        case .tube: fields(["radius", "points"])
        case .extrusion: fields(["points", "depth"])
        case .mesh: fields(["vertices", "indices"])
        }
        let present = Set([
            g.size != nil ? "size" : nil, g.radius != nil ? "radius" : nil,
            g.secondaryRadius != nil ? "secondaryRadius" : nil, g.depth != nil ? "depth" : nil,
            g.points != nil ? "points" : nil, g.vertices != nil ? "vertices" : nil,
            g.indices != nil ? "indices" : nil, g.values != nil ? "values" : nil,
            g.labels != nil ? "labels" : nil, g.fromID != nil ? "fromID" : nil, g.toID != nil ? "toID" : nil
        ].compactMap { $0 })
        try check(required.isSubset(of: present) && present.isSubset(of: allowed), "geometry parameters")
        let is3D = [.box, .sphere, .cylinder, .cone, .tube, .extrusion, .mesh].contains(g.kind)
        try check(g.kind == .group || g.kind == .label || (is3D ? space == .world : space != .world), "geometry coordinate system")
        if let size = g.size {
            try vector(size)
            try check(size.x > 0 && size.y > 0 && (is3D ? size.z > 0 : size.z == 0), "geometry size")
        }
        if let radius = g.radius { try positive(radius) }
        if let radius = g.secondaryRadius { try check(radius.isFinite && radius >= 0 && radius <= (g.radius ?? 0), "secondary radius") }
        if let depth = g.depth { try positive(depth) }
        if let points = g.points {
            let minimum = g.kind == .extrusion ? 3 : 2
            try check(points.count >= minimum && points.count <= ExplanationLimits.points, "path point budget")
            if [.arrow, .underline].contains(g.kind) { try check(points.count == 2, "segment point count") }
            for point in points { try vector(point); if !is3D || g.kind == .extrusion { try check(point.z == 0, "planar path") } }
            try check(zip(points, points.dropFirst()).contains { $0 != $1 }, "degenerate path")
            if g.kind == .extrusion {
                var area = 0.0
                for index in points.indices {
                    let next = points[(index + 1) % points.count]
                    area += points[index].x * next.y - next.x * points[index].y
                }
                try check(area.isFinite && abs(area) > 0.000001, "degenerate extrusion")
            }
        }
        if let vertices = g.vertices {
            try check((3...ExplanationLimits.vertices).contains(vertices.count), "mesh vertex budget")
            for vertex in vertices { try vector(vertex) }
        }
        if let indices = g.indices {
            try check(!indices.isEmpty && indices.count <= ExplanationLimits.indices && indices.count.isMultiple(of: 3), "mesh index budget")
            try check(indices.allSatisfy { $0 >= 0 && $0 < (g.vertices?.count ?? 0) }, "mesh index reference")
            for offset in stride(from: 0, to: indices.count, by: 3) {
                try check(Set(indices[offset..<(offset + 3)]).count == 3, "degenerate mesh triangle")
                if let vertices = g.vertices {
                    let a = vertices[indices[offset]], b = vertices[indices[offset + 1]], c = vertices[indices[offset + 2]]
                    let u = ExplanationVector3(x: b.x - a.x, y: b.y - a.y, z: b.z - a.z)
                    let v = ExplanationVector3(x: c.x - a.x, y: c.y - a.y, z: c.z - a.z)
                    let cross = ExplanationVector3(x: u.y * v.z - u.z * v.y, y: u.z * v.x - u.x * v.z, z: u.x * v.y - u.y * v.x)
                    try check(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z > 1e-12, "collinear mesh triangle")
                }
            }
        }
        if let values = g.values {
            try check(!values.isEmpty && values.count <= 64 && values.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }, "chart values")
            if g.kind == .timeline { try check(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }, "timeline order") }
            try check(g.labels?.count == values.count, "chart label count")
        }
        for label in g.labels ?? [] { try text(label, maximum: 80, empty: false) }
        if let id = g.fromID { try identifier(id) }
        if let id = g.toID { try identifier(id) }
    }

    private static func camera(_ camera: ExplanationCamera) throws {
        try vector(camera.position); try vector(camera.target)
        let dx = camera.position.x - camera.target.x, dy = camera.position.y - camera.target.y, dz = camera.position.z - camera.target.z
        try check(dx * dx + dy * dy + dz * dz > 0.000001, "camera target")
        try check(camera.fieldOfView.isFinite && (5...120).contains(camera.fieldOfView), "camera field of view")
    }
    private static func transform(_ transform: ExplanationTransform) throws {
        try vector(transform.position); try vector(transform.rotation, maximum: 100 * Double.pi); try scale(transform.scale)
    }
    private static func scale(_ value: ExplanationVector3) throws {
        try vector(value, maximum: 100)
        try check(value.x >= 0.001 && value.y >= 0.001 && value.z >= 0.001, "transform scale")
    }
    private static func style(_ style: ExplanationStyle) throws {
        try check(style.lineWidth.isFinite && (0...64).contains(style.lineWidth)
                  && style.opacity.isFinite && (0...1).contains(style.opacity), "style bounds")
    }
    private static func vector(_ value: ExplanationVector3, maximum: Double = ExplanationLimits.coordinate) throws {
        try check([value.x, value.y, value.z].allSatisfy { $0.isFinite && abs($0) <= maximum }, "finite bounded coordinates")
    }
    private static func positive(_ value: Double) throws {
        try check(value.isFinite && value > 0 && value <= ExplanationLimits.coordinate, "positive geometry dimension")
    }
    private static func length(_ value: ExplanationVector3) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }
    private static func revision(_ value: Int) throws { try check((0...ExplanationLimits.revision).contains(value), "scene revision budget") }
    /// `^t[0-9]{1,2}$`
    public static func isTargetID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return (2...3).contains(bytes.count) && bytes[0] == 116 && bytes.dropFirst().allSatisfy { (48...57).contains($0) }
    }
    static func identifier(_ id: String) throws {
        let bytes = Array(id.utf8)
        try check((1...64).contains(bytes.count) && bytes.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }, "identifier")
    }
    private static func text(_ value: String, maximum: Int, empty: Bool) throws {
        try check((empty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                  && value.utf8.count <= maximum
                  && !value.unicodeScalars.contains { ($0.value < 32 && $0 != "\n" && $0 != "\t") || $0.value == 127 }, "text bounds")
    }
    static func check(_ condition: Bool, _ reason: String) throws {
        if !condition { throw ExplanationFailure.invalid(reason) }
    }
}
