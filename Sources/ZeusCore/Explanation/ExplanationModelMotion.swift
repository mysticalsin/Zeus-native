import Foundation

enum ExplanationV3 {
    static func add(_ a: ExplanationVector3, _ b: ExplanationVector3) -> ExplanationVector3 {
        .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }
    static func sub(_ a: ExplanationVector3, _ b: ExplanationVector3) -> ExplanationVector3 {
        .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }
    static func scale(_ a: ExplanationVector3, _ k: Double) -> ExplanationVector3 {
        .init(x: a.x * k, y: a.y * k, z: a.z * k)
    }
    static func dot(_ a: ExplanationVector3, _ b: ExplanationVector3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    static func cross(_ a: ExplanationVector3, _ b: ExplanationVector3) -> ExplanationVector3 {
        .init(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
    }
    static func length(_ a: ExplanationVector3) -> Double { sqrt(dot(a, a)) }
    static func normalized(_ a: ExplanationVector3) -> ExplanationVector3 {
        let l = length(a)
        return l > 1e-12 ? scale(a, 1 / l) : .zero
    }
    static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }
}

/// Integrates part spins and flow travel from timestamps. It never counts frames: the same elapsed
/// time gives the same angle at 30 or 120 frames per second. A step is capped so a stalled display
/// (sleep, occlusion) resumes smoothly instead of jumping. `animationRate` scales every step, and a
/// rate or direction change continues from the present pose because only increments are summed.
public struct ExplanationModelClock: Equatable, Sendable {
    public static let maximumStep = 0.25
    public private(set) var timestamp: Double?
    /// Animation seconds elapsed (real seconds times the rate in force at each step).
    public private(set) var elapsed = 0.0
    public private(set) var spinAngles: [String: Double] = [:]
    /// Signed distance travelled along each flow's path, in path order, wrapped to the path length.
    public private(set) var flowProgress: [String: Double] = [:]
    public init() {}

    public mutating func advance(to now: Double, model: ExplanationModel3D, reduceMotion: Bool = false) {
        guard now.isFinite else { return }
        defer { timestamp = now }
        guard let last = timestamp, !reduceMotion else { return }
        let step = min(max(now - last, 0), Self.maximumStep)
        let rate = min(max(model.animationRate, 0), ExplanationModelLimits.animationRate)
        let dt = step * rate
        elapsed += dt
        var angles: [String: Double] = [:]
        for part in model.parts.values {
            let current = spinAngles[part.id] ?? 0
            guard let spin = part.spin, part.visible else { if current != 0 { angles[part.id] = current }; continue }
            angles[part.id] = (current + spin.radiansPerSecond * dt).truncatingRemainder(dividingBy: 2 * Double.pi)
        }
        spinAngles = angles
        var progress: [String: Double] = [:]
        for flow in model.flows.values {
            let current = flowProgress[flow.id] ?? 0
            guard flow.active, let path = model.paths[flow.pathID] else { progress[flow.id] = current; continue }
            let length = ExplanationFlowMath.length(of: path.points)
            guard length > 1e-9 else { continue }
            let moved = current + flow.direction.sign * flow.speed * dt
            progress[flow.id] = ExplanationV3.positiveModulo(moved, length)
        }
        flowProgress = progress
    }

    /// Call when the display stops, so the first frame after a restart does not add the idle gap.
    public mutating func suspend() { timestamp = nil }
    public mutating func reset() { self = Self() }
}

public struct ExplanationFlowMarker: Equatable, Sendable {
    public var position: ExplanationVector3
    /// Unit direction of travel in world space.
    public var tangent: ExplanationVector3
}

public enum ExplanationFlowMath {
    public static func length(of points: [ExplanationVector3]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + ExplanationV3.length(ExplanationV3.sub($1.1, $1.0)) }
    }

