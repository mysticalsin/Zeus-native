import AppKit
import Observation
import SwiftUI
import ZeusCore

/// A small row used by the Today, Reminders and Notifications tabs.
private struct GlanceRow<Leading: View, Trailing: View>: View {
    let key: String
    let topBar: TopBarModel
    let title: String
    var detail: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        // A row with an action is one Button (focusable, Space/Return, VoiceOver press). A row without one
        // keeps its own nested controls (the tick buttons) as the focusable parts.
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(PressableStyle())
                    .accessibilityElement(children: .combine)
            } else {
                rowContent.accessibilityElement(children: .contain)
            }
        }
        .onHover { topBar.hovered = $0 ? key : (topBar.hovered == key ? nil : topBar.hovered) }
    }

    private var rowContent: some View {
        let hovered = topBar.hovered == key
        return HStack(spacing: 8) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TopBarStyle.label(11.5, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(Color.white.opacity(hovered ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(TopBarStyle.label(9, .bold)).foregroundStyle(Theme.cloudQuiet)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
    }
}

/// An empty or permission state: icon, one line, optional button.
private struct GlanceEmpty: View {
    let symbol: String
    var tint: Color = Theme.cloudSecondary
    let text: String
    var button: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            if let button {
                Button(button, action: action).buttonStyle(PressableStyle())
                    .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.storm)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.bolt))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Today

/// What you have today: events, due to-dos and tasks from your second brain, today's note.
struct TodayPage: View {
    let topBar: TopBarModel
    let today: TodayController

    private var events: [TopBarModel.CalendarItem] { topBar.events.filter { Calendar.current.isDateInToday($0.start) } }
    private var todos: [TodoItem] {
        let day = TodoQuickAdd.dayString(Date())
        return TodoController.shared.open.filter { ($0.due ?? "9999") <= day }
    }

    /// Before the first scan of a connected brain returns there is no summary yet; that is loading, not an empty day.
    private var loading: Bool { today.scanning || (today.vault != nil && today.summary == nil) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            main
            BrainTodayCard(model: .shared, connection: TodoController.shared.connection)
                .frame(width: 200)
        }
    }

    private var main: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(Self.dayTitle())
                    .font(TopBarStyle.label(13, .bold)).foregroundStyle(Theme.cloudPrimary)
                Spacer()
                if let name = today.vaultName {
                    Label(name, systemImage: "diamond.fill").labelStyle(.titleAndIcon)
                        .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet)
                }
                GlyphButton(symbol: "speaker.wave.2.fill", size: 11, tint: Theme.bolt, label: "Read my day aloud") { speakBrief() }
            }
            if events.isEmpty && todos.isEmpty && (today.summary?.isEmpty ?? true) {
                if loading {
                    GlanceEmpty(symbol: "hourglass", text: "Reading your day…")
                } else if topBar.calendarAccess == .denied {
                    GlanceEmpty(symbol: "calendar.badge.exclamationmark", tint: Theme.ember,
                                text: "Calendar is off, so events can't show here. Turn it on in Settings, Permissions.",
                                button: "Open Permissions") { topBar.openPermissions() }
                } else {
                    GlanceEmpty(symbol: "sun.max.fill", tint: Theme.bolt,
                                text: today.vault == nil ? "A clear day. Connect your notes in Settings to see their tasks here." : "A clear day. Nothing due, no events.")
                }
            } else {
                PageScroll(.vertical) {
                    VStack(spacing: 4) {
                        if !events.isEmpty {
                            SectionLabel(text: "Calendar")
                            ForEach(events) { event in
                                GlanceRow(key: "te\(event.id)", topBar: topBar, title: event.title, detail: event.location) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: event.colorHex)).frame(width: 3, height: 18)
                                } trailing: {
                                    Text(event.isAllDay ? "All day" : event.start.formatted(ZeusDates.style.hour().minute()))
                                        .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                                }
                            }
                        }
                        let tasks = today.summary?.tasks ?? []
                        if !todos.isEmpty || !tasks.isEmpty {
                            SectionLabel(text: "To do")
                            ForEach(todos) { item in
                                GlanceRow(key: "tt\(item.id)", topBar: topBar, title: item.title) {
                                    Button { TodoController.shared.toggle(item.id) } label: {
                                        Image(systemName: "circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                                    }.buttonStyle(PressableStyle()).accessibilityLabel("Mark done")
                                } trailing: { if let due = item.due { DueChip(due: due, done: false) } }
                            }
                            ForEach(tasks) { task in
                                GlanceRow(key: "tb\(task.id)", topBar: topBar, title: task.title,
                                          detail: (task.file as NSString).deletingPathExtension, action: { today.open(task.file) }) {
                                    Image(systemName: "diamond").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                                } trailing: { if let due = task.due { DueChip(due: due, done: false) } }
                            }
                        }
                        let notes = (today.summary?.dailyNote.map { [TodayNote(title: "Today's note", file: $0)] } ?? []) + (today.summary?.meetings ?? [])
                        if !notes.isEmpty {
                            SectionLabel(text: "Notes")
                            ForEach(notes) { note in
                                GlanceRow(key: "tn\(note.id)", topBar: topBar, title: note.title, detail: note.file, action: { today.open(note.file) }) {
                                    Image(systemName: "doc.text").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudSecondary)
                                } trailing: { EmptyView() }
                            }
                        }
                    }
                }
            }
        }
        .task { await today.refresh() }
    }

    /// Always the Gregorian calendar, like the rest of ZEUS's dates.
    static func dayTitle(_ date: Date = Date()) -> String {
        ZeusDates.string(date, template: "EEEEdMMMM")
    }

    private func speakBrief() {
        Task { @MainActor in
            let text = await today.brief(events: topBar.events, weather: topBar.weather)
            topBar.speakBrief(text)
        }
    }
}

