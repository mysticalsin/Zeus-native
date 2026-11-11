import AppKit
import Metal
import QuartzCore
import SceneKit
import SwiftUI
import simd
import ZeusCore

@MainActor
private enum ExplanationSceneCapability {
    static let hasMetalDevice = MTLCreateSystemDefaultDevice() != nil
}

/// SceneKit renders only explicitly supplied presentation snapshots. There are no
/// SCNActions, implicit transitions, physics, or autonomous speech-sync clocks.
@MainActor
struct ExplanationSceneView: View {
    let scene: ExplanationScene
    @Binding var selection: String?
    var isActive = true
    var isInteractive = true
    var registry: ExplanationRegistry = .empty
    var onEdit: (ExplanationOperation) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pauseMotion = false
    @State private var frozenScene: ExplanationScene?
    @State private var resetCamera = ExplanationCamera()

    var body: some View {
        VStack(spacing: 8) {
            if (try? ExplanationSceneReducer.validate(scene, registry: registry)) == nil {
                ContentUnavailableView("Scene unavailable", systemImage: "exclamationmark.triangle",
                    description: Text("The scene did not pass geometry validation."))
            } else if !ExplanationSceneCapability.hasMetalDevice {
                ContentUnavailableView("3D rendering unavailable", systemImage: "cube",
                    description: Text("The objects and their descriptions remain available below."))
            } else {
                ExplanationSceneSurface(scene: pauseMotion ? frozenScene ?? scene : scene,
                    selection: $selection, isActive: isActive, isInteractive: isInteractive,
                    reduceMotion: reduceMotion, motionPaused: pauseMotion, registry: registry, onEdit: onEdit)
                    .frame(minHeight: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Interactive procedural 3D illustration")
            }
            HStack(spacing: 10) {
                Button { orbit(-Double.pi / 12) } label: { Image(systemName: "rotate.left") }
                    .help("Orbit left").accessibilityLabel("Orbit left")
                Button { orbit(Double.pi / 12) } label: { Image(systemName: "rotate.right") }
                    .help("Orbit right").accessibilityLabel("Orbit right")
                Button { zoom(0.8) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in").accessibilityLabel("Zoom in")
                Button { zoom(1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out").accessibilityLabel("Zoom out")
                Button("Reset view") { onEdit(.camera(resetCamera)) }
                Spacer(minLength: 4)
                Toggle("Pause motion", isOn: $pauseMotion).toggleStyle(.checkbox)
            }
            .buttonStyle(.borderless).disabled(!isInteractive)
            .font(.caption)
            Text(scene.model?.caption ?? "Procedural illustration · not a measured engineering model")
                .font(.caption2).foregroundStyle(.secondary)
            if let model = scene.model, !model.parts.isEmpty { ExplanationModelPartList(model: model) }
            if !worldObjects.isEmpty {
                ExplanationObjectList(objects: worldObjects, selection: $selection, isInteractive: isInteractive, onEdit: onEdit)
            }
        }
        .onAppear { resetCamera = scene.camera }
        .onChange(of: scene.sceneID) { _, _ in resetCamera = scene.camera; frozenScene = nil; pauseMotion = false }
        .onChange(of: pauseMotion) { _, paused in frozenScene = paused ? scene : nil }
        .accessibilityElement(children: .contain)
    }

    private var worldObjects: [ExplanationObject] {
        guard (try? ExplanationSceneReducer.validate(scene, registry: registry)) != nil else { return [] }
        return scene.objects.values.filter { $0.space == .world }.sorted { $0.id < $1.id }
    }
    private func orbit(_ angle: Double) {
        let p = scene.camera.position, t = scene.camera.target, x = p.x - t.x, z = p.z - t.z
        onEdit(.camera(.init(position: .init(x: t.x + x * cos(angle) + z * sin(angle), y: p.y,
                                            z: t.z - x * sin(angle) + z * cos(angle)),
                             target: t, fieldOfView: scene.camera.fieldOfView)))
    }
    private func zoom(_ factor: Double) {
        let p = scene.camera.position, t = scene.camera.target
        let length = sqrt(pow(p.x - t.x, 2) + pow(p.y - t.y, 2) + pow(p.z - t.z, 2))
        let scale = min(10_000, max(0.25, length * factor)) / max(length, 0.000001)
        onEdit(.camera(.init(position: .init(x: t.x + (p.x - t.x) * scale, y: t.y + (p.y - t.y) * scale,
                                            z: t.z + (p.z - t.z) * scale), target: t, fieldOfView: scene.camera.fieldOfView)))
    }
}

@MainActor
private struct ExplanationSceneSurface: NSViewRepresentable {
    let scene: ExplanationScene
    @Binding var selection: String?
    let isActive: Bool
    let isInteractive: Bool
    let reduceMotion: Bool
    var motionPaused = false
    let registry: ExplanationRegistry
    let onEdit: (ExplanationOperation) -> Void
    func makeNSView(context: Context) -> ExplanationSCNHostView { ExplanationSCNHostView() }
    func updateNSView(_ view: ExplanationSCNHostView, context: Context) {
        view.onSelection = { selection = $0 }
        view.onEdit = onEdit
        view.apply(scene, registry: registry, selectedID: selection, active: isActive,
                   interactive: isInteractive, reduceMotion: reduceMotion, motionPaused: motionPaused)
    }
    static func dismantleNSView(_ view: ExplanationSCNHostView, coordinator: ()) { view.dispose() }
}

@MainActor
final class ExplanationSCNHostView: SCNView {
    private struct Entry {
        let node: SCNNode
        var content: SCNNode
        var object: ExplanationObject
        var reveal: Double
        var highlighted: Bool
    }
    private var entries: [String: Entry] = [:]
    private let world = SCNNode()
    private let cameraNode = SCNNode()
    private let modelRenderer = ExplanationModelRenderer()
    private var model: ExplanationModel3D?
    private var clock = ExplanationModelClock()
    private var reduceMotion = false
    private var motionPaused = false
    private var isActiveSurface = true
    private var userInteracting = false
    private var modelLink: CADisplayLink?
    private var windowObservers: [NSObjectProtocol] = []
    private var cameraTween: (from: ExplanationCamera, to: ExplanationCamera, startedAt: Double?)?
    private var calloutLabels: [String: ExplanationCalloutLabel] = [:]
    private var calloutDots: [String: ExplanationCalloutDot] = [:]
    private var labelSlots: [String: Int] = [:]
    static let cameraTweenSeconds = 0.8
    private var lastCamera: ExplanationCamera?
    private var sceneID: UUID?
    private var selectedID: String?
    private var interactive = true
    private(set) var disposed = false
    private(set) var rejectedScene = false
    var onSelection: ((String?) -> Void)?
    var onEdit: ((ExplanationOperation) -> Void)?
    var objectIDs: Set<String> { Set(entries.keys) }
    var modelPartIDs: Set<String> { modelRenderer.partIDs }
    var modelFlowIDs: Set<String> { modelRenderer.flowIDs }
    var isRunningModelClock: Bool { modelLink != nil }
    func modelPartNode(_ id: String) -> SCNNode? { modelRenderer.partNode(id) }
    var visibleCalloutIDs: Set<String> { Set(calloutLabels.filter { !$0.value.isHidden }.keys) }
    func node(for id: String) -> SCNNode? { entries[id]?.node }

    init() {
        super.init(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let owned = SCNScene()
        owned.isPaused = true
        owned.rootNode.addChildNode(world)
        world.addChildNode(modelRenderer.root)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 100_000
        cameraNode.camera?.automaticallyAdjustsZRange = true
        owned.rootNode.addChildNode(cameraNode)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 450; owned.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni
        key.light?.intensity = 900; key.position = .init(4, 8, 6); owned.rootNode.addChildNode(key)
        scene = owned; pointOfView = cameraNode
        backgroundColor = .windowBackgroundColor
        antialiasingMode = .multisampling4X
        rendersContinuously = false; isPlaying = false
        defaultCameraController.inertiaEnabled = false
        defaultCameraController.interactionMode = .orbitTurntable
        setAccessibilityIdentifier("explanation.scene3D")
        setAccessibilityLabel("Procedural 3D scene. Use the Objects list to inspect each part.")
    }
    required init?(coder: NSCoder) { nil }

    func apply(_ value: ExplanationScene, registry: ExplanationRegistry = .empty, selectedID: String? = nil,
               active: Bool = true, interactive: Bool = true, reduceMotion: Bool = false, motionPaused: Bool = false) {
        guard !disposed else { return }
        self.reduceMotion = reduceMotion; self.motionPaused = motionPaused; isActiveSurface = active
        self.interactive = interactive && active
        if !self.interactive { userInteracting = false }
        allowsCameraControl = self.interactive
        rendersContinuously = false; isPlaying = false; scene?.isPaused = true
        guard (try? ExplanationSceneReducer.validate(value, registry: registry)) != nil else {
            rejectedScene = true; removeObjects(); modelRenderer.apply(nil); model = nil
            cameraTween = nil; refreshCallouts(); updateRunState(); return
        }
        rejectedScene = false
        let objects = value.objects.values.filter { $0.space == .world }.sorted { $0.id < $1.id }
        let currentIDs = Set(objects.map(\.id))
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
        if sceneID != value.sceneID {
            removeObjects(); sceneID = value.sceneID; lastCamera = nil
            clock.reset(); cameraTween = nil; labelSlots = [:]
        }
        model = value.model
        modelRenderer.apply(value.model)
        if let model { modelRenderer.update(model: model, clock: clock, reduceMotion: reduceMotion) }
        for object in objects {
            // The playback sampler has already removed optional motion. Static
            // reveal0 must remain hidden until its own admitted audio cue.
            let reveal = object.reveal
            var highlighted = object.highlighted || selectedID == object.id, ancestor = object.parentID
            while let id = ancestor, let parent = value.objects[id] {
                highlighted = highlighted || parent.highlighted || selectedID == id
                ancestor = parent.parentID
            }
            let previous = entries[object.id]
            let contentChanged = previous?.object.geometry != object.geometry || previous?.object.text != object.text
                || (object.geometry.kind == .tube && previous?.reveal != reveal)
            let materialChanged = contentChanged || previous?.object.style != object.style
                || previous?.highlighted != highlighted
            if var entry = entries[object.id] {
                if contentChanged {
                    Self.release(entry.content)
                    entry.content = ExplanationSceneGeometry.content(for: object, reveal: reveal)
                    entry.node.addChildNode(entry.content)
                }
                entry.object = object; entry.reveal = reveal; entry.highlighted = highlighted
                entries[object.id] = entry
            } else {
                let node = SCNNode(); node.name = object.id
                let content = ExplanationSceneGeometry.content(for: object, reveal: reveal)
                node.addChildNode(content)
                entries[object.id] = .init(node: node, content: content, object: object, reveal: reveal, highlighted: highlighted)
            }
            guard let entry = entries[object.id] else { continue }
            let node = entry.node, t = object.transform
            node.position = Self.vector(t.position); node.eulerAngles = Self.vector(t.rotation); node.scale = Self.vector(t.scale)
            node.opacity = CGFloat(object.style.opacity * reveal)
            node.isHidden = reveal <= 0
            if materialChanged {
                let material = ExplanationSceneGeometry.material(object.style, highlighted: highlighted)
                entry.content.enumerateChildNodes { child, _ in child.geometry?.materials = [material] }
                entry.content.geometry?.materials = [material]
            }
        }
        // Reparent retained IDs before disposing a removed group. Moving a child
        // out of a removed group must not clear the retained child's geometry.
        for object in objects {
            guard let entry = entries[object.id] else { continue }
            let parent = object.parentID.flatMap { entries[$0]?.node } ?? world
            if entry.node.parent !== parent { parent.addChildNode(entry.node) }
        }
        for id in Set(entries.keys).subtracting(currentIDs) {
            if let removed = entries.removeValue(forKey: id) { Self.release(removed.node) }
        }
        if lastCamera != value.camera {
            // A model scene turns the camera over a short, timestamped sweep; every other scene,
            // and Reduce Motion, jumps as before. The sweep starts from the pose on screen, so a
            // camera the user just dragged to is not swept back and forth.
            if value.hasModel3D, !reduceMotion, active, lastCamera != nil, let from = currentCameraPose(),
               Self.pose(from, differsFrom: value.camera) {
                cameraTween = (from, value.camera, nil)
            } else { cameraTween = nil; setCamera(value.camera) }
            lastCamera = value.camera
        }
        self.selectedID = selectedID
        SCNTransaction.commit()
        refreshCallouts(); updateRunState()
        if active && !isHiddenOrHasHiddenAncestor { needsDisplay = true }
    }

    private func setCamera(_ camera: ExplanationCamera) {
        pointOfView = cameraNode
        cameraNode.position = Self.vector(camera.position)
        cameraNode.look(at: Self.vector(camera.target))
        cameraNode.camera?.fieldOfView = CGFloat(camera.fieldOfView)
        defaultCameraController.target = Self.vector(camera.target)
    }
    private func currentCameraPose() -> ExplanationCamera? {
        let node = pointOfView ?? cameraNode
        let position = node.worldPosition, target = defaultCameraController.target
        return .init(position: .init(x: Double(position.x), y: Double(position.y), z: Double(position.z)),
                     target: .init(x: Double(target.x), y: Double(target.y), z: Double(target.z)),
                     fieldOfView: Double(node.camera?.fieldOfView ?? 45))
    }
    private static func pose(_ a: ExplanationCamera, differsFrom b: ExplanationCamera) -> Bool {
        let d = [a.position.x - b.position.x, a.position.y - b.position.y, a.position.z - b.position.z,
                 a.target.x - b.target.x, a.target.y - b.target.y, a.target.z - b.target.z]
        return d.contains { abs($0) > 0.001 }
    }

    // MARK: Model clock and callouts

    private var motionActive: Bool { !motionPaused && !reduceMotion && model?.hasMotion == true }
    private var onScreen: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible)
    }

    /// One display link, only while something moves and the view can be seen. Hidden, occluded,
    /// minimised, paused and idle views run no timer at all.
    private func updateRunState() {
        let wanted = !disposed && isActiveSurface && onScreen && (cameraTween != nil || userInteracting || motionActive)
        if wanted {
            guard modelLink == nil else { return }
            let link = displayLink(target: self, selector: #selector(modelTick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            modelLink = link
        } else if let link = modelLink {
            link.invalidate(); modelLink = nil; clock.suspend()
        }
    }

    @objc private func modelTick(_ link: CADisplayLink) {
        guard !disposed else { updateRunState(); return }
        let now = link.timestamp
        if var tween = cameraTween {
            let started = tween.startedAt ?? now
            tween.startedAt = started
            let progress = min(1, max(0, (now - started) / Self.cameraTweenSeconds))
            setCamera(ExplanationCameraMath.interpolate(tween.from, tween.to, progress * progress * (3 - 2 * progress)))
            cameraTween = progress >= 1 ? nil : tween
        }
        if let model, motionActive {
            clock.advance(to: now, model: model, reduceMotion: reduceMotion)
            modelRenderer.update(model: model, clock: clock, reduceMotion: reduceMotion)
        }
        refreshCallouts()
        needsDisplay = true
        if cameraTween == nil && !userInteracting && !motionActive { updateRunState() }
    }

    private func installWindowObservers() {
        removeWindowObservers()
        guard let window else { return }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateRunState(); self?.refreshCallouts() }
            })
        }
    }
    private func removeWindowObservers() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
    }

    private func projectionCamera() -> ExplanationCamera {
        let node = (pointOfView ?? cameraNode).presentation
        let p = node.worldPosition, f = node.worldFront
        return .init(position: .init(x: Double(p.x), y: Double(p.y), z: Double(p.z)),
                     target: .init(x: Double(p.x + f.x), y: Double(p.y + f.y), z: Double(p.z + f.z)),
                     fieldOfView: Double((pointOfView ?? cameraNode).camera?.fieldOfView ?? 45))
    }

    private func hideCallouts() {
        for view in calloutLabels.values { view.isHidden = true }
        for view in calloutDots.values { view.isHidden = true }
    }

    /// Projects every callout anchor with the camera on screen, then places the labels with the
    /// shared 2D rule so none overlap. Labels follow their parts because the anchor is read from the
    /// part's node every time.
    private func refreshCallouts() {
        guard !disposed, let model, !model.callouts.isEmpty, bounds.width >= 1, bounds.height >= 1 else {
            hideCallouts(); return
        }
        let camera = projectionCamera()
        let viewport = ExplanationSize2(width: Double(bounds.width), height: Double(bounds.height))
        var requests: [ExplanationLabelRequest] = []
        var anchors: [String: ExplanationProjectedPoint] = [:]
        for callout in model.callouts.values.sorted(by: { $0.id < $1.id }) where callout.visible {
            if let part = callout.partID, ExplanationModelAppearance.appearance(of: part, in: model)?.visible != true { continue }
            guard let world = modelRenderer.worldAnchor(for: callout),
                  let projected = ExplanationProjection.project(world, camera: camera, viewport: viewport) else { continue }
            let label = calloutLabels[callout.id] ?? makeCalloutLabel(callout.id)
            if label.stringValue != callout.text { label.stringValue = callout.text }
            let width = ceil((callout.text as NSString).size(withAttributes: [.font: ExplanationCalloutLabel.font]).width) + 14
            anchors[callout.id] = projected
            requests.append(.init(id: callout.id, anchorX: projected.x, anchorY: projected.y, width: width, height: 22))
        }
        let layout = ExplanationLabelLayout.place(requests, bounds: .init(x: 0, y: 0, width: viewport.width, height: viewport.height),
                                                  previousSlots: labelSlots)
        labelSlots = layout.slots
        func flipped(_ y: Double, _ height: Double) -> CGFloat { isFlipped ? CGFloat(y) : bounds.height - CGFloat(y + height) }
        for (id, label) in calloutLabels {
            guard let rect = layout.placed[id], let anchor = anchors[id] else {
                label.isHidden = true; calloutDots[id]?.isHidden = true; continue
            }
            label.frame = NSRect(x: rect.x, y: flipped(rect.y, rect.height), width: rect.width, height: rect.height)
            label.isHidden = false
            if let dot = calloutDots[id] {
                dot.frame = NSRect(x: anchor.x - 3, y: flipped(anchor.y, 0) - 3, width: 6, height: 6)
                dot.isHidden = false
            }
        }
        for id in Set(calloutLabels.keys).subtracting(model.callouts.keys) {
            calloutLabels.removeValue(forKey: id)?.removeFromSuperview()
            calloutDots.removeValue(forKey: id)?.removeFromSuperview()
        }
    }

    private func makeCalloutLabel(_ id: String) -> ExplanationCalloutLabel {
        let label = ExplanationCalloutLabel(frame: .zero)
        label.isHidden = true
        addSubview(label)
        calloutLabels[id] = label
        let dot = ExplanationCalloutDot(frame: .zero)
        dot.isHidden = true
        addSubview(dot)
        calloutDots[id] = dot
        return label
    }

    override var acceptsFirstResponder: Bool { interactive && !disposed }
    override func mouseDown(with event: NSEvent) {
        guard interactive && !disposed else { return }
        userInteracting = true; updateRunState()
        let point = convert(event.locationInWindow, from: nil)
        let hits = hitTest(point, options: [.firstFoundOnly: false])
        var selected: String?
        for hit in hits {
            var cursor: SCNNode? = hit.node
            while let node = cursor {
                if let id = node.name, entries[id]?.node === node { selected = id; break }
                cursor = node.parent
            }
            if selected != nil { break }
        }
        onSelection?(selected)
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        guard interactive && !disposed else { return }
        userInteracting = false; updateRunState()
        super.mouseUp(with: event)
        let currentCamera = pointOfView ?? cameraNode
        let position = currentCamera.worldPosition, target = defaultCameraController.target
        let camera = ExplanationCamera(position: .init(x: Double(position.x), y: Double(position.y), z: Double(position.z)),
            target: .init(x: Double(target.x), y: Double(target.y), z: Double(target.z)),
            fieldOfView: Double(currentCamera.camera?.fieldOfView ?? 45))
        if camera != lastCamera { onEdit?(.camera(camera)) }
        isPlaying = false
    }
    override func keyDown(with event: NSEvent) {
        guard interactive && !disposed else { return }
        if let id = selectedID, let object = entries[id]?.object {
            if event.keyCode == 51 || event.keyCode == 117 { onEdit?(.remove(id: id)); return }
            var p = object.transform.position
            switch event.keyCode {
            case 123: p.x -= 0.1
            case 124: p.x += 0.1
            case 125: p.y -= 0.1
            case 126: p.y += 0.1
            default: super.keyDown(with: event); return
            }
            if [p.x, p.y, p.z].allSatisfy({ abs($0) <= ExplanationLimits.coordinate }) { onEdit?(.move(id: id, position: p)) }
        } else { super.keyDown(with: event) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); isPlaying = false; rendersContinuously = false
        installWindowObservers(); updateRunState(); refreshCallouts()
    }
    override func viewDidHide() { super.viewDidHide(); isPlaying = false; updateRunState() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateRunState(); refreshCallouts() }
    override func layout() { super.layout(); refreshCallouts() }
    override func scrollWheel(with event: NSEvent) { super.scrollWheel(with: event); refreshCallouts() }
    override func magnify(with event: NSEvent) { super.magnify(with: event); refreshCallouts() }

    func dispose() {
        guard !disposed else { return }
        disposed = true; isPlaying = false; rendersContinuously = false; allowsCameraControl = false
        onSelection = nil; onEdit = nil
        modelLink?.invalidate(); modelLink = nil; removeWindowObservers(); cameraTween = nil
        modelRenderer.dispose(); model = nil
        for view in calloutLabels.values { view.removeFromSuperview() }
        for view in calloutDots.values { view.removeFromSuperview() }
        calloutLabels.removeAll(); calloutDots.removeAll()
        removeObjects(); scene?.rootNode.enumerateChildNodes { node, _ in node.removeAllActions(); node.removeAllAnimations() }
        pointOfView = nil; scene = nil; lastCamera = nil; selectedID = nil
    }
    private func removeObjects() { for entry in entries.values { Self.release(entry.node) }; entries.removeAll() }
    private static func release(_ node: SCNNode) {
        node.removeAllActions(); node.removeAllAnimations()
        node.enumerateChildNodes { child, _ in
            child.removeAllActions(); child.removeAllAnimations(); child.geometry?.materials = []; child.geometry = nil
        }
        node.geometry?.materials = []; node.geometry = nil; node.removeFromParentNode()
    }
    static func vector(_ p: ExplanationVector3) -> SCNVector3 { .init(Float(p.x), Float(p.y), Float(p.z)) }
}

