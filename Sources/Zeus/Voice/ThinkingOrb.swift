import SwiftUI
import ZeusCore

/// The Murmure pill's orb, replacing the plain red record dot (P0 item F, QA7 -- Tony: "maybe an
/// orb animation instead of the red dot"). Geometry is `ThinkingOrbMath` (loosely ported from
/// thinking-orbs 0.3.2, MIT, Jakub Antalik -- see `Resources/NOTICES.txt`); this view only paints
/// it. `Canvas` driven by `TickingView`, never `TimelineView` -- the perf rule in PLAN-QA7.md
/// section 0.5 wins even for a small, non-notch panel like this one. Under Reduce Motion it falls
/// back to a soft, slow opacity pulse instead of the dotted sphere.
struct ThinkingOrbView: View {
    enum Mode: Equatable {
        /// `level` is the live mic level, 0 (silence) ... 1 (loud).
        case listening(level: Double)
        case working
    }

    let mode: Mode
    var diameter: CGFloat = 18
    var tint: Color = RecorderPill.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                SoftPulse(tint: tint)
            } else {
                TickingView(interval: 1.0 / 30) { context in
                    Canvas { context2D, size in
                        Self.paint(mode: mode, time: context.date.timeIntervalSinceReferenceDate, size: size, tint: tint, into: &context2D)
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private static func paint(mode: Mode, time: TimeInterval, size: CGSize, tint: Color, into ctx: inout GraphicsContext) {
        let orbMode: ThinkingOrbMath.Mode = {
            switch mode {
            case .listening(let level): return .listening(level: level)
            case .working: return .working
            }
        }()
        let dots = ThinkingOrbMath.dots(mode: orbMode, time: time)
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Far to near: the math already orders by generation, not depth, so sort here.
        for dot in dots.sorted(by: { $0.depth < $1.depth }) {
            let point = CGPoint(x: center.x + dot.x * radius, y: center.y + dot.y * radius)
            let dotRadius = max(0.5, dot.radius * radius)
            let rect = CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(dot.opacity)))
        }
    }

    /// Reduce Motion fallback: a slow, gentle opacity breathe -- not the dotted sphere, not a
    /// `TimelineView` either (a ticking view at well under 1 Hz costs nothing).
    private struct SoftPulse: View {
        let tint: Color
        var body: some View {
            TickingView(interval: 1.0 / 8) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
                let opacity = 0.35 + 0.35 * (0.5 + 0.5 * sin(phase * 2 * .pi))
                Circle().fill(tint.opacity(opacity))
            }
        }
    }
}
