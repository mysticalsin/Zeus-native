import AppKit
import SwiftUI
import ZeusCore

/// The To-do tab: one input line on top, the list underneath, Glance's compact row style.
struct TodoPage: View {
    let topBar: TopBarModel
    let todo: TodoController

    var body: some View { list }
    private var list: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TodoInput(todo: todo)
                    .frame(height: 30)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(todo.listening ? TopBarStyle.rec.opacity(0.7) : TopBarStyle.tileStroke))
                GlyphButton(symbol: todo.listening ? "stop.fill" : "mic.fill", size: 11,
                            tint: todo.listening ? TopBarStyle.rec : Theme.cloudSecondary,
                            label: todo.listening ? "Stop and add" : "Say a to-do") {
                    // A leftover failure message must not pose as the first partial of the next try.
                    if !todo.listening { todo.voicePartial = "" }
                    todo.toggleVoice()
                }
                GlyphButton(symbol: "plus", size: 12, tint: Theme.accent, label: "Add") { todo.submitDraft() }
            }
            let suggestions = Array(todo.suggestions.prefix(3))
            let headerHeight = Self.headerHeight(voiceError: todo.voiceError != nil, warning: todo.warning != nil, suggestions: suggestions.count)
            if headerHeight > 0 {
                // Warnings and suggestions share a budget inside the fixed page; past it they scroll and the list keeps its room.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        header(suggestions: suggestions)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: headerHeight)
            }
            if todo.visible.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.leaf)
                    Text(todo.items.isEmpty ? "Nothing to do. Type above, or say it." : "All done.")
                        .font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PageScroll(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(todo.visible) { item in TodoRow(item: item, topBar: topBar, todo: todo) }
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: todo.noteName == nil ? "internaldrive" : "diamond.fill")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.cloudQuiet)
                Text(footer).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                Spacer()
                if todo.items.contains(where: \.done) {
                    Button(todo.showDone ? "Hide done" : "Show done") { todo.showDone.toggle() }
                        .buttonStyle(PressableStyle()).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                    Button("Clear done") { todo.clearDone() }
                        .buttonStyle(PressableStyle()).font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                }
            }
        }
    }

    /// The most height the notices and suggestions may take of the 236 pt page (input, footer and at least two rows keep the rest).
    static let headerBudget: CGFloat = 72
    private static let noticeHeight: CGFloat = 26
    private static let suggestionHeight: CGFloat = 38

    /// Estimated height of the warning and suggestion block, capped at the budget; zero when there is nothing to show.
    static func headerHeight(voiceError: Bool, warning: Bool, suggestions: Int) -> CGFloat {
        var rows = 0, total: CGFloat = 0
        if voiceError { rows += 1; total += noticeHeight }
        if warning { rows += 1; total += noticeHeight }
        if suggestions > 0 { rows += suggestions; total += CGFloat(suggestions) * suggestionHeight }
        guard rows > 0 else { return 0 }
        return min(total + CGFloat(rows - 1) * 4, headerBudget)
    }

    @ViewBuilder
    private func header(suggestions: [TodoLearning.Suggestion]) -> some View {
        if let error = todo.voiceError {
            Text(error)
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.ember)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Microphone problem: \(error)")
        }
        if let warning = todo.warning {
            Text(warning)
                .font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.ember)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("To-do warning: \(warning)")
        }
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(suggestions) { suggestion in
                        Button { todo.applySuggestion(suggestion) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: suggestion.kind == "split" ? "scissors" : (suggestion.kind == "recurring" ? "arrow.triangle.2.circlepath" : "calendar.badge.clock"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.glow)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.kind == "split" ? "Split into \(suggestion.split.count)" : suggestion.title)
                                        .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                                    Text(suggestion.reason)
                                        .font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Suggestion: \(suggestion.reason)")
                }
            }
        }
    }

    private var footer: String {
        let count = "\(todo.open.count) open"
        if let note = todo.noteName { return "\(count) · synced with \(note)" }
        if let connection = todo.connection, connection.access == .readOnly { return "\(count) · \(connection.source.name) is read-only, kept in ZEUS" }
        return "\(count) · kept on this Mac"
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let topBar: TopBarModel
    let todo: TodoController

    private var key: String { "t\(item.id)" }
    private var hovered: Bool { topBar.hovered == key }

    var body: some View {
        HStack(spacing: 8) {
            Button { todo.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.done ? Theme.leaf : Theme.cloudSecondary)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(item.done ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(TopBarStyle.label(11.5, .medium))
                    .foregroundStyle(item.done ? Theme.cloudQuiet : Theme.cloudPrimary)
                    .strikethrough(item.done, color: Theme.cloudQuiet)
                    .lineLimit(1)
                if !item.done, let why = todo.reason(for: item) {
                    Text(why).font(TopBarStyle.label(9)).foregroundStyle(Theme.glow).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if hovered {
                GlyphButton(symbol: "chevron.up", size: 9, tint: Theme.cloudSecondary, label: "Move up") { todo.move(item.id, by: -1) }
                GlyphButton(symbol: "chevron.down", size: 9, tint: Theme.cloudSecondary, label: "Move down") { todo.move(item.id, by: 1) }
                GlyphButton(symbol: "calendar", size: 9, tint: Theme.cloudSecondary, label: "Change due date") { todo.cycleDue(item.id) }
                GlyphButton(symbol: "xmark", size: 9, tint: Theme.cloudSecondary, label: "Delete") { todo.remove(item.id) }
            } else if let due = item.due {
                DueChip(due: due, done: item.done)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.white.opacity(hovered ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { topBar.hovered = $0 ? key : (topBar.hovered == key ? nil : topBar.hovered) }
        .accessibilityElement(children: .contain)
        // The hover buttons are not in the tree until the pointer is over the row, so the same
        // actions are offered to VoiceOver and, through the context menu, to the keyboard.
        .accessibilityAction(named: "Move up") { todo.move(item.id, by: -1) }
        .accessibilityAction(named: "Move down") { todo.move(item.id, by: 1) }
        .accessibilityAction(named: "Change due date") { todo.cycleDue(item.id) }
        .accessibilityAction(named: "Delete") { todo.remove(item.id) }
        .contextMenu {
            Button("Move up") { todo.move(item.id, by: -1) }
            Button("Move down") { todo.move(item.id, by: 1) }
            Button("Change due date") { todo.cycleDue(item.id) }
            Button("Delete", role: .destructive) { todo.remove(item.id) }
        }
    }
}

/// "Today", "Tomorrow", a weekday or a short Gregorian date; red when overdue.
struct DueChip: View {
    let due: String
    let done: Bool
    /// When the reminder has a time of day, the chip adds it ("Today 17:00").
    var time: Date? = nil

    var body: some View {
        let described = Self.describe(due)
        let overdue = described.1
        let text = time.map { described.0 + " " + Self.clock($0) } ?? described.0
        Text(text)
            .font(TopBarStyle.label(10, .semibold))
            .foregroundStyle(overdue && !done ? Theme.ember : Theme.cloudSecondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill((overdue && !done ? Theme.ember : Color.white).opacity(0.12)))
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func describe(_ due: String, now: Date = Date()) -> (String, Bool) {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = TodoQuickAdd.day(due) else { return (due, false) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        switch days {
        case ..<0: formatter.dateFormat = "MMM d"; return (formatter.string(from: date), true)
        case 0: return ("Today", false)
        case 1: return ("Tomorrow", false)
        case 2...6: formatter.dateFormat = "EEEE"; return (formatter.string(from: date), false)
        default: formatter.dateFormat = "MMM d"; return (formatter.string(from: date), false)
        }
    }
}

/// The input line. An AppKit field so the notch can take typing only while this page is open.
struct TodoInput: View {
    let todo: TodoController

    var body: some View {
        if TopBarStyle.isSnapshot {
            HStack {
                Text(!todo.voicePartial.isEmpty ? todo.voicePartial : (todo.draft.isEmpty ? placeholder : todo.draft))
                    .font(TopBarStyle.label(11.5)).foregroundStyle(todo.draft.isEmpty && !todo.listening ? Theme.cloudQuiet : Theme.cloudPrimary)
                Spacer()
            }
        } else {
            TodoField(todo: todo, focus: todo.focusRequest, placeholder: todo.listening ? (todo.voicePartial.isEmpty ? "Listening…" : todo.voicePartial)
                         : (todo.voicePartial.isEmpty ? placeholder : todo.voicePartial))
        }
    }

    private var placeholder: String { "Add a to-do. Try \"call Anna tomorrow\"" }
}

private struct TodoField: NSViewRepresentable {
    let todo: TodoController
    let focus: Int
    let placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 11.5, weight: .medium)
        field.textColor = .white
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
        ])
        if field.stringValue != todo.draft { field.stringValue = todo.draft }
        if context.coordinator.focus != focus {
            context.coordinator.focus = focus
            DispatchQueue.main.async {
                field.window?.makeKey()
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(todo: todo, focus: focus) }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let todo: TodoController
        var focus: Int
        init(todo: TodoController, focus: Int) { self.todo = todo; self.focus = focus }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSTextField { todo.draft = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { todo.submitDraft(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { control.window?.resignKey(); return true }
            return false
        }
    }
}


/// "What do I have today?" from the second brain, shown beside the Today tab.
@MainActor
@Observable
final class BrainTodayModel {
    static let shared = BrainTodayModel()
    private(set) var tasks: [BrainTask] = []
    private(set) var root: URL?
    private(set) var loadedAt: Date?
    private var loading = false

    func refresh(connection: BrainConnection?) {
        let root = connection?.source.kind.isFileBased == true ? connection?.source.url : BrainToday.defaultRoot()
        guard !loading, loadedAt.map({ Date().timeIntervalSince($0) > 120 }) ?? true || root != self.root else { return }
        self.root = root
        guard let root else { tasks = []; loadedAt = Date(); return }
        loading = true
        Task.detached(priority: .utility) {
            let found = BrainToday.scan(root: root)
            await MainActor.run {
                self.tasks = found
                self.loadedAt = Date()
                self.loading = false
            }
        }
    }

    func seedForSnapshot(_ tasks: [BrainTask]) { self.tasks = tasks; root = URL(fileURLWithPath: "/brain"); loadedAt = Date() }
}

struct BrainTodayCard: View {
    let model: BrainTodayModel
    let connection: BrainConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "brain.head.profile").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.bolt)
                Text("TODAY · FROM YOUR BRAIN").font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.cloudSecondary)
                Spacer(minLength: 0)
            }
            if model.root == nil, model.loadedAt != nil {
                Text("Connect your second brain in Settings > Memory and ZEUS lists what's on today.")
                    .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            } else if model.tasks.isEmpty {
                Text(model.loadedAt == nil ? "Reading your brain…" : "Nothing open for today.")
                    .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            } else {
                PageScroll(.vertical) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.tasks) { task in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(task.dueToday ? Theme.bolt : (task.highPriority ? Theme.ember : Theme.cloudQuiet))
                                    .frame(width: 5, height: 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.title).font(TopBarStyle.label(10.5, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(2)
                                    Text(task.dueToday ? "\(task.project) · today" : task.project)
                                        .font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(TopBarStyle.tileStroke))
        .onAppear { model.refresh(connection: connection) }
    }
}