@MainActor
enum ExplanationSceneGeometry {
    static func material(_ style: ExplanationStyle, highlighted: Bool) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = ExplanationRenderPalette.native(style.fill)
        result.lightingModel = style.material == .emissive ? .constant : .physicallyBased
        result.roughness.contents = style.material == .metal ? 0.25 : 0.7
        result.metalness.contents = style.material == .metal ? 0.85 : 0.0
        if style.material == .glass { result.transparency = 0.45; result.roughness.contents = 0.1; result.isDoubleSided = true }
        if highlighted || style.material == .emissive {
            result.emission.contents = highlighted ? NSColor.systemYellow : ExplanationRenderPalette.native(style.fill)
            result.emission.intensity = highlighted ? 0.4 : 0.7
        }
        return result
    }

    static func content(for object: ExplanationObject, reveal: Double) -> SCNNode {
        let g = object.geometry
        let geometry: SCNGeometry?
        switch g.kind {
        case .box:
            guard let size = g.size else { return SCNNode() }
            geometry = SCNBox(width: size.x, height: size.y, length: size.z, chamferRadius: 0)
        case .sphere:
            let sphere = SCNSphere(radius: g.radius ?? 1); sphere.segmentCount = 24; geometry = sphere
        case .cylinder:
            let cylinder = SCNCylinder(radius: g.radius ?? 1, height: g.depth ?? 1)
            cylinder.radialSegmentCount = 24; geometry = cylinder
        case .cone:
            let cone = SCNCone(topRadius: g.secondaryRadius ?? 0, bottomRadius: g.radius ?? 1, height: g.depth ?? 1)
            cone.radialSegmentCount = 24; geometry = cone
        case .tube:
            geometry = tube(points: revealed(g.points ?? [], fraction: reveal), radius: g.radius ?? 0.1)
        case .extrusion:
            let path = NSBezierPath()
            if let first = g.points?.first {
                path.move(to: .init(x: first.x, y: first.y))
                for p in (g.points ?? []).dropFirst() { path.line(to: .init(x: p.x, y: p.y)) }
                path.close()
            }
            geometry = SCNShape(path: path, extrusionDepth: g.depth ?? 1)
        case .mesh:
            geometry = mesh(vertices: g.vertices ?? [], indices: g.indices ?? [])
        case .label:
            let label = SCNText(string: object.text ?? "", extrusionDepth: 0)
            label.font = NSFont.systemFont(ofSize: 1, weight: .medium); label.flatness = 0.1
            label.containerFrame = CGRect(x: 0, y: 0, width: 24, height: 6)
            label.isWrapped = true; geometry = label
        default: geometry = nil
        }
        let node = SCNNode(geometry: geometry)
        if g.kind == .label { node.scale = .init(0.25, 0.25, 0.25) }
        return node
    }

    static func revealed(_ points: [ExplanationVector3], fraction: Double) -> [ExplanationVector3] {
        guard fraction.isFinite, fraction > 0, let first = points.first else { return [] }
        if fraction >= 1 { return points }
        func distance(_ a: ExplanationVector3, _ b: ExplanationVector3) -> Double {
            sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2) + pow(b.z - a.z, 2))
        }
        let lengths = zip(points, points.dropFirst()).map { distance($0.0, $0.1) }
        var remaining = lengths.reduce(0, +) * fraction, result = [first]
        for (index, length) in lengths.enumerated() where length > 0 {
            let a = points[index], b = points[index + 1]
            if remaining >= length { result.append(b); remaining -= length }
            else {
                let t = remaining / length
                result.append(.init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t)); break
            }
        }
        return result
    }

    static func mesh(vertices: [ExplanationVector3], indices: [Int]) -> SCNGeometry? {
        guard vertices.count <= ExplanationLimits.vertices, indices.count <= ExplanationLimits.indices,
              indices.count.isMultiple(of: 3), indices.allSatisfy({ vertices.indices.contains($0) }) else { return nil }
        let vectors = vertices.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        var normals = Array(repeating: SIMD3<Float>.zero, count: vectors.count)
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = indices[offset], b = indices[offset + 1], c = indices[offset + 2]
            let normal = simd_cross(vectors[b] - vectors[a], vectors[c] - vectors[a])
            if simd_length(normal) > 0.000001 { for index in [a, b, c] { normals[index] += simd_normalize(normal) } }
        }
        let converted = normals.map { value -> SCNVector3 in
            let normal = simd_length(value) > 0.000001 ? simd_normalize(value) : SIMD3<Float>(0, 0, 1)
            return .init(normal.x, normal.y, normal.z)
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices.map(ExplanationSCNHostView.vector)),
                                    SCNGeometrySource(normals: converted)],
                           elements: [SCNGeometryElement(indices: indices.map { Int32($0) }, primitiveType: .triangles)])
    }

    /// One bounded mesh per tube, avoiding thousands of independently rendered
    /// cylinder nodes. Its path is already clipped by cumulative 3D arc length.
    static func tube(points raw: [ExplanationVector3], radius: Double) -> SCNGeometry? {
        guard raw.count <= ExplanationLimits.points else { return nil }
        var points: [SIMD3<Float>] = []
        for p in raw {
            let value = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            if points.last.map({ simd_length(value - $0) > 0.000001 }) ?? true { points.append(value) }
        }
        guard points.count >= 2 else { return nil }
        let sides = 8
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for index in points.indices {
            var tangent = points[min(index + 1, points.count - 1)] - points[max(0, index - 1)]
            if simd_length(tangent) < 0.000001 { tangent = points[index] - points[max(0, index - 1)] }
            guard simd_length(tangent) > 0.000001 else { return nil }
            tangent = simd_normalize(tangent)
            let axis = abs(tangent.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let right = simd_normalize(simd_cross(tangent, axis)), up = simd_cross(right, tangent)
            for side in 0..<sides {
                let angle = Float(side) * 2 * .pi / Float(sides), normal = right * cos(angle) + up * sin(angle)
                let p = points[index] + normal * Float(radius)
                vertices.append(.init(p.x, p.y, p.z)); normals.append(.init(normal.x, normal.y, normal.z))
            }
            if index > 0 {
                for side in 0..<sides {
                    let a = Int32((index - 1) * sides + side), b = Int32((index - 1) * sides + (side + 1) % sides)
                    let c = Int32(index * sides + side), d = Int32(index * sides + (side + 1) % sides)
                    indices += [a, b, c, b, d, c]
                }
            }
        }
        for end in [0, points.count - 1] {
            let center = points[end]
            let direction = simd_normalize(end == 0 ? points[0] - points[1] : points[end] - points[end - 1])
            let centerIndex = Int32(vertices.count)
            vertices.append(.init(center.x, center.y, center.z)); normals.append(.init(direction.x, direction.y, direction.z))
            for side in 0..<sides {
                let a = Int32(end * sides + side), b = Int32(end * sides + (side + 1) % sides)
                indices += end == 0 ? [centerIndex, b, a] : [centerIndex, a, b]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}

/// Pass-through callout chip. It never takes a click, so orbiting the camera works under it.
@MainActor
final class ExplanationCalloutLabel: NSTextField {
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    override init(frame: NSRect) {
        super.init(frame: frame)
        isEditable = false; isSelectable = false; isBordered = false; drawsBackground = true
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85)
        textColor = .labelColor; font = Self.font; alignment = .center
        lineBreakMode = .byTruncatingTail; maximumNumberOfLines = 1
        wantsLayer = true; layer?.cornerRadius = 5
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class ExplanationCalloutDot: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 3; layer?.backgroundColor = NSColor.systemYellow.cgColor
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Accessible, read-only list of the named parts in a model scene.
@MainActor
struct ExplanationModelPartList: View {
    let model: ExplanationModel3D
    var body: some View {
        DisclosureGroup("Parts (\(model.parts.count))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.parts.values.sorted { $0.id < $1.id }) { part in
                    Text(part.accessibleDescription).font(.callout)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
        }
        .font(.caption.weight(.medium))
        .accessibilityIdentifier("explanation.model.parts")
    }
}
