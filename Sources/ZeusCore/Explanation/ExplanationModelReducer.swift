import Foundation

/// Bounds for slice S3 data. Every check here runs on model data before any native object exists.
public enum ExplanationModelValidator {
    private static func check(_ condition: Bool, _ reason: String) throws {
        if !condition { throw ExplanationFailure.invalid(reason) }
    }
    private static func finite(_ value: Double, _ range: ClosedRange<Double>, _ reason: String) throws {
        try check(value.isFinite && range.contains(value), reason)
    }
    private static func vector(_ v: ExplanationVector3, maximum: Double = ExplanationLimits.coordinate, _ reason: String) throws {
        try check([v.x, v.y, v.z].allSatisfy { $0.isFinite && abs($0) <= maximum }, reason)
    }
    private static func text(_ value: String, maximum: Int, _ reason: String) throws {
        try check(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximum
                  && !value.unicodeScalars.contains { ($0.value < 32 && $0 != "\n") || $0.value == 127 }, reason)
    }
    private static func revision(_ value: Int) throws {
        try check((0...ExplanationLimits.revision).contains(value), "expected revision")
    }

    // MARK: Operations (no scene context)

    public static func validate(_ operation: ExplanationModelOperation) throws {
        switch operation {
        case .part(let part): try validate(part)
        case .path(let path): try validate(path)
        case .flow(let flow): try validate(flow)
        case .callout(let callout): try validate(callout)
        case .view(let change):
            try check(change.preset != nil || change.orbit != nil || change.zoom != nil, "empty view change")
            if let orbit = change.orbit { try finite(orbit, -720...720, "view orbit") }
            if let zoom = change.zoom { try finite(zoom, 0.2...5, "view zoom") }
        case .cutaway(let change):
            try revision(change.expectedRevision)
            try check(change.partIDs.count <= 24 && Set(change.partIDs).count == change.partIDs.count, "cutaway targets")
            try check(change.style == .none || !change.partIDs.isEmpty, "cutaway needs targets")
            for id in change.partIDs { try ExplanationSceneReducer.identifier(id) }
            if let opacity = change.opacity { try finite(opacity, 0...1, "cutaway opacity") }
        case .settings(let settings):
            try check(settings.caption != nil || settings.animationRate != nil, "empty model settings")
            if let caption = settings.caption { try text(caption, maximum: ExplanationModelLimits.caption, "caption") }
            if let rate = settings.animationRate {
                try finite(rate, ExplanationModelLimits.minimumAnimationRate...ExplanationModelLimits.animationRate, "animation rate")
            }
        case .edit(let edit):
            try ExplanationSceneReducer.identifier(edit.id)
            try revision(edit.expectedRevision)
            try validate(edit.change)
        }
    }

    static func validate(_ change: ExplanationPartChange) throws {
        try check(!change.isEmpty, "empty edit")
        if let value = change.opacity { try finite(value, 0...1, "edit opacity") }
        if let value = change.metalness { try finite(value, 0...1, "edit metalness") }
        if let value = change.roughness { try finite(value, 0...1, "edit roughness") }
        if let value = change.position { try vector(value, "edit position") }
        if let value = change.rotation { try vector(value, maximum: 100 * Double.pi, "edit rotation") }
        if let value = change.scale {
            try vector(value, maximum: 100, "edit scale")
            try check(value.x >= 0.001 && value.y >= 0.001 && value.z >= 0.001, "edit scale")
        }
        if let value = change.spin { try finite(value, -ExplanationModelLimits.spinRate...ExplanationModelLimits.spinRate, "edit spin") }
        if let value = change.speed { try finite(value, 0...ExplanationModelLimits.flowSpeed, "edit speed") }
        if let value = change.text { try text(value, maximum: ExplanationModelLimits.calloutText, "edit text") }
    }

