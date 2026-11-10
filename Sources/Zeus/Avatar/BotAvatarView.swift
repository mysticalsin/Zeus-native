import AppKit
import SwiftUI
import ZeusCore

/// Pointer and click state for one interactive avatar. The timeline redraws every frame and reads
/// these, so only `visible` publishes (it pauses the timeline while the avatar is off screen).
@MainActor
final class BotAvatarInput: ObservableObject {
    var pointer: CGPoint?
    var clickStart: Date?
    @Published var visible = true
}

/// One agent's avatar: a lit, rounded vector head that looks around, hops, spins and sleeps.
/// Drawn with Canvas at up to 30 fps; Reduce Motion shows a still pose.
struct BotAvatarView: View {
    let type: BotAvatarType
    let face: BotFace
    let state: BotAvatarState
    let size: CGFloat
    let color: Color?
    let shading: BotShading
    let accessories: BotAccessories
    let seed: Double
    let interactive: Bool
    let agentName: String?
    let lightAngle: Double
    let customPath: BotPath?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var input = BotAvatarInput()

    init(type: BotAvatarType, face: BotFace = .mouth, state: BotAvatarState = .default, size: CGFloat = 28,
         color: Color? = nil, shading: BotShading = .plastic, accessories: BotAccessories = .none,
         seed: Double = 0, interactive: Bool = false, agentName: String? = nil,
         lightAngle: Double = BotLight.defaultAngleDegrees, customPath: BotPath? = nil) {
        self.type = type
        self.face = face
        self.state = state
        self.size = size
        self.color = color
        self.shading = shading
        self.accessories = accessories
        self.seed = seed
        self.interactive = interactive
        self.agentName = agentName
        self.lightAngle = lightAngle
        self.customPath = customPath
    }

    /// The avatar for a named agent: its own shape and seed, the state from the session.
    static func forAgent(_ name: String, state: BotAvatarState, size: CGFloat = 28) -> BotAvatarView {
        BotAvatarView(type: BotAvatarSpec.type(forAgent: name), state: state, size: size,
                      seed: BotAvatarSpec.seed(forAgent: name), agentName: name)
    }

    var body: some View {
        let paused = reduceMotion || !input.visible
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            let frame = makeFrame(date: timeline.date)
            Canvas { context, canvasSize in
                var ctx = context
                BotAvatarPainter.draw(frame, in: &ctx, size: canvasSize)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard interactive else { return }
            switch phase {
            case .active(let point): input.pointer = point
            case .ended: input.pointer = nil
            }
        }
        .onTapGesture {
            if interactive, !reduceMotion { input.clickStart = Date() }
        }
        .onAppear { if !input.visible { input.visible = true } }
        .onDisappear { if input.visible { input.visible = false } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BotAvatarSpec.accessibilityLabel(agent: agentName, state: state))
        .accessibilityAddTraits(.isImage)
    }

    private func makeFrame(date: Date) -> BotAvatarFrame {
        var pose = BotTimeline.pose(state: state, time: date.timeIntervalSinceReferenceDate, seed: seed, reduceMotion: reduceMotion)
        if interactive, !reduceMotion {
            if let start = input.clickStart, let click = BotTimeline.clickPose(elapsed: date.timeIntervalSince(start), over: pose) {
                pose = click
            }
            if let pointer = input.pointer, state != .sleeping {
                let half = Double(size) / 2
                pose.lookX = min(max((Double(pointer.x) - half) / half, -1), 1)
                pose.lookY = min(max((Double(pointer.y) - half) / half, -1), 1)
            }
        }
        let spec = customPath.map { BotAvatarSpec(type: type, customPath: $0) } ?? BotAvatarSpec.spec(for: type)
        let base = color.map(BotAvatarFrame.rgb(of:)) ?? BotRGB(hex: spec.defaultColorHex)
        let light = BotLight.direction(degrees: lightAngle)
        return BotAvatarFrame(spec: spec, face: face, pose: pose, base: base,
                              shading: BotShadingParams.params(for: shading),
                              lightX: light.x, lightY: light.y, accessories: accessories,
                              bodyScale: accessories.hat == .none ? 0.78 : 0.66)
    }
}

