import SwiftUI

/// One screen's layer of the buddy overlay. Everything is placed from the top-left corner with
/// offsets, converted from the model's global AppKit coordinates.
struct BuddyOverlayView: View {
    let model: BuddyModel
    let screenFrame: CGRect

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: screenFrame.maxY - point.y)
    }

    var body: some View {
        let spark = local(model.position)
        let strike = local(model.strikeCenter)

        ZStack(alignment: .topLeading) {
            if let ring = model.ringFrame {
                let origin = local(CGPoint(x: ring.minX, y: ring.maxY))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.bolt, lineWidth: 2)
                    .frame(width: ring.width, height: ring.height)
                    .shadow(color: Theme.bolt.opacity(0.8), radius: model.glow)
                    .offset(x: origin.x, y: origin.y)
            }

            if model.strikeProgress < 1 {
                let diameter = 4 + 36 * model.strikeProgress
                Circle()
                    .stroke(Theme.bolt, lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: Theme.bolt.opacity(0.8), radius: 6)
                    .opacity(0.9 * (1 - model.strikeProgress))
                    .offset(x: strike.x - diameter / 2, y: strike.y - diameter / 2)
            }

            // The avatar art: one coloured bolt per state. It leans into a flight, upright otherwise.
            AvatarView(state: AvatarStatus.shared.current, size: SparkView.avatarSize, paused: !(model.sparkVisible && model.hasAppeared))
                .rotationEffect(.degrees(model.mode == .flying ? model.rotation : 0))
                .scaleEffect(model.scale)
                .shadow(color: Theme.bolt.opacity(0.55), radius: model.glow)
                .opacity(model.sparkVisible && model.hasAppeared ? 1 : 0)
                .animation(.easeIn(duration: model.hasAppeared ? 0.25 : 2), value: model.sparkVisible)
                .animation(.easeIn(duration: 2), value: model.hasAppeared)
                .offset(x: spark.x - SparkView.avatarSize / 2, y: spark.y - SparkView.avatarSize / 2)

            WaveformView(level: model.audioLevel, active: model.mode == .listening)
                .opacity(model.mode == .listening ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: model.mode)
                .offset(x: spark.x - 9, y: spark.y - 8)

            SpinnerView(active: model.mode == .thinking)
                .opacity(model.mode == .thinking ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: model.mode)
                .offset(x: spark.x - 7, y: spark.y - 7)

            BubbleView(text: model.bubbleText)
                .scaleEffect(model.bubbleVisible ? 1 : 0.5, anchor: .topLeading)
                .opacity(model.bubbleVisible ? 1 : 0)
                .animation(model.bubbleVisible ? .spring(response: 0.4, dampingFraction: 0.6) : .easeOut(duration: 0.5),
                           value: model.bubbleVisible)
                .offset(x: spark.x + 14, y: spark.y + 14)

            CaptionView(text: model.caption)
                .opacity(model.captionVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: model.captionVisible)
                .offset(x: captionX(spark.x), y: spark.y + (model.bubbleVisible ? 46 : 18))
        }
        .frame(width: screenFrame.width, height: screenFrame.height, alignment: .topLeading)
        .allowsHitTesting(false)
        // Decorative: what ZEUS says is spoken and captioned; VoiceOver reads approvals in the notch.
        .accessibilityHidden(true)
    }
}

struct SparkView: View {
    static let size: CGFloat = 18
    static let avatarSize: CGFloat = 26
    let rotation: Double
    let scale: Double

    var body: some View {
        BoltShape()
            .fill(Theme.bolt)
            .frame(width: Self.size, height: Self.size)
            .shadow(color: Theme.bolt.opacity(0.9), radius: 4 + (scale - 1) * 20)
            .shadow(color: Theme.bolt.opacity(0.45), radius: 10)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
    }
}

/// Five bars driven by the mic level; idles on a slow sine until real audio arrives (PR 03).
struct WaveformView: View {
    let level: Double?
    /// Hidden bars must not tick: an always-on .animation timeline redrew the overlay every frame.
    var active = true
    private let profile: [Double] = [0.4, 0.7, 1, 0.7, 0.4]

    var body: some View {
        if active {
            TickingView(interval: 1.0 / 30) { context in
                bars(at: context.date)
            }
        }
    }

    private func bars(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        return HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let simulated = 0.45 + 0.45 * sin(t * 9 + Double(index) * 1.3) * sin(t * 2.3)
                let value = min(max(level ?? abs(simulated), 0), 1)
                Capsule()
                    .fill(Theme.bolt)
                    .frame(width: 2, height: 3 + pow(value, 0.76) * 10 * profile[index] + 1.5 * sin(t * 3.6 + Double(index)))
            }
        }
        .frame(height: 16)
        .shadow(color: Theme.bolt.opacity(0.7), radius: 4)
    }
}

struct SpinnerView: View {
    var active = true

    var body: some View {
        if active {
            TickingView(interval: 1.0 / 30) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        AngularGradient(colors: [Theme.sky.opacity(0), Theme.sky, Theme.bolt], center: .center),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 0.8) / 0.8 * 360))
                    .shadow(color: Theme.sky.opacity(0.6), radius: 4)
            }
        }
    }
}

extension BuddyOverlayView {
    /// Keeps the caption on screen near the right edge.
    func captionX(_ sparkX: CGFloat) -> CGFloat {
        min(sparkX + 14, screenFrame.width - CaptionView.maxWidth - 16)
    }
}

/// Spoken reply as text: dark plate, light text (well above 7:1), 13 pt.
struct CaptionView: View {
    static let maxWidth: CGFloat = 340
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.cloudPrimary)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .background(Theme.storm.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .frame(width: Self.maxWidth, alignment: .leading)
    }
}

struct BubbleView: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.storm)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.bolt, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
            .shadow(color: Theme.bolt.opacity(0.5), radius: 8)
            .fixedSize()
    }
}
