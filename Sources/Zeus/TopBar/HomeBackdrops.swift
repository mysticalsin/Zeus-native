import SwiftUI
import ZeusCore

/// Home's backdrop, drawn with SwiftUI Canvas (no images, no shaders to compile). It is quiet on purpose:
/// the cards above are nearly clear glass. It animates only while Home is on screen, at 20 frames a second,
/// and holds one fixed frame when Reduce Motion is on (and in snapshots).
struct HomeBackdropView: View {
    let backdrop: HomeBackdrop
    /// Home is on screen. The page sets this; a hidden Home never ticks.
    var visible = true
    var reduceMotion: Bool = Motion.reduced

    var body: some View {
        if backdrop == .off {
            Color.clear
        } else {
            let animates = HomeBackdrop.animates(backdrop, visible: visible, reduceMotion: reduceMotion) && !TopBarStyle.isSnapshot
            TickingView(interval: 1.0 / 24.0, paused: !animates) { context in
                Canvas(opaque: false, rendersAsynchronously: false) { gc, size in
                    let t = animates ? context.date.timeIntervalSinceReferenceDate : HomeBackdrop.stillTime
                    HomeBackdropPainter.draw(backdrop, in: &gc, size: size, t: t)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

/// The twelve drawings. Each takes the canvas, its size and a time in seconds; all are deterministic.
enum HomeBackdropPainter {
    static func draw(_ backdrop: HomeBackdrop, in gc: inout GraphicsContext, size: CGSize, t: Double) {
        switch backdrop {
        case .off: break
        case .aurora: aurora(&gc, size, t)
        case .flutedGlass: flutedGlass(&gc, size, t)
        case .halftone: halftone(&gc, size, t)
        case .ripple: ripple(&gc, size, t)
        case .marble: marble(&gc, size, t)
        case .watercolor: watercolor(&gc, size, t)
        case .terrazzo: terrazzo(&gc, size)
        case .sunset: sunset(&gc, size, t)
        case .caustics: caustics(&gc, size, t)
        case .cosmos: cosmos(&gc, size, t)
        case .lowPoly: lowPoly(&gc, size)
        case .matcha: matcha(&gc, size, t)
        }
    }

    // MARK: Helpers

    private static func blob(_ gc: inout GraphicsContext, _ center: CGPoint, _ radius: CGFloat, _ color: Color, _ alpha: Double = 1) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        gc.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                                              center: center, startRadius: 0, endRadius: radius))
    }

    /// A small deterministic generator, so still frames and chips never change between launches.
    private struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
    }

    private static func fillBase(_ gc: inout GraphicsContext, _ size: CGSize, _ top: Color, _ bottom: Color) {
        gc.fill(Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    // MARK: 1. Aurora: three soft ribbons of green, teal and violet drifting over a night sky.

    private static func aurora(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.03, green: 0.05, blue: 0.12), Color(red: 0.05, green: 0.09, blue: 0.16))
        let ribbons: [(Color, Double, Double, Double)] = [
            (Color(red: 0.20, green: 0.95, blue: 0.60), 0.38, 0.55, 0.0),
            (Color(red: 0.15, green: 0.75, blue: 0.95), 0.52, 0.42, 1.9),
            (Color(red: 0.62, green: 0.40, blue: 0.98), 0.62, 0.35, 3.7),
        ]
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            for (color, level, speed, phase) in ribbons {
                var top = Path()
                let steps = 24
                for i in 0...steps {
                    let x = size.width * CGFloat(i) / CGFloat(steps)
                    let u = Double(i) / Double(steps)
                    let wave = sin(u * 5.2 + t * speed * 0.6 + phase) * 0.12 + sin(u * 11 - t * speed * 0.35 + phase * 2) * 0.05
                    let y = size.height * CGFloat(level + wave)
                    i == 0 ? top.move(to: CGPoint(x: x, y: y)) : top.addLine(to: CGPoint(x: x, y: y))
                }
                var band = top
                for i in stride(from: steps, through: 0, by: -1) {
                    let u = Double(i) / Double(steps)
                    let wave = sin(u * 5.2 + t * speed * 0.6 + phase) * 0.12 + sin(u * 11 - t * speed * 0.35 + phase * 2) * 0.05
                    let y = size.height * CGFloat(level + wave) + size.height * 0.34 * CGFloat(1 + 0.3 * sin(u * 7 + t * speed + phase))
                    band.addLine(to: CGPoint(x: size.width * CGFloat(u), y: y))
                }
                band.closeSubpath()
                layer.fill(band, with: .linearGradient(Gradient(colors: [color.opacity(0.75), color.opacity(0)]),
                                                       startPoint: CGPoint(x: 0, y: size.height * CGFloat(level - 0.1)),
                                                       endPoint: CGPoint(x: 0, y: size.height * CGFloat(level + 0.4))))
            }
        }
    }