    /// Point and path-order tangent at `distance` along the polyline (clamped to its ends).
    public static func sample(_ points: [ExplanationVector3], at distance: Double) -> (position: ExplanationVector3, tangent: ExplanationVector3)? {
        guard points.count >= 2 else { return nil }
        var remaining = max(0, distance)
        var lastTangent = ExplanationVector3.zero
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let segment = ExplanationV3.sub(b, a)
            let l = ExplanationV3.length(segment)
            guard l > 1e-12 else { continue }
            let tangent = ExplanationV3.scale(segment, 1 / l)
            lastTangent = tangent
            if remaining <= l { return (ExplanationV3.add(a, ExplanationV3.scale(tangent, remaining)), tangent) }
            remaining -= l
        }
        guard let end = points.last, ExplanationV3.length(lastTangent) > 0 else { return nil }
        return (end, lastTangent)
    }

    /// Marker poses for one flow. `progress` is the clock's signed distance travelled; with Reduce
    /// Motion pass 0 for a static arrangement. Tangents already include the flow's direction, so an
    /// arrow drawn along the tangent points where the energy goes whatever the camera does.
    public static func markers(for flow: ExplanationFlow, path: ExplanationFlowPath, progress: Double) -> [ExplanationFlowMarker] {
        let total = length(of: path.points)
        guard total > 1e-9, flow.count > 0, progress.isFinite else { return [] }
        var result: [ExplanationFlowMarker] = []
        for index in 0..<flow.count {
            let distance = ExplanationV3.positiveModulo(progress + total * Double(index) / Double(flow.count), total)
            guard let sampled = sample(path.points, at: distance) else { continue }
            result.append(.init(position: sampled.position, tangent: ExplanationV3.scale(sampled.tangent, flow.direction.sign)))
        }
        return result
    }
}

public enum ExplanationRolling {
    /// Angular velocity of a wheel rolling without slipping: omega = n x v / r.
    public static func angularVelocity(travel: ExplanationVector3, groundNormal: ExplanationVector3 = .init(x: 0, y: 1, z: 0),
                                       radius: Double) -> ExplanationVector3 {
        guard radius > 0 else { return .zero }
        return ExplanationV3.scale(ExplanationV3.cross(groundNormal, travel), 1 / radius)
    }
    /// Signed spin about the wheel's axle, in radians per second, for a car moving along `travel`.
    public static func spinRate(travel: ExplanationVector3, axle: ExplanationAxis, radius: Double) -> Double {
        ExplanationV3.dot(angularVelocity(travel: travel, radius: radius), axle.unit)
    }
}

public struct ExplanationPartAppearance: Equatable, Sendable {
    public var visible: Bool
    public var opacity: Double
}

public enum ExplanationModelAppearance {
    /// What a part looks like once its ancestors and the cutaway are applied.
    public static func appearance(of id: String, in model: ExplanationModel3D) -> ExplanationPartAppearance? {
        guard model.parts[id] != nil else { return nil }
        var visible = true, opacity = 1.0, targeted = false
        let targets = Set(model.cutaway.partIDs)
        var cursor: String? = id, hops = 0
        while let current = cursor, let part = model.parts[current], hops <= ExplanationModelLimits.hierarchyDepth + 1 {
            visible = visible && part.visible
            opacity *= part.material.opacity
            if targets.contains(current) { targeted = true }
            cursor = part.parentID; hops += 1
        }
        if targeted {
            switch model.cutaway.style {
            case .none: break
            case .hide: visible = false
            case .transparent: opacity = min(opacity, model.cutaway.opacity)
            }
        }
        return .init(visible: visible, opacity: opacity)
    }
}

public enum ExplanationCameraMath {
    static func direction(_ preset: ExplanationCameraPreset) -> ExplanationVector3 {
        switch preset {
        case .overview: .init(x: 0.62, y: 0.38, z: 0.68)
        case .front: .init(x: 1, y: 0.18, z: 0)
        case .rear: .init(x: -1, y: 0.18, z: 0)
        case .side: .init(x: 0, y: 0.15, z: 1)
        case .top: .init(x: 0.12, y: 1, z: 0.05)
        case .inside: .init(x: 0.55, y: 0.5, z: 0.62)
        }
    }

