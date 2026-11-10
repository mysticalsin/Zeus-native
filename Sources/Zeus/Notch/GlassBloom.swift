import Combine
import SwiftUI
import ZeusCore

/// The glass bloom Glance shows while the panel expands (TOPBAR-SPEC §5): a translucent
/// frosted rim about 9 pt wide around the body with white glints along the bottom edge,
/// fading out within 0.4 s. Drawn behind the body, so each stroke is twice as wide as what
/// shows outside the edge.
///
/// Like Glance, it is drawn on the final open outline from the first frame (the body grows inside
/// it), so NotchView keeps it out of the open/close animation.
///
/// It ticks only for those 0.4 s: `paused` is read when the view is built, so a task marks the
/// bloom finished when the fade ends, which rebuilds the view and pauses the timeline.
struct GlassBloom: View {
    let shoulder: CGFloat
    let earHeight: CGFloat
    let bottomRadius: CGFloat
    /// When the panel last opened; nil draws nothing.
    let start: Date?

    private final class Clock: ObservableObject {
        @Published var finished: Date?
    }

    @StateObject private var clock = Clock()

    var body: some View {
        let duration = GlanceTopBar.bloomDuration
        let done = start.map { started in
            Motion.reduced || TopBarStyle.isSnapshot || clock.finished == started
                || Date().timeIntervalSince(started) > duration
        } ?? true
        Group {
            if done {
                Color.clear
            } else {
                TickingView(interval: 1.0 / 60) { context in
                    let t = start.map { min(max(context.date.timeIntervalSince($0) / duration, 0), 1) } ?? 1
                    let fade = 1 - t * t
                    bloom(fade: fade)
                }
            }
        }
        .task(id: start) {
            guard let start else { return }
            let left = duration - Date().timeIntervalSince(start)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard !Task.isCancelled else { return }
            clock.finished = start
        }
        .accessibilityHidden(true)
    }

    private func bloom(fade: Double) -> some View {
        let shape = NotchShape(shoulder: shoulder, earHeight: earHeight, bottomRadius: bottomRadius)
        return ZStack {
            shape.stroke(Theme.glow.opacity(0.55 * fade), lineWidth: 2 * GlanceTopBar.bloomRim * fade)
                .blur(radius: 5)
            shape.stroke(Theme.accent.opacity(0.28 * fade), lineWidth: 2 * GlanceTopBar.bloomRim * fade)
                .blur(radius: 2.2)
            shape.stroke(Color.white.opacity(0.18 * fade), lineWidth: 2 * GlanceTopBar.bloomRim * fade)
                .blur(radius: 3)
            shape.stroke(LinearGradient(stops: [
                .init(color: .clear, location: 0.55),
                .init(color: .white.opacity(0.9 * fade), location: 0.86),
                .init(color: .white.opacity(0.4 * fade), location: 0.94),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 3.2)
            .blur(radius: 0.6)
        }
        .allowsHitTesting(false)
    }
}
