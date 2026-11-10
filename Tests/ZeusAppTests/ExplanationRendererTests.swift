import AppKit
import CoreGraphics
import CryptoKit
import SceneKit
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// Owned geometry and generated production-view frames. These are not screen
/// captures, live speech synchronization proof, or display frame-rate measurements.
@MainActor @Suite("Explanation native renderers", .serialized)
struct ExplanationRendererTests {
    private func scene(_ objects: [ExplanationObject], size: ExplanationSize2 = .init(width: 400, height: 200)) -> ExplanationScene {
        .init(sessionID: UUID(), sceneID: UUID(), canvasSize: size,
              objects: Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) }))
    }
    private func rectangle(_ id: String, x: Double, y: Double, width: Double = 60, height: Double = 40) -> ExplanationObject {
        .init(id: id, geometry: .init(kind: .roundedRectangle, size: .init(x: width, y: height)),
              transform: .init(position: .init(x: x, y: y)), accessibleDescription: id)
    }
    private func worldObject(_ id: String, geometry: ExplanationGeometry) -> ExplanationObject {
        .init(id: id, space: .world, geometry: geometry, accessibleDescription: id)
    }

    @Test func cumulativeRevealUsesDistanceAndHandlesZeroDuplicateAndInvalidProgress() {
        let points = [CGPoint.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 90)]
        #expect(ExplanationCanvasLayout.revealed(points, fraction: 0.5).last == CGPoint(x: 10, y: 40))
        #expect(ExplanationCanvasLayout.revealed([.zero] + points, fraction: 0.5).last == CGPoint(x: 10, y: 40))
        #expect(ExplanationCanvasLayout.revealed(points, fraction: 0).isEmpty)
        #expect(ExplanationCanvasLayout.revealed(points, fraction: .nan).isEmpty)
        #expect(ExplanationCanvasLayout.revealed(points, fraction: 1) == points)
        let world = [ExplanationVector3.zero, .init(x: 0, y: 0, z: 10), .init(x: 0, y: 90, z: 10)]
        #expect(ExplanationSceneGeometry.revealed(world, fraction: 0.5).last == .init(x: 0, y: 40, z: 10))
        #expect(ExplanationSceneGeometry.revealed(world, fraction: 0).isEmpty)
    }

    @Test func connectorsFollowSubjectEdgesAndSelectionUsesTheRevealedPath() throws {
        let a = rectangle("a", x: 30, y: 80), b = rectangle("b", x: 300, y: 80)
        var line = ExplanationObject(id: "connection", geometry: .init(kind: .connector, fromID: "a", toID: "b"),
                                     accessibleDescription: "A connects to B", reveal: 0.5)
        var input = scene([a, b, line])
        let first = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200))
        let item = try #require(first.items.first { $0.object.id == line.id })
        #expect(item.linePoints == [.init(x: 90, y: 100), .init(x: 300, y: 100)])
        #expect(first.hitTest(.init(x: 130, y: 100)) == line.id)
        #expect(first.hitTest(.init(x: 250, y: 100)) == nil)
        line.reveal = 1; input.objects[line.id] = line; input.objects["b"]?.transform.position.x = 260
        let updated = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200))
        #expect(updated.items.first { $0.object.id == line.id }?.linePoints.last == .init(x: 260, y: 100))
        #expect(updated.hitTest(.init(x: 250, y: 100)) == line.id)
    }

    @Test func nestedTransformsAndKeyboardNudgesShareOneInverseMapping() throws {
        let parent = ExplanationObject(id: "parent", geometry: .init(kind: .group),
            transform: .init(position: .init(x: 100, y: 50), rotation: .init(x: 0, y: 0, z: .pi / 2),
                             scale: .init(x: 2, y: 2, z: 1)), accessibleDescription: "Group")
        var child = rectangle("child", x: 10, y: 0, width: 20, height: 10); child.parentID = parent.id
        let layout = ExplanationCanvasLayout(scene: scene([parent, child]), size: .init(width: 400, height: 200))
        let item = try #require(layout.items.first { $0.object.id == child.id })
        #expect(abs(item.bounds.minX - 80) < 0.001 && abs(item.bounds.minY - 70) < 0.001)
        #expect(layout.hitTest(.init(x: 90, y: 90)) == child.id)
        guard case .move(let id, let position) = try #require(layout.nudge(id: child.id, direction: .right)) else {
            Issue.record("Keyboard edit did not preserve stable object identity"); return
        }
        #expect(id == child.id && abs(position.x - 10) < 0.001 && abs(position.y + 4) < 0.001)
    }

    @Test func groupVisibilityAndConnectorBoundsFollowTheSameTransformedDescendants() throws {
        var parent = ExplanationObject(id: "group", geometry: .init(kind: .group),
            transform: .init(position: .init(x: 20, y: 20), scale: .init(x: 2, y: 2, z: 1)),
            accessibleDescription: "Grouped subjects")
        var child = rectangle("child", x: 10, y: 20, width: 30, height: 20); child.parentID = parent.id
        let target = rectangle("target", x: 300, y: 60)
        let connector = ExplanationObject(id: "link", geometry: .init(kind: .connector, fromID: parent.id, toID: target.id),
                                          accessibleDescription: "Group to target")
        var input = scene([parent, child, target, connector])
        let layout = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200))
        #expect(layout.items.first { $0.object.id == parent.id }?.bounds == CGRect(x: 40, y: 60, width: 60, height: 40))
        #expect(layout.items.first { $0.object.id == connector.id }?.linePoints == [.init(x: 100, y: 80), .init(x: 300, y: 80)])
        #expect(layout.hitTest(.init(x: 70, y: 80)) == child.id)
        parent.style.opacity = 0; input.objects[parent.id] = parent
        let hidden = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200))
        #expect(hidden.items.first { $0.object.id == child.id }?.opacity == 0)
        #expect(hidden.hitTest(.init(x: 70, y: 80)) == nil)
        parent.style.opacity = 1; parent.reveal = 0; input.objects[parent.id] = parent
        let unrevealed = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200))
        #expect(unrevealed.items.first { $0.object.id == child.id }?.opacity == 0)
        let reduced = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200), reduceMotion: true)
        #expect(reduced.items.first { $0.object.id == child.id }?.opacity == 0)
    }

    @Test func captureProjectionClipsLetterboxingRejectsStaleContextAndInvertsEdits() throws {
        let display = try ExplanationDisplayContext(displayID: 42, frame: .init(x: -1200, y: 0, width: 1200, height: 800), backingScale: 2)
        let capture = try ExplanationCaptureGeometry(display: display, fullImageSize: .init(width: 2400, height: 1600),
            crop: .init(x: 0, y: 0, width: 2400, height: 1600), imageSize: .init(width: 800, height: 400))
        var object = rectangle("capture-region", x: 40, y: 60, width: 100, height: 80)
        object.space = .capture; object.captureID = capture.captureID
        var input = scene([object]); input.captureID = capture.captureID
        let current = ExplanationCaptureContext(geometry: capture, currentDisplay: display)
        let layout = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 300), captureContext: current)
        let item = try #require(layout.items.first)
        #expect(item.bounds == CGRect(x: 20, y: 80, width: 50, height: 40))
        #expect(layout.hitTest(.init(x: 30, y: 90)) == object.id)
        #expect(layout.hitTest(.init(x: 30, y: 20)) == nil)
        guard case .move(_, let position) = try #require(layout.nudge(id: object.id, direction: .right)) else {
            Issue.record("Capture edit could not invert delivered-image projection"); return
        }
        #expect(position.x == 56 && position.y == 60)
        let changed = try ExplanationDisplayContext(displayID: display.displayID, frame: display.frame, backingScale: 2)
        let stale = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 300),
            captureContext: .init(geometry: capture, currentDisplay: changed))
        #expect(stale.items.isEmpty && stale.hitTest(.init(x: 30, y: 90)) == nil)
        let override = try #require(ExplanationCaptureDrawingTransform(context: current,
            affine: .init(a: 0.25, b: 0, c: 0, d: 0.5, tx: 10, ty: 20), clip: .init(x: 10, y: 20, width: 200, height: 200)))
        let overlay = ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 300),
            captureContext: current, captureTransform: override)
        #expect(overlay.items.first?.bounds == CGRect(x: 20, y: 50, width: 25, height: 40))
        #expect(ExplanationCaptureDrawingTransform(context: current, affine: .init(scaleX: 0, y: 0), clip: layout.viewport) == nil)
    }

    @Test func measuredLabelsStayClippedAndDoNotOverlapSubjectsOrEachOther() {
        var left = rectangle("a", x: 50, y: 70); left.text = "A measured label"
        var right = rectangle("b", x: 250, y: 70); right.text = "Another measured label"
        let layout = ExplanationCanvasLayout(scene: scene([left, right]), size: .init(width: 400, height: 200))
        let labels = layout.items.compactMap(\.label)
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(layout.viewport.contains(label))
            #expect(!layout.items.contains { $0.bounds.intersects(label) })
        }
        for index in labels.indices { for other in labels.indices where index != other { #expect(!labels[index].intersects(labels[other])) } }
        #expect(labels.count + layout.hiddenLabelIDs.count == 2)
    }

    @Test func invalidSceneCannotRenderAndReducedMotionPreservesSuppliedPresentation() {
        var object = ExplanationObject(id: "stroke", geometry: .init(kind: .path, points: [.zero, .init(x: 200, y: 100)]),
                                      accessibleDescription: "Stroke", reveal: 0.25)
        let input = scene([object])
        #expect(ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200)).items.first?.reveal == 0.25)
        #expect(ExplanationCanvasLayout(scene: input, size: .init(width: 400, height: 200), reduceMotion: true).items.first?.reveal == 0.25)
        object.reveal = 0
        let hidden = ExplanationCanvasLayout(scene: scene([object]), size: .init(width: 400, height: 200), reduceMotion: true)
        #expect(hidden.items.first?.reveal == 0 && hidden.hitTest(.init(x: 10, y: 5)) == nil)
        object.transform.position.x = .infinity
        let invalid = ExplanationCanvasLayout(scene: scene([object]), size: .init(width: 400, height: 200))
        #expect(!invalid.isValid && invalid.items.isEmpty && invalid.hitTest(.zero) == nil)
    }

    @Test func productionCanvasPixelsChangeOnlyWithSuppliedPresentationAndRespectReducedMotion() throws {
        func render(_ reveal: Double, reduced: Bool = false) throws -> String {
            let object = ExplanationObject(id: "stroke", geometry: .init(kind: .path,
                points: [.init(x: 20, y: 100), .init(x: 60, y: 100), .init(x: 360, y: 100)]),
                style: .init(stroke: .blue, lineWidth: 5), accessibleDescription: "Growing path", reveal: reveal)
            let layout = ExplanationCanvasLayout(scene: scene([object]), size: .init(width: 400, height: 200), reduceMotion: reduced)
            let renderer = ImageRenderer(content: ExplanationCanvasArtwork(layout: layout)
                .frame(width: 400, height: 200).background(.white).environment(\.colorScheme, .light))
            renderer.scale = 2; renderer.isOpaque = true
            let image = try #require(renderer.cgImage)
            #expect(image.width == 800 && image.height == 400)
            let pixels = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            pixels.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = try #require(pixels.data)
            return SHA256.hash(data: Data(bytes: bytes, count: image.width * image.height * 4)).map { String(format: "%02x", $0) }.joined()
        }
        let empty = try render(0), half = try render(0.5), full = try render(1)
        #expect(Set([empty, half, full]).count == 3)
        #expect(try render(0.5) == half)
        #expect(try render(0, reduced: true) == empty)
        #expect(try render(0.5, reduced: true) == half)
    }

    @Test func worldGeometryIsBoundedAndContainsRealMeshNormalsAndCappedTubes() throws {
        let mesh = try #require(ExplanationSceneGeometry.mesh(vertices: [.zero, .init(x: 1, y: 0), .init(x: 0, y: 1)], indices: [0, 1, 2]))
        #expect(mesh.sources(for: .vertex).first?.vectorCount == 3)
        #expect(mesh.sources(for: .normal).first?.vectorCount == 3)
        #expect(mesh.elements.first?.primitiveCount == 1)
        #expect(ExplanationSceneGeometry.mesh(vertices: [.zero], indices: [0, 1, 2]) == nil)
        let tube = try #require(ExplanationSceneGeometry.tube(points: [.zero, .init(x: 0, y: 1), .init(x: 1, y: 1)], radius: 0.1))
        #expect(tube.sources(for: .vertex).first?.vectorCount == 3 * 8 + 2)
        #expect(tube.elements.first?.primitiveCount == 2 * 8 * 2 + 8 * 2)
        #expect(ExplanationSceneGeometry.tube(points: [.zero, .zero], radius: 0.1) == nil)
        #expect(ExplanationSceneGeometry.tube(points: Array(repeating: .zero, count: ExplanationLimits.points + 1), radius: 0.1) == nil)
        let extrusion = worldObject("shape", geometry: .init(kind: .extrusion, depth: 0.5,
            points: [.zero, .init(x: 1, y: 0), .init(x: 0, y: 1)]))
        #expect(ExplanationSceneGeometry.content(for: extrusion, reveal: 1).geometry is SCNShape)
    }

    @Test func nativeScenePreservesStableNodesReparentsLiveChildrenAndDisposesResources() throws {
        _ = NSApplication.shared
        let view = ExplanationSCNHostView()
        defer { view.dispose() }
        let group = worldObject("group", geometry: .init(kind: .group))
        var box = worldObject("box", geometry: .init(kind: .box, size: .one)); box.parentID = group.id
        var input = scene([group, box])
        view.apply(input, selectedID: box.id)
        let node = try #require(view.node(for: box.id)), content = try #require(node.childNodes.first)
        let geometry = try #require(content.geometry)
        #expect(view.objectIDs == ["group", "box"] && node.parent === view.node(for: group.id))
        #expect(!view.isPlaying && !view.rendersContinuously && view.scene?.isPaused == true)
        input.objects[box.id]?.transform.position.x = 2
        input.objects[box.id]?.reveal = 0.5
        view.apply(input, selectedID: box.id)
        #expect(view.node(for: box.id) === node && node.childNodes.first?.geometry === geometry)
        #expect(node.position.x == 2 && node.opacity == 0.5)
        input.objects.removeValue(forKey: group.id); input.objects[box.id]?.parentID = nil
        view.apply(input, selectedID: box.id)
        #expect(view.objectIDs == ["box"] && node.childNodes.first?.geometry === geometry)
        input.objects.removeAll(); view.apply(input)
        #expect(view.objectIDs.isEmpty && node.parent == nil && content.geometry == nil)
        view.dispose(); view.dispose(); view.apply(scene([box]))
        #expect(view.disposed && view.scene == nil && view.pointOfView == nil && view.objectIDs.isEmpty)
    }

    @Test func nativeSceneReducedMotionNeverRevealsFutureObjectsAndGroupHighlightReachesChildren() throws {
        _ = NSApplication.shared
        let view = ExplanationSCNHostView()
        defer { view.dispose() }
        var group = worldObject("group", geometry: .init(kind: .group)); group.highlighted = true
        var sphere = worldObject("part", geometry: .init(kind: .sphere, radius: 1))
        sphere.parentID = group.id; sphere.reveal = 0
        var input = scene([group, sphere])
        view.apply(input, reduceMotion: true)
        let node = try #require(view.node(for: sphere.id))
        #expect(node.isHidden && node.opacity == 0)
        #expect(node.childNodes.first?.geometry?.firstMaterial?.emission.intensity == 0.4)
        input.objects[sphere.id]?.reveal = 0.5
        view.apply(input, reduceMotion: true)
        #expect(!node.isHidden && node.opacity == 0.5)
    }

    @Test func nativeSceneRejectsMalformedGeometryAndReadOnlyModeNeverEmitsKeyboardEdits() throws {
        _ = NSApplication.shared
        let view = ExplanationSCNHostView()
        defer { view.dispose() }
        let sphere = worldObject("sphere", geometry: .init(kind: .sphere, radius: 1))
        var input = scene([sphere])
        var edits: [ExplanationOperation] = []
        view.onEdit = { edits.append($0) }
        let left = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123))
        view.apply(input, selectedID: sphere.id, interactive: false)
        view.keyDown(with: left)
        #expect(edits.isEmpty && !view.allowsCameraControl && !view.acceptsFirstResponder)
        view.apply(input, selectedID: sphere.id, interactive: true)
        view.keyDown(with: left)
        #expect(edits == [.move(id: sphere.id, position: .init(x: -0.1, y: 0))])
        input.objects[sphere.id]?.geometry.radius = .nan
        view.apply(input)
        #expect(view.rejectedScene && view.objectIDs.isEmpty)
    }
}