    static func validate(_ part: ExplanationPart) throws {
        try ExplanationSceneReducer.identifier(part.id)
        if let parent = part.parentID {
            try ExplanationSceneReducer.identifier(parent)
            try check(parent != part.id, "part parent")
        }
        try text(part.accessibleDescription, maximum: 512, "part description")
        try vector(part.transform.position, "part position")
        try vector(part.transform.rotation, maximum: 100 * Double.pi, "part rotation")
        try vector(part.transform.scale, maximum: 100, "part scale")
        let s = part.transform.scale
        try check(s.x >= 0.001 && s.y >= 0.001 && s.z >= 0.001, "part scale")
        if let value = part.material.metalness { try finite(value, 0...1, "part metalness") }
        if let value = part.material.roughness { try finite(value, 0...1, "part roughness") }
        try finite(part.material.opacity, 0...1, "part opacity")
        let dimension = 0.001...ExplanationModelLimits.dimension
        switch part.kind {
        case .group:
            try check(part.size == nil && part.radius == nil && part.depth == nil && part.recipe == nil, "group parameters")
            try check(part.repeats == nil && part.spin == nil, "group repeat or spin")
        case .box:
            guard let size = part.size else { throw ExplanationFailure.invalid("box size") }
            for value in [size.x, size.y, size.z] { try finite(value, dimension, "box size") }
            try check(part.radius == nil && part.depth == nil && part.recipe == nil, "box parameters")
        case .cylinder:
            try finite(part.radius ?? .nan, dimension, "cylinder radius")
            try finite(part.depth ?? .nan, dimension, "cylinder depth")
            try check(part.size == nil && part.recipe == nil, "cylinder parameters")
        case .sphere:
            try finite(part.radius ?? .nan, dimension, "sphere radius")
            try check(part.size == nil && part.depth == nil && part.recipe == nil, "sphere parameters")
        case .recipe:
            try check(part.recipe != nil, "recipe name")
            try check(part.size == nil && part.radius == nil && part.depth == nil, "recipe parameters")
        }
        if let repeats = part.repeats {
            try check((1...ExplanationModelLimits.repeatCount).contains(repeats.count), "repeat count")
            try vector(repeats.offset, maximum: 1000, "repeat offset")
        }
        if let spin = part.spin {
            try check(part.kind == .recipe, "spin needs a recipe part")
            try finite(spin.radiansPerSecond, -ExplanationModelLimits.spinRate...ExplanationModelLimits.spinRate, "spin rate")
        }
    }

    static func validate(_ path: ExplanationFlowPath) throws {
        try ExplanationSceneReducer.identifier(path.id)
        try check((2...ExplanationModelLimits.pathPoints).contains(path.points.count), "path points")
        for point in path.points { try vector(point, "path point") }
        try check(ExplanationFlowMath.length(of: path.points) > 0.000001, "degenerate flow path")
    }

    static func validate(_ flow: ExplanationFlow) throws {
        try ExplanationSceneReducer.identifier(flow.id)
        try ExplanationSceneReducer.identifier(flow.pathID)
        try finite(flow.speed, 0...ExplanationModelLimits.flowSpeed, "flow speed")
        try check((1...ExplanationModelLimits.markersPerFlow).contains(flow.count), "flow marker count")
        try finite(flow.markerSize, 0.01...0.5, "flow marker size")
    }

    static func validate(_ callout: ExplanationCallout) throws {
        try ExplanationSceneReducer.identifier(callout.id)
        if let part = callout.partID { try ExplanationSceneReducer.identifier(part) }
        try text(callout.text, maximum: ExplanationModelLimits.calloutText, "callout text")
        try vector(callout.anchor, "callout anchor")
    }

    // MARK: Whole model

