import Foundation

/// Pure preparation of the scene the desktop card hosts: only non-capture objects, optionally one
/// beat's worth, shifted so the diagram's own bounds (plus label room) fill the card instead of
/// a mostly empty 1024 x 768 stage.
public enum ExplanationCardContentBuilder {
    public struct Fit: Equatable, Sendable {
        public var dx: Double
        public var dy: Double
        public var canvasSize: ExplanationSize2
        public var hasCanvas: Bool
        public var hasWorld: Bool
    }

    static let threeD: Set<ExplanationGeometry.Kind> = [.box, .sphere, .cylinder, .cone, .tube, .extrusion, .mesh]
    static let basePadding = 28.0, labelPadding = 100.0

    /// Non-capture objects, or only those in `focus` plus what they need to stay valid: their parent
    /// groups and the endpoints of a connector. nil when nothing remains.
    public static func cardScene(from scene: ExplanationScene, focus: Set<String>? = nil) -> ExplanationScene? {
        let candidates = Set(scene.objects.values.filter { $0.space != .capture }.map(\.id))
        var included = focus.map { candidates.intersection($0) } ?? candidates
        var changed = true
        while changed {
            changed = false
            for id in Array(included) {
                guard let object = scene.objects[id] else { continue }
                for need in [object.parentID, object.geometry.fromID, object.geometry.toID].compactMap({ $0 })
                where candidates.contains(need) && !included.contains(need) {
                    included.insert(need); changed = true
                }
            }
        }
        guard !included.isEmpty else { return nil }
        var result = scene
        result.captureID = nil
        result.objects = scene.objects.filter { included.contains($0.key) }
        return result
    }

    public static func fit(_ scene: ExplanationScene) -> Fit {
        let objects = Array(scene.objects.values)
        let hasWorld = objects.contains { $0.space == .world && threeD.contains($0.geometry.kind) }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var drawn = false, labelled = false
        for object in objects where object.space == .canvas {
            let kind = object.geometry.kind
            guard kind != .group, kind != .connector else { continue }
            for local in localPoints(object.geometry) {
                let p = absolute(local, of: object, in: scene)
                guard p.x.isFinite, p.y.isFinite else { continue }
                minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
                drawn = true
            }
            if let text = object.text, !text.isEmpty, ![.badge, .card].contains(kind) { labelled = true }
        }
        guard drawn else {
            return Fit(dx: 0, dy: 0, canvasSize: scene.canvasSize, hasCanvas: false, hasWorld: hasWorld)
        }
        let pad = basePadding + (labelled ? labelPadding : 0)
        let size = ExplanationSize2(width: min(8192, max(1, maxX - minX + 2 * pad)),
                                    height: min(8192, max(1, maxY - minY + 2 * pad)))
        return Fit(dx: minX - pad, dy: minY - pad, canvasSize: size, hasCanvas: true, hasWorld: hasWorld)
    }

    /// Shifts root canvas objects; groups carry their children. World objects are untouched.
    public static func applying(_ fit: Fit, to scene: ExplanationScene) -> ExplanationScene {
        guard fit.hasCanvas, fit.dx.isFinite, fit.dy.isFinite else { return scene }
        var result = scene
        result.canvasSize = fit.canvasSize
        for (id, object) in scene.objects where object.space == .canvas && object.parentID == nil {
            var shifted = object
            shifted.transform.position.x -= fit.dx
            shifted.transform.position.y -= fit.dy
            result.objects[id] = shifted
        }
        return result
    }

    public static func content(_ fit: Fit, caption: String) -> ExplanationCardContent {
        ExplanationCardContent(visual: fit.hasCanvas ? fit.canvasSize : nil, hasWorld: fit.hasWorld,
                               captionCharacters: caption.count)
    }

    /// Local-space extreme points of a planar geometry. Labels have no geometry: their anchor point.
    static func localPoints(_ g: ExplanationGeometry) -> [(x: Double, y: Double)] {
        if let points = g.points { return points.map { (x: $0.x, y: $0.y) } }
        if let radius = g.radius, [.point, .ring, .badge].contains(g.kind) {
            return [(-radius, -radius), (radius, -radius), (-radius, radius), (radius, radius)].map { (x: $0.0, y: $0.1) }
        }
        if let size = g.size { return [(x: 0, y: 0), (x: size.x, y: 0), (x: 0, y: size.y), (x: size.x, y: size.y)] }
        return [(x: 0, y: 0)]
    }

    static func absolute(_ local: (x: Double, y: Double), of object: ExplanationObject,
                         in scene: ExplanationScene) -> (x: Double, y: Double) {
        var point = local
        var current: ExplanationObject? = object
        var depth = 0
        while let o = current, depth < 17 {
            let t = o.transform
            let sx = point.x * t.scale.x, sy = point.y * t.scale.y
            let c = cos(t.rotation.z), s = sin(t.rotation.z)
            point = (x: c * sx - s * sy + t.position.x, y: s * sx + c * sy + t.position.y)
            current = o.parentID.flatMap { scene.objects[$0] }
            depth += 1
        }
        return point
    }
}
