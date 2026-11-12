import AppKit
import SwiftUI
import ZeusCore

/// The Alerts tab's list: one stack per app (newest first), real app icons, relative times in monospaced
/// digits, hover actions, and a Clear all that collapses the stacks. Notification Center is never modified.
struct AlertsGroupedList: View {
    @Bindable var notifications: NotificationsController
    @State private var expandedOverride: [String: Bool] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [AlertGroup] {
        AlertGrouping.groups(notifications.visibleItems) { notifications.appName($0) }
    }

    private var spring: Animation? { reduceMotion ? .easeInOut(duration: AlertMotion.reducedFade) : .spring(response: 0.36, dampingFraction: 0.82) }

    private func isExpanded(_ group: AlertGroup, index: Int) -> Bool { expandedOverride[group.id] ?? (index == 0) }

    var body: some View {
        let groups = self.groups
        VStack(spacing: 6) {
            HStack {
                Text(summary(groups)).font(TopBarStyle.label(10.5, .medium).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                Spacer()
                Button { withAnimation(spring) { notifications.clearAll() } } label: {
                    Label("Clear all", systemImage: "xmark")
                        .font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Hides every alert here. Notification Center is not changed.")
            }
            PageScroll(.vertical) {
                VStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        AlertGroupStack(group: group, expanded: isExpanded(group, index: index), notifications: notifications,
                                        spring: spring) {
                            withAnimation(spring) { expandedOverride[group.id] = !isExpanded(group, index: index) }
                        }
                        .transition(removal(delay: 0.04 * Double(index)))
                    }
                }
            }
        }
    }

    private func summary(_ groups: [AlertGroup]) -> String {
        let count = groups.reduce(0) { $0 + $1.items.count }
        return "\(count) \(count == 1 ? "alert" : "alerts") from \(groups.count) \(groups.count == 1 ? "app" : "apps")"
    }

    /// Clear all: stacks fold up toward the header one after another.
    private func removal(delay: Double) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
            .animation(.spring(response: 0.36, dampingFraction: 0.82).delay(delay))
    }
}

struct AlertGroupStack: View {
    let group: AlertGroup
    let expanded: Bool
    let notifications: NotificationsController
    let spring: Animation?
    let toggle: () -> Void

    var body: some View {
        let accent = AppIconCache.shared.entry(for: group.appID).accent
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    AlertAppIcon(bundleID: group.appID, size: 22)
                    Text(group.appName).font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                    Text("\(group.items.count)").font(TopBarStyle.label(10, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.cloudPrimary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(accent.opacity(0.28)))
                    if !expanded, let first = group.items.first {
                        Text(Self.line(first)).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.cloudQuiet)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 10).frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(group.appName), \(group.items.count) alerts")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides this app's alerts.")
            if expanded {
                VStack(spacing: 2) {
                    ForEach(group.items) { item in
                        AlertRow(item: item, notifications: notifications)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .animation(spring, value: group.items.map(\.id))
    }

    static func line(_ item: MirroredNotification) -> String {
        let title = item.title.isEmpty ? item.body : item.title
        return item.title.isEmpty || item.body.isEmpty ? title : "\(item.title): \(item.body)"
    }
}

struct AlertRow: View {
    let item: MirroredNotification
    let notifications: NotificationsController
    @State private var hovered = false
    @State private var drag: CGFloat = 0

    var body: some View {
        let detail = [item.subtitle, item.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        let title = item.title.isEmpty ? notifications.appName(item.app) : item.title
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TopBarStyle.label(11.5, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if hovered {
                AlertActionButton(title: "Open", symbol: "arrow.up.forward.app.fill", tint: nil) { notifications.openApp(item.app) }
                AlertActionButton(title: "Clear", symbol: "xmark", tint: nil) { withAnimation { notifications.clear(item.id) } }
            } else {
                AlertRelativeTimeText(date: item.date)
            }
        }
        .padding(.leading, 40).padding(.trailing, 8)
        .frame(minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovered ? 0.08 : 0)))
        .contentShape(Rectangle())
        .offset(x: drag)
        .onHover { hovered = $0 }
        .gesture(DragGesture(minimumDistance: 16)
            .onChanged { drag = min(0, $0.translation.width) }
            .onEnded { value in
                if value.translation.width < -80 { withAnimation { notifications.clear(item.id) } }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
            })
        .onTapGesture { notifications.openApp(item.app) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail). \(AlertRelativeTime.text(from: item.date, now: Date()))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { notifications.openApp(item.app) }
        .accessibilityAction(named: "Clear") { notifications.clear(item.id) }
    }
}

/// The relative time as static text in a fixed-width monospaced-digit column. It re-renders when the page
/// refreshes its list (every 15 s while the tab is open); it owns no timer.
private struct AlertRelativeTimeText: View {
    let date: Date
    var body: some View {
        Text(AlertRelativeTime.text(from: date, now: Date()))
            .font(TopBarStyle.label(10, .medium).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
            .frame(minWidth: 34, alignment: .trailing)
    }
}

/// Nothing to show: the idle mascot and one line. Static, no animation.
struct AlertsAllClear: View {
    var body: some View {
        VStack(spacing: 8) {
            AvatarView(state: .idle, size: 56, animated: false)
                .accessibilityHidden(true)
            Text("All clear").font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary)
            Text("New alerts land here.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
