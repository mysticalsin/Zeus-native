import SwiftUI
import ZeusCore

/// Mac-pending. Draws the push-to-talk bar light and the round mark inside the notch panel that
/// already exists. It opens no window. Linux tests cover the pure model only.
struct PTTIndicatorOverlay: View {
    let held: Bool
    let listening: Bool
    let level: Double
    let failureText: String?
    /// The caller passes the live Reduce Motion value. This view does not read or write that setting.
    let reduceMotion: Bool

    @State private var model = PTTIndicatorModel()
    @State private var lastPosted: String?

    var body: some View {
        let ticking = model.needsClock(at: Date().timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
        TickingView(interval: PTTIndicatorMotion.frameBudget, paused: !ticking) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            PTTIndicatorMark(frame: model.frame(at: now, reduceMotion: reduceMotion))
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear { step(now) }
                .onChange(of: held) { _, _ in step(now) }
                .onChange(of: listening) { _, _ in step(now) }
                .onChange(of: level) { _, _ in step(now) }
                .onChange(of: failureText) { _, _ in step(now) }
                .onChange(of: reduceMotion) { _, _ in step(now) }
                .onChange(of: context.date) { _, date in step(date.timeIntervalSinceReferenceDate) }
        }
        .allowsHitTesting(false)
    }

    /// Posts only when the model returns a phrase, and not again for the same phrase.
    private func step(_ now: TimeInterval) {
        let phrase = model.advance(
            PTTIndicatorInput(held: held, listening: listening, level: level,
                              failed: PTTIndicatorFailure.isPublished(failureText)),
            now: now, reduceMotion: reduceMotion)
        guard let phrase, phrase != lastPosted else { return }
        lastPosted = phrase
        AccessibilityNotification.Announcement(phrase).post()
    }
}

/// The light along the bar and the round mark. Values come from the pure frame, with no extra animation.
private struct PTTIndicatorMark: View {
    let frame: PTTIndicatorFrame

    private var ring: Color {
        Color(red: PTTIndicatorContrast.ring.r, green: PTTIndicatorContrast.ring.g, blue: PTTIndicatorContrast.ring.b)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(ring)
                .frame(width: max(3, PTTIndicatorMotion.barWidth * frame.barSweep), height: 3)
                .opacity(frame.barOpacity)
                .frame(width: PTTIndicatorMotion.barWidth, height: 3, alignment: .leading)
                .padding(.top, 3)
            Circle()
                .strokeBorder(ring, lineWidth: 2)
                .background(Circle().fill(ring.opacity(0.22)))
                .frame(width: 14 * frame.ringScale, height: 14 * frame.ringScale)
                .opacity(frame.orbOpacity)
                .position(x: frame.orbX, y: frame.orbY)
        }
        .frame(width: PTTIndicatorMotion.barWidth, height: PTTIndicatorMotion.barHeight)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(frame.accessibilityLabel)
        .accessibilityHidden(frame.accessibilityLabel.isEmpty)
        .allowsHitTesting(false)
    }
}
