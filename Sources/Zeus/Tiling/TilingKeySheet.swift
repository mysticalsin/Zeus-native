import AppKit
import SwiftUI
import ZeusCore

/// A small card that lists the tiling keys, shown when the owner asks for it and gone after a few seconds.
///
/// One panel: click-through, non-activating, never key or main, on every Space, at the status-bar level. It is
/// built from the same key table the tap matches. It exists only while it is showing. It follows the screen share
/// policy like every other Zeus overlay, and `ZeusWindowSharing.refresh` reaches it.
@MainActor
final class TilingKeySheet {
    static let shared = TilingKeySheet()

    static let width: CGFloat = 380
    static let rowHeight: CGFloat = 24
    static let chrome: CGFloat = 62

    private var panel: NSPanel?
    private var lastVisibleInShare = false

    /// The panel while it is showing; empty otherwise. For tests.
    var ownedWindows: [NSWindow] { panel.map { [$0] } ?? [] }

    /// Shows `rows` centred on `display`, or on the main screen when there is none. An empty list shows nothing.
    func show(rows: [TileKeyRow], on display: TileDisplay?) {
        guard !TopBarStyle.isSnapshot, !rows.isEmpty, !NSScreen.screens.isEmpty else {
            hide()
            return
        }
        let screen = display.map { CGRect(x: $0.appKitFrame.x, y: $0.appKitFrame.y, width: $0.appKitFrame.width, height: $0.appKitFrame.height) }
            ?? NSScreen.main?.frame ?? .zero
        let size = CGSize(width: Self.width, height: Self.chrome + CGFloat(rows.count) * Self.rowHeight)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: TilingKeySheetView(rows: rows))
        panel.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    func applyScreenSharePolicy(visibleInShare: Bool) {
        lastVisibleInShare = visibleInShare
        if let panel { ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard) }
    }

    /// For `zeus debug animate`: shown to capture for a moment, then back to the policy.
    func boostCaptureVisibility(for seconds: TimeInterval) {
        panel?.sharingType = .readOnly
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyScreenSharePolicy(visibleInShare: self.lastVisibleInShare)
            }
        }
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

private struct TilingKeySheetView: View {
    let rows: [TileKeyRow]

    var body: some View {
        let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        VStack(alignment: .leading, spacing: 0) {
            Text("Tiling keys")
                .font(TopBarStyle.label(13, .bold)).foregroundStyle(Theme.cloudPrimary)
                .padding(.bottom, 10)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.title).font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary)
                    Spacer(minLength: 8)
                    Text(row.keys).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                }
                .frame(height: TilingKeySheet.rowHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.title)
                .accessibilityValue(row.spoken)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(width: TilingKeySheet.width, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(solid ? AnyShapeStyle(Theme.storm) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.storm.opacity(solid ? 0 : 0.55)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}
