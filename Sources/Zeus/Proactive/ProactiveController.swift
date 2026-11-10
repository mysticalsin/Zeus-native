import AppKit
import EventKit
import Intents
import Observation
import SwiftUI
import UserNotifications
import ZeusCore

/// Proactive settings. Both start off: turning one on is when ZEUS asks for permission.
@MainActor
@Observable
final class ProactiveSettings {
    static let shared = ProactiveSettings()
    private let defaults = UserDefaults.standard

    var morningBrief: Bool { didSet { defaults.set(morningBrief, forKey: "proactive.brief") } }
    var dueNudges: Bool { didSet { defaults.set(dueNudges, forKey: "proactive.nudges") } }
    var problem: String?

    private init() {
        morningBrief = defaults.bool(forKey: "proactive.brief")
        dueNudges = defaults.bool(forKey: "proactive.nudges")
    }
}

/// The morning brief at the first unlock of the day, and system notifications when a to-do
/// is due. Event driven only: unlock, wake and calendar-change notifications, plus nudges
/// scheduled ahead with the system. Nothing polls.
@MainActor
final class ProactiveController {
    static let shared = ProactiveController()

    private let store = EKEventStore()
    private let settings = ProactiveSettings.shared
    private var observers: [NSObjectProtocol] = []
    private var gate = FirstUnlockGate(lastShownDay: UserDefaults.standard.string(forKey: "proactive.lastBrief"))
    private let card = BriefCardWindow()

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ProactiveController.shared.unlocked() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ProactiveController.shared.unlocked() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { ProactiveController.shared.rescheduleNudges() }
        })
        rescheduleNudges()
    }

    // MARK: Settings actions (permission is asked here, never before)

    func setMorningBrief(_ on: Bool) {
        settings.problem = nil
        settings.morningBrief = on
        guard on else { return }
        Task {
            let granted = await requestCalendar()
            if !granted {
                // Without Calendars the brief would run with no events, so it stays off until allowed.
                settings.morningBrief = false
                settings.problem = Self.calendarProblem
            }
            // So the card can stay away during Focus. If macOS declines, full screen is still respected.
            if INFocusStatusCenter.default.authorizationStatus == .notDetermined {
                INFocusStatusCenter.default.requestAuthorization { _ in }
            }
        }
    }

    func setDueNudges(_ on: Bool) {
        settings.problem = nil
        settings.dueNudges = on
        guard on else {
            removeAllNudges()
            return
        }
        Task {
            let reminders = (try? await store.requestFullAccessToReminders()) ?? false
            let notifications = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            if !reminders || !notifications { settings.problem = Self.nudgeProblem }
            rescheduleNudges()
        }
    }

    private static let calendarProblem = "Allow Calendars for ZEUS in System Settings › Privacy & Security to see your day, then turn the morning brief on again."
    private static let nudgeProblem = "Allow Reminders and Notifications for ZEUS to get nudges when a to-do is due."

    /// Clears a stale message once the permission was granted in System Settings. Called when the
    /// settings appear and at unlock; it never asks for anything.
    func refreshProblem() {
        guard settings.problem != nil else { return }
        let calendarMissing = settings.morningBrief && EKEventStore.authorizationStatus(for: .event) != .fullAccess
        let remindersMissing = settings.dueNudges && EKEventStore.authorizationStatus(for: .reminder) != .fullAccess
        // Notification authorization is only readable asynchronously.
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            let notificationsMissing = settings.dueNudges && status != .authorized && status != .provisional
            if calendarMissing { settings.problem = Self.calendarProblem }
            else if remindersMissing || notificationsMissing { settings.problem = Self.nudgeProblem }
            else { settings.problem = nil }
        }
    }

    /// Shows today's brief now, for Settings › Preview.
    func previewBrief() {
        Task { await presentBrief(force: true) }
    }

    // MARK: Events

    private func unlocked() {
        refreshProblem()
        rescheduleNudges()
        guard settings.morningBrief, gate.shouldShow(at: Date()) else { return }
        Task { await presentBrief(force: false) }
    }

    private func presentBrief(force: Bool) async {
        let fullScreen = FullScreenDetector.frontAppIsFullScreen()
        let focused = INFocusStatusCenter.default.authorizationStatus == .authorized
            && INFocusStatusCenter.default.focusStatus.isFocused == true
        // Held back, not lost: the next unlock today tries again.
        guard force || ProactiveQuiet.allowsCard(fullScreen: fullScreen, focusActive: focused) else { return }
        let now = Date()
        let brief = MorningBrief.build(now: now, events: todayEvents(now: now), todos: await todos(),
                                       name: UserDefaults.standard.string(forKey: "aboutYou.name") ?? NSFullUserName())
        if !force {
            gate.markShown(at: now)
            UserDefaults.standard.set(gate.lastShownDay, forKey: "proactive.lastBrief")
        }
        card.show(brief)
    }

    // MARK: EventKit

    private func requestCalendar() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    private func todayEvents(now: Date) -> [BriefEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            let text = [event.location, event.notes, event.url?.absoluteString].compactMap { $0 }.joined(separator: " ").lowercased()
            let call = ["zoom.us", "meet.google", "teams.microsoft", "facetime", "webex"].contains { text.contains($0) }
            return BriefEvent(title: event.title ?? "Event", start: event.startDate, end: event.endDate,
                              isAllDay: event.isAllDay, hasCall: call)
        }
    }

    /// Open reminders with a due date; ZEUS's own to-do list can feed the same shape later.
    private func todos() async -> [BriefTodo] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let end = Date().addingTimeInterval(3 * 86_400)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let items: [(String, String, DateComponents?)] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { ($0.calendarItemIdentifier, $0.title ?? "To-do", $0.dueDateComponents) })
            }
        }
        return items.compactMap { id, title, components in
            guard let components, let date = Calendar.current.date(from: components) else { return nil }
            return BriefTodo(id: id, title: title, due: date, dateOnly: components.hour == nil)
        }
    }

    // MARK: Nudges

    func rescheduleNudges() {
        guard settings.dueNudges else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let planned = DueNudge.plan(await todos(), now: Date())
            let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
            let diff = DueNudge.diff(planned: planned, scheduled: pending)
            center.removePendingNotificationRequests(withIdentifiers: diff.remove)
            for nudge in diff.add {
                let content = UNMutableNotificationContent()
                content.title = nudge.title
                content.body = nudge.body
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nudge.fireDate)
                let request = UNNotificationRequest(identifier: nudge.id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try? await center.add(request)
            }
        }
    }

    private func removeAllNudges() {
        Task {
            let center = UNUserNotificationCenter.current()
            let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(DueNudge.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }
}

/// Settings › General › Proactive.
struct ProactiveSettingsSection: View {
    let settings = ProactiveSettings.shared

    var body: some View {
        Section("Proactive") {
            Toggle("Morning brief at the first unlock of the day",
                   isOn: Binding(get: { settings.morningBrief }, set: { ProactiveController.shared.setMorningBrief($0) }))
            Toggle("Notify me when a to-do is due",
                   isOn: Binding(get: { settings.dueNudges }, set: { ProactiveController.shared.setDueNudges($0) }))
            Button("Show Today's Brief") { ProactiveController.shared.previewBrief() }
            if let problem = settings.problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            } else {
                Text("Uses your calendar and reminders on this Mac. Nothing appears while an app is full screen or during Focus.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { ProactiveController.shared.refreshProblem() }
    }
}