    /// Preset first (same target and distance, except `inside` which moves closer), then orbit
    /// about the world Y axis through the target, then zoom as a multiplier on the distance.
    public static func apply(_ change: ExplanationViewChange, to camera: ExplanationCamera) -> ExplanationCamera {
        var offset = ExplanationV3.sub(camera.position, camera.target)
        if let preset = change.preset {
            let distance = ExplanationV3.length(offset)
            let factor = preset == .inside ? 0.55 : 1
            offset = ExplanationV3.scale(ExplanationV3.normalized(direction(preset)), distance * factor)
        }
        if let degrees = change.orbit {
            let angle = degrees * Double.pi / 180
            offset = .init(x: offset.x * cos(angle) + offset.z * sin(angle), y: offset.y,
                           z: -offset.x * sin(angle) + offset.z * cos(angle))
        }
        if let zoom = change.zoom { offset = ExplanationV3.scale(offset, zoom) }
        var result = camera
        result.position = ExplanationV3.add(camera.target, offset)
        return result
    }

    /// Interpolates in orbit space (azimuth, radius, height), so a turn sweeps an arc around the
    /// target and never cuts through the model.
    public static func interpolate(_ a: ExplanationCamera, _ b: ExplanationCamera, _ t: Double) -> ExplanationCamera {
        if !(t > 0) { return a }
        if t >= 1 { return b }
        let oa = ExplanationV3.sub(a.position, a.target), ob = ExplanationV3.sub(b.position, b.target)
        let phiA = atan2(oa.x, oa.z), phiB = atan2(ob.x, ob.z)
        var delta = phiB - phiA
        while delta > Double.pi { delta -= 2 * Double.pi }
        while delta < -Double.pi { delta += 2 * Double.pi }
        let phi = phiA + delta * t
        let radiusA = sqrt(oa.x * oa.x + oa.z * oa.z), radiusB = sqrt(ob.x * ob.x + ob.z * ob.z)
        let radius = radiusA + (radiusB - radiusA) * t
        let target = ExplanationVector3(x: a.target.x + (b.target.x - a.target.x) * t,
                                        y: a.target.y + (b.target.y - a.target.y) * t,
                                        z: a.target.z + (b.target.z - a.target.z) * t)
        let height = oa.y + (ob.y - oa.y) * t
        let offset = ExplanationVector3(x: radius * sin(phi), y: height, z: radius * cos(phi))
        return .init(position: ExplanationV3.add(target, offset), target: target,
                     fieldOfView: a.fieldOfView + (b.fieldOfView - a.fieldOfView) * t)
    }
}

public struct ExplanationProjectedPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// Distance along the view direction.
    public var depth: Double
}

public enum ExplanationProjection {
    /// Pinhole projection with a vertical field of view, Y up, to a top-left, y-down viewport.
    /// Nil when the point is behind the camera or the viewport is degenerate.
    public static func project(_ point: ExplanationVector3, camera: ExplanationCamera,
                               viewport: ExplanationSize2) -> ExplanationProjectedPoint? {
        guard viewport.width >= 1, viewport.height >= 1, camera.fieldOfView > 0, camera.fieldOfView < 180 else { return nil }
        let forward = ExplanationV3.normalized(ExplanationV3.sub(camera.target, camera.position))
        guard ExplanationV3.length(forward) > 0 else { return nil }
        var right = ExplanationV3.normalized(ExplanationV3.cross(forward, .init(x: 0, y: 1, z: 0)))
        if ExplanationV3.length(right) == 0 { right = .init(x: 1, y: 0, z: 0) }
        let up = ExplanationV3.cross(right, forward)
        let d = ExplanationV3.sub(point, camera.position)
        let depth = ExplanationV3.dot(d, forward)
        guard depth > 0.01 else { return nil }
        let tanHalf = tan(camera.fieldOfView * Double.pi / 360)
        let aspect = viewport.width / viewport.height
        let ndcX = ExplanationV3.dot(d, right) / (depth * tanHalf * aspect)
        let ndcY = ExplanationV3.dot(d, up) / (depth * tanHalf)
        return .init(x: (ndcX * 0.5 + 0.5) * viewport.width, y: (0.5 - ndcY * 0.5) * viewport.height, depth: depth)
    }
}

