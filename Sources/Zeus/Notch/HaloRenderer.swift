import SwiftUI
import AppKit
import ZeusCore

/// An outline flattened to points, so styles can place rays, dots and pixels along it by arc length.
struct Polyline {
    var points: [CGPoint]
    var cumulative: [CGFloat]
    /// Distance of this slice's start along the whole outline: rays and dots stay put while the lit part grows.
    var origin: CGFloat = 0
    var length: CGFloat { cumulative.last ?? 0 }
    var isEmpty: Bool { points.count < 2 || length <= 0 }

    init(points: [CGPoint], origin: CGFloat = 0) {
        self.points = points
        self.origin = origin
        var sum: CGFloat = 0
        cumulative = points.indices.map { i in
            if i > 0 { sum += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
            return sum
        }
    }

    init(path: Path) {
        var pts: [CGPoint] = []
        var current = CGPoint.zero
        path.forEach { (element: Path.Element) in
            switch element {
            case .move(let p): pts.append(p); current = p
            case .line(let p): pts.append(p); current = p
            case .quadCurve(let p, let c):
                for i in 1...8 {
                    let t = CGFloat(i) / 8
                    pts.append(Self.quadraticPoint(from: current, control: c, to: p, at: t))
                }
                current = p
            case .curve(let p, let c1, let c2):
                for i in 1...10 {
                    let t = CGFloat(i) / 10
                    pts.append(Self.cubicPoint(from: current, control1: c1, control2: c2, to: p, at: t))
                }
                current = p
            case .closeSubpath: break
            }
        }
        self.init(points: pts)
    }

    // Explicit scalar types keep SwiftUI's CGFloat/Double overloads out of the path visitor.
    private static func quadraticPoint(from start: CGPoint, control: CGPoint, to end: CGPoint, at t: CGFloat) -> CGPoint {
        let u: CGFloat = 1 - t
        let a: CGFloat = u * u
        let b: CGFloat = 2 * u * t
        let c: CGFloat = t * t
        let x: CGFloat = a * start.x + b * control.x + c * end.x
        let y: CGFloat = a * start.y + b * control.y + c * end.y
        return CGPoint(x: x, y: y)
    }

    private static func cubicPoint(from start: CGPoint, control1: CGPoint, control2: CGPoint, to end: CGPoint, at t: CGFloat) -> CGPoint {
        let u: CGFloat = 1 - t
        let a: CGFloat = u * u * u
        let b: CGFloat = 3 * u * u * t
        let c: CGFloat = 3 * u * t * t
        let d: CGFloat = t * t * t
        let firstX: CGFloat = a * start.x + b * control1.x
        let firstY: CGFloat = a * start.y + b * control1.y
        let x: CGFloat = (firstX + c * control2.x) + d * end.x
        let y: CGFloat = (firstY + c * control2.y) + d * end.y
        return CGPoint(x: x, y: y)
    }

    /// The part from fraction `a` to `b` of this polyline's length.
    func slice(from a: Double, to b: Double) -> Polyline {
        let da = CGFloat(max(0, min(1, a))) * length, db = CGFloat(max(0, min(1, b))) * length
        guard db > da, points.count > 1 else { return Polyline(points: [], origin: origin) }
        var out = [point(at: da).0]
        for i in points.indices where cumulative[i] > da && cumulative[i] < db { out.append(points[i]) }
        out.append(point(at: db).0)
        return Polyline(points: out, origin: origin + da)
    }

    func point(at d: CGFloat) -> (CGPoint, CGVector) {
        guard points.count > 1 else { return (points.first ?? .zero, CGVector(dx: 1, dy: 0)) }
        var i = 1
        while i < points.count - 1, cumulative[i] < d { i += 1 }
        let a = points[i - 1], b = points[i]
        let seg = max(cumulative[i] - cumulative[i - 1], 0.0001)
        let f = max(0, min(1, (d - cumulative[i - 1]) / seg))
        return (CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), CGVector(dx: (b.x - a.x) / seg, dy: (b.y - a.y) / seg))
    }