    // MARK: 2. Fluted glass: vertical flutes over two drifting colour fields.

    private static func flutedGlass(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.10, green: 0.10, blue: 0.20), Color(red: 0.07, green: 0.08, blue: 0.14))
        blob(&gc, CGPoint(x: size.width * (0.3 + 0.12 * sin(t * 0.15)), y: size.height * 0.45), size.width * 0.34, Color(red: 0.40, green: 0.50, blue: 1.0), 0.8)
        blob(&gc, CGPoint(x: size.width * (0.72 + 0.1 * cos(t * 0.12)), y: size.height * 0.6), size.width * 0.3, Color(red: 0.95, green: 0.45, blue: 0.70), 0.7)
        let width: CGFloat = 13
        var x: CGFloat = 0
        while x < size.width {
            let rect = CGRect(x: x, y: 0, width: width, height: size.height)
            gc.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.01), Color.black.opacity(0.22)]),
                                                      startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + width, y: 0)))
            gc.fill(Path(CGRect(x: x, y: 0, width: 0.7, height: size.height)), with: .color(.white.opacity(0.10)))
            x += width
        }
    }

    // MARK: 3. Halftone: a field of dots that swell and shrink in slow waves.

    private static func halftone(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.13, green: 0.09, blue: 0.10), Color(red: 0.09, green: 0.07, blue: 0.10))
        let step: CGFloat = 11
        var y: CGFloat = step / 2
        var row = 0
        while y < size.height + step {
            var x: CGFloat = (row % 2 == 0 ? 0 : step / 2) + step / 2
            while x < size.width + step {
                let u = Double(x / size.width), v = Double(y / size.height)
                let field = sin(u * 6.5 + t * 0.4) * 0.5 + sin(v * 7 - t * 0.3 + u * 2) * 0.5
                let r = step * 0.30 * CGFloat(max(0.05, 0.5 + 0.5 * field)) * CGFloat(0.5 + 0.5 * u)
                let hue = 0.02 + 0.09 * u
                gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color(hue: hue, saturation: 0.5, brightness: 0.9).opacity(0.5)))
                x += step
            }
            y += step * 0.86
            row += 1
        }
    }

    // MARK: 4. Ripple: rings spreading from two points on dark water.

    private static func ripple(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.03, green: 0.10, blue: 0.17), Color(red: 0.04, green: 0.14, blue: 0.22))
        let sources = [CGPoint(x: size.width * 0.28, y: size.height * 0.55), CGPoint(x: size.width * 0.74, y: size.height * 0.40)]
        for (index, center) in sources.enumerated() {
            for ring in 0..<7 {
                let phase = (t * 0.32 + Double(ring) / 7 + Double(index) * 0.37).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(phase) * size.width * 0.42
                let alpha = (1 - phase) * 0.55
                gc.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.62, width: r * 2, height: r * 1.24)),
                          with: .color(Color(red: 0.55, green: 0.85, blue: 1.0).opacity(alpha)), lineWidth: 1.2)
            }
        }
    }

    // MARK: 5. Marble: pale stone with slow dark veins.

    private static func marble(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.17, green: 0.17, blue: 0.22), Color(red: 0.10, green: 0.10, blue: 0.15))
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.8))
            for vein in 0..<6 {
                let path = marbleVein(vein, size: size, time: t)
                let opacity: Double = vein % 2 == 0 ? 0.40 : 0.2
                let lineWidth: CGFloat = vein % 2 == 0 ? 1.6 : 0.8
                let color = Color(red: 0.82, green: 0.82, blue: 0.95).opacity(opacity)
                layer.stroke(path, with: .color(color), lineWidth: lineWidth)
            }
        }
        blob(&gc, CGPoint(x: size.width * 0.8, y: size.height * 0.2), size.width * 0.3, .white, 0.08)
    }

    private static func marbleVein(_ vein: Int, size: CGSize, time: Double) -> Path {
        var path = Path()
        let seed: Double = Double(vein) * 1.7
        let verticalShift: Double = 0.5 * (Double(vein) / 6.0 - 0.5)
        for sample in 0...40 {
            let u: Double = Double(sample) / 40.0
            let primaryPhase: Double = u * 4.3 + seed + time * 0.05
            let secondaryPhase: Double = u * 13.0 + seed * 2.0 - time * 0.04
            let primaryWave: Double = 0.34 * sin(primaryPhase)
            let secondaryWave: Double = 0.12 * sin(secondaryPhase)
            let normalizedY: Double = 0.5 + primaryWave + secondaryWave + verticalShift
            let point = CGPoint(x: size.width * CGFloat(u), y: size.height * CGFloat(normalizedY))
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    // MARK: 6. Watercolor: overlapping washes that breathe.

    private static func watercolor(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.13, green: 0.11, blue: 0.17), Color(red: 0.10, green: 0.10, blue: 0.15))
        let washes: [(Color, Double, Double, Double)] = [
            (Color(red: 0.98, green: 0.55, blue: 0.62), 0.22, 0.45, 0.0), (Color(red: 0.45, green: 0.65, blue: 0.98), 0.50, 0.40, 1.3),
            (Color(red: 0.98, green: 0.82, blue: 0.40), 0.74, 0.55, 2.6), (Color(red: 0.62, green: 0.50, blue: 0.95), 0.90, 0.35, 4.1),
        ]
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 16))
            for (color, x, y, phase) in washes {
                let breathe = 1 + 0.12 * sin(t * 0.35 + phase)
                let center = CGPoint(x: size.width * CGFloat(x + 0.03 * sin(t * 0.2 + phase)), y: size.height * CGFloat(y + 0.06 * cos(t * 0.25 + phase)))
                blob(&layer, center, size.height * 0.95 * CGFloat(breathe), color, 0.5)
            }
        }
    }

    // MARK: 7. Terrazzo: stone chips scattered on plaster (still).

    private static func terrazzo(_ gc: inout GraphicsContext, _ size: CGSize) {
        fillBase(&gc, size, Color(red: 0.19, green: 0.18, blue: 0.20), Color(red: 0.15, green: 0.14, blue: 0.17))
        var rng = Seeded(state: 7)
        let palette: [Color] = [Color(red: 0.84, green: 0.38, blue: 0.30), Color(red: 0.20, green: 0.40, blue: 0.45), Color(red: 0.95, green: 0.72, blue: 0.30),
                                Color(red: 0.25, green: 0.25, blue: 0.30), Color(red: 0.62, green: 0.70, blue: 0.55), Color(red: 0.93, green: 0.60, blue: 0.62)]
        for _ in 0..<(Int(size.width * size.height / 520)) {
            let cx = rng.next() * size.width, cy = rng.next() * size.height
            let r = 2 + rng.next() * 6
            var path = Path()
            let points = 5 + Int(rng.next() * 2)
            let spin = rng.next() * .pi
            for k in 0..<points {
                let angle = spin + Double(k) / Double(points) * 2 * .pi
                let rr = r * (0.6 + 0.5 * rng.next())
                let point = CGPoint(x: cx + cos(angle) * rr, y: cy + sin(angle) * rr)
                k == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            gc.fill(path, with: .color(palette[Int(rng.next() * Double(palette.count)) % palette.count].opacity(0.6)))
        }
    }

    // MARK: 8. Sunset: a low sun over banded sky with drifting cloud.

    private static func sunset(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: Color(red: 0.16, green: 0.12, blue: 0.38), location: 0), .init(color: Color(red: 0.62, green: 0.22, blue: 0.52), location: 0.45),
                             .init(color: Color(red: 0.98, green: 0.45, blue: 0.32), location: 0.75), .init(color: Color(red: 1.0, green: 0.72, blue: 0.42), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let sun = CGPoint(x: size.width * 0.62, y: size.height * (1.0 + 0.02 * sin(t * 0.2)))  // the sun sits on the horizon: below the cards' text, never over it
        blob(&gc, sun, size.height * 1.2, Color(red: 1.0, green: 0.62, blue: 0.35), 0.4)
        gc.fill(Path(ellipseIn: CGRect(x: sun.x - 17, y: sun.y - 17, width: 34, height: 34)), with: .color(Color(red: 1.0, green: 0.90, blue: 0.62).opacity(0.7)))
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            for i in 0..<4 {
                let drift = (t * (6 + Double(i) * 2.5) + Double(i) * 160).truncatingRemainder(dividingBy: Double(size.width + 240)) - 120
                let y = size.height * (0.2 + 0.16 * Double(i))
                layer.fill(Path(roundedRect: CGRect(x: drift, y: y, width: 130 + Double(i) * 30, height: 7), cornerRadius: 3.5),
                           with: .color(Color(red: 1.0, green: 0.78, blue: 0.7).opacity(0.28)))
            }
        }
    }

    // MARK: 9. Caustics: light netting on the floor of a pool.

    private static func caustics(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.05, green: 0.38, blue: 0.52), Color(red: 0.03, green: 0.25, blue: 0.42))
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.6))
            layer.blendMode = .plusLighter
            for layerIndex in 0..<2 {
                for k in 0..<9 {
                    let path = causticLine(k, layerIndex: layerIndex, size: size, time: t)
                    let color = Color(red: 0.7, green: 1.0, blue: 0.95).opacity(0.17)
                    layer.stroke(path, with: .color(color), lineWidth: 1.4)
                }
            }
        }
    }

    private static func causticLine(_ index: Int, layerIndex: Int, size: CGSize, time: Double) -> Path {
        var path = Path()
        let scale: Double = layerIndex == 0 ? 1.0 : 1.7
        let direction: Double = layerIndex == 0 ? 1.0 : -1.0
        let row: Double = Double(index) / 9.0
        for sample in 0...48 {
            let u: Double = Double(sample) / 48.0
            let primaryPhase: Double = u * 9.0 * scale + time * 0.7 * direction + row * 11.0
            let secondaryPhase: Double = u * 4.5 * scale - time * 0.5 * direction + row * 5.0
            let primaryWave: Double = sin(primaryPhase) * 0.045
            let secondaryWave: Double = sin(secondaryPhase) * 0.06
            let wobble: Double = primaryWave + secondaryWave
            let normalizedY: Double = row * 1.1 - 0.05 + wobble
            let point = CGPoint(x: size.width * CGFloat(u), y: size.height * CGFloat(normalizedY))
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    // MARK: 10. Cosmos: a dark sky, twinkling stars and two nebulae.

    private static func cosmos(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.02, green: 0.02, blue: 0.07), Color(red: 0.05, green: 0.03, blue: 0.12))
        blob(&gc, CGPoint(x: size.width * (0.25 + 0.03 * sin(t * 0.1)), y: size.height * 0.4), size.width * 0.28, Color(red: 0.45, green: 0.25, blue: 0.85), 0.55)
        blob(&gc, CGPoint(x: size.width * (0.78 + 0.03 * cos(t * 0.08)), y: size.height * 0.65), size.width * 0.24, Color(red: 0.20, green: 0.40, blue: 0.95), 0.5)
        var rng = Seeded(state: 11)
        for _ in 0..<150 {
            let x = rng.next() * size.width, y = rng.next() * size.height
            let size0 = 0.5 + rng.next() * 1.3
            let twinkle = 0.55 + 0.45 * sin(t * (0.6 + rng.next() * 1.6) + rng.next() * 6.28)
            gc.fill(Path(ellipseIn: CGRect(x: x, y: y, width: size0, height: size0)), with: .color(.white.opacity(0.35 + 0.6 * twinkle * rng.next())))
        }
    }

    // MARK: 11. Low-poly: a jittered triangle mesh in teal and indigo (still).

    private static func lowPoly(_ gc: inout GraphicsContext, _ size: CGSize) {
        fillBase(&gc, size, Color(red: 0.10, green: 0.14, blue: 0.30), Color(red: 0.06, green: 0.10, blue: 0.22))
        var rng = Seeded(state: 23)
        let cols = 14, rows = 5
        let cw = size.width / CGFloat(cols - 1), rh = size.height / CGFloat(rows - 1)
        var grid: [[CGPoint]] = []
        for r in 0..<rows {
            grid.append((0..<cols).map { c in
                let edgeX = c == 0 || c == cols - 1, edgeY = r == 0 || r == rows - 1
                return CGPoint(x: CGFloat(c) * cw + (edgeX ? 0 : (rng.next() - 0.5) * cw * 0.7),
                               y: CGFloat(r) * rh + (edgeY ? 0 : (rng.next() - 0.5) * rh * 0.7))
            })
        }
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let a = grid[r][c], b = grid[r][c + 1], d = grid[r + 1][c], e = grid[r + 1][c + 1]
                for tri in [[a, b, d], [b, e, d]] {
                    var path = Path()
                    path.move(to: tri[0]); path.addLine(to: tri[1]); path.addLine(to: tri[2]); path.closeSubpath()
                    let u = Double(tri[0].x / size.width)
                    let shade = 0.35 + 0.5 * u + (rng.next() - 0.5) * 0.25
                    gc.fill(path, with: .color(Color(hue: 0.52 + 0.12 * (1 - u), saturation: 0.55, brightness: min(0.9, max(0.25, shade)))))
                    gc.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: 12. Matcha: whisked green with a slow swirl and fine foam.

    private static func matcha(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        fillBase(&gc, size, Color(red: 0.36, green: 0.52, blue: 0.27), Color(red: 0.26, green: 0.40, blue: 0.20))
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 12))
            for i in 0..<5 {
                let a = t * 0.12 + Double(i) * 1.26
                blob(&layer, CGPoint(x: size.width * CGFloat(0.5 + 0.34 * cos(a)), y: size.height * CGFloat(0.5 + 0.38 * sin(a * 1.3))),
                     size.height * 0.8, i % 2 == 0 ? Color(red: 0.62, green: 0.78, blue: 0.40) : Color(red: 0.18, green: 0.30, blue: 0.14), 0.6)
            }
        }
        var rng = Seeded(state: 31)
        for _ in 0..<70 {
            let x = rng.next() * size.width, y = rng.next() * size.height, r = 0.8 + rng.next() * 2.2
            let drift = sin(t * 0.3 + rng.next() * 6.28) * 2
            gc.fill(Path(ellipseIn: CGRect(x: x + drift, y: y, width: r * 2, height: r * 2)), with: .color(Color(red: 0.85, green: 0.95, blue: 0.70).opacity(0.18 + 0.2 * rng.next())))
        }
    }
}
