import AppKit
import EventKit
import Observation
import ZeusCore

/// The notch to-do list: add, check, reorder and due dates, two-way with a note in your
/// second brain (read-write connections only), `zeus todo` from the terminal, voice quick-add,
/// and an optional mirror into Apple Reminders.
@MainActor @Observable
final class TodoController {
    static let shared = TodoController()

    private(set) var sync: TodoSync
    var draft = ""
    var listening = false
    var voicePartial = ""
    /// Why the mic could not start; shown beside the input even while a draft is typed.
    var voiceError: String?
    var showDone = false
    /// Bumped to ask the input field to take focus (quick to-do shortcut).
    private(set) var focusRequest = 0
    /// Celebrates via the living mascot when a to-do is finished.
    var onCompleted: (() -> Void)?
    var remindersMirror: Bool {
        didSet { if !TopBarStyle.isSnapshot { UserDefaults.standard.set(remindersMirror, forKey: "todo.reminders") }; if remindersMirror { askReminders() } }
    }
    var learningEnabled: Bool {
        get { learningStore.learning.enabled }
        set {
            learningStore.learning.enabled = newValue
            if !TopBarStyle.isSnapshot { UserDefaults.standard.set(newValue, forKey: "todo.learning") }
            persistLearning()
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var speech: SpeechInput?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var reminderIDs: [String: String]
    /// Reminders whose deletion failed or had to wait for access; retried by the timer.
    @ObservationIgnored private var pendingReminderDeletes: [String]
    @ObservationIgnored private var learningStore: TodoLearningStore

    var items: [TodoItem] { sync.list.items }
    var open: [TodoItem] { sync.list.open }
    var visible: [TodoItem] {
        let base = showDone ? items : open
        return learningEnabled ? learningStore.learning.rank(base) : base
    }
    var suggestions: [TodoLearning.Suggestion] {
        guard learningEnabled else { return [] }
        var out: [TodoLearning.Suggestion] = []
        if !draft.isEmpty {
            if let split = learningStore.learning.suggestSplit(draft) { out.append(split) }
            let title = TodoQuickAdd.parse(draft).title
            if let due = learningStore.learning.suggestDue(for: title) { out.append(due) }
        }
        out.append(contentsOf: learningStore.learning.recurringSuggestions(openTitles: open.map(\.title)))
        return out
    }
    var connection: BrainConnection? { sync.connection }
    var noteName: String? { sync.noteURL()?.lastPathComponent }
    var overdueCount: Int {
        let today = TodoQuickAdd.dayString(Date())
        return open.filter { ($0.due ?? "9999") < today }.count
    }

    /// Lights the notch when a reminder lands in Apple Reminders.
    var onReminderSaved: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        let connection = defaults.data(forKey: "todo.connection").flatMap { try? JSONDecoder().decode(BrainConnection.self, from: $0) }
        sync = TodoSync(storeFile: ZeusPaths.supportDirectory.appendingPathComponent("todos.json"), connection: connection)
        remindersMirror = defaults.bool(forKey: "todo.reminders")
        reminderIDs = defaults.dictionary(forKey: "todo.reminderIDs") as? [String: String] ?? [:]
        pendingReminderDeletes = defaults.stringArray(forKey: "todo.reminderPendingDeletes") ?? []
        learningStore = TodoLearningStore.load(file: ZeusPaths.supportDirectory.appendingPathComponent("todo-learning.json"))
        if defaults.object(forKey: "todo.learning") != nil {
            learningStore.learning.enabled = defaults.bool(forKey: "todo.learning")
        }
    }

    func start() {
        sync.pull()
        publishSyncState()
        retryPendingDeletes()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retryPendingDeletes()
                guard self.sync.noteMayHaveChanged() else { return }
                _ = self.sync.pull()
                self.publishSyncState()
            }
        }
    }

    /// What the timer's pull could not do (read the note, save ZEUS's copy), shown with the other warnings.
    private(set) var pullNotice: String?

    /// Copies the sync's own error into the notice the page shows. A pending save keeps being retried by the timer.
    private func publishSyncState() {
        let next = sync.syncError ?? (sync.pendingSave ? sync.saveError : nil)
        if next != pullNotice { pullNotice = next }
    }

    /// The one line the To-do page shows above the list: a failed save, a failed pull, or the launch notice.
    var warning: String? { saveError ?? pullNotice ?? loadNotice }

    /// Snapshots only: a fixed list, nothing saved.
    func seedForSnapshot(_ items: [TodoItem], connection: BrainConnection?) {
        sync = TodoSync(storeFile: URL(fileURLWithPath: "/dev/null/none"), connection: nil)
        sync.list = TodoList(items: items)
        sync.connection = connection
        learningStore = TodoLearningStore(file: URL(fileURLWithPath: "/dev/null/learning"))
    }

    func connect(_ connection: BrainConnection?) {
        sync.connection = connection
        if !TopBarStyle.isSnapshot {
            UserDefaults.standard.set(connection.flatMap { try? JSONEncoder().encode($0) }, forKey: "todo.connection")
        }
        if !sync.pull() { save() }
        publishSyncState()
    }

    func requestFocus() { focusRequest += 1 }

    // MARK: Edits

    @discardableResult
    func add(_ text: String) -> TodoItem? {
        let parsed = TodoQuickAdd.parse(text)
        // A learned habit is a suggestion the person can accept. It is not a due date they did not say.
        // Auto-applying one is how "buy milk" was saved as 0784-06-02 (a poisoned offset from the Persian calendar).
        let due = parsed.due
        guard let item = sync.list.add(parsed.title, due: due) else { return nil }
        learningStore.learning.observeAdd(item.title, due: item.due)
        persistLearning()
        save()
        mirrorAdd(item)
        return item
    }

    func applySuggestion(_ suggestion: TodoLearning.Suggestion) {
        switch suggestion.kind {
        case "split":
            for part in suggestion.split { _ = add(part) }
            draft = ""
        case "due":
            if draft.isEmpty { draft = suggestion.title }
            if let due = suggestion.due, let item = add(draft) {
                sync.list.setDue(item.id, due)
                save()
                draft = ""
            } else {
                _ = add(draft.isEmpty ? suggestion.title : draft)
                draft = ""
            }
        case "recurring":
            _ = add(suggestion.due.map { "\(suggestion.title) due \($0)" } ?? suggestion.title)
        default:
            _ = add(suggestion.title)
        }
    }

    func clearLearning() {
        learningStore.learning.clear()
        persistLearning()
    }

    func reason(for item: TodoItem) -> String? {
        learningStore.learning.rankReason(for: item)
    }

    func submitDraft() {
        if add(draft) != nil { draft = "" }
    }

    /// "call Ana tomorrow, send the invoice Friday and book the dentist": one to-do per part,
    /// each with its own due day. A leading "add these to-dos" is optional here.
    @discardableResult
    func addSpoken(_ text: String) -> [TodoItem] {
        let parts: [String]
        if case .add(let items)? = TodoVoice.parse(text) { parts = items } else { parts = TodoVoice.split(text) }
        return parts.compactMap { add($0) }
    }

    /// Ticks the first open to-do whose title contains `words` (case and accent blind).
    func complete(matching words: String) -> TodoItem? {
        let needle = words.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard let item = open.first(where: { $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle) }) else { return nil }
        toggle(item.id)
        return item
    }

    func toggle(_ id: UUID) {
        sync.list.toggle(id)
        if let item = items.first(where: { $0.id == id }) {
            if item.done {
                ZeusSound.play(.todo)
                learningStore.learning.observeDone(item.title)
                persistLearning()
                onCompleted?()
            }
            mirrorDone(item)
        }
        save()
    }

    func remove(_ id: UUID) {
        mirrorRemove(id)
        sync.list.remove(id)
        save()
    }
    func move(_ id: UUID, by delta: Int) { sync.list.move(id, by: delta); save() }

    /// Cycles the due date: none, today, tomorrow, next week, none.
    func cycleDue(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let calendar = Calendar(identifier: .gregorian)
        let days = [0, 1, 7].map { TodoQuickAdd.dayString(calendar.date(byAdding: .day, value: $0, to: Date())!) }
        let previous = item.due
        let next: String? = switch item.due {
        case nil: days[0]
        case days[0]: days[1]
        case days[1]: days[2]
        default: nil
        }
        if let previous, let next, next > previous {
            learningStore.learning.observePushBack(item.title, from: previous, to: next)
            persistLearning()
        }
        sync.list.setDue(id, next)
        save()
    }

    private func persistLearning() {
        guard !TopBarStyle.isSnapshot else { return }
        learningStore.save()
    }

    func clearDone() {
        for item in items where item.done {
            mirrorRemove(item.id)
            sync.list.remove(item.id)
        }
        save()
    }

    /// Why the last save failed (shown on the To-do page); nil after a good save.
    private(set) var saveError: String?
    /// Set at launch when todos.json was unreadable and was moved aside.
    var loadNotice: String? { sync.loadNotice }

    private func save() {
        guard !TopBarStyle.isSnapshot else { return }
        do {
            try sync.commit()
            saveError = nil
        } catch {
            saveError = sync.saveError ?? sync.syncError ?? "Your to-dos could not be saved to the note: \(error.localizedDescription)"
            NSLog("[ZEUS] todo: save failed: %@", error.localizedDescription)
        }
        publishSyncState()
    }

    // MARK: Voice quick-add

    func toggleVoice() {
        voiceError = nil
        if listening {
            listening = false
            let input = speech
            Task { @MainActor in
                let text = await input?.stop() ?? ""
                self.voicePartial = ""
                if !text.isEmpty { self.addSpoken(text) }
            }
            return
        }
        let input = SpeechInput()
        input.onPartial = { text in DispatchQueue.main.async { MainActor.assumeIsolated { TodoController.shared.voicePartial = text } } }
        do {
            try input.start()
            speech = input
            listening = true
            // Never leave the microphone open if nobody presses stop: add what was heard after a minute.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(TodoController.voiceLimitSeconds))
                guard let self, self.listening, self.speech === input else { return }
                self.toggleVoice()
            }
        } catch {
            voiceError = "Allow the microphone and speech recognition in Settings, Permissions."
        }
    }

    /// Longest a spoken to-do may listen before it is added on its own.
    static let voiceLimitSeconds = 60

    /// Ends a spoken to-do when its page goes away (the bar closed or another page opened): what was heard is
    /// added and the microphone is released.
    func endVoice() {
        if listening { toggleVoice() }
    }

    // MARK: Terminal

    func handleCLI(_ text: String, id: String) -> ZeusCommandReply {
        let words = text.split(separator: " ", maxSplits: 1).map(String.init)
        if words.first == "add", words.count == 2 {
            let added = addSpoken(words[1])
            if !added.isEmpty {
                let lines = added.map { "Added: \($0.title)\($0.due.map { " (due \($0))" } ?? "")" }
                return ZeusCommandReply(id: id, ok: true, text: lines.joined(separator: "\n"))
            }
        }
        if words.first == "list" {
            let lines = open.enumerated().map { "\($0.offset + 1). \($0.element.title)\($0.element.due.map { "  📅 \($0)" } ?? "")" }
            return ZeusCommandReply(id: id, ok: true, text: lines.isEmpty ? "Nothing to do." : lines.joined(separator: "\n"))
        }
        // `done` ticks a to-do off, `remove` deletes it; the target is a number from `zeus todo list`
        // or words from its title.
        if let verb = words.first, verb == "done" || verb == "remove", words.count == 2 {
            let target = words[1].trimmingCharacters(in: .whitespaces)
            let item: TodoItem? = Int(target).flatMap { $0 >= 1 && $0 <= open.count ? open[$0 - 1] : nil }
                ?? open.first { $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    .contains(target.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
            guard let item else { return ZeusCommandReply(id: id, ok: false, text: "No open to-do matches \"\(target)\".") }
            if verb == "done" { toggle(item.id) } else { remove(item.id) }
            return ZeusCommandReply(id: id, ok: true, text: "\(verb == "done" ? "Done" : "Removed"): \(item.title)")
        }
        return ZeusCommandReply(id: id, ok: false, text: "Use zeus todo add \"<text>\", list, done <n|words> or remove <n|words>.")
    }

    // MARK: Apple Reminders (optional mirror, ZEUS-made reminders only)

    var remindersAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    private func askReminders() {
        // No prompt here: the mirror waits until Reminders is on in Settings > Permissions.
        guard !TopBarStyle.isSnapshot, !remindersAllowed else { return }
        NSLog("[ZEUS] permissions: Reminders mirror waiting for access")
    }

    private func mirrorAdd(_ item: TodoItem) {
        guard remindersMirror, remindersAllowed, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = item.title
        reminder.calendar = list
        if let due = item.due, let date = TodoQuickAdd.day(due) {
            reminder.dueDateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        }
        guard (try? store.save(reminder, commit: true)) != nil else { return }
        reminderIDs[item.id.uuidString] = reminder.calendarItemIdentifier
        onReminderSaved?()
        UserDefaults.standard.set(reminderIDs, forKey: "todo.reminderIDs")
    }

    /// Deleting a to-do deletes the Reminder ZEUS made for it (only that one, found by its saved id), but only
    /// while the mirror is on. A deletion that cannot happen yet (access off, save failed) is kept and retried.
    private func mirrorRemove(_ id: UUID) {
        guard !TopBarStyle.isSnapshot, let key = reminderIDs.removeValue(forKey: id.uuidString) else { return }
        UserDefaults.standard.set(reminderIDs, forKey: "todo.reminderIDs")
        // Mirroring is off: the person opted out of Zeus touching Reminders, so the Reminder stays.
        guard remindersMirror else { return }
        if !deleteReminder(key) { rememberPendingDelete(key) }
    }

    /// True when the Reminder is gone (deleted now, or already missing); false when it should be retried.
    private func deleteReminder(_ key: String) -> Bool {
        guard remindersAllowed else { return false }
        guard let reminder = store.calendarItem(withIdentifier: key) as? EKReminder else { return true }
        do {
            try store.remove(reminder, commit: true)
            return true
        } catch {
            NSLog("[ZEUS] todo: Reminder delete failed: %@", error.localizedDescription)
            return false
        }
    }

    private func rememberPendingDelete(_ key: String) {
        guard !pendingReminderDeletes.contains(key) else { return }
        pendingReminderDeletes.append(key)
        UserDefaults.standard.set(pendingReminderDeletes, forKey: "todo.reminderPendingDeletes")
    }

    /// Retries deletions that failed earlier; nothing happens while the mirror or Reminders access is off.
    private func retryPendingDeletes() {
        guard !TopBarStyle.isSnapshot, remindersMirror, remindersAllowed, !pendingReminderDeletes.isEmpty else { return }
        pendingReminderDeletes = pendingReminderDeletes.filter { !deleteReminder($0) }
        UserDefaults.standard.set(pendingReminderDeletes, forKey: "todo.reminderPendingDeletes")
    }

    private func mirrorDone(_ item: TodoItem) {
        guard remindersMirror, remindersAllowed, let key = reminderIDs[item.id.uuidString],
              let reminder = store.calendarItem(withIdentifier: key) as? EKReminder else { return }
        reminder.isCompleted = item.done
        try? store.save(reminder, commit: true)
    }
}
