import AppKit
import ApplicationServices
import SwiftUI
import ZeusCore

/// Settings > Notifications: apps whose notifications stay out of the notch, plus the mirror, quiet-originals and banner rows.
struct GSOtherAppsCards: View {
    @Bindable var notifications: NotificationsController = .shared
    private var store: SettingsStore { .shared }

    var body: some View {
        GSCard("Other apps") {
            GSToggleRow(symbol: "bell.and.waves.left.and.right", title: "Show notifications from other apps in the notch",
                        text: "Reads Notification Center on this Mac. Needs Full Disk Access; nothing leaves your Mac.",
                        isOn: Binding(get: { notifications.enabled }, set: { notifications.enabled = $0 }))
            GSDivider()
            GSToggleRow(symbol: "rectangle.topthird.inset.filled", title: "Peek new notifications under the notch",
                        text: "A slim line for about four seconds. Click it to open the app.", isOn: store.boolBinding("notify.peek"))
            GSDivider()
            GSToggleRow(symbol: "text.alignleft", title: "Show details", text: "Off shows only the app's name. Meeting mode hides details either way.",
                        isOn: store.boolBinding("notify.peekDetails"))
            if notifications.failure == .noAccess {
                GSInfo(text: "Allow Full Disk Access in Settings \u{203A} Permissions to see them.")
            }
        }
        GSCard("Quiet the originals") {
            let topApps = topNotifyingApps()
            if topApps.isEmpty {
                Text("Apps appear here after they send a notification.").font(GS.rowText).foregroundStyle(GS.secondary).padding(.vertical, 14)
            }
            ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { GSDivider() }
                GSRow(symbol: "app", title: notifications.appName(app.id), text: app.id) {
                    Button("Open in Settings") {
                        if let url = NotificationSettingsURL.url(for: app.id) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GSButtonStyle())
                }
            }
        }
        GSCard("Replace system banners (Experimental)") {
            Text("Automatically dismisses macOS system banners for selected apps after Zeus has shown the notification in the notch. Requires Accessibility.")
                .font(GS.rowText).foregroundStyle(GS.secondary).padding(.bottom, 6)
            GSToggleRow(symbol: "xmark.circle", title: "Auto-dismiss banners (Experimental)",
                        text: "Closes the Notification Center banner when Zeus displays it.",
                        isOn: Binding(
                            get: { store.bool("notify.replaceBanners") },
                            set: { value in
                                store.set("notify.replaceBanners", value ? "true" : "false")
                                BannerAutoDismisser.shared.update()
                            }
                        ))
            if store.bool("notify.replaceBanners") {
                if !AXIsProcessTrusted() {
                    GSInfo(text: "Accessibility access is required to auto-dismiss banners.")
                }
                let seenApps = Array(Set(notifications.items.map { $0.app.lowercased() })).sorted()
                let ticked = BannerDismissDecision.parseTickedApps(store.string("notify.dismissApps"))
                if seenApps.isEmpty {
                    Text("Apps will be listed here as they send notifications.").font(GS.rowText).foregroundStyle(GS.secondary).padding(.vertical, 8)
                } else {
                    Text("Auto-dismiss banners for:").font(OB.font(12, .semibold)).foregroundStyle(GS.secondary).padding(.top, 4)
                    ForEach(seenApps, id: \.self) { appID in
                        GSDivider()
                        let isTicked = ticked.contains(appID)
                        GSRow(symbol: "app.badge", title: notifications.appName(appID), text: appID) {
                            Toggle(appID, isOn: Binding(
                                get: { isTicked },
                                set: { isOn in
                                    var next = ticked
                                    if isOn { next.insert(appID) } else { next.remove(appID) }
                                    store.set("notify.dismissApps", BannerDismissDecision.formatTickedApps(next))
                                    BannerAutoDismisser.shared.update()
                                }
                            ))
                            .toggleStyle(GSToggleStyle())
                            .labelsHidden()
                        }
                    }
                }
            }
        }
        GSCard("Muted apps") {
            let muted = NotificationPeekRules.mutedSet(store.string("notify.mutedApps"))
            let seen = Set(notifications.items.map { $0.app.lowercased() })
            let ids = Array(muted.union(seen)).sorted()
            if ids.isEmpty {
                Text("Apps appear here after they send a notification.").font(GS.rowText).foregroundStyle(GS.secondary).padding(.vertical, 14)
            }
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                if index > 0 { GSDivider() }
                let isMuted = muted.contains(id)
                GSRow(symbol: "app", title: notifications.appName(id), text: id) {
                    Button(isMuted ? "Unmute" : "Mute") { toggle(id, muted: muted) }.buttonStyle(GSButtonStyle())
                }
            }
        }
    }

    private struct AppCount: Identifiable {
        let id: String
        let count: Int
    }

    private func topNotifyingApps() -> [AppCount] {
        var counts: [String: Int] = [:]
        for item in notifications.items {
            let id = item.app.lowercased()
            counts[id, default: 0] += 1
        }
        return counts.map { AppCount(id: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func toggle(_ id: String, muted: Set<String>) {
        var next = muted
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        store.set("notify.mutedApps", NotificationPeekRules.mutedText(next))
        notifications.refresh()
    }
}

/// Settings > Permissions: chats trusted from an approval card.
struct GSTrustedChatsCard: View {
    let trusted = TrustedChatStore.shared

    var body: some View {
        GSCard("Trusted chats") {
            GSRow(symbol: "checkmark.shield", title: "Chats you allowed", text: "\u{201C}Allow this whole chat\u{201D} approves a chat's requests without a card, except risky commands. Cleared when Zeus quits.") {
                if !trusted.entries.isEmpty {
                    Button("Clear all") { trusted.clear() }.buttonStyle(GSButtonStyle())
                } else {
                    GSStatus(ok: false, text: trusted.summary)
                }
            }
            ForEach(trusted.entries) { entry in
                GSDivider()
                GSRow(symbol: "bubble.left", title: entry.agent, text: MeetingState.hideDetails ? nil : entry.project) {
                    Button("Stop trusting") { trusted.revoke(session: entry.id) }.buttonStyle(GSButtonStyle())
                }
            }
        }
    }
}