/// Everything one frame needs, as plain Sendable values so the Canvas closure can draw it anywhere.
struct BotAvatarFrame: Sendable {
    let spec: BotAvatarSpec
    let face: BotFace
    let pose: BotPose
    let base: BotRGB
    let shading: BotShadingParams
    let lightX: Double
    let lightY: Double
    let accessories: BotAccessories
    /// How much of the canvas the body box fills; the rest is headroom for hops and hats.
    let bodyScale: Double

    static func rgb(of color: Color) -> BotRGB {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.gray
        return BotRGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }
}

private struct BotPen {
    let t: CGAffineTransform
    let k: Double

    func fill(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color) {
        ctx.fill(path.applying(t), with: .color(color))
    }

    func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ width: Double) {
        ctx.stroke(path.applying(t), with: .color(color), style: StrokeStyle(lineWidth: width * k, lineCap: .round, lineJoin: .round))
    }

    func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    func polygon(_ points: [(Double, Double)]) -> Path {
        var path = Path()
        for (index, p) in points.enumerated() {
            let point = CGPoint(x: p.0, y: p.1)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    func arc(from a: (Double, Double), control c: (Double, Double), to b: (Double, Double)) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: a.0, y: a.1))
        path.addQuadCurve(to: CGPoint(x: b.0, y: b.1), control: CGPoint(x: c.0, y: c.1))
        return path
    }
}

enum BotAvatarPainter {
    private static func color(_ rgb: BotRGB, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    private static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        color(BotRGB(hex: value), opacity)
    }

