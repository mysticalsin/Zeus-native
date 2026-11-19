import AppKit
import SceneKit
import simd
import ZeusCore

/// Builds and animates the SceneKit nodes of an `ExplanationModel3D`. It owns no clock: callers pass
/// a sampled `ExplanationModelClock`, and with no model motion nothing here runs.
@MainActor
final class ExplanationModelRenderer {
    let root = SCNNode()

    private struct Look: Equatable {
        var color: ExplanationColor?
        var metalness: Double?
        var roughness: Double?
    }
    private struct PartSignature: Equatable {
        var kind: ExplanationPart.Kind
        var recipe: ExplanationPartRecipe?
        var size: ExplanationVector3?
        var radius: Double?
        var depth: Double?
        var count: Int
        var offset: ExplanationVector3
        var look: Look
    }
    private struct PartEntry {
        let node: SCNNode
        var content: SCNNode
        var signature: PartSignature
        var spinners: [(wrapper: SCNNode, factor: Double)]
    }
    private struct FlowSignature: Equatable {
        var points: [ExplanationVector3]
        var count: Int
        var color: ExplanationColor
        var markerSize: Double
    }
    private struct FlowEntry {
        let node: SCNNode
        var markers: [SCNNode]
        var signature: FlowSignature
    }
    private var parts: [String: PartEntry] = [:]
    private var flows: [String: FlowEntry] = [:]

    var partIDs: Set<String> { Set(parts.keys) }
    var flowIDs: Set<String> { Set(flows.keys) }
    func partNode(_ id: String) -> SCNNode? { parts[id]?.node }
    func markerCount(forFlow id: String) -> Int { flows[id]?.markers.count ?? 0 }

    // MARK: Colours

    static func color(_ value: ExplanationColor) -> NSColor {
        switch value {
        case .ink: NSColor(white: 0.17, alpha: 1)
        case .secondary: NSColor(white: 0.62, alpha: 1)
        default: ExplanationRenderPalette.native(value)
        }
    }

    // MARK: Structure

    /// Reconciles nodes with the model by id. A part whose shape did not change keeps its nodes,
    /// so a follow-up edit changes the existing part instead of rebuilding or duplicating it.
    func apply(_ model: ExplanationModel3D?) {
        let model = model ?? .empty
        for id in Set(parts.keys).subtracting(model.parts.keys) {
            if let removed = parts.removeValue(forKey: id) { Self.release(removed.node) }
        }
        for id in Set(flows.keys).subtracting(model.flows.keys) {
            if let removed = flows.removeValue(forKey: id) { Self.release(removed.node) }
        }
        let targets = Set(model.cutaway.partIDs)
        for part in model.parts.values.sorted(by: { $0.id < $1.id }) {
            let signature = Self.signature(part)
            var entry: PartEntry
            if let existing = parts[part.id] {
                entry = existing
                if existing.signature != signature {
                    Self.release(existing.content)
                    let built = Self.buildContent(part)
                    entry.content = built.node; entry.spinners = built.spinners; entry.signature = signature
                    entry.node.addChildNode(built.node)
                }
            } else {
                let node = SCNNode(); node.name = part.id
                let built = Self.buildContent(part)
                node.addChildNode(built.node)
                entry = PartEntry(node: node, content: built.node, signature: signature, spinners: built.spinners)
            }
            let t = part.transform
            entry.node.position = ExplanationSCNHostView.vector(t.position)
            entry.node.eulerAngles = ExplanationSCNHostView.vector(t.rotation)
            entry.node.scale = ExplanationSCNHostView.vector(t.scale)
            var opacity = part.material.opacity, hidden = !part.visible
            if targets.contains(part.id) {
                switch model.cutaway.style {
                case .none: break
                case .hide: hidden = true
                case .transparent: opacity = min(opacity, model.cutaway.opacity)
                }
            }
            entry.node.opacity = CGFloat(opacity)
            entry.node.isHidden = hidden || opacity <= 0
            parts[part.id] = entry
        }
        for part in model.parts.values {
            guard let entry = parts[part.id] else { continue }
            let parent = part.parentID.flatMap { parts[$0]?.node } ?? root
            if entry.node.parent !== parent { parent.addChildNode(entry.node) }
        }
        for flow in model.flows.values.sorted(by: { $0.id < $1.id }) {
            guard let path = model.paths[flow.pathID] else { continue }
            let signature = FlowSignature(points: path.points, count: flow.count, color: flow.color, markerSize: flow.markerSize)
            if let existing = flows[flow.id], existing.signature == signature {
                existing.node.isHidden = !flow.active
                continue
            }
            if let existing = flows.removeValue(forKey: flow.id) { Self.release(existing.node) }
            let entry = Self.buildFlow(flow, path: path, signature: signature)
            entry.node.isHidden = !flow.active
            root.addChildNode(entry.node)
            flows[flow.id] = entry
        }
    }

