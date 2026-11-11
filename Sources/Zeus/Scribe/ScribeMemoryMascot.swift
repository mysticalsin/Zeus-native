import AppKit
import SwiftUI
import ZeusCore

// Zeus in the Memory window's bottom lane. He uses the mascot's bundled sprite clips only (walking, curious, idle,
// welcome, searching). The decisions live in ZeusCore's `ScribeMascot` state machine; this file draws them.
//
// Cost: while he sits (the usual state) nothing ticks at all. While he walks, looks, waves or reads, one 12 fps
// clock runs, and TickingView stops it whenever the window is hidden or covered. Reduce Motion draws a still pose
// that changes only when the state does.

/// Owns the state machine and stamps each event with the time. The view reads `machine`; it never advances it.
@MainActor
final class ScribeMascotDriver: ObservableObject {
    @Published private(set) var machine: ScribeMascot
    private var settling = false

    init(startX: Double = 0.15) {
        machine = ScribeMascot(startX: startX)
    }

    func send(_ event: ScribeMascot.Event) {
        var next = machine
        next.send(event, at: Date.timeIntervalSinceReferenceDate)
        // Equatable: an event that changes nothing does not redraw the lane.
        if next != machine { machine = next }
    }

    /// Called while drawing a frame. If a walk has arrived or a wave has gone on long enough, finish it once,
    /// outside the view update.
    func settleIfNeeded(at now: TimeInterval) {
        guard machine.needsTick(at: now), !settling else { return }
        settling = true
        Task { @MainActor [weak self] in
            self?.send(.tick)
            self?.settling = false
        }
    }
}

/// The reserved 64 pt lane under both panes. It never holds text, and Zeus never leaves it.
struct ScribeMemoryLane: View {
    enum Side: Equatable { case list, content }

    static let height: CGFloat = 64
    static let spriteSize: CGFloat = 52

    @ObservedObject var driver: ScribeMascotDriver
    let listWidth: CGFloat
    /// Which pane he should stand under.
    let side: Side
    /// The pointer is over a meeting in the list.
    let hoveringList: Bool
    let searching: Bool
    let isEmpty: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            ZStack(alignment: .bottomLeading) {
                Color.clear
                mascot(width: width)
                    .padding(.bottom, 4)
            }
            .onChange(of: side) { _, next in
                driver.send(.goTo(fraction(next, width: width)))
            }
            .onChange(of: hoveringList) { _, hovering in
                driver.send(hovering ? .hover(fraction(.list, width: width)) : .hoverEnded)
            }
            .onChange(of: searching) { _, on in
                driver.send(on ? .searchStarted : .searchEnded)
            }
            .onChange(of: isEmpty, initial: true) { _, empty in
                driver.send(empty ? .emptyShown : .emptyHidden)
            }
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch driver.machine.mode {
        case .walking: "Zeus walking"
        case .looking: "Zeus looking at a meeting"
        case .sitting: "Zeus sitting"
        case .waving: "Zeus waving"
        case .reading: "Zeus reading"
        }
    }

    /// Where the middle of a pane is, as a fraction of the lane he can walk along.
    private func fraction(_ side: Side, width: CGFloat) -> Double {
        let travel = max(1, width - Self.spriteSize)
        let center: CGFloat = side == .list ? listWidth / 2 : listWidth + (width - listWidth) / 2
        return Double(min(1, max(0, (center - Self.spriteSize / 2) / travel)))
    }

    @ViewBuilder
    private func mascot(width: CGFloat) -> some View {
        let size = Self.spriteSize
        let travel = max(0, width - size)
        if reduceMotion {
            let still = driver.machine.stillFrame
            ScribeMascotSprite(pose: still.pose, elapsed: 0, size: size, facing: driver.machine.facing)
                .offset(x: CGFloat(still.x) * travel)
        } else {
            TickingView(interval: 1.0 / 12, paused: !driver.machine.isAnimating) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                let _ = driver.settleIfNeeded(at: now)
                ScribeMascotSprite(
                    pose: driver.machine.pose,
                    elapsed: max(0, now - driver.machine.modeStart),
                    size: size,
                    facing: driver.machine.facing
                )
                .offset(x: CGFloat(driver.machine.x(at: now)) * travel)
            }
        }
    }
}

/// One frame of the mascot's sprite clip, flipped to face the way he is going. Falls back to the still pose.
private struct ScribeMascotSprite: View {
    let pose: ScribeMascotPose
    let elapsed: Double
    let size: CGFloat
    /// 1 faces right, -1 faces left.
    let facing: Double
    @Environment(\.mascotRasterScale) private var mascotRasterScale

    var body: some View {
        let living = LivingPose(rawValue: pose.rawValue) ?? .idle
        let scale = MascotRasterScale.resolve(mascotRasterScale)
        let crisp = scale <= 1.01
        let sprite = MascotAtlasStore.shared.frame(living.clipID, elapsed: elapsed, points: size, pixelScale: scale)
        Group {
            if let sprite {
                Image(decorative: sprite, scale: 1)
                    .resizable().interpolation(crisp ? .none : .high).aspectRatio(contentMode: .fit)
            } else if let image = AvatarArt.image(for: living, points: size, pixelScale: scale) {
                Image(nsImage: image)
                    .resizable().interpolation(crisp ? .none : .high).aspectRatio(contentMode: .fit)
            } else {
                BoltShape().fill(Theme.bolt).padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: facing < 0 ? -1 : 1, y: 1, anchor: .center)
    }
}
