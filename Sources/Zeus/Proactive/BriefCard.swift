import AppKit
import SwiftUI
import ZeusCore

/// The morning brief as a Glance-glass card just under the notch. It goes away by itself
/// after half a minute, on Esc, or with Dismiss.
@MainActor
final class BriefCardWindow {
    private var panel: BriefPanel?
    private var dismissal: DispatchWorkItem?

    func show(_ brief: MorningBrief) {
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: BriefCardView(brief: brief, dismiss: { [weak self] in self?.hide() }))
        let size = panel.contentView?.fittingSize ?? CGSize(width: 420, height: 220)
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        if let screen {
            let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) - 8
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: "\(brief.greeting). \(brief.summary)",
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
        // One-shot, only while the card is up.
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        self.panel = panel
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func makePanel() -> BriefPanel {
        let panel = BriefPanel(contentRect: CGRect(x: 0, y: 0, width: 420, height: 220),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onEscape = { [weak self] in self?.hide() }
        return panel
    }
}

final class BriefPanel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

struct BriefCardView: View {
    let brief: MorningBrief
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill").foregroundStyle(Theme.bolt).font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
                Text(brief.greeting).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cloudQuiet)
                        .frame(width: 22, height: 22).contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Dismiss brief")
                .keyboardShortcut(.cancelAction)
            }
            Text(brief.summary).font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary)
            if !brief.events.isEmpty {
                Tile(padding: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(brief.events.enumerated()), id: \.offset) { _, event in
                            HStack(spacing: 8) {
                                Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                                    .font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.sky)
                                    .frame(width: 58, alignment: .leading)
                                Text(event.title).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                                if event.hasCall {
                                    Image(systemName: "video.fill").font(.system(size: 9)).foregroundStyle(Theme.cloudQuiet)
                                        .accessibilityLabel("with a call")
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !brief.dueToday.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(brief.dueToday) { todo in
                        Label(todo.title, systemImage: "circle").font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudPrimary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Due today: " + brief.dueToday.map(\.title).joined(separator: ", "))
            }
        }
        .padding(16)
        .frame(width: 420)
        .alertGlass(radius: Theme.panelRadius + 6)
        .preferredColorScheme(.dark)
    }
}