// MARK: Reminders

struct RemindersPage: View {
    let topBar: TopBarModel
    @Bindable var reminders: RemindersController

    var body: some View {
        Group {
            if !reminders.allowed {
                GlanceEmpty(symbol: "list.bullet.circle.fill", tint: Theme.ember,
                            text: reminders.access == .notDetermined ? "See and tick off your Apple Reminders here." : "ZEUS can't see Reminders. Turn it on in System Settings, Privacy, Reminders.",
                            button: reminders.access == .notDetermined ? "Allow Reminders" : "Open Settings") {
                    topBar.openPermissions()
                }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(ReminderFilter.allCases) { filter in
                            ReminderChip(title: filter.rawValue, count: reminders.count(for: filter), selected: reminders.filter == filter) { reminders.filter = filter }
                        }
                        Spacer(minLength: 6)
                        ForEach(ReminderQuickDue.allCases) { quick in
                            ReminderChip(title: quick.rawValue, count: nil, selected: reminders.pendingDue == quick, tint: Theme.glow) {
                                reminders.pendingDue = reminders.pendingDue == quick ? nil : quick
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        if TopBarStyle.isSnapshot {
                            Text("New reminder. Try \"pay rent friday at 5pm\"").font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudQuiet)
                            Spacer()
                        } else {
                            TextField("New reminder. Try \"pay rent friday at 5pm\"", text: $reminders.draft)
                                .textFieldStyle(.plain).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudPrimary)
                                .onSubmit { reminders.submitDraft() }
                        }
                        if let quick = reminders.pendingDue {
                            Text("Due \(quick.rawValue.lowercased())").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.glow)
                        }
                    }
                    .frame(height: 30).padding(.horizontal, 10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(TopBarStyle.tileStroke))
                    if reminders.visibleItems.isEmpty {
                        GlanceEmpty(symbol: "checkmark.circle", tint: Theme.leaf, text: !reminders.loaded ? "Loading reminders…" : reminders.items.isEmpty ? "Nothing to do" : "Nothing in \(reminders.filter.rawValue)")
                    } else {
                        PageScroll(.vertical) {
                            VStack(spacing: 4) {
                                ForEach(reminders.visibleItems) { item in
                                    GlanceRow(key: "r\(item.id)", topBar: topBar, title: item.title, detail: item.list) {
                                        Button { reminders.complete(item.id) } label: {
                                            Image(systemName: "circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: item.colorHex))
                                        }.buttonStyle(PressableStyle()).accessibilityLabel("Complete \(item.title)")
                                    } trailing: {
                                        HStack(spacing: 6) {
                                            if item.flagged { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(Theme.ember).accessibilityLabel("Flagged") }
                                            if let due = item.due { DueChip(due: TodoQuickAdd.dayString(due), done: false, time: item.hasTime ? due : nil) }
                                            if topBar.hovered == "r\(item.id)" {
                                                GlyphButton(symbol: item.flagged ? "flag.slash" : "flag", size: 10, tint: Theme.cloudSecondary, label: item.flagged ? "Unflag" : "Flag") {
                                                    reminders.toggleFlag(item.id)
                                                }
                                            }
                                        }
                                    }
                                    // The Flag button only exists while hovered; keep it reachable without a pointer.
                                    .accessibilityAction(named: item.flagged ? "Unflag" : "Flag") { reminders.toggleFlag(item.id) }
                                    .contextMenu {
                                        Button(item.flagged ? "Unflag" : "Flag") { reminders.toggleFlag(item.id) }
                                        Button("Complete") { reminders.complete(item.id) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { reminders.refresh() }
    }
}

// MARK: Notifications

struct NotificationsPage: View {
    let topBar: TopBarModel
    @Bindable var notifications: NotificationsController

    var body: some View {
        Group {
            if !notifications.enabled {
                GlanceEmpty(symbol: "bell.badge.fill", tint: Theme.bolt,
                            text: "Keep your recent notifications here, read straight from Notification Center on this Mac.",
                            button: "Show notifications") { notifications.enabled = true }
            } else if notifications.failure == .noAccess {
                // Glance Alerts empty (parity/tabs/glance-empty-alerts): left ornament + FDA card.
                GlanceSplitEmpty(
                    leftTitle: "Alerts",
                    left: AnyView(
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 54, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .symbolRenderingMode(.hierarchical)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ),
                    title: "Allow Full Disk Access",
                    detail: "Turn on ZEUS in Full Disk Access, then relaunch the app so macOS applies the permission.",
                    primary: "Open Full Disk Access",
                    primaryAction: { notifications.openFullDiskAccess() },
                    secondary: "Try again",
                    secondaryAction: { notifications.refresh() }
                )
            } else if notifications.items.isEmpty {
                GlanceEmpty(symbol: "bell.slash", text: notifications.failure == nil ? "No recent notifications" : "Notification Center's history couldn't be read.")
            } else {
                PageScroll(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(notifications.items) { item in
                            GlanceRow(key: "n\(item.id)", topBar: topBar, title: item.title.isEmpty ? notifications.appName(item.app) : item.title,
                                      detail: [item.subtitle, item.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                      action: { notifications.openApp(item.app) }) {
                                if let icon = notifications.icon(item.app) {
                                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "app.fill").font(.system(size: 14)).foregroundStyle(Theme.cloudSecondary)
                                }
                            } trailing: {
                                Text(item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { notifications.refresh() }
        .task(id: notifications.enabled) {
            // Fresh while the tab is open; stops when it closes.
            while notifications.enabled, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                notifications.refresh()
            }
        }
    }
}


/// A small capsule chip: a filter (with its count) or a quick due time.
struct ReminderChip: View {
    let title: String
    let count: Int?
    let selected: Bool
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let count, count > 0 { Text("\(count)").foregroundStyle(Theme.cloudQuiet) }
            }
            .font(TopBarStyle.label(10.5, .semibold))
            .foregroundStyle(selected ? Color.white : Theme.cloudSecondary)
            .padding(.horizontal, 9).frame(height: 24)
            .background(Capsule().fill(selected ? tint.opacity(tint == .white ? 0.16 : 0.35) : Color.white.opacity(0.06)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
