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
    /// Code is moving the sprite across the screen (the idle stroll, the done jump, the error shake): the clock
    /// runs at 60 fps then, so the offsets are smooth, and at the clip's own rate otherwise.
    var travelling = false

    /// The mood the mascot is in: the app state, or asleep/waking when Tony is away.
    enum Mood: Equatable {
        case awake(AvatarState)
        case asleep
        case waking
    }

    /// Poses a state cycles through and how long each slot lasts: the mascot "does" the action.
    /// A slot restarts its pose's clip, so one-shots replay and loops line up with `hold`.
    static func cycle(for state: AvatarState) -> (poses: [LivingPose], hold: Double) {
        let row = MascotPoseCycle.cycle(for: state.rawValue)
        return (row.poses.compactMap(LivingPose.init(rawValue:)), row.hold)
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
                    motion.travelling = true
                    motion.elapsed = into
                    motion.dx = unit * 5 * CGFloat(sin(p * 2 * .pi))
                    motion.dy = -unit * 1 * CGFloat(abs(sin(p * 6 * .pi)))
                    motion.scaleX = sin(p * 2 * .pi + .pi / 2) >= 0 ? 1 : -1 // face the way it walks
                } else if glance >= glanceEvery - glanceLength {
                    motion.pose = .curious
                    motion.elapsed = glance - (glanceEvery - glanceLength)
                }
            case .error:
                if slotElapsed < 0.5 {
                    motion.dx = unit * 1.6 * CGFloat(sin(slotElapsed * 2 * .pi * 6))
                    motion.travelling = true
                }
            case .done:
                if slotElapsed < 0.5 {
                    motion.dy = -unit * 4 * CGFloat(sin(.pi * slotElapsed / 0.5))
                    motion.travelling = true
                }
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

    /// Code moves the sprite now or within `lookahead` seconds. The clock asks one tick ahead so the display link is
    /// already running when the stroll starts, instead of picking it up one clip frame (up to 83 ms) late.
    static func travels(at t: Double, within lookahead: Double, mood: Mood, size: CGFloat) -> Bool {
        at(t, mood: mood, size: size).travelling || at(t + lookahead, mood: mood, size: size).travelling
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

/// Reference point for a waking clip, so it starts at its first frame, and what the frame clock should do next (a
/// class, not @State: the toolchain lacks StateMacro; it only publishes when the wanted clock changes).
@MainActor
final class MascotClipClock: ObservableObject {
    var wakeStart: Double?
    /// Seconds between timer ticks: the on-screen clip's own frame rate. It follows the pose, one tick behind.
    @Published private(set) var interval: Double = 1 / 12
    /// Code is moving the sprite (the stroll, the shake, the jump): the view runs on the display link at 60 fps.
    @Published private(set) var travelling = false

    func follow(interval wanted: Double, travelling wantsTravel: Bool) {
        guard abs(wanted - interval) > 1e-9 || wantsTravel != travelling else { return }
        // Not inside the view update that asked: publishing from there is undefined.
        DispatchQueue.main.async { [weak self] in
            self?.interval = wanted
            self?.travelling = wantsTravel
        }
    }
}

/// The v2 mascot, alive: plays the state's sprite animation frame by frame (timed from the atlas
/// metadata; the 128 px atlas for the notch, 320 px for chat and onboarding) and adds code motion only
/// for travel. Ticks at each clip's own frame rate (12, 20 or 24 fps) on a run-loop timer, and at 60 fps on the display link while it travels; gone from the view tree (the notch
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

    /// The fastest clip rate (the halo lights share this grid). Clips run at 12, 20 or 24 fps; the clock follows each.
    static let busyFPS = 24.0
    /// The rate when a clip is missing and only the still pose shows.
    static let fallbackFPS = 12.0

    private var mood: MascotMotion.Mood {
        if asleep { return .asleep }
        if waking { return .waking }
        return .awake(state)
    }

    /// The clock follows the sprite: its clip's own frame rate, or 60 fps while code moves it.
    static func tickInterval(clipFPS: Double, travelling: Bool) -> Double {
        1 / MotionRules.fps(clipFPS: clipFPS, travelling: travelling)
    }

    /// The clip's own interval, whether or not code is moving the sprite: this is the run-loop timer's.
    static func clipInterval(for motion: MascotMotion, atlas: MascotAtlasStore) -> Double {
        tickInterval(clipFPS: atlas.clip(motion.pose.clipID).map { Double($0.fps) } ?? fallbackFPS, travelling: false)
    }

    /// The rate the mascot is drawn at: the clip's, or 60 fps while travelling (on the display link).
    static func tickInterval(for motion: MascotMotion, atlas: MascotAtlasStore) -> Double {
        motion.travelling ? tickInterval(clipFPS: fallbackFPS, travelling: true) : clipInterval(for: motion, atlas: atlas)
    }

    var body: some View {
        Group {
            if let pinnedPose {
                TickingView(interval: Self.clipInterval(for: MascotMotion(pose: pinnedPose), atlas: atlas), paused: paused) { context in
                    frame(MascotMotion(pose: pinnedPose, elapsed: context.date.timeIntervalSinceReferenceDate))
                }
            } else if let frameTime {
                frame(MascotMotion.at(frameTime, mood: mood, size: size))
            } else if Motion.reduced || TopBarStyle.isSnapshot {
                frame(MascotMotion(pose: asleep ? .sleepingClean : MascotMotion.cycle(for: state).poses[0]))
            } else {
                if clock.travelling {
                    // Code is moving the sprite: the display link at 60 fps (it honours Reduce Motion and hidden windows).
                    DisplaySynchronizedView(paused: paused, preferredFramesPerSecond: Motion.ambientFPS) { context in
                        step(at: context.date)
                    }
                } else {
                    TickingView(interval: clock.interval, paused: paused) { context in
                        step(at: context.date)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(asleep ? "Zeus: sleeping" : "Zeus: \(state.title)")
    }

    private func step(at date: Date) -> some View {
        let t = clipTime(date.timeIntervalSinceReferenceDate)
        let motion = MascotMotion.at(t, mood: mood, size: size)
        let _ = clock.follow(interval: Self.clipInterval(for: motion, atlas: atlas),
                             travelling: MascotMotion.travels(at: t, within: clock.interval, mood: mood, size: size))
        return frame(motion)
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
