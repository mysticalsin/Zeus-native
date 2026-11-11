import SwiftUI
import ZeusCore

// All of the Scribe opening animation lives here (timing numbers: ZeusCore `ScribeOpenSequence`).
// It is declarative: `ScribeOpenScope` flips one flag when the page appears and each piece animates itself with a
// delayed spring. There are no timers or tasks, so nothing runs once the last piece has landed.
// `isOpen = false` plays the same pieces back faster, with no delay.

private struct ScribeOpenKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False until the page has appeared, and again while it closes.
    var scribeOpen: Bool {
        get { self[ScribeOpenKey.self] }
        set { self[ScribeOpenKey.self] = newValue }
    }
}

/// Wraps a page: starts closed, opens on appear. Pass `isOpen: false` to reverse (quicker).
struct ScribeOpenScope<Content: View>: View {
    let isOpen: Bool
    let content: Content
    @State private var appeared = false

    init(isOpen: Bool = true, @ViewBuilder content: () -> Content) {
        self.isOpen = isOpen
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.scribeOpen, appeared && isOpen)
            .onAppear { appeared = true }
    }
}

extension View {
    /// One piece of the choreography: scale, drop and opacity from the sequence table.
    func scribeEntrance(_ stage: ScribeOpenSequence.Stage) -> some View {
        modifier(ScribeEntrance(stage: stage))
    }

    /// The single soft light sweep across the glass capture button.
    func scribeLightSweep() -> some View {
        modifier(ScribeLightSweep())
    }
}

private struct ScribeEntrance: ViewModifier {
    let stage: ScribeOpenSequence.Stage
    @Environment(\.scribeOpen) private var open
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(open ? 1 : 0)
            .scaleEffect(reduceMotion || open ? 1 : ScribeOpenSequence.startScale(stage), anchor: .top)
            .offset(y: reduceMotion || open ? 0 : ScribeOpenSequence.startOffset(stage))
            .animation(animation, value: open)
    }

    private var animation: Animation {
        if reduceMotion { return .easeInOut(duration: ScribeOpenSequence.reducedMotionFade) }
        let closing = !open
        let delay = ScribeOpenSequence.delay(stage, closing: closing)
        let duration = ScribeOpenSequence.duration(stage, closing: closing)
        if closing { return .easeIn(duration: duration) }
        return .spring(response: duration, dampingFraction: 0.82).delay(delay)
    }
}

private struct ScribeLightSweep: ViewModifier {
    @Environment(\.scribeOpen) private var open
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 26)
                    .rotationEffect(.degrees(20))
                    .offset(x: open ? 46 : -46)
                    .animation(open ? .easeOut(duration: ScribeOpenSequence.sweepDuration)
                        .delay(ScribeOpenSequence.delay(.capture) + 0.12) : nil, value: open)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
