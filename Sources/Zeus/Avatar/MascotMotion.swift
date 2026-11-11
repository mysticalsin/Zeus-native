import AppKit
import CoreGraphics
import SwiftUI
import ZeusCore

/// How Mini ZEUS moves: which v2 pose plays, how far into its sprite clip it is, and the little
/// bit of travel code adds on top. Pure (no views, no clocks) so it is tested.
///
/// The animation itself (breathing, blinks, head tilts, waves, the hop, Zzz) is baked into the sprite
/// atlases in `Avatar/Anim` by tools/mascot/build_animated_zeus.py, timed from the pack manifest.
/// Code motion is only for travel across the screen: the idle stroll, the done jump, the error shake.
struct MascotMotion: Equatable {
    var pose: LivingPose
    /// Seconds into `pose`'s sprite clip (loops wrap, one-shots hold their last frame).
    var elapsed: Double = 0
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    /// -1 flips the sprite to face the way it strolls.
    var scaleX: CGFloat = 1
    /// 0...1 phase of the floating Zzz while asleep. Drawn by code only when the sleeping atlas is missing.
    var sleepPhase: Double?

    /// The mood the mascot is in: the app state, or asleep/waking when Tony is away.
    enum Mood: Equatable {
        case awake(AvatarState)
        case asleep
        case waking
    }

    /// Poses a state cycles through and how long each slot lasts: the mascot "does" the action.
    /// A slot restarts its pose's clip, so one-shots replay and loops line up with `hold`.
    static func cycle(for state: AvatarState) -> (poses: [LivingPose], hold: Double) {
        switch state {
        case .idle: ([.idle], 4)
        case .listening: ([.listening], 3)
        case .thinking: ([.thinking, .curious], 3.2)
        case .speaking: ([.welcome, .guiding], 1.8)
        case .pointing: ([.guiding], 2)
        case .clicking: ([.working, .organizing], 2.4)
        case .typing: ([.typing], 2.4)
        case .browsing: ([.searching, .curious], 2.4)
        case .agent: ([.working, .typing, .searching, .organizing, .carrying], 2.4)
        case .approval: ([.approval_wait], 4)
        case .error: ([.error, .confused], 2)
        case .done: ([.success, .celebrate], 1.8)
        case .teleprompter: ([.guiding, .curious], 3)
        }
    }

    /// Idle extras: a curious glance every `glanceEvery` s and a short walk every `walkEvery` s.
    static let glanceEvery = 13.0, glanceLength = 1.6
    static let walkEvery = 37.0, walkLength = 3.2

    static func at(_ t: Double, mood: Mood, size: CGFloat) -> MascotMotion {
        let unit = size / 22 // offsets are designed at the notch's 22 pt
        switch mood {
        case .asleep:
            return MascotMotion(pose: .sleepingClean, elapsed: t, sleepPhase: (t / 2.4).truncatingRemainder(dividingBy: 1))
        case .waking:
            return MascotMotion(pose: .waking, elapsed: t)
        case .awake(let state):
            let (pose, slotElapsed) = slot(at: t, state: state)
            var motion = MascotMotion(pose: pose, elapsed: slotElapsed)
            switch state {
            case .idle:
                let walk = t.truncatingRemainder(dividingBy: walkEvery)
                let glance = t.truncatingRemainder(dividingBy: glanceEvery)
                if walk >= walkEvery - walkLength {
                    // A little stroll out and back, hopping on each step.
                    let into = walk - (walkEvery - walkLength)
                    let p = into / walkLength
                    motion.pose = .walking
                    motion.elapsed = into
                    motion.dx = unit * 5 * CGFloat(sin(p * 2 * .pi))
                    motion.dy = -unit * 1 * CGFloat(abs(sin(p * 6 * .pi)))
                    motion.scaleX = sin(p * 2 * .pi + .pi / 2) >= 0 ? 1 : -1 // face the way it walks
                } else if glance >= glanceEvery - glanceLength {
                    motion.pose = .curious
                    motion.elapsed = glance - (glanceEvery - glanceLength)
                }
            case .error:
                if slotElapsed < 0.5 { motion.dx = unit * 1.6 * CGFloat(sin(slotElapsed * 2 * .pi * 6)) }
            case .done:
                if slotElapsed < 0.5 { motion.dy = -unit * 4 * CGFloat(sin(.pi * slotElapsed / 0.5)) }
            case .thinking:
                // QA23: the sprite's paw-at-cheek was too small at 22 pt to tell from idle. A slow sway
                // and bob by code, the way a mind drums its fingers while it works.
                motion.dx = unit * 1.2 * CGFloat(sin(t * 2 * .pi / 1.6))
                motion.dy = -unit * 0.8 * CGFloat(abs(sin(t * 2 * .pi / 1.6)))
            default:
                break
            }
            return motion
        }
    }

    /// The pose in the cycle at `t` and how far into its slot (hence its clip) `t` is.
    static func slot(at t: Double, state: AvatarState) -> (pose: LivingPose, elapsed: Double) {
        let (poses, hold) = cycle(for: state)
        let time = max(0, t)
        let slot = Int(time / hold)
        return (poses[slot % poses.count], time - Double(slot) * hold)
    }

