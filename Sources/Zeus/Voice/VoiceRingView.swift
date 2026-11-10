import SwiftUI
import ZeusCore

/// The saved "Voice orb style" (Mascot / Ring / Mono ring). Shared and observable so the avatar
/// swaps art the moment Settings changes it.
@MainActor @Observable
final class VoiceOrbStyleStore {
    static let shared = VoiceOrbStyleStore()

    var style: VoiceOrbStyle {
        didSet {
            guard style != oldValue, !TopBarStyle.isSnapshot else { return }
            UserDefaults.standard.set(style.rawValue, forKey: VoiceOrbStyle.defaultsKey)
        }
    }

    init() {
        style = VoiceOrbStyle.resolve(UserDefaults.standard.string(forKey: VoiceOrbStyle.defaultsKey))
    }
}

/// Holds one ring's running state between frames (this toolchain has no @State, and SwiftUI
/// rebuilds the view struct freely). Keyed by `VoiceRingView.runnerID`. Locked, so it is safe
/// from any isolation a SwiftUI closure runs under.
final class VoiceRingRunner: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: VoiceRingRunner] = [:]

    static func runner(_ id: String) -> VoiceRingRunner {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let hit = registry[id] { return hit }
        let made = VoiceRingRunner()
        registry[id] = made
        return made
    }

    struct Frame: Sendable {
        let input: VoiceRingInput
        let stops: [VoiceRingRGB]
    }

    private let lock = NSLock()
    private var engine = VoiceRingEngine()
    private var lastTime: TimeInterval?
    private var pointer: VoiceRingPoint?

    func setPointer(_ point: VoiceRingPoint?) {
        lock.lock()
        pointer = point
        lock.unlock()
    }

    func frame(now: TimeInterval, state: VoiceRingState, rawLevel: Double, sensitivity: Double,
               emotion: VoiceRingEmotion?, direction: Double, hoverBend: Double,
               speed: Double, reduceMotion: Bool) -> Frame {
        lock.lock()
        defer { lock.unlock() }
        // The first frame (or a restart after a long pause) shows the state as it is, without easing in.
        if lastTime == nil || reduceMotion {
            engine = VoiceRingEngine(snappedTo: state, emotion: emotion)
        }
        let dt = lastTime.map { now - $0 } ?? 0
        lastTime = reduceMotion ? nil : now
        let hover = pointer.map { VoiceRingModel.hover(x: $0.x, y: $0.y) }
        engine.advance(dt: dt, state: state, rawLevel: rawLevel, sensitivity: sensitivity, emotion: emotion,
                       direction: direction, hover: reduceMotion ? nil : hover, hoverBend: hoverBend,
                       speed: speed, reduceMotion: reduceMotion)
        return Frame(input: engine.input(reduceMotion: reduceMotion), stops: engine.stops)
    }
}

/// A voice-reactive ring of light for voice mode: a glassy spectrum ribbon (`.ring`) or two loops of
/// grey tube a voice opens into a globe (`.mono`). Original Zeus drawing: `Canvas` under a
/// `TimelineView` capped at 30 fps. Reduce Motion draws the held state and crossfades between states.
///
/// - `level`: live 0...1 voice level, read once per frame (listening and speaking only).
/// - `direction`: -1...1 lean toward left or right.
/// - `hoverBend`: 0...1 how far a pointer near the rim bends it (idle and processing only).
/// - `paused`: freezes the frame clock (hidden orb) without dropping the view.
struct VoiceRingView: View {
    let size: CGFloat
    let state: VoiceRingState
    let level: () -> Double
    var type: VoiceRingType = .ring
    var emotion: VoiceRingEmotion? = nil
    var direction: Double = 0
    var hoverBend: Double = 1
    var sensitivity: Double = VoiceRingModel.defaultSensitivity
    var speed: Double = 1
    var paused = false
    /// Rings that stay on screen together need different ids so each keeps its own motion.
    var runnerID = "voice-ring"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let runner = VoiceRingRunner.runner(runnerID)
        Group {
            if reduceMotion {
                ZStack {
                    canvas(runner: runner, now: 0, live: false)
                        .id(state)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.3), value: state)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                    canvas(runner: runner, now: timeline.date.timeIntervalSinceReferenceDate, live: true)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let half = max(1, size / 2)
                runner.setPointer(VoiceRingPoint(x: Double((location.x - half) / half), y: Double((location.y - half) / half)))
            case .ended:
                runner.setPointer(nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(for: state))
    }

    static func label(for state: VoiceRingState) -> String {
        switch state {
        case .idle: "ZEUS voice, ready"
        case .listening: "ZEUS voice, listening"
        case .speaking: "ZEUS voice, speaking"
        case .processing: "ZEUS voice, thinking"
        }
    }

    private func canvas(runner: VoiceRingRunner, now: TimeInterval, live: Bool) -> some View {
        let frame = runner.frame(now: now, state: state, rawLevel: live ? level() : 0, sensitivity: sensitivity,
                                 emotion: emotion, direction: direction, hoverBend: hoverBend,
                                 speed: speed, reduceMotion: !live)
        let type = type
        return Canvas { context, canvasSize in
            switch type {
            case .ring: Self.drawRing(frame, size: canvasSize, into: &context)
            case .mono: Self.drawMono(frame, size: canvasSize, into: &context)
            }
        }
    }

    // MARK: Drawing

    private static func color(_ rgb: VoiceRingRGB, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    private static func polygon(_ points: [VoiceRingPoint], center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: center.x + CGFloat(point.x) * radius, y: center.y + CGFloat(point.y) * radius)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func drawRing(_ frame: VoiceRingRunner.Frame, size: CGSize, into context: inout GraphicsContext) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let samples = VoiceRingModel.ribbon(frame.input, samples: radius < 20 ? 48 : 96)
        let outer = polygon(samples.map(\.outer), center: center, radius: radius)
        let inner = polygon(samples.map(\.inner), center: center, radius: radius)
        var band = outer
        band.addPath(inner)

        var colors = frame.stops.map { color($0) }
        if let first = colors.first { colors.append(first) }
        let shading = GraphicsContext.Shading.conicGradient(Gradient(colors: colors), center: center,
                                                            angle: .radians(frame.input.time * 0.5))
        let fill = FillStyle(eoFill: true)

        // Soft bloom under the ribbon.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(1, radius * 0.09)))
            layer.opacity = 0.55
            layer.fill(band, with: shading, style: fill)
        }
        context.opacity = 0.94
        context.fill(band, with: shading, style: fill)
        context.opacity = 1

        // Glass: a bright rim on the outer edge and a faint one inside.
        context.stroke(outer, with: .color(.white.opacity(0.38)), lineWidth: max(0.6, radius * 0.012))
        context.stroke(inner, with: .color(.white.opacity(0.14)), lineWidth: max(0.5, radius * 0.008))
    }

    private static func drawMono(_ frame: VoiceRingRunner.Frame, size: CGSize, into context: inout GraphicsContext) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let tube = max(1.2, radius * 0.075)
        let base = Color(hex: 0x5A5F66)
        let light = Color(hex: 0xD8DCE2)
        let count = radius < 20 ? 48 : 96
        for loop in 0..<2 {
            let path = polygon(VoiceRingModel.monoLoop(loop, samples: count, input: frame.input), center: center, radius: radius)
            let round = StrokeStyle(lineWidth: tube, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(base), style: round)
            context.stroke(path, with: .color(light.opacity(0.7)),
                           style: StrokeStyle(lineWidth: max(0.6, tube * 0.38), lineCap: .round, lineJoin: .round))
        }
    }
}