    public static func validate(_ model: ExplanationModel3D) throws {
        try check(model.parts.count <= ExplanationModelLimits.parts && model.paths.count <= ExplanationModelLimits.paths
                  && model.flows.count <= ExplanationModelLimits.flows && model.callouts.count <= ExplanationModelLimits.callouts,
                  "model object budget")
        let identifiers = Set(model.parts.keys).union(model.paths.keys).union(model.flows.keys).union(model.callouts.keys)
        try check(identifiers.count == model.parts.count + model.paths.count + model.flows.count + model.callouts.count,
                  "model identifiers must be unique across parts, paths, flows and callouts")
        for (key, part) in model.parts { try check(key == part.id, "part identity"); try validate(part) }
        for (key, path) in model.paths { try check(key == path.id, "path identity"); try validate(path) }
        for (key, flow) in model.flows { try check(key == flow.id, "flow identity"); try validate(flow) }
        for (key, callout) in model.callouts { try check(key == callout.id, "callout identity"); try validate(callout) }
        var instances = 0, primitives = 0
        for part in model.parts.values {
            instances += max(1, part.repeats?.count ?? 1)
            primitives += ExplanationRecipes.primitiveCount(of: part)
            var cursor = part.parentID, seen: Set<String> = [part.id]
            while let id = cursor {
                try check(seen.insert(id).inserted, "part parent cycle")
                try check(seen.count <= ExplanationModelLimits.hierarchyDepth + 1, "part hierarchy depth")
                guard let parent = model.parts[id] else { throw ExplanationFailure.invalid("missing part parent") }
                try check(parent.kind == .group, "part parent must be a group")
                cursor = parent.parentID
            }
        }
        try check(instances <= ExplanationModelLimits.instances, "part instance budget")
        try check(primitives <= ExplanationModelLimits.primitives, "solid budget")
        var markers = 0
        for flow in model.flows.values {
            try check(model.paths[flow.pathID] != nil, "flow path missing")
            markers += flow.count
        }
        try check(markers <= ExplanationModelLimits.markers, "marker budget")
        for callout in model.callouts.values {
            if let part = callout.partID { try check(model.parts[part] != nil, "callout part missing") }
        }
        try finite(model.cutaway.opacity, 0...1, "cutaway opacity")
        try check(model.cutaway.partIDs.count <= 24 && Set(model.cutaway.partIDs).count == model.cutaway.partIDs.count, "cutaway targets")
        try check(model.cutaway.style != .none || model.cutaway.partIDs.isEmpty, "cutaway state")
        for id in model.cutaway.partIDs {
            guard let part = model.parts[id] else { throw ExplanationFailure.invalid("cutaway part missing") }
            try check(part.isShell, "cutaway target is not a shell")
        }
        try finite(model.animationRate, ExplanationModelLimits.minimumAnimationRate...ExplanationModelLimits.animationRate, "animation rate")
        if let caption = model.caption { try text(caption, maximum: ExplanationModelLimits.caption, "caption") }
    }
}

/// Applies one slice S3 operation to a scene. Pure and transactional at the caller: it throws
/// on a missing target or a stale expected revision, and the caller keeps the scene it passed in.
public enum ExplanationModelReducer {
    /// `baseRevision` is the revision the model last saw: `resultingRevision - 1` for the beat
    /// that carries the edit. An `expectedRevision` that differs is stale.
    static func apply(_ operation: ExplanationModelOperation, to scene: inout ExplanationScene, baseRevision: Int) throws {
        var model = scene.model ?? .empty
        func taken(_ id: String) -> Bool {
            model.parts[id] != nil || model.paths[id] != nil || model.flows[id] != nil || model.callouts[id] != nil
        }
        switch operation {
        case .part(let part):
            guard !taken(part.id) else { throw ExplanationFailure.invalid("duplicate model identifier") }
            model.parts[part.id] = part
        case .path(let path):
            guard !taken(path.id) else { throw ExplanationFailure.invalid("duplicate model identifier") }
            model.paths[path.id] = path
        case .flow(let flow):
            guard !taken(flow.id) else { throw ExplanationFailure.invalid("duplicate model identifier") }
            model.flows[flow.id] = flow
        case .callout(let callout):
            guard !taken(callout.id) else { throw ExplanationFailure.invalid("duplicate model identifier") }
            model.callouts[callout.id] = callout
        case .view(let change):
            scene.camera = ExplanationCameraMath.apply(change, to: scene.camera)
        case .cutaway(let change):
            try requireRevision(change.expectedRevision, baseRevision)
            for id in change.partIDs where model.parts[id] == nil {
                throw ExplanationFailure.editRejected(.missingTarget(id))
            }
            model.cutaway = ExplanationCutaway(style: change.style, partIDs: change.style == .none ? [] : change.partIDs,
                                               opacity: change.opacity ?? model.cutaway.opacity)
        case .settings(let settings):
            if let caption = settings.caption { model.caption = caption }
            if let rate = settings.animationRate { model.animationRate = rate }
        case .edit(let edit):
            try requireRevision(edit.expectedRevision, baseRevision)
            try applyEdit(edit, to: &model)
        }
        scene.model = model
    }

