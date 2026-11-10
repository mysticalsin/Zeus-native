import AppKit
import Combine
import SwiftUI
import ZeusCore

/// Zeus-only Settings pages: To-do, Memory (second brain), Prompter, Agents, Stickies, Routines.
/// Each one persists real values — no stubs. No @State (toolchain).

struct TodoSettingsPage: View {
    var topBar: TopBarModel?

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "To-do tab") {
                GlassRow(title: "Show in the notch", note: "Adds the To-do tab beside Home.") {
                    GlassToggle(isOn: Binding(
                        get: { topBar?.layout.contains(.todo) ?? true },
                        set: { on in
                            guard let topBar else { return }
                            if on != topBar.layout.contains(.todo) { topBar.layout.toggle(.todo) }
                        }
                    ), label: "To-do tab")
                }
                GlassDivider()
                GlassRow(title: "Mirror into Apple Reminders",
                         note: TodoController.shared.remindersMirror && !TodoController.shared.remindersAllowed
                            ? "Nothing is mirrored yet: Reminders access is off. Turn it on in Settings > Permissions, then new to-dos are added to Reminders."
                            : "Only reminders ZEUS creates. Needs Reminders access.") {
                    GlassToggle(isOn: Binding(
                        get: { TodoController.shared.remindersMirror },
                        set: { TodoController.shared.remindersMirror = $0 }
                    ), label: "Reminders mirror")
                }
            }
            GlassCard(title: "Learning (on this Mac)") {
                GlassRow(title: "Learn from how you use to-dos",
                         note: "Remembers recurring tasks, usual times and push-backs. Suggests due days and ranks what to do next.") {
                    GlassToggle(isOn: Binding(
                        get: { TodoController.shared.learningEnabled },
                        set: { TodoController.shared.learningEnabled = $0 }
                    ), label: "Learning")
                }
                GlassDivider()
                GlassRow(title: "Clear what ZEUS learned", note: "Wipes patterns. Your to-do list stays.") {
                    Button("Clear learning") { TodoController.shared.clearLearning() }
                        .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                }
            }
            ProactiveSettingsSection()
        }
    }
}

@MainActor
final class MemorySettingsModel: ObservableObject {
    @Published var connection: BrainConnection?
    @Published var note = ""

    init() { connection = TodoController.shared.connection }

    func disconnect() {
        connection = nil
        TodoController.shared.connect(nil)
        note = "Disconnected. To-dos stay in ZEUS."
    }

    func setAccess(_ access: BrainConnection.Access) {
        guard var current = connection else { return }
        current.access = access
        if access == .readWrite, case .none = current.todo {
            current.todo = .note(BrainConnection.defaultTodoNote)
        }
        connection = current
        TodoController.shared.connect(current)
    }

    func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Vault"
        panel.message = "Choose an Obsidian vault or Markdown folder. ZEUS never deletes your notes."
        let brain = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/brain")
        panel.directoryURL = FileManager.default.fileExists(atPath: brain.path) ? brain
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = (try? url.bookmarkData(options: [.withSecurityScope])) ?? (try? url.bookmarkData())
        UserDefaults.standard.set(scoped, forKey: "todo.vaultBookmark")
        let kind = BrainDetector.classify(url) ?? .markdown
        let source = BrainSource(kind: kind, name: url.lastPathComponent, path: url.path)
        let next = BrainConnection(source: source, access: .readWrite,
                                   todo: .note(BrainConnection.defaultTodoNote),
                                   inboxFolder: "ZEUS/Inbox")
        connection = next
        TodoController.shared.connect(next)
        note = "Connected to \(source.name). To-dos sync to \(BrainConnection.defaultTodoNote)."
    }
}

struct MemorySettingsPage: View {
    @StateObject private var model = MemorySettingsModel()

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Second brain") {
                GlassRow(title: "Vault folder",
                         note: model.connection.map { "\($0.source.name) · \($0.source.path)" }
                            ?? "Choose an Obsidian vault or Markdown folder to connect.") {
                    HStack(spacing: 8) {
                        Button("Choose…") { model.pickVault() }
                            .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                        if model.connection != nil {
                            Button("Disconnect") { model.disconnect() }
                                .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                        }
                    }
                }
                GlassDivider()
                GlassRow(title: "Access", note: "Writes only go to the ZEUS inbox or the chosen to-do note. Existing notes are never rewritten.") {
                    Picker("Access", selection: Binding(
                        get: { model.connection?.access ?? .readOnly },
                        set: { model.setAccess($0) }
                    )) {
                        Text("Read only").tag(BrainConnection.Access.readOnly)
                        Text("Read and write inbox").tag(BrainConnection.Access.readWrite)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Theme.accent)
                }
                GlassDivider()
                GlassRow(title: "Inbox folder", note: model.connection?.inboxFolder ?? "ZEUS/Inbox") {
                    EmptyView()
                }
            }
            if !model.note.isEmpty {
                Text(model.note).font(Glass.caption).foregroundStyle(Glass.secondary)
            }
            AboutYouSettingsRow()
        }
    }
}

