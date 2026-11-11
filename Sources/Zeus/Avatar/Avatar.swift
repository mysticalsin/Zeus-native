import AppKit
import SwiftUI
import ZeusCore

/// What ZEUS is doing, shown by the avatar: one lightning bolt colour per state.
enum AvatarState: String, CaseIterable, Identifiable, Sendable {
    case idle, listening, thinking, speaking, pointing, clicking, typing, browsing, agent, approval, error, done, teleprompter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "Ready"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .pointing: "Pointing"
        case .clicking: "Clicking"
        case .typing: "Typing"
        case .browsing: "Browsing"
        case .agent: "Agent working"
        case .approval: "Needs you"
        case .error: "Something went wrong"
        case .done: "Done"
        case .teleprompter: "Prompting"
        }
    }

    /// Glow colour for the pulse around the art.
    var glow: Color {
        // Matches each bolt's own colour in the art.
        switch self {
        case .idle: Theme.bolt
        case .listening: Color(hex: 0xB46BFF)
        case .thinking: Color(hex: 0x3D8BFF)
        case .speaking: Color(hex: 0xFF4FB8)
        case .pointing: Color(hex: 0x2EE6D0)
        case .clicking: Theme.ember
        case .typing: Color(hex: 0x8FD3FF)
        case .browsing: Color(hex: 0x2ED3C6)
        case .agent: Color(hex: 0x52E04A)
        case .approval: Color(hex: 0xFFC83D)
        case .error: Theme.danger
        case .done: Color(hex: 0xB8F03C)
        case .teleprompter: Color(hex: 0xE8ECF4)
        }
    }

    /// States that breathe (a slow glow pulse) rather than sit still.
    var pulses: Bool { self != .idle && self != .done }
}

extension AvatarState {
    /// The v2 mascot pose (Design/mascot-v2, copied into Avatar/Poses) that shows this state.
    var pose: LivingPose {
        switch self {
        case .idle: .idle
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: .welcome
        case .pointing: .guiding
        case .clicking: .organizing
        case .typing: .typing
        case .browsing: .searching
        case .agent: .working
        case .approval: .approval_wait
        case .error: .error
        case .done: .success
        case .teleprompter: .curious
        }
    }
}

extension AvatarState {
    /// The voice ring's state: listening, speaking, thinking and agent work (processing); the rest rest.
    var ringState: VoiceRingState {
        switch self {
        case .listening: .listening
        case .speaking: .speaking
        case .thinking, .agent: .processing
        default: .idle
        }
    }
}

/// The one place avatar art is loaded: the v2 cloud mascot's pose for each state, trimmed to the
/// character and scaled once per size so it stays sharp at 22 pt in the notch.
@MainActor
enum AvatarArt {
    private static var cache: [String: NSImage] = [:]

    static func image(for state: AvatarState, points: CGFloat) -> NSImage? {
        image(for: state.pose, points: points)
    }

    static func image(for pose: LivingPose, points: CGFloat, pixelScale: CGFloat = 2) -> NSImage? {
        let pixels = Int((points * pixelScale).rounded(.up))
        let key = "\(pose.rawValue)-\(pixels)"
        if let hit = cache[key] { return hit }
        guard let source = LivingPoseArt.image(pose)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let trimmed = trim(source),
              let scaled = squareFit(trimmed, pixels: pixels, crisp: pixelScale <= 1.01) else { return nil }
        let image = NSImage(cgImage: scaled, size: NSSize(width: points, height: points))
        cache[key] = image
        return image
    }

    /// Crops the transparent margin the 1254 px poses carry, so the character fills small sizes.
    private static func trim(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// Centres the character on a square canvas of `pixels`, keeping its aspect ratio.
    private static func squareFit(_ image: CGImage, pixels: Int, crisp: Bool) -> CGImage? {
        guard pixels > 0, let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = crisp ? .none : .high
        let scale = CGFloat(pixels) / CGFloat(max(image.width, image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (CGFloat(pixels) - w) / 2, y: (CGFloat(pixels) - h) / 2, width: w, height: h))
        return context.makeImage()
    }
}

/// The avatar with Glance-style state changes: a crossfade with a small scale, and a soft
/// glow that breathes while ZEUS is busy.
struct AvatarView: View {
    let state: AvatarState
    var size: CGFloat = 22
    var animated = true
    /// Freezes the frame clock without dropping the view (the buddy while hidden).
    var paused = false

    var body: some View {
        let orb = VoiceOrbStyleStore.shared.style
        if orb != .mascot {
            ringOrb(orb)
        } else if animated {
            LivingAvatar(state: state, size: size, paused: paused)
        } else {
            still
        }
    }

    /// The voice ring in place of the mascot. AvatarView is not handed the mic meter (TopBarModel's
    /// `micLevel` is not reachable from its inputs), so listening and speaking drive the ring with
    /// `VoiceRingModel.proceduralLevel`, a smoothed stand-in wave, not the real voice.
    private func ringOrb(_ orb: VoiceOrbStyle) -> some View {
        let ringState = state.ringState
        return VoiceRingView(size: size, state: ringState,
                             level: { VoiceRingModel.proceduralLevel(time: Date().timeIntervalSinceReferenceDate, state: ringState) },
                             type: orb == .mono ? .mono : .ring,
                             paused: paused || !animated,
                             runnerID: "avatar-ring-\(Int(size))")
    }