public struct ExplanationScreenRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public func insetBy(dx: Double, dy: Double) -> Self { .init(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy) }
    /// Overlap with positive area. Rectangles that only touch do not intersect.
    public func intersects(_ other: Self) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }
    public func contains(_ other: Self) -> Bool {
        other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
    }
}

public struct ExplanationLabelRequest: Equatable, Sendable {
    public var id: String
    public var anchorX: Double
    public var anchorY: Double
    public var width: Double
    public var height: Double
    public init(id: String, anchorX: Double, anchorY: Double, width: Double, height: Double) {
        self.id = id; self.anchorX = anchorX; self.anchorY = anchorY; self.width = width; self.height = height
    }
}

public struct ExplanationLabelLayoutResult: Equatable, Sendable {
    public var placed: [String: ExplanationScreenRect] = [:]
    public var slots: [String: Int] = [:]
    public var hidden: [String] = []
}

/// The 2D label rule of `ExplanationCanvasLayout`, on screen-projected anchors: try right, left,
/// above, below, 10 points from the anchor; keep 4 points inside the view and 4 points between
/// labels; never cover an anchor dot. A label with no free slot is hidden, not stacked.
/// `previousSlots` is tried first so a label does not jump between sides as the camera orbits.
public enum ExplanationLabelLayout {
    public static let offset = 10.0
    public static let margin = 4.0
    public static let anchorRadius = 5.0

    public static func place(_ requests: [ExplanationLabelRequest], bounds: ExplanationScreenRect,
                             previousSlots: [String: Int] = [:]) -> ExplanationLabelLayoutResult {
        var result = ExplanationLabelLayoutResult()
        let ordered = requests.sorted { $0.id < $1.id }
        let dots = ordered.map {
            ExplanationScreenRect(x: $0.anchorX - anchorRadius, y: $0.anchorY - anchorRadius,
                                  width: anchorRadius * 2, height: anchorRadius * 2)
        }
        var occupied: [ExplanationScreenRect] = []
        let inner = bounds.insetBy(dx: margin, dy: margin)
        for request in ordered {
            let w = request.width, h = request.height, ax = request.anchorX, ay = request.anchorY
            let candidates = [
                ExplanationScreenRect(x: ax + offset, y: ay - h / 2, width: w, height: h),
                ExplanationScreenRect(x: ax - w - offset, y: ay - h / 2, width: w, height: h),
                ExplanationScreenRect(x: ax - w / 2, y: ay - h - offset, width: w, height: h),
                ExplanationScreenRect(x: ax - w / 2, y: ay + offset, width: w, height: h)
            ]
            var order = Array(candidates.indices)
            if let previous = previousSlots[request.id], candidates.indices.contains(previous) {
                order.removeAll { $0 == previous }
                order.insert(previous, at: 0)
            }
            let chosen = order.first { slot in
                let candidate = candidates[slot]
                return inner.contains(candidate)
                    && !occupied.contains { $0.insetBy(dx: -margin, dy: -margin).intersects(candidate) }
                    && !dots.contains { $0.intersects(candidate) }
            }
            if let slot = chosen {
                result.placed[request.id] = candidates[slot]; result.slots[request.id] = slot
                occupied.append(candidates[slot])
            } else { result.hidden.append(request.id) }
        }
        return result
    }
}
