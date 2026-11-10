import AppKit
import SwiftUI

/// Pose names from design/mascot-v2 (copied into Avatar/Poses).
enum LivingPose: String, CaseIterable, Identifiable, Sendable {
    case welcome, idle, curious, guiding, listening, thinking, approval_wait
    case working, success, celebrate, grateful, confused, error, sleeping, waking
    case typing, searching, organizing, surprised, goodbye, offline, paused, carrying
    case walking
    case sleepingClean = "sleeping-clean" // sleeping without baked-in Zzz (Zeus draws its own)

    var id: String { rawValue }

    /// The pack-manifest state id of the sprite clip that animates this pose (`Avatar/Anim/<id>.json`).
    var clipID: String { self == .sleepingClean ? "sleeping" : rawValue }

    var accessibilityLabel: String {
        switch self {
        case .welcome: "Zeus waving hello"
        case .idle: "Zeus ready"
        case .curious: "Zeus curious"
        case .guiding: "Zeus guiding you"
        case .listening: "Zeus listening"
        case .thinking: "Zeus thinking"
        case .approval_wait: "Zeus waiting for your go-ahead"
        case .working: "Zeus working"
        case .success: "Zeus nodding success"
        case .celebrate: "Zeus celebrating"
        case .grateful: "Zeus grateful"
        case .confused: "Zeus confused"
        case .error: "Zeus worried"
        case .sleeping: "Zeus sleeping"
        case .waking: "Zeus waking up"
        case .typing: "Zeus typing"
        case .searching: "Zeus searching"
        case .organizing: "Zeus organizing"
        case .surprised: "Zeus surprised"
        case .goodbye: "Zeus waving goodbye"
        case .offline: "Zeus offline"
        case .paused: "Zeus paused"
        case .carrying: "Zeus carrying"
        case .walking: "Zeus walking"
        case .sleepingClean: "Zeus sleeping"
        }
    }
}

@MainActor
enum LivingPoseArt {
    private static var cache: [String: NSImage] = [:]

    static func image(_ pose: LivingPose) -> NSImage? {
        if let hit = cache[pose.rawValue] { return hit }
        guard let url = ZeusResources.bundle?.url(forResource: pose.rawValue, withExtension: "png", subdirectory: "Poses"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[pose.rawValue] = image
        return image
    }
}

/// Mutable bits for the living mascot (no @State — toolchain lacks StateMacro).
@MainActor
final class LivingMascotModel: ObservableObject {
    @Published var hop: CGFloat = 0
    @Published var pointer = CGSize.zero
    @Published var hovering = false
    private var hopToken = 0

    func reactHover() {
        guard !Motion.reduced else { return }
        hopToken += 1
        let token = hopToken
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { hop = -6 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22))
            guard self.hopToken == token else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { self.hop = 0 }
        }
    }

    func playCelebrate() {
        guard !Motion.reduced else { return }
        hopToken += 1
        let token = hopToken
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { hop = -14 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.28))
            guard self.hopToken == token else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) { self.hop = 0 }
        }
    }
}

/// Living gold mascot: breathes/blinks on idle, reacts to hover/success, slight pointer follow,
/// celebrates. Honours Reduce Motion. No @State (toolchain).
struct LivingMascot: View {
    var pose: LivingPose = .idle
    var size: CGFloat = 160
    var celebrate = false
    var followPointer = true

    @StateObject private var model = LivingMascotModel()

    var body: some View {
        TickingView(interval: Motion.reduced ? 1 : 1 / 30, paused: Motion.reduced) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathScale: CGFloat = Motion.reduced ? 1 : 1 + 0.018 * CGFloat(sin(t * 2.1))
            let bob: CGFloat = Motion.reduced ? 0 : 2.2 * CGFloat(sin(t * 1.4))
            let blinkFactor: CGFloat = Motion.reduced ? 1 : (sin(t * 0.55) > 0.97 ? 0.12 : 1)
            art
                .scaleEffect(breathScale * (celebrate && !Motion.reduced ? 1.06 : 1) * (model.hovering ? 1.03 : 1))
                .offset(x: model.pointer.width * 0.04, y: bob + model.hop + model.pointer.height * 0.03)
                .scaleEffect(x: 1, y: blinkFactor, anchor: .center)
                .animation(Motion.reduced ? nil : .spring(response: 0.34, dampingFraction: 0.72), value: pose)
                .animation(Motion.reduced ? nil : .easeInOut(duration: 0.18), value: celebrate)
        }
        .frame(width: size, height: size)
        .onHover { hovering in
            model.hovering = hovering
            if hovering { model.reactHover() }
        }
        .onContinuousHover { phase in
            guard followPointer, !Motion.reduced else { return }
            if case .active(let point) = phase {
                let mid = CGPoint(x: size / 2, y: size / 2)
                model.pointer = CGSize(width: min(max(point.x - mid.x, -40), 40),
                                       height: min(max(point.y - mid.y, -30), 30))
            } else {
                model.pointer = .zero
            }
        }
        .onChange(of: celebrate) { _, on in if on { model.playCelebrate() } }
        .accessibilityElement()
        .accessibilityLabel(pose.accessibilityLabel)
    }

    @ViewBuilder
    private var art: some View {
        ZStack {
            Circle()
                .fill(Theme.glow.opacity(0.22))
                .blur(radius: size * 0.18)
                .frame(width: size * 0.9, height: size * 0.9)
            if let image = LivingPoseArt.image(pose) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                BoltShape().fill(Theme.bolt).padding(size * 0.18)
                    .shadow(color: Theme.bolt.opacity(0.45), radius: 12)
            }
        }
        .id(pose)
    }
}
