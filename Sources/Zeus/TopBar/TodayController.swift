import AppKit
import EventKit
import Observation
import ZeusCore

/// The Today tab's data: today's daily note, due and overdue tasks and today's meeting notes
/// from the connected second brain (read only), plus the spoken daily brief.
@MainActor @Observable
final class TodayController {
    static let shared = TodayController()

    private(set) var summary: TodaySummary?
    private(set) var vaultName: String?
    private(set) var scanning = false
    private var scannedAt = Date.distantPast

    /// The connected brain's folder, else `~/Documents/brain` when it exists.
    var vault: URL? {
        if let source = TodoController.shared.connection?.source, source.kind.isFileBased {
            return URL(fileURLWithPath: source.path, isDirectory: true)
        }
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/brain", isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: fallback.path, isDirectory: &isDir) && isDir.boolValue ? fallback : nil
    }

    /// Scans at most once a minute unless forced; the walk runs off the main thread.
    func refresh(force: Bool = false) async {
        guard !scanning, force || Date().timeIntervalSince(scannedAt) > 60 else { return }
        guard let vault else { summary = nil; vaultName = nil; return }
        scanning = true
        let result = await Task.detached(priority: .utility) { TodayScanner.scan(vault: vault) }.value
        summary = result
        vaultName = vault.lastPathComponent
        scannedAt = Date()
        scanning = false
    }

    func seedForSnapshot(_ summary: TodaySummary, vault: String) {
        self.summary = summary; vaultName = vault; scannedAt = .distantFuture
    }

    func brief(events: [TopBarModel.CalendarItem], weather: WeatherSnapshot?) async -> String {
        await refresh()
        let today = Calendar.current
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let todays = events.filter { today.isDateInToday($0.start) }
            .map { (title: $0.title, time: $0.isAllDay ? "all day" : formatter.string(from: $0.start)) }
        let summary = summary ?? TodaySummary(day: TodoQuickAdd.dayString(Date()))
        return DailyBrief.text(summary: summary, events: todays, zeusTodos: TodoController.shared.items,
                               weather: weather.map { "It's \(Int($0.temperature.rounded())) degrees, high of \(Int($0.high.rounded()))." })
    }

    func open(_ file: String) {
        guard let vault else { return }
        let url = vault.appendingPathComponent(file)
        if vault.appendingPathComponent(".obsidian").hasDirectoryPath || FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian").path),
           var components = URLComponents(string: "obsidian://open") {
            components.queryItems = [URLQueryItem(name: "path", value: url.path)]
            if let link = components.url, NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
                NSWorkspace.shared.open(link)
                return
            }
        }
        NSWorkspace.shared.open(url)
    }
}

/// Voice and typed turns that ZEUS answers on the Mac, before any model is asked:
/// "add these to-dos: ...", "what do I have today", "give me my daily brief", "mark ... done".
@MainActor
enum LocalTurns {
    static func handle(_ transcript: String, topBar: TopBarModel?) async -> String? {
        guard let intent = TodoVoice.parse(transcript) else { return nil }
        switch intent {
        case .add(let titles):
            let todo = TodoController.shared
            let added = titles.compactMap { todo.add($0) }
            guard !added.isEmpty else { return nil }
            return added.count == 1 ? "Added \(added[0].title)." : "Added \(added.count) to-dos: \(added.map(\.title).joined(separator: ", "))."
        case .complete(let words):
            guard let item = TodoController.shared.complete(matching: words) else { return "I couldn't find a to-do called \(words)." }
            return "Done: \(item.title)."
        case .today, .brief:
            if let topBar { topBar.selectedTab = .today }
            return await TodayController.shared.brief(events: topBar?.events ?? [], weather: topBar?.weather)
        }
    }
}

/// The Reminders tab: Apple Reminders, every list, read and tick, plus quick add to the default list.
@MainActor @Observable
final class RemindersController {
    static let shared = RemindersController()

    struct Item: Identifiable, Equatable {
        let id: String
        var title: String
        var list: String
        var due: Date?
        var colorHex: UInt32
        /// EventKit does not expose Reminders' flag; high priority stands in for it.
        var flagged = false
        var hasTime = false
    }

    private(set) var items: [Item] = []
    /// False until the first fetch returns, so the page can show a loading line instead of "nothing to do".
    private(set) var loaded = false
    /// The chips on the Reminders page, and the due time picked for the next new reminder (@State is unavailable here).
    var filter: ReminderFilter = .all
    var pendingDue: ReminderQuickDue?

    var visibleItems: [Item] {
        items.filter { filter.includes(due: $0.due, flagged: $0.flagged) }
    }