    private static func requireRevision(_ expected: Int, _ actual: Int) throws {
        guard expected == actual else { throw ExplanationFailure.editRejected(.staleRevision(expected: expected, actual: actual)) }
    }

    private static func inapplicable(_ field: String) -> ExplanationFailure { .editRejected(.inapplicableChange(field)) }

    private static func applyEdit(_ edit: ExplanationPartEdit, to model: inout ExplanationModel3D) throws {
        let change = edit.change
        if var part = model.parts[edit.id] {
            if change.speed != nil { throw inapplicable("speed") }
            if change.direction != nil { throw inapplicable("direction") }
            if change.active != nil { throw inapplicable("active") }
            if change.text != nil { throw inapplicable("text") }
            if let value = change.opacity { part.material.opacity = value }
            if let value = change.visible { part.visible = value }
            if let value = change.color { part.material.color = value }
            if let value = change.metalness { part.material.metalness = value }
            if let value = change.roughness { part.material.roughness = value }
            if let value = change.position { part.transform.position = value }
            if let value = change.rotation { part.transform.rotation = value }
            if let value = change.scale { part.transform.scale = value }
            if let value = change.spin {
                guard part.kind == .recipe else { throw inapplicable("spin") }
                part.spin = ExplanationPartSpin(radiansPerSecond: value, axis: part.spin?.axis ?? .z)
            }
            model.parts[edit.id] = part
        } else if var flow = model.flows[edit.id] {
            if change.opacity != nil { throw inapplicable("opacity") }
            if change.visible != nil { throw inapplicable("visible") }
            if change.metalness != nil { throw inapplicable("metalness") }
            if change.roughness != nil { throw inapplicable("roughness") }
            if change.position != nil { throw inapplicable("position") }
            if change.rotation != nil { throw inapplicable("rotation") }
            if change.scale != nil { throw inapplicable("scale") }
            if change.spin != nil { throw inapplicable("spin") }
            if change.text != nil { throw inapplicable("text") }
            if let value = change.speed { flow.speed = value }
            if let value = change.direction { flow.direction = value }
            if let value = change.active { flow.active = value }
            if let value = change.color { flow.color = value }
            model.flows[edit.id] = flow
        } else if var callout = model.callouts[edit.id] {
            let others: [(String, Bool)] = [
                ("opacity", change.opacity != nil), ("color", change.color != nil), ("metalness", change.metalness != nil),
                ("roughness", change.roughness != nil), ("position", change.position != nil),
                ("rotation", change.rotation != nil), ("scale", change.scale != nil), ("spin", change.spin != nil),
                ("speed", change.speed != nil), ("direction", change.direction != nil), ("active", change.active != nil)
            ]
            if let field = others.first(where: { $0.1 }) { throw inapplicable(field.0) }
            if let value = change.text { callout.text = value }
            if let value = change.visible { callout.visible = value }
            model.callouts[edit.id] = callout
        } else {
            throw ExplanationFailure.editRejected(.missingTarget(edit.id))
        }
    }
}