    private var still: some View {
        ZStack {
            art(state)
                .id(state)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.86)),
                                        removal: .opacity.combined(with: .scale(scale: 1.08))))
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: state)
        .accessibilityElement()
        .accessibilityLabel("Zeus: \(state.title)")
    }

    @ViewBuilder
    private func art(_ state: AvatarState) -> some View {
        let base = Group {
            if let image = AvatarArt.image(for: state, points: size) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                // Fallback if the art is missing: the mascot's golden bolt.
                BoltShape().fill(Theme.bolt).padding(size * 0.12)
            }
        }
        if animated, state.pulses, !TopBarStyle.isSnapshot {
            base.phaseAnimator([false, true]) { content, high in
                content
                    .scaleEffect(high ? 1.05 : 1)
                    .shadow(color: state.glow.opacity(high ? 0.75 : 0.35), radius: high ? size * 0.32 : size * 0.16)
            } animation: { _ in .easeInOut(duration: 0.9) }
        } else {
            base.shadow(color: state.glow.opacity(0.5), radius: size * 0.2)
        }
    }
}

extension AvatarState {
    /// Fits the closed notch's right wing.
    var short: String {
        switch self {
        case .idle: "Ready"
        case .agent: "Agent"
        case .approval: "Needs you"
        case .error: "Error"
        case .teleprompter: "Prompter"
        default: title
        }
    }
}

/// The single source of truth for the avatar's state, shared by the notch and the cursor buddy.
/// Priority: approval, then a short flash (done, error, an action), then the voice turn
/// (listening, thinking, speaking, pointing), then ambient work (prompter, agents), then idle.
@MainActor @Observable
final class AvatarStatus {
    static let shared = AvatarStatus()

    /// Voice turn state from the buddy: idle, listening, thinking or pointing.
    var turn: AvatarState = .idle
    var speaking = false
    var needsApproval = false
    var agentWorking = false
    var prompting = false
    private(set) var flash: AvatarState?
    /// Snapshots and previews pin a state.
    var pinned: AvatarState?
    /// QA7 round 11 (report-11.md): `zeus debug animate working|approval_wait|carrying|celebrate`
    /// (and the rest of `LivingPose`) returned "Unknown animation" -- those are v2 mascot *poses*
    /// (`LivingMascot.swift`), reached today only indirectly, a few steps into an `AvatarState`'s
    /// multi-pose cycle (`MascotMotion.cycle(for:)`), never directly addressable on demand. Lets
    /// `zeus debug animate <any LivingPose rawValue>` show that exact pose for a moment, the same
    /// way `flash` previews an exact `AvatarState`.
    private(set) var posePreview: LivingPose?
    private var poseToken = 0
    /// Settings: keep Mini ZEUS beside the closed notch even when resting (on by default).
    /// On by default so Mini ZEUS is always there; turn it off for a bare hardware notch like Glance.
    var alwaysInNotch = UserDefaults.standard.object(forKey: "avatar.alwaysInNotch") as? Bool ?? true {
        didSet { if !TopBarStyle.isSnapshot { UserDefaults.standard.set(alwaysInNotch, forKey: "avatar.alwaysInNotch") } }
    }
    private var flashToken = 0

    /// Mini ZEUS dozes off when Tony has been away this long with nothing going on, and plays its
    /// waking pose for `wakeLength` when he is back. Idle time is the system's own input clock.
    static let sleepAfter: TimeInterval = 300, wakeLength: TimeInterval = 1.4
    private(set) var asleep = false
    private(set) var waking = false
    private var sleepTimer: Timer?

    /// Starts the once-every-10-seconds sleep check (the app calls this at launch).
    func startSleepWatch() {
        guard sleepTimer == nil, !TopBarStyle.isSnapshot else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in AvatarStatus.shared.checkSleep() }
        }
        sleepTimer?.tolerance = 3
    }

    func checkSleep(idleSeconds: TimeInterval = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)) {
        let shouldSleep = current == .idle && idleSeconds >= Self.sleepAfter
        if shouldSleep == asleep { return }
        asleep = shouldSleep
        if !shouldSleep {
            waking = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.wakeLength))
                self?.waking = false
            }
        }
    }

    var current: AvatarState {
        if let pinned { return pinned }
        if needsApproval { return .approval }
        if let flash { return flash }
        if turn != .idle { return speaking && turn != .pointing ? .speaking : turn }
        if speaking { return .speaking }
        if prompting { return .teleprompter }
        if agentWorking { return .agent }
        return .idle
    }

    /// Shows `state` for a moment, then falls back to whatever is underneath.
    func flash(_ state: AvatarState, for seconds: Double = 2) {
        flashToken += 1
        let token = flashToken
        flash = state
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.flashToken == token else { return }
            self.flash = nil
        }
    }

    /// Shows the exact `pose` for a moment, overriding whatever `AvatarState` cycle is otherwise
    /// active, then falls back to it. See `posePreview`'s doc comment above.
    func previewPose(_ pose: LivingPose, for seconds: Double = 3) {
        poseToken += 1
        let token = poseToken
        posePreview = pose
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.poseToken == token else { return }
            self.posePreview = nil
        }
    }

    func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AvatarStatus, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

/// Mini ZEUS, the little mascot that lives left of the notch (where Glance keeps its critter):
/// the v2 cloud, alive (LivingAvatar): it breathes, glances, strolls, works through its poses and
/// falls asleep when Tony is away.
struct MiniMascotView: View {
    let state: AvatarState
    var size: CGFloat = 22
    /// Pins the motion clock (snapshots); nil runs live.
    var frameTime: Double? = nil

    var body: some View {
        let status = AvatarStatus.shared
        LivingAvatar(state: state, size: size, asleep: status.asleep && state == .idle,
                     waking: status.waking && state == .idle, frameTime: frameTime, pinnedPose: status.posePreview)
            .animation(.easeInOut(duration: 0.25), value: state)
    }
}

