import SwiftUI
import AppKit
import ZeusCore

/// S2: rounds the two bottom corners of a notched display, which has rounded top corners and square
/// bottom ones. Two tiny black panels per notched screen, one over each bottom corner. Click-through,
/// joins every Space, shows over full-screen apps, never takes focus, and is left out of screenshots and
/// screen sharing unless "Show in screen sharing" is on. Static: no timer, no animation.
///
/// Rebuilt on every screen parameter change (resolution, arrangement, a display added or removed) and
/// when either setting changes, and removed when the setting is off. The geometry lives in
/// `ZeusCore.ScreenCorners`.
@MainActor
final class ScreenCornerOverlay {
    static let shared = ScreenCornerOverlay()

    /// One corner panel's job: which corner, and where (screen coordinates).
    private struct Placement: Equatable {
        let side: ScreenCornerSide
        let frame: CGRect
    }

    private var panels: [NSPanel] = []
    private var placements: [Placement] = []
    private var screenObserver: NSObjectProtocol?
    private var lastVisibleInShare = false

    /// Starts following the screen. Safe to call more than once.
    func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
    }

    /// Either setting changed: draw, resize or remove the corners now, no restart.
    func settingsChanged() {
        rebuild()
    }

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        for panel in panels {
            ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }

    func boostCaptureVisibility(for seconds: TimeInterval) {
        for panel in panels { panel.sharingType = .readOnly }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.applyScreenSharePolicy(visibleInShare: self.lastVisibleInShare)
        }
    }

    /// A notch shows as a top safe-area inset with a menu bar area on each side of it. The side areas are
    /// optional and can be empty, which does not count.
    private static func hasNotch(_ screen: NSScreen) -> Bool {
        ScreenCorners.hasNotch(
            safeAreaTop: Double(screen.safeAreaInsets.top),
            leftAreaWidth: Double(screen.auxiliaryTopLeftArea?.width ?? 0),
            rightAreaWidth: Double(screen.auxiliaryTopRightArea?.width ?? 0))
    }

    private func desiredPlacements() -> [Placement] {
        let store = SettingsStore.shared
        let enabled = store.bool("screen.roundBottomCorners")
        let radius = ScreenCornerSize(label: store.string("screen.cornerRadius")).radius
        var result: [Placement] = []
        for screen in NSScreen.screens where ScreenCorners.draws(hasNotch: Self.hasNotch(screen), enabled: enabled) {
            let frames = ScreenCorners.cornerFrames(screenFrame: screen.frame, radius: radius)
            for side in ScreenCornerSide.allCases {
                let frame = frames.frame(for: side)
                if !frame.isEmpty { result.append(Placement(side: side, frame: frame)) }
            }
        }
        return result
    }

    private func rebuild() {
        guard !TopBarStyle.isSnapshot else { return }
        let wanted = desiredPlacements()
        // Nothing moved: keep the panels, so a repeated screen notification never flickers the corners.
        guard wanted != placements else { return }
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels = wanted.map { placement in
            let panel = makePanel()
            panel.setFrame(placement.frame, display: false)
            panel.contentView = NSHostingView(rootView: ScreenCornerView(side: placement.side, radius: Double(placement.frame.width)))
            panel.orderFrontRegardless()
            return panel
        }
        placements = wanted
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ZeusWindowSharing.apply(to: panel, visibleInShare: lastVisibleInShare, surface: .zeusStandard)
        return panel
    }
}

/// The black fill of one corner: the square minus the quarter disc (`ScreenCorners.maskPoints`).
private struct ScreenCornerView: View {
    let side: ScreenCornerSide
    let radius: Double

    var body: some View {
        Canvas { ctx, _ in
            let points = ScreenCorners.maskPoints(side: side, radius: radius)
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            ctx.fill(path, with: .color(.black))
        }
        .frame(width: radius, height: radius)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