    /// Points every `step`, at absolute positions k * step along the whole outline.
    func samples(every step: CGFloat) -> [(point: CGPoint, tangent: CGVector, index: Int, arc: CGFloat)] {
        guard !isEmpty, step > 0 else { return [] }
        let first = Int((origin / step).rounded(.up)), last = Int(((origin + length) / step).rounded(.down))
        guard last >= first else { return [] }
        return (first...last).map { k in
            let arc = CGFloat(k) * step
            let (p, t) = point(at: arc - origin)
            return (p, t, k, arc)
        }
    }

    var path: Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for q in points.dropFirst() { p.addLine(to: q) }
        }
    }

    /// The outline pushed sideways by `distance(arc)` along its normal.
    func offset(sign: CGFloat, _ distance: (CGFloat) -> CGFloat) -> Path {
        Path { p in
            for (i, pt) in points.enumerated() {
                let (_, t) = point(at: cumulative[i])
                let n = HaloRenderer.normal(t, sign: sign), d = distance(origin + cumulative[i])
                let q = CGPoint(x: pt.x + n.dx * d, y: pt.y + n.dy * d)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
        }
    }
}

/// How one lit stretch is painted.
struct HaloPaint {
    var color: Color
    var opacity: Double = 1
    /// 0...1 toward white (a bright wallpaper, or an entrance's flash).
    var white: Double = 0
    /// Turns of hue shifted from `color` (the hue-slide entrance).
    var hueShift: Double = 0
    /// Core line width in points at scale 1.
    var line: CGFloat = 1.6
    var bloom: CGFloat = 1
    /// Points per design point: 1 in the notch, smaller in the Settings and welcome previews.
    var scale: CGFloat = 1
    var time: Double = 0.35
    var reduceMotion = false
    /// +1 when the outline's right-hand side faces away from the notch (left arm drawn as a shape, mirrored for the right).
    var normalSign: CGFloat = 1
}

/// One renderer for every halo: the live notch, the Settings cards and the welcome guide all call this.
enum HaloRenderer {
    static func normal(_ t: CGVector, sign: CGFloat) -> CGVector {
        sign > 0 ? CGVector(dx: t.dy, dy: -t.dx) : CGVector(dx: -t.dy, dy: t.dx)
    }

    static func rnd(_ k: Int, _ salt: Double = 0) -> CGFloat {
        let x = sin(Double(k) * 12.9898 + salt * 78.233) * 43758.5453
        return CGFloat(x - x.rounded(.down))
    }

    /// Colour with a shift in hue and a blend toward white.
    static func tinted(_ color: Color, white: Double = 0, hue: Double = 0) -> Color {
        guard white > 0.001 || abs(hue) > 0.001, let ns = NSColor(color).usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var shifted = (h + CGFloat(hue)).truncatingRemainder(dividingBy: 1)
        if shifted < 0 { shifted += 1 }
        let base = NSColor(hue: shifted, saturation: s, brightness: b, alpha: a).usingColorSpace(.sRGB) ?? ns
        let w = CGFloat(max(0, min(1, white)))
        return Color(.sRGB, red: base.redComponent + (1 - base.redComponent) * w, green: base.greenComponent + (1 - base.greenComponent) * w,
                     blue: base.blueComponent + (1 - base.blueComponent) * w, opacity: Double(a))
    }