    func count(for filter: ReminderFilter) -> Int {
        items.filter { filter.includes(due: $0.due, flagged: $0.flagged) }.count
    }
    private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    var draft = ""
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    var allowed: Bool { access == .fullAccess }

    func requestAccess() {
        Task { @MainActor in
            _ = try? await store.requestFullAccessToReminders()
            access = EKEventStore.authorizationStatus(for: .reminder)
            refresh()
        }
    }

    func refresh() {
        guard !seeded else { return }
        access = EKEventStore.authorizationStatus(for: .reminder)
        guard allowed else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated { RemindersController.shared.refresh() }
            }
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            let mapped = (reminders ?? []).map { reminder in
                Item(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Reminder",
                     list: reminder.calendar?.title ?? "", due: reminder.dueDateComponents?.date,
                     colorHex: Self.hex(reminder.calendar?.color),
                     flagged: (1...4).contains(reminder.priority), hasTime: reminder.dueDateComponents?.hour != nil)
            }
            .sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
            DispatchQueue.main.async { MainActor.assumeIsolated { let shared = RemindersController.shared; shared.items = mapped; shared.loaded = true } }
        }
    }

    func seedForSnapshot(_ items: [Item]) { self.items = items; loaded = true; access = .fullAccess; seeded = true }
    private var seeded = false

    func complete(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        // Only leave the list once Reminders accepted the change; otherwise it would reappear on refresh.
        guard (try? store.save(reminder, commit: true)) != nil else { return }
        items.removeAll { $0.id == id }
        ZeusSound.play(.todo)
    }

    /// Flags or unflags (high priority) a reminder.
    func toggleFlag(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.priority = (1...4).contains(reminder.priority) ? 0 : 1
        try? store.save(reminder, commit: true)
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].flagged.toggle() }
    }

    func submitDraft() {
        let parsed = ReminderDraft.parse(draft)
        guard allowed, !parsed.title.isEmpty, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = parsed.title
        reminder.calendar = list
        // A time typed in the draft ("friday at 5pm") wins; otherwise the quick form picked above the field.
        var due = parsed.due
        var hasTime = parsed.hasTime
        if due == nil, let quick = pendingDue { due = quick.date(); hasTime = true }
        if let due {
            let calendar = Calendar(identifier: .gregorian)
            reminder.dueDateComponents = calendar.dateComponents(hasTime ? [.calendar, .year, .month, .day, .hour, .minute] : [.calendar, .year, .month, .day], from: due)
            if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        guard (try? store.save(reminder, commit: true)) != nil else { return }
        draft = ""
        pendingDue = nil
        refresh()
    }

    nonisolated private static func hex(_ color: NSColor?) -> UInt32 {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return 0xFF9F0A }
        return UInt32(rgb.redComponent * 255) << 16 | UInt32(rgb.greenComponent * 255) << 8 | UInt32(rgb.blueComponent * 255)
    }
}

/// The Notifications tab: recent banners from other apps, read from Notification Center's own
/// database (needs Full Disk Access). Off until the person turns it on; nothing leaves the Mac.
@MainActor @Observable
final class NotificationsController {
    static let shared = NotificationsController()

    private(set) var items: [MirroredNotification] = []
    private(set) var failure: NotificationMirror.Failure?
    var enabled: Bool {
        didSet {
            if !TopBarStyle.isSnapshot { UserDefaults.standard.set(enabled, forKey: "notifications.mirror") }
            refresh()
        }
    }

    init() { enabled = UserDefaults.standard.bool(forKey: "notifications.mirror") }

    private var seeded = false
    func seedForSnapshot(_ items: [MirroredNotification]) { seeded = true; enabled = true; self.items = items; failure = nil }

    func refresh() {
        guard !seeded else { return }
        guard enabled else { items = []; failure = nil; return }
        let muted: Set<String> = [Bundle.main.bundleIdentifier ?? "app.zeus.mac"]
        Task.detached(priority: .utility) {
            let result = NotificationMirror.recent(limit: 40, muted: muted)
            await MainActor.run {
                switch result {
                case .success(let list):
                    // Muted apps (Settings > Notifications) stay out of the Alerts tab too.
                    let muted = NotificationPeekRules.mutedSet(SettingsStore.shared.string("notify.mutedApps"))
                    NotificationsController.shared.items = list.filter { !NotificationPeekRules.isMuted($0.app, muted: muted) }
                    NotificationsController.shared.failure = nil
                case .failure(let error): NotificationsController.shared.items = []; NotificationsController.shared.failure = error
                }
            }
        }
    }

    func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return NotificationMirror.shortName(bundleID)
    }

    func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