    private static func swiftUIPath(_ outline: BotPath) -> Path {
        Path { path in
            for command in outline.commands {
                switch command {
                case .move(let a): path.move(to: CGPoint(x: a.x, y: a.y))
                case .line(let a): path.addLine(to: CGPoint(x: a.x, y: a.y))
                case .quad(let c, let a): path.addQuadCurve(to: CGPoint(x: a.x, y: a.y), control: CGPoint(x: c.x, y: c.y))
                case .cubic(let c1, let c2, let a):
                    path.addCurve(to: CGPoint(x: a.x, y: a.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
                case .close: path.closeSubpath()
                }
            }
        }
    }

    static func draw(_ f: BotAvatarFrame, in ctx: inout GraphicsContext, size: CGSize) {
        let s = Double(min(size.width, size.height))
        guard s > 0 else { return }
        let k = s * f.bodyScale / 100
        let pose = f.pose
        let midX = Double(size.width) / 2
        let midY = Double(size.height) / 2
        // Body pivot is near the feet so squash and stretch stay planted; the spin turns about the middle.
        let pivotY = midY + 38 * k - pose.lift * s + pose.sink * s
        let t = CGAffineTransform.identity
            .translatedBy(x: midX, y: pivotY)
            .scaledBy(x: pose.scaleX * pose.breath * k, y: pose.scaleY * pose.breath * k)
            .translatedBy(x: 0, y: -38)
            .rotated(by: pose.rotation)
            .translatedBy(x: -50, y: -50)
        let pen = BotPen(t: t, k: k * pose.scaleX * pose.breath)
        let rgb = f.base

        // Ground shadow, fading as the body rises.
        let airborne = min(1, pose.lift * 5)
        let shadowW = 23 * k * (1 - 0.35 * airborne)
        ctx.fill(Path(ellipseIn: CGRect(x: midX - shadowW, y: midY + 44 * k - 3 * k, width: shadowW * 2, height: 6 * k)),
                 with: .color(.black.opacity(0.22 * (1 - 0.6 * airborne))))

        let body = swiftUIPath(f.spec.outline).applying(t)
        let centre = CGPoint(x: 50, y: 50).applying(t)
        let reach = s * 0.42
        let towardLight = CGPoint(x: centre.x + f.lightX * reach, y: centre.y + f.lightY * reach)
        let awayFromLight = CGPoint(x: centre.x - f.lightX * reach, y: centre.y - f.lightY * reach)
        let lit = rgb.mixed(with: .white, 0.28 * f.shading.contrast)
        let shade = rgb.mixed(with: .black, 0.38 * f.shading.contrast)

        // Plush: a soft fuzzy edge just outside the body.
        if f.shading.fuzz > 0 {
            for i in 1...3 {
                ctx.stroke(body, with: .color(color(lit, 0.14 / Double(i))), lineWidth: f.shading.fuzz * k * Double(i))
            }
        }

        if f.shading.contrast > 0 {
            let gradient = Gradient(stops: [
                .init(color: color(lit), location: 0),
                .init(color: color(rgb), location: 0.5),
                .init(color: color(shade), location: 1)
            ])
            ctx.fill(body, with: .linearGradient(gradient, startPoint: towardLight, endPoint: awayFromLight))
        } else {
            ctx.fill(body, with: .color(color(rgb)))
        }

        if f.shading.gloss > 0 || f.shading.rim > 0 {
            let everything = Path(CGRect(origin: .zero, size: size))
            ctx.drawLayer { layer in
                layer.clip(to: body)
                if f.shading.rim > 0 {
                    let rimGradient = Gradient(stops: [
                        .init(color: .white.opacity(f.shading.rim), location: 0),
                        .init(color: .white.opacity(0), location: 0.55)
                    ])
                    layer.stroke(body, with: .linearGradient(rimGradient, startPoint: towardLight, endPoint: awayFromLight),
                                 lineWidth: f.shading.rimWidth * 2 * k)
                }
                if f.shading.gloss > 0 {
                    let spot = CGPoint(x: centre.x + f.lightX * reach * 0.55, y: centre.y + f.lightY * reach * 0.55)
                    let glossGradient = Gradient(colors: [.white.opacity(f.shading.gloss), .white.opacity(0)])
                    layer.fill(everything, with: .radialGradient(glossGradient, center: spot, startRadius: 0, endRadius: reach * 0.5))
                }
            }
        }

        let bounds = f.spec.bounds
        let anchor = f.spec.faceAnchor
        let spacing = f.spec.eyeSpacing
        let ink = Color(.sRGB, red: 0.106, green: 0.122, blue: 0.165, opacity: 1)

        if f.accessories.bowTie {
            let y = bounds.maxY - 7
            let bow = hex(0xE0405A)
            pen.fill(&ctx, pen.polygon([(49, y), (36, y - 7), (36, y + 7)]), bow)
            pen.fill(&ctx, pen.polygon([(51, y), (64, y - 7), (64, y + 7)]), bow)
            pen.fill(&ctx, pen.ellipse(50, y, 3.4, 3.4), hex(0xB02F46))
        }

        if f.accessories.headphones {
            let y = anchor.y - 4
            var band = Path()
            band.move(to: CGPoint(x: bounds.minX + 2, y: y))
            band.addQuadCurve(to: CGPoint(x: bounds.maxX - 2, y: y), control: CGPoint(x: 50, y: bounds.minY - 18))
            pen.stroke(&ctx, band, hex(0x2A2F3A), 3.6)
            for x in [bounds.minX - 1, bounds.maxX + 1] {
                pen.fill(&ctx, Path(roundedRect: CGRect(x: x - 4, y: y - 8, width: 8, height: 16), cornerRadius: 3.5), hex(0x3A4150))
                pen.fill(&ctx, Path(roundedRect: CGRect(x: x - 2, y: y - 5, width: 4, height: 10), cornerRadius: 2), hex(0x9B6BFF))
            }
        }

        // Face: it slides a little with the gaze, which gives the flat shape some depth.
        let ax = anchor.x + pose.lookX * 3.5
        let ay = anchor.y + pose.lookY * 2.2
        let eyeR = 5.2
        for side in [-1.0, 1.0] {
            let ex = ax + side * spacing + pose.lookX * 1.4
            let ey = ay + pose.lookY * 1.0
            let open = 1 - pose.lid
            if pose.squint > 0.5 && pose.lid < 0.5 {
                pen.stroke(&ctx, pen.arc(from: (ex - eyeR, ey + 2), control: (ex, ey - eyeR * 1.5), to: (ex + eyeR, ey + 2)), ink, 2.4)
            } else if open < 0.15 {
                pen.stroke(&ctx, pen.arc(from: (ex - eyeR, ey), control: (ex, ey + 5), to: (ex + eyeR, ey)), ink, 2.2)
            } else {
                pen.fill(&ctx, pen.ellipse(ex, ey, eyeR, eyeR * 1.25 * open), ink)
                if open > 0.5 {
                    pen.fill(&ctx, pen.ellipse(ex + 1.6, ey - 2.3, 1.7, 1.7), .white.opacity(0.9))
                }
            }
            if f.face == .mouth {
                pen.fill(&ctx, pen.ellipse(ex + side * 3.5, ay + 8, 3.6, 2.2), Color(.sRGB, red: 1, green: 0.4, blue: 0.5, opacity: 0.22))
            }
        }
        if f.face == .mouth {
            let my = ay + 11
            if pose.mouthOpen > 0.08 {
                pen.fill(&ctx, pen.ellipse(ax, my, 4.6, 1.4 + 4.2 * pose.mouthOpen), ink)
            } else {
                pen.stroke(&ctx, pen.arc(from: (ax - 4.5, my - 1), control: (ax, my + 4), to: (ax + 4.5, my - 1)), ink, 2)
            }
        }

        switch f.accessories.glasses {
        case .none: break
        case .round, .square, .shades:
            let ey = ay + pose.lookY * 1.0
            let frameInk = hex(0x20242E)
            for side in [-1.0, 1.0] {
                let ex = ax + side * spacing + pose.lookX * 1.4
                switch f.accessories.glasses {
                case .round:
                    pen.stroke(&ctx, pen.ellipse(ex, ey, 7.6, 7.6), frameInk, 1.8)
                case .square:
                    pen.stroke(&ctx, Path(roundedRect: CGRect(x: ex - 7.5, y: ey - 6, width: 15, height: 12), cornerRadius: 2.5), frameInk, 1.8)
                default:
                    pen.fill(&ctx, Path(roundedRect: CGRect(x: ex - 8, y: ey - 5.5, width: 16, height: 11), cornerRadius: 3.5), frameInk.opacity(0.94))
                    pen.stroke(&ctx, pen.arc(from: (ex - 5, ey - 2.5), control: (ex - 3, ey - 3.5), to: (ex - 1, ey - 2.5)), .white.opacity(0.35), 1.2)
                }
            }
            pen.stroke(&ctx, pen.arc(from: (ax - spacing + 7.5, ey), control: (ax, ey - 2), to: (ax + spacing - 7.5, ey)), frameInk, 1.6)
        }

        let top = bounds.minY
        switch f.accessories.hat {
        case .none: break
        case .beanie:
            var dome = Path()
            dome.move(to: CGPoint(x: 26, y: top + 12))
            dome.addCurve(to: CGPoint(x: 74, y: top + 12), control1: CGPoint(x: 24, y: top - 16), control2: CGPoint(x: 76, y: top - 16))
            dome.closeSubpath()
            pen.fill(&ctx, dome, hex(0x3D8BFF))
            pen.fill(&ctx, Path(roundedRect: CGRect(x: 24, y: top + 9, width: 52, height: 7), cornerRadius: 3.5), hex(0x2A6BD6))
            pen.fill(&ctx, pen.ellipse(50, top - 8, 5, 5), hex(0xE9EDF2))
        case .beret:
            pen.fill(&ctx, pen.ellipse(54, top + 3, 24, 9), hex(0xC0405A))
            pen.fill(&ctx, Path(roundedRect: CGRect(x: 52, y: top - 8, width: 4, height: 6), cornerRadius: 2), hex(0xC0405A))
        case .party:
            pen.fill(&ctx, pen.polygon([(36, top + 8), (64, top + 8), (53, top - 16)]), hex(0xFF4FB8))
            pen.fill(&ctx, pen.ellipse(49, top - 2, 2.2, 2.2), hex(0xFFD84D))
            pen.fill(&ctx, pen.ellipse(56, top + 3, 2.2, 2.2), hex(0xFFD84D))
            pen.fill(&ctx, pen.ellipse(53, top - 17, 3.4, 3.4), hex(0xFFD84D))
        case .crown:
            let gold = hex(0xFFD84D)
            pen.fill(&ctx, pen.polygon([(32, top + 8), (32, top - 8), (41, top + 1), (50, top - 12), (59, top + 1), (68, top - 8), (68, top + 8)]), gold)
            pen.fill(&ctx, Path(roundedRect: CGRect(x: 32, y: top + 5, width: 36, height: 4), cornerRadius: 2), hex(0xE0A92B))
            pen.fill(&ctx, pen.ellipse(50, top - 4, 2.2, 2.2), hex(0xFF4FB8))
        }
    }
}