    /// Draws `line` (already sliced to the lit part) in `style`.
    static func draw(_ style: HaloStyle, line poly: Polyline, in ctx: inout GraphicsContext, paint: HaloPaint) {
        guard style.renderer != .none, !poly.isEmpty, paint.opacity > 0.005 else { return }
        let u = paint.scale
        let lw = paint.line * u
        let o = paint.opacity
        let t = paint.reduceMotion ? 0.35 : paint.time
        let base = tinted(paint.color, white: paint.white, hue: paint.hueShift)
        let path = poly.path

        switch style.renderer {
        case .none: return
        case .line:
            glow(&ctx, path, base, o, lw, bloom: paint.bloom, u: u)
            ctx.stroke(path, with: .color(tinted(base, white: 0.3).opacity(o)), style: .init(lineWidth: lw, lineCap: .round, lineJoin: .round))

        case .storm:
            let bolt = tinted(Theme.bolt, white: paint.white)
            glow(&ctx, path, bolt, o * 0.45, lw, bloom: paint.bloom * 2, u: u, spread: 1.6)
            glow(&ctx, path, base, o, lw, bloom: paint.bloom, u: u)
            ctx.stroke(path, with: .color(tinted(base, white: 0.3).opacity(o)), style: .init(lineWidth: lw, lineCap: .round, lineJoin: .round))
            let flash = paint.reduceMotion ? 0 : pow(max(0, sin(t * 3.7)), 24)
            if flash > 0.02 {
                let jag = poly.offset(sign: paint.normalSign) { arc in (rnd(Int(arc / (3 * u))) - 0.5) * 7 * u }
                ctx.stroke(jag, with: .color(bolt.opacity(o * flash)), style: .init(lineWidth: lw * 0.8, lineCap: .round, lineJoin: .bevel))
            }

        case .aurora:
            let chunks = poly.samples(every: 6 * u)
            var glowLayer = ctx
            glowLayer.addFilter(.blur(radius: 9 * paint.bloom * u))
            glowLayer.opacity = o * 0.6
            for (a, b) in zip(chunks, chunks.dropFirst()) {
                let c = Color(hue: Double((t / 9 + Double(a.arc) / 420).truncatingRemainder(dividingBy: 1)), saturation: 0.55, brightness: 1)
                let seg = Path { $0.move(to: a.point); $0.addLine(to: b.point) }
                glowLayer.stroke(seg, with: .color(tinted(c, white: paint.white)), style: .init(lineWidth: lw * 4, lineCap: .round))
                ctx.stroke(seg, with: .color(tinted(c, white: paint.white + 0.15).opacity(o)), style: .init(lineWidth: lw, lineCap: .round))
            }

        case .rays:
            glow(&ctx, path, base, o * 0.7, lw, bloom: 0.7 * paint.bloom, u: u)
            ctx.stroke(path, with: .color(tinted(base, white: 0.35).opacity(o)), style: .init(lineWidth: lw * 0.8, lineCap: .round))
            let rays = poly.samples(every: 4.5 * u)
            for (reach, alpha) in [(1.0, 0.2), (0.66, 0.28), (0.34, 0.4)] {
                var p = Path()
                for r in rays {
                    let twinkle = 0.85 + 0.15 * sin(t * 2 + Double(r.index) * 1.7)
                    let length = (5 + 15 * rnd(r.index)) * u * CGFloat(twinkle * reach)
                    let n = normal(r.tangent, sign: paint.normalSign)
                    p.move(to: r.point)
                    p.addLine(to: CGPoint(x: r.point.x + n.dx * length, y: r.point.y + n.dy * length))
                }
                ctx.stroke(p, with: .color(tinted(base, white: 0.3).opacity(o * alpha)), style: .init(lineWidth: max(0.5, 0.55 * lw), lineCap: .round))
            }

        case .prism:
            // Light split into its colours: red, green and blue lines that part toward the arm tip and add back to white.
            let total = max(poly.origin + poly.length, 1)
            var layer = ctx
            layer.blendMode = .plusLighter
            let channels: [(Color, CGFloat)] = [(Color(red: 1, green: 0.18, blue: 0.1), -1), (Color(red: 0.12, green: 1, blue: 0.3), 0), (Color(red: 0.15, green: 0.35, blue: 1), 1)]
            for (color, side) in channels {
                let shifted = tinted(color, white: paint.white * 0.6)
                let spread = poly.offset(sign: paint.normalSign) { arc in side * (1.0 + 2.6 * (arc / total)) * u * (paint.line / 1.6) }
                var soft = layer
                soft.addFilter(.blur(radius: 5 * paint.bloom * u))
                soft.stroke(spread, with: .color(shifted.opacity(o * 0.5)), style: .init(lineWidth: lw * 3, lineCap: .round))
                layer.stroke(spread, with: .color(shifted.opacity(o)), style: .init(lineWidth: lw * 0.9, lineCap: .round, lineJoin: .round))
            }
            // A slow sweep of spectrum riding along the line.
            let phase = (t / 6).truncatingRemainder(dividingBy: 1)
            for r in poly.samples(every: 9 * u) {
                let hue = (Double(r.arc) / 260 + phase).truncatingRemainder(dividingBy: 1)
                let dot = Path(ellipseIn: CGRect(x: r.point.x - 1.1 * u, y: r.point.y - 1.1 * u, width: 2.2 * u, height: 2.2 * u))
                layer.fill(dot, with: .color(Color(hue: hue, saturation: 0.6, brightness: 1).opacity(o * 0.7)))
            }

        case .cloud:
            let haze = tinted(base, white: 0.45)
            var puffs = ctx
            puffs.addFilter(.blur(radius: 7 * paint.bloom * u))
            puffs.opacity = o
            for r in poly.samples(every: 8 * u) {
                let drift = 0.6 + 0.4 * sin(t * 0.7 + Double(r.index) * 0.9)
                let radius = (8 + 11 * rnd(r.index, 1)) * u * CGFloat(0.8 + 0.2 * drift) * (paint.line / 1.6)
                let n = normal(r.tangent, sign: paint.normalSign)
                let off = (rnd(r.index, 2) - 0.3) * 7 * u
                let c = CGPoint(x: r.point.x + n.dx * off, y: r.point.y + n.dy * off)
                puffs.fill(Path(ellipseIn: CGRect(x: c.x - radius * 1.25, y: c.y - radius * 0.85, width: radius * 2.5, height: radius * 1.7)),
                           with: .color(haze.opacity(0.34 * drift + 0.1)))
            }
            ctx.stroke(path, with: .color(tinted(base, white: 0.55).opacity(o * 0.4)), style: .init(lineWidth: lw * 0.8, lineCap: .round))

        case .core:
            // A white-hot core and a long, smooth fall-off.
            let warm = tinted(base, white: 0.15)
            for (w, a, b) in [(11.0, 0.07, 9.0), (6.0, 0.14, 5.0), (3.4, 0.28, 2.5), (2.0, 0.5, 1.0)] {
                var layer = ctx
                layer.addFilter(.blur(radius: CGFloat(b) * paint.bloom * u))
                layer.stroke(path, with: .color(warm.opacity(o * a)), style: .init(lineWidth: lw * CGFloat(w), lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(path, with: .color(Color.white.opacity(o)), style: .init(lineWidth: lw * 0.85, lineCap: .round, lineJoin: .round))

        case .grid:
            // Real pixels: the outline snapped to a square grid, with a dimmer ring of cells outside it.
            let cell = max(2, 3 * u * (paint.line / 1.6))
            let step = cell * 0.6
            let tick = floor(t * 4)
            var cells: [Int: (CGPoint, CGFloat)] = [:]
            func key(_ x: Int, _ y: Int) -> Int { x &* 73856093 ^ y &* 19349663 }
            for r in poly.samples(every: step) {
                let gx = Int((r.point.x / cell).rounded(.down)), gy = Int((r.point.y / cell).rounded(.down))
                let n = normal(r.tangent, sign: paint.normalSign)
                let sx = n.dx.rounded(), sy = n.dy.rounded()
                for (ring, level) in [(0, 1.0), (1, 0.42), (2, 0.16)] {
                    let cx = gx + Int(sx) * ring, cy = gy + Int(sy) * ring
                    let k = key(cx, cy)
                    if let existing = cells[k], existing.1 >= CGFloat(level) { continue }
                    cells[k] = (CGPoint(x: CGFloat(cx) * cell, y: CGFloat(cy) * cell), CGFloat(level))
                }
            }
            for band in [(1.0, 1.0), (0.42, 0.5), (0.16, 0.22)] {
                var p = Path()
                for (k, cellInfo) in cells where abs(cellInfo.1 - CGFloat(band.0)) < 0.001 {
                    let flicker = paint.reduceMotion ? 1 : 0.7 + 0.3 * rnd(k, tick)
                    if flicker < 0.78 && band.0 < 1 { continue }
                    p.addRect(CGRect(x: cellInfo.0.x + 0.25 * u, y: cellInfo.0.y + 0.25 * u, width: cell - 0.5 * u, height: cell - 0.5 * u))
                }
                ctx.fill(p, with: .color((band.0 == 1 ? tinted(base, white: 0.35) : base).opacity(o * band.1)))
            }

        case .depth:
            // Beams that fan away from the line, each fading with distance.
            glow(&ctx, path, base, o, lw, bloom: 2.2 * paint.bloom, u: u, spread: 1.5)
            var beams = ctx
            beams.addFilter(.blur(radius: 1.6 * u))
            for r in poly.samples(every: 12 * u) {
                let n = normal(r.tangent, sign: paint.normalSign)
                let length = (26 + 28 * rnd(r.index, 3)) * u
                let spread = (2 + 5 * rnd(r.index, 4)) * u
                let tip = CGPoint(x: r.point.x + n.dx * length, y: r.point.y + n.dy * length)
                let shimmer = 0.8 + 0.2 * sin(t * 1.3 + Double(r.index))
                var wedge = Path()
                wedge.move(to: CGPoint(x: r.point.x - r.tangent.dx * 1.2 * u, y: r.point.y - r.tangent.dy * 1.2 * u))
                wedge.addLine(to: CGPoint(x: tip.x - r.tangent.dx * spread, y: tip.y - r.tangent.dy * spread))
                wedge.addLine(to: CGPoint(x: tip.x + r.tangent.dx * spread, y: tip.y + r.tangent.dy * spread))
                wedge.addLine(to: CGPoint(x: r.point.x + r.tangent.dx * 1.2 * u, y: r.point.y + r.tangent.dy * 1.2 * u))
                wedge.closeSubpath()
                beams.fill(wedge, with: .linearGradient(Gradient(colors: [tinted(base, white: 0.35).opacity(o * 0.42 * shimmer), base.opacity(0)]),
                                                        startPoint: r.point, endPoint: tip))
            }
            ctx.stroke(path, with: .color(tinted(base, white: 0.45).opacity(o)), style: .init(lineWidth: lw, lineCap: .round))

        case .dots:
            // A string of small lights over a faint core.
            let hue = 0.47 + 0.05 * sin(t / 2)
            let bio = tinted(Color(hue: hue, saturation: 0.7, brightness: 1), white: paint.white, hue: paint.hueShift)
            ctx.stroke(path, with: .color(bio.opacity(o * 0.22)), style: .init(lineWidth: lw * 0.5, lineCap: .round))
            var halo = ctx
            halo.addFilter(.blur(radius: 3.5 * paint.bloom * u))
            let dots = poly.samples(every: 5.5 * u)
            for r in dots {
                let pulse = 0.5 + 0.5 * sin(t * 2.4 - Double(r.index) * 0.45)
                let radius = (1.0 + 1.0 * pulse) * u * (paint.line / 1.6)
                let rect = CGRect(x: r.point.x - radius, y: r.point.y - radius, width: radius * 2, height: radius * 2)
                halo.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)), with: .color(bio.opacity(o * 0.5 * (0.4 + 0.6 * pulse))))
                ctx.fill(Path(ellipseIn: rect), with: .color(tinted(bio, white: 0.3).opacity(o * (0.45 + 0.55 * pulse))))
            }
        }
    }

    /// A soft bloom under the core line.
    private static func glow(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ opacity: Double, _ lw: CGFloat, bloom: CGFloat, u: CGFloat, spread: CGFloat = 1) {
        var wide = ctx
        wide.addFilter(.blur(radius: 11 * bloom * u))
        wide.stroke(path, with: .color(color.opacity(opacity * 0.5)), style: .init(lineWidth: lw * 5 * spread, lineCap: .round, lineJoin: .round))
        var tight = ctx
        tight.addFilter(.blur(radius: 3.2 * bloom * u))
        tight.stroke(path, with: .color(color.opacity(opacity * 0.8)), style: .init(lineWidth: lw * 2.2 * spread, lineCap: .round, lineJoin: .round))
    }
}