struct TeleprompterSettingsPage: View {
    @AppStorage(PrompterHub.followKey) private var followPresentation = false

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Prompter") {
                GlassRow(title: "Follow my presentation",
                         note: "When a Keynote or PowerPoint slideshow starts, the prompter opens above it with the notes of the slide on screen. Needs Automation in Permissions.") {
                    GlassToggle(isOn: Binding(get: { followPresentation }, set: { value in
                        followPresentation = value
                        PrompterHub.shared.updateWatcher()
                    }), label: "Follow my presentation")
                }
                GlassDivider()
                GlassRow(title: "Hide from screen shares", note: "Uses a sharing-type that stays off recordings.") {
                    GlassStatus(ok: true, text: "Always on while the prompter runs")
                }
                GlassDivider()
                GlassRow(title: "Open script window") {
                    Button("Open Prompter") {
                        NotificationCenter.default.post(name: .zeusOpenPrompter, object: nil)
                    }
                    .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                }
            }
        }
    }
}

struct AgentsSettingsPage: View {
    var body: some View {
        VStack(spacing: Glass.gap) {
            AgentSettingsSection()
            CommandModeSettingsPage()
        }
    }
}

struct StickiesSettingsPage: View {
    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Stickies") {
                GlassRow(title: "New sticky", note: "A little note that stays on your screen.") {
                    Button("New sticky") { _ = StickiesController.shared.new() }
                        .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                }
                GlassDivider()
                GlassRow(title: "Save to second brain", note: "Uses your Memory vault inbox when connected.") {
                    GlassStatus(ok: TodoController.shared.connection != nil,
                                text: TodoController.shared.connection == nil ? "Connect a vault in Memory" : "Ready")
                }
            }
        }
    }
}

struct KeepAwakeSettingsPage: View {
    private var session: KeepAwakeSession { .shared }

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Timed session") {
                GlassRow(title: "Status", note: statusNote) {
                    GlassStatus(ok: session.isActive, text: session.isActive ? session.label : "Off")
                }
                GlassDivider()
                GlassRow(title: "Start", note: "Blocks idle sleep. The screen can still lock unless display keep-awake is on.") {
                    HStack(spacing: 6) {
                        ForEach(KeepAwakeSession.presets, id: \.self) { minutes in
                            Button(KeepAwakeLength.label(minutes)) { session.start(minutes: minutes) }
                                .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                        }
                    }
                }
                GlassDivider()
                GlassRow(title: "Longer", note: "Indefinitely runs until you end it or a battery or heat rule does.") {
                    HStack(spacing: 6) {
                        ForEach(KeepAwakeSession.longPresets, id: \.self) { minutes in
                            Button(KeepAwakeLength.label(minutes)) { session.start(minutes: minutes) }
                                .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                        }
                        Button(KeepAwakeLength.label(nil)) { session.start(minutes: nil) }
                            .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                    }
                }
                if session.isActive {
                    GlassDivider()
                    GlassRow(title: "While running") {
                        HStack(spacing: 8) {
                            if !session.isOpenEnded {
                                Button("+15 min") { session.add(minutes: 15) }
                                    .buttonStyle(GlassButtonStyle(kind: .primary, compact: true))
                            }
                            Button("End now") { session.end() }
                                .buttonStyle(GlassButtonStyle(kind: .quiet, compact: true))
                        }
                    }
                }
            }
            GlassCard(title: "Stop early") {
                GlassRow(title: "Battery floor", note: "Ends the session below this charge on battery. A notice comes first at 20%.") {
                    Picker("Battery floor", selection: Binding(
                        get: { session.batteryFloor },
                        set: { session.batteryFloor = $0 }
                    )) {
                        ForEach(KeepAwakeRules.floorChoices, id: \.self) { percent in
                            Text(KeepAwakeRules.floorLabel(percent)).tag(percent)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Theme.accent)
                }
                GlassDivider()
                GlassRow(title: "End when the Mac gets too hot", note: "Ends the session when macOS reports a critical thermal state.") {
                    GlassToggle(isOn: Binding(
                        get: { session.endWhenHot },
                        set: { session.endWhenHot = $0 }
                    ), label: "Too hot")
                }
            }
            GlassCard(title: "Options") {
                GlassRow(title: "Also keep the display awake", note: "Uses a separate display assertion. Releases when the session ends.") {
                    GlassToggle(isOn: Binding(
                        get: { session.keepDisplay },
                        set: { session.keepDisplay = $0 }
                    ), label: "Display")
                }
                GlassDivider()
                GlassRow(title: "While agents work", note: "Settings › General also has a toggle that holds sleep only while an agent is working.") {
                    GlassToggle(isOn: Binding(
                        get: { SettingsStore.shared.bool("general.keepAwake") },
                        set: { SettingsStore.shared.set("general.keepAwake", $0 ? "true" : "false") }
                    ), label: "Agents keep awake")
                }
            }
        }
    }

    private var statusNote: String {
        if session.isOpenEnded { return "On until you end it. The Mac stays awake until then." }
        if session.isActive { return "Ends in \(session.label). The Mac stays awake until then." }
        if let ended = session.lastEnd { return "\(ended.text). Pick a length to start again." }
        return "Off. Pick a length to start."
    }
}

extension Notification.Name {
    static let zeusOpenPrompter = Notification.Name("zeus.openPrompter")
}