    static func pose(at t: Double, state: AvatarState) -> LivingPose {
        slot(at: t, state: state).pose
    }
}

/// Reference point for a waking clip, so it starts at its first frame (a class, not @State: the
/// toolchain lacks StateMacro; it never publishes, so reading it in `body` is free).
@MainActor
final class MascotClipClock: ObservableObject {
    var wakeStart: Double?
}

/// The v2 mascot, alive: plays the state's sprite animation frame by frame (timed from the atlas
/// metadata; the 128 px atlas for the notch, 320 px for chat and onboarding) and adds code motion only
/// for travel. Ticks at 24 fps while busy and 6 fps at rest; gone from the view tree (the notch
/// hidden) means no timeline and no work. Reduce Motion shows the state's first (rest) frame, and
/// snapshots pin `frameTime`. A missing atlas falls back to the still pose PNG.
struct LivingAvatar: View {
    let state: AvatarState
    var size: CGFloat = 22
    var asleep = false
    var waking = false
    /// Stops the frame clock (the buddy while it is hidden); the last frame stays.
    var paused = false
    /// Pins the clock (snapshots, previews).
    var frameTime: Double? = nil
    /// Overrides the normal `AvatarState` cycle to show this exact pose (`zeus debug animate
    /// <pose>`, `AvatarStatus.posePreview`). See its doc comment in `Avatar.swift`.
    var pinnedPose: LivingPose? = nil
    /// Where the sprite atlases live; nil = the app bundle's `Anim` folder.
    var atlas: MascotAtlasStore = .shared

    @Environment(\.mascotRasterScale) private var mascotRasterScale
    @StateObject private var clock = MascotClipClock()

    /// Rest is 6 fps: the idle clip still breathes, and a closed notch stays under the idle CPU cap.
    static let busyFPS = 24.0, restFPS = 6.0

    private var mood: MascotMotion.Mood {
        if asleep { return .asleep }
        if waking { return .waking }
        return .awake(state)
    }

    /// Resting states tick slowly; everything the mascot is actively doing ticks faster.
    static func tickInterval(asleep: Bool, waking: Bool, state: AvatarState) -> Double {
        if waking { return 1 / busyFPS }
        if asleep { return 1 / restFPS }
        switch state {
        case .idle, .listening, .approval: return 1 / restFPS
        default: return 1 / busyFPS
        }
    }

    var body: some View {
        Group {
            if let pinnedPose {
                TickingView(interval: 1 / Self.busyFPS, paused: paused) { context in
                    frame(MascotMotion(pose: pinnedPose, elapsed: context.date.timeIntervalSinceReferenceDate))
                }
            } else if let frameTime {
                frame(MascotMotion.at(frameTime, mood: mood, size: size))
            } else if Motion.reduced || TopBarStyle.isSnapshot {
                frame(MascotMotion(pose: asleep ? .sleepingClean : MascotMotion.cycle(for: state).poses[0]))
            } else {
                TickingView(interval: Self.tickInterval(asleep: asleep, waking: waking, state: state), paused: paused) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    frame(MascotMotion.at(clipTime(t), mood: mood, size: size))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(asleep ? "Zeus: sleeping" : "Zeus: \(state.title)")
    }

    /// Waking starts from its first frame; everything else runs on the shared clock.
    private func clipTime(_ t: Double) -> Double {
        guard waking && !asleep else { clock.wakeStart = nil; return t }
        if clock.wakeStart == nil { clock.wakeStart = t }
        return t - (clock.wakeStart ?? t)
    }

    private func frame(_ motion: MascotMotion) -> some View {
        let scale = MascotRasterScale.resolve(mascotRasterScale)
        let crisp = scale <= 1.01
        let sprite = atlas.frame(motion.pose.clipID, elapsed: motion.elapsed, points: size, pixelScale: scale)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let sprite {
                    Image(decorative: sprite, scale: 1).resizable().interpolation(crisp ? .none : .high).aspectRatio(contentMode: .fit)
                } else if let image = AvatarArt.image(for: motion.pose, points: size, pixelScale: scale) {
                    Image(nsImage: image).resizable().interpolation(crisp ? .none : .high).aspectRatio(contentMode: .fit)
                } else {
                    BoltShape().fill(Theme.bolt).padding(size * 0.12)
                }
            }
            .scaleEffect(x: motion.scaleX, y: 1, anchor: .bottom)
            .offset(x: motion.dx, y: motion.dy)
            // The sleeping atlas carries its own Zzz; code draws them only for the still-pose fallback.
            if sprite == nil, let phase = motion.sleepPhase { zzz(phase) }
        }
        .shadow(color: Theme.bolt.opacity(motion.sleepPhase == nil ? 0.3 : 0.12), radius: size * 0.12)
    }

    /// Three z's drifting up and fading, staggered.
    private func zzz(_ phase: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let p = (phase + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: size * (0.22 + 0.08 * CGFloat(i)), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85)
                    .offset(x: size * (0.05 + 0.12 * CGFloat(p)), y: -size * 0.45 * CGFloat(p))
            }
        }
        .offset(x: size * 0.15, y: size * 0.05)
        .allowsHitTesting(false)
    }
}
