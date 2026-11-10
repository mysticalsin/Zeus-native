import AppKit
import SwiftUI
import ZeusCore

// The guide's mascot is the living Zeus: the v2 sprite atlases (Avatar/Anim, via MascotAtlasStore, the
// same clips LivingAvatar plays in the notch) at the 320 px size, with a still-PNG fallback. There are
// no separate onboarding poses any more.

/// One frame of a pose's sprite clip, `elapsed` seconds after the clip started (loops wrap, one-shots
/// hold their last frame). Pure of any clock, so films and the live guide share it.
struct SpriteFrame: View {
    let pose: LivingPose
    let elapsed: Double
    let size: CGFloat
    @Environment(\.mascotRasterScale) private var mascotRasterScale

    var body: some View {
        let scale = MascotRasterScale.resolve(mascotRasterScale)
        let crisp = scale <= 1.01
        Group {
            if let sprite = MascotAtlasStore.shared.frame(pose.clipID, elapsed: elapsed, points: size, pixelScale: scale) {
                Image(decorative: sprite, scale: 1).resizable().interpolation(crisp ? .none : .high).scaledToFit()
            } else if let image = LivingPoseArt.image(pose) {
                Image(nsImage: image).resizable().interpolation(crisp ? .none : .high).scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}

/// Where the guide's mascot rests and how it is posed on a step.
extension OnboardingStep {
    /// The mascot's wake-up on the first appearance of the guide: asleep, waking, then waving.
    enum Wake: Int, Comparable, Sendable {
        case asleep, waking, awake
        static func < (a: Wake, b: Wake) -> Bool { a.rawValue < b.rawValue }
    }

    /// The pose per step. Welcome follows the wake-up (sleeping, waking, then the wave); the voice
    /// step listens, the agents step works, and the last step celebrates.
    func mascotPose(wake: Wake = .awake) -> LivingPose {
        switch self {
        case .welcome: wake == .asleep ? .sleepingClean : wake == .waking ? .waking : .welcome
        case .murmure: .listening
        case .agents: .working
        case .control: .approval_wait
        case .reach: .guiding
        case .day: .curious
        case .theme: .idle
        case .halo: .thinking
        case .sounds: .celebrate
        }
    }

    /// The big tile on the welcome step; a small companion everywhere else.
    var mascotIsHero: Bool { self == .welcome }
}

/// Plays the clip of the pose it is given, restarting it whenever the pose changes (a class, not @State:
/// the toolchain lacks the StateMacro; it never publishes, so reading it in `body` is free).
@MainActor
final class SpriteClock: ObservableObject {
    var pose: LivingPose?
    var since = Date()
}

/// The 112 pt tile where Glance shows its app icon: Zeus's living mascot on a pale sky tile. The tile
/// takes the size it is given, so `matchedGeometryEffect` can grow and shrink it between steps.
struct MascotTile: View {
    let pose: LivingPose
    var side: CGFloat? = nil
    var animated = true
    @StateObject private var clock = SpriteClock()

    var body: some View {
        if let side {
            tile(side).frame(width: side, height: side)
        } else {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                tile(side).frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func tile(_ side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: 246, 249, 255), Color(rgb: 214, 228, 250)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            sprite(side * 0.80)
        }
        .frame(width: side, height: side)
        .accessibilityElement()
        .accessibilityLabel(pose.accessibilityLabel)
    }

    @ViewBuilder private func sprite(_ points: CGFloat) -> some View {
        if animated && !Motion.reduced && !TopBarStyle.isSnapshot {
            TickingView(interval: 1 / 24) { context in
                let now = context.date
                SpriteFrame(pose: pose, elapsed: elapsed(now), size: points)
            }
        } else {
            // Still: the pose's rest frame, or its last frame for the one-shots that end on the pay-off.
            SpriteFrame(pose: pose, elapsed: MascotAtlasStore.shared.clip(pose.clipID)?.isLoop == false ? 99 : 0, size: points)
        }
    }

    private func elapsed(_ now: Date) -> Double {
        if clock.pose != pose { clock.pose = pose; clock.since = now }
        return max(0, now.timeIntervalSince(clock.since))
    }
}
