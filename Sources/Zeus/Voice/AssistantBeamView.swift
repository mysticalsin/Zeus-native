import SwiftUI
import ZeusCore

/// Paints only the supplied deterministic frame. The owning surface supplies its own timeline.
/// Bottom inner light, a taller bloom, an edge ring and a chromatic bell contour adapt VoiceBeam
/// to Zeus's native palette. No audio capture, shared driver or SVG displacement is used.
struct AssistantBeamView: View {
    let frame: AssistantBeam.Frame
    var reduceTransparency = false
    var cornerRadius: CGFloat = 24
    var colors: [Color] = []

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = colors.isEmpty
            ? [Theme.danger, Theme.sky, Theme.accent, Theme.leaf, Theme.ember, Theme.glow, Color(hex: 0x28C8BE)]
            : Array(colors.prefix(7))
        Canvas { context, size in
            let geometry = frame.geometry(width: size.width, height: size.height, cornerRadius: cornerRadius)
            guard geometry.scale > 0 else { return }
            let bounds = CGRect(origin: .zero, size: CGSize(width: geometry.width, height: geometry.height))
            let shape = Path(roundedRect: bounds, cornerRadius: geometry.cornerRadius)
            context.clip(to: shape)
            if reduceTransparency {
                // Opaque, unblurred state mark: no material, bloom or translucent wash.
                let y = max(0, geometry.height - max(1, 2 * geometry.scale))
                context.fill(Path(CGRect(x: 0, y: y, width: geometry.width, height: geometry.height - y)),
                             with: .color(Theme.glow))
            } else {
                paintLobes(context: &context, geometry: geometry, palette: palette, bloom: false)
                context.drawLayer { bloom in
                    bloom.addFilter(.blur(radius: 10 * geometry.scale))
                    paintLobes(context: &bloom, geometry: geometry, palette: palette, bloom: true)
                }
                let edge = max(0.6, geometry.scale)
                if bounds.width > edge * 2, bounds.height > edge * 2 {
                    var ring = shape
                    ring.addPath(Path(roundedRect: bounds.insetBy(dx: edge, dy: edge),
                                      cornerRadius: max(0, geometry.cornerRadius - edge)))
                    context.drawLayer { stroke in
                        stroke.clip(to: ring, style: FillStyle(eoFill: true))
                        paintLobes(context: &stroke, geometry: geometry, palette: palette, bloom: true)
                    }
                }
                paintBand(context: &context, geometry: geometry)
            }
        }
        .hueRotation(.degrees(reduceTransparency ? 0 : frame.hueDegrees))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func paintLobes(context: inout GraphicsContext, geometry: AssistantBeam.Geometry,
                           palette: [Color], bloom: Bool) {
        guard !palette.isEmpty else { return }
        let dark = scheme == .dark
        let opacity = geometry.glowOpacity * (bloom ? (dark ? 0.80 : 0.44) : (dark ? 0.36 : 0.55))
        for lobe in geometry.lobes {
            let radiusX = lobe.radiusX * (bloom ? 1.15 : 0.9)
            let radiusY = lobe.radiusY * (bloom ? 1.5 : 0.9)
            guard radiusX > 0.01, radiusY > 0.01 else { continue }
            let color = palette[lobe.colorIndex % palette.count]
            let gradient = Gradient(stops: [
                .init(color: color.opacity(opacity), location: 0),
                .init(color: color.opacity(opacity * 0.45), location: 0.42),
                .init(color: color.opacity(0), location: 0.75),
            ])
            var layer = context
            layer.translateBy(x: lobe.center.x, y: lobe.center.y)
            layer.scaleBy(x: radiusX, y: radiusY)
            layer.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                       with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
        }
    }

    private func paintBand(context: inout GraphicsContext, geometry: AssistantBeam.Geometry) {
        guard let first = geometry.band.first, let last = geometry.band.last, geometry.bandOpacity > 0 else { return }
        let start = CGPoint(x: first.x, y: 0)
        let end = CGPoint(x: last.x, y: 0)
        func shading(_ color: Color, opacity: Double) -> GraphicsContext.Shading {
            .linearGradient(Gradient(stops: [
                .init(color: color.opacity(0), location: 0),
                .init(color: color.opacity(opacity), location: 0.12),
                .init(color: color.opacity(opacity), location: 0.88),
                .init(color: color.opacity(0), location: 1),
            ]), startPoint: start, endPoint: end)
        }
        func path(x: Double = 0, y: Double = 0) -> Path {
            var line = Path()
            line.move(to: CGPoint(x: first.x + x, y: first.y + y))
            for point in geometry.band.dropFirst() { line.addLine(to: CGPoint(x: point.x + x, y: point.y + y)) }
            return line
        }
        let core = scheme == .dark ? Theme.cloudPrimary : Theme.glow
        let width = 14 * geometry.bandWidth
        let corePath = path()
        context.drawLayer { halo in
            halo.addFilter(.blur(radius: 9 * geometry.scale))
            halo.stroke(corePath, with: shading(core, opacity: geometry.bandOpacity * 0.13),
                        style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round, lineJoin: .round))
        }
        let fringes: [(Color, Double, Double, Double)] = [
            (Theme.danger, geometry.fringeX, -geometry.fringeY, 1),
            (Theme.leaf, geometry.fringeX * 0.35, -geometry.fringeY * 0.35, 0.55),
            (Theme.sky, -geometry.fringeX, geometry.fringeY, 1),
            (core, 0, 0, 0.9),
        ]
        context.drawLayer { ridge in
            ridge.addFilter(.blur(radius: 3.5 * geometry.bandWidth / 2))
            for (color, x, y, alpha) in fringes {
                let fringePath = path(x: x, y: y)
                for (size, weight) in [(1.0, 0.16), (0.72, 0.20), (0.46, 0.26), (0.22, 0.34)] {
                    ridge.stroke(fringePath,
                        with: shading(color, opacity: geometry.bandOpacity * 0.42 * alpha * weight),
                        style: StrokeStyle(lineWidth: max(0.6, width * size), lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
