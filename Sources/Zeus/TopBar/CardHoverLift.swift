import AppKit
import Combine
import SwiftUI

/// Glance cards rise slightly under the pointer: 1 % larger with a deeper shadow, and a light
/// trackpad tick the first time. A press sinks to 0.985. Off with Reduce Motion.
private final class HoverFlag: ObservableObject {
    @Published var on = false
    @Published var pressed = false
}

private struct CardHoverLift: ViewModifier {
    @StateObject private var hover = HoverFlag()

    func body(content: Content) -> some View {
        let active = !Motion.reduced && !TopBarStyle.isSnapshot
        let scale: CGFloat = {
            guard active else { return 1 }
            if hover.pressed { return 0.985 }
            return hover.on ? 1.01 : 1
        }()
        content
            .scaleEffect(scale)
            .shadow(color: .black.opacity(active && hover.on && !hover.pressed ? 0.35 : 0),
                    radius: active && hover.on && !hover.pressed ? 14 : 0,
                    y: active && hover.on && !hover.pressed ? 6 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: scale)
            .onHover { inside in
                guard inside != hover.on else { return }
                hover.on = inside
                if inside { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                if !inside { hover.pressed = false }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if active && !hover.pressed { hover.pressed = true }
                    }
                    .onEnded { _ in hover.pressed = false }
            )
    }
}

extension View {
    /// The Glance card hover: a small lift and a haptic tick.
    func cardHoverLift() -> some View { modifier(CardHoverLift()) }
}

/// Trackpad feedback for the notch opening and for actions, as Glance does.
enum NotchHaptics {
    static func open() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    static func action() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
}