    /// Poses the moving parts for one clock sample. Reduce Motion passes a static pose: no spin,
    /// and markers laid out at fixed spacing, still pointing the way the energy goes.
    func update(model: ExplanationModel3D, clock: ExplanationModelClock, reduceMotion: Bool) {
        for (id, entry) in parts where !entry.spinners.isEmpty {
            let axis = (model.parts[id]?.spin?.axis ?? .z).unit
            let angle = reduceMotion ? 0 : (clock.spinAngles[id] ?? 0)
            for spinner in entry.spinners {
                spinner.wrapper.rotation = SCNVector4(x: CGFloat(axis.x), y: CGFloat(axis.y), z: CGFloat(axis.z),
                                                      w: CGFloat(angle * spinner.factor))
            }
        }
        for (id, entry) in flows {
            guard let flow = model.flows[id], let path = model.paths[flow.pathID] else { continue }
            entry.node.isHidden = !flow.active
            guard flow.active else { continue }
            let progress = reduceMotion ? 0 : (clock.flowProgress[id] ?? 0)
            let poses = ExplanationFlowMath.markers(for: flow, path: path, progress: progress)
            for (node, pose) in zip(entry.markers, poses) {
                node.simdPosition = SIMD3<Float>(Float(pose.position.x), Float(pose.position.y), Float(pose.position.z))
                let direction = SIMD3<Float>(Float(pose.tangent.x), Float(pose.tangent.y), Float(pose.tangent.z))
                if simd_length(direction) > 0.0001 {
                    node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(direction))
                }
            }
        }
    }

    /// World position a callout is anchored to: the part's origin plus the callout offset, or the
    /// offset alone for a free callout.
    func worldAnchor(for callout: ExplanationCallout) -> ExplanationVector3? {
        guard let partID = callout.partID else { return callout.anchor }
        guard let node = parts[partID]?.node else { return nil }
        let origin = node.worldPosition
        return .init(x: Double(origin.x) + callout.anchor.x, y: Double(origin.y) + callout.anchor.y,
                     z: Double(origin.z) + callout.anchor.z)
    }

    func dispose() {
        for entry in parts.values { Self.release(entry.node) }
        for entry in flows.values { Self.release(entry.node) }
        parts.removeAll(); flows.removeAll()
        root.removeFromParentNode()
    }

    // MARK: Building

    private static func signature(_ part: ExplanationPart) -> PartSignature {
        PartSignature(kind: part.kind, recipe: part.recipe, size: part.size, radius: part.radius, depth: part.depth,
                      count: max(1, part.repeats?.count ?? 1), offset: part.repeats?.offset ?? .zero,
                      look: Look(color: part.material.color, metalness: part.material.metalness,
                                 roughness: part.material.roughness))
    }

    private static func buildContent(_ part: ExplanationPart) -> (node: SCNNode, spinners: [(wrapper: SCNNode, factor: Double)]) {
        let content = SCNNode()
        var spinners: [(wrapper: SCNNode, factor: Double)] = []
        let copies = max(1, part.repeats?.count ?? 1), offset = part.repeats?.offset ?? .zero
        for index in 0..<copies {
            let instance = SCNNode()
            instance.position = ExplanationSCNHostView.vector(
                .init(x: offset.x * Double(index), y: offset.y * Double(index), z: offset.z * Double(index)))
            switch part.kind {
            case .group: break
            case .recipe:
                for primitive in ExplanationRecipes.primitives(part.recipe ?? .carShell) {
                    let node = primitiveNode(primitive, look: part.material)
                    if let spin = primitive.spin {
                        let wrapper = SCNNode()
                        wrapper.position = ExplanationSCNHostView.vector(spin.pivot)
                        node.position = ExplanationSCNHostView.vector(
                            .init(x: primitive.position.x - spin.pivot.x, y: primitive.position.y - spin.pivot.y,
                                  z: primitive.position.z - spin.pivot.z))
                        wrapper.addChildNode(node)
                        instance.addChildNode(wrapper)
                        spinners.append((wrapper, spin.factor))
                    } else {
                        node.position = ExplanationSCNHostView.vector(primitive.position)
                        instance.addChildNode(node)
                    }
                }
            case .box:
                let size = part.size ?? .one
                instance.addChildNode(plainNode(SCNBox(width: size.x, height: size.y, length: size.z, chamferRadius: 0), look: part.material))
            case .cylinder:
                let cylinder = SCNCylinder(radius: part.radius ?? 0.1, height: part.depth ?? 0.1)
                cylinder.radialSegmentCount = 24
                instance.addChildNode(plainNode(cylinder, look: part.material))
            case .sphere:
                let sphere = SCNSphere(radius: part.radius ?? 0.1)
                sphere.segmentCount = 20
                instance.addChildNode(plainNode(sphere, look: part.material))
            }
            content.addChildNode(instance)
        }
        return (content, spinners)
    }

    private static func plainNode(_ geometry: SCNGeometry, look: ExplanationPartMaterial) -> SCNNode {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color(look.color ?? .secondary)
        material.metalness.contents = look.metalness ?? 0.3
        material.roughness.contents = look.roughness ?? 0.55
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func primitiveNode(_ primitive: ExplanationRecipePrimitive, look: ExplanationPartMaterial) -> SCNNode {
        let geometry: SCNGeometry
        var euler = SCNVector3Zero
        switch primitive.shape {
        case .box(let size):
            geometry = SCNBox(width: size.x, height: size.y, length: size.z, chamferRadius: 0)
            euler.z = CGFloat(primitive.roll)
        case .cylinder(let radius, let length, let axis):
            let cylinder = SCNCylinder(radius: radius, height: length)
            cylinder.radialSegmentCount = 24
            geometry = cylinder
            switch axis {
            case .y: break
            case .z: euler.x = CGFloat.pi / 2
            case .x: euler.z = CGFloat.pi / 2
            }
        case .sphere(let radius):
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 20
            geometry = sphere
        }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color(look.color ?? primitive.color)
        material.metalness.contents = look.metalness ?? primitive.metalness
        material.roughness.contents = look.roughness ?? primitive.roughness
        if primitive.opacity < 1 {
            material.transparency = CGFloat(primitive.opacity)
            material.isDoubleSided = true
        }
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.eulerAngles = euler
        return node
    }

    private static func buildFlow(_ flow: ExplanationFlow, path: ExplanationFlowPath, signature: FlowSignature) -> FlowEntry {
        let group = SCNNode()
        group.name = flow.id
        let tint = color(flow.color)
        let lineMaterial = SCNMaterial()
        lineMaterial.lightingModel = .constant
        lineMaterial.diffuse.contents = tint
        if let tube = ExplanationSceneGeometry.tube(points: path.points, radius: flow.markerSize * 0.18) {
            tube.materials = [lineMaterial]
            let line = SCNNode(geometry: tube)
            line.opacity = 0.35
            group.addChildNode(line)
        }
        var markers: [SCNNode] = []
        for _ in 0..<flow.count {
            let cone = SCNCone(topRadius: 0, bottomRadius: flow.markerSize * 0.7, height: flow.markerSize * 2.2)
            cone.radialSegmentCount = 12
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = tint
            cone.materials = [material]
            let marker = SCNNode(geometry: cone)
            group.addChildNode(marker)
            markers.append(marker)
        }
        return FlowEntry(node: group, markers: markers, signature: signature)
    }

    private static func release(_ node: SCNNode) {
        node.removeAllActions(); node.removeAllAnimations()
        node.enumerateChildNodes { child, _ in
            child.removeAllActions(); child.removeAllAnimations(); child.geometry?.materials = []; child.geometry = nil
        }
        node.geometry?.materials = []; node.geometry = nil; node.removeFromParentNode()
    }
}
