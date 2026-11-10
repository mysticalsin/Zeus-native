import AppKit
import SwiftUI
import ZeusCore

/// Dictation history in its own window: read, correct, teach the vocabulary from a fix, and
/// run a past dictation again with another mode or engine.
@MainActor
final class DictationHistoryWindow {
    static let shared = DictationHistoryWindow()
    private var window: NSWindow?

    func show(topBar: TopBarModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Dictation History"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 600, height: 380)
        window.contentView = NSHostingView(rootView: DictationHistoryView(topBar: topBar))
        if !window.setFrameUsingName("ZeusDictationHistory") { window.center() }
        window.setFrameAutosaveName("ZeusDictationHistory")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}

/// State of the history window (this toolchain has no SwiftUI `@State` macro).
@MainActor
@Observable
final class DictationHistoryState {
    var selection: String? {
        didSet { if selection != oldValue { resetEditor() } }
    }
    var search = ""
    // Editor of the selected dictation.
    var draft = "" {
        didSet { if draft != oldValue { editorGeneration &+= 1 } }
    }
    var suggestion: VocabularyCapture.Suggestion?
    var modeKey = ""
    var engine: TranscriptionEngineKind?
    /// A reprocess is running. Kept across selection changes, so a second one cannot start meanwhile.
    var working = false
    var note: String?
    /// Changes whenever the editor is reset or its text is edited. A reprocess writes its result back only
    /// while this is the value it started with, so returning to the same record cannot be overwritten.
    private(set) var editorGeneration = 0
    private var loadedID: String?

    func load(_ record: DictationRecord, modes: [DictationMode]) {
        guard loadedID != record.id else { return }
        loadedID = record.id
        draft = record.result
        modeKey = record.modeKey == "file" ? (modes.first?.key ?? "voice") : record.modeKey
    }

    private func resetEditor() {
        loadedID = nil
        editorGeneration &+= 1
        suggestion = nil
        engine = nil
        note = nil
    }
}

struct DictationHistoryView: View {
    let topBar: TopBarModel
    let state = DictationHistoryState()

    private var selectionBinding: Binding<String?> { Binding(get: { state.selection }, set: { state.selection = $0 }) }

    private var records: [DictationRecord] {
        let needle = state.search.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return topBar.dictationHistory }
        return topBar.dictationHistory.filter { $0.result.localizedCaseInsensitiveContains(needle) || $0.rawResult.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        NavigationSplitView {
            List(records, selection: selectionBinding) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.result).lineLimit(2)
                    Text("\(record.modeName) · \(record.datetime.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(record.id)
                .accessibilityElement(children: .combine)
            }
            .searchable(text: Binding(get: { state.search }, set: { state.search = $0 }), placement: .sidebar, prompt: "Search dictations")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if records.isEmpty {
                    Text(state.search.isEmpty ? "No dictations yet." : "No matches.").foregroundStyle(.secondary)
                }
            }
        } detail: {
            if let id = state.selection, let record = topBar.dictationHistory.first(where: { $0.id == id }) {
                DictationRecordDetail(topBar: topBar, record: record, state: state)
            } else {
                Text("Select a dictation").foregroundStyle(.secondary)
            }
        }
        .onAppear { state.selection = state.selection ?? topBar.dictationHistory.first?.id }
    }
}

private struct DictationRecordDetail: View {
    let topBar: TopBarModel
    let record: DictationRecord
    let state: DictationHistoryState

    private var controller: DictationController? { DictationHub.shared.controller }

    var body: some View {
        Form {
            Section {
                TextEditor(text: Binding(get: { state.draft }, set: { state.draft = $0 }))
                    .font(.body)
                    .frame(minHeight: 110)
                    .accessibilityLabel("Dictated text")
                HStack {
                    Button("Save Correction") { saveCorrection() }
                        .disabled(state.draft == record.result)
                        .keyboardShortcut("s", modifiers: .command)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.draft, forType: .string)
                    }
                    Spacer()
                    Button("Delete", role: .destructive) { controller?.deleteRecord(record.id) }
                }
                if record.rawResult != record.result {
                    LabeledContent("Heard") { Text(record.rawResult).textSelection(.enabled).foregroundStyle(.secondary) }
                }
            } header: {
                Text(details)
            }

            if let suggestion = state.suggestion, !suggestion.isEmpty {
                Section("Teach the vocabulary") {
                    ForEach(suggestion.replacements, id: \.original) { rule in
                        Label("“\(rule.original)” becomes “\(rule.with)”", systemImage: "arrow.right")
                    }
                    ForEach(suggestion.words, id: \.self) { word in
                        Label("Expect the word “\(word)”", systemImage: "character.book.closed")
                    }
                    HStack {
                        Button("Add to Vocabulary") {
                            controller?.learn(suggestion)
                            state.suggestion = nil
                            state.note = "Added. Future dictations will use it."
                        }
                        .buttonStyle(GSButtonStyle(prominent: true))
                        Button("Not Now") { state.suggestion = nil }
                    }
                }
            }

            Section("Reprocess") {
                Picker("Mode", selection: Binding(get: { state.modeKey }, set: { state.modeKey = $0 })) {
                    ForEach(topBar.dictationModes) { mode in Label(mode.name, systemImage: mode.symbol).tag(mode.key) }
                }
                Picker("Listen again with", selection: Binding(get: { state.engine }, set: { state.engine = $0 })) {
                    Text("Keep the words heard").tag(TranscriptionEngineKind?.none)
                    if controller?.hasAudio(record.id) == true {
                        ForEach(TranscriptionEngineKind.allCases) { kind in
                            Text(kind.title).tag(TranscriptionEngineKind?.some(kind))
                        }
                    }
                }
                .disabled(controller?.hasAudio(record.id) != true)
                if controller?.hasAudio(record.id) != true {
                    Text("This dictation has no saved audio, so only the mode can change.").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(state.working ? "Working…" : "Reprocess") { reprocess() }
                        .disabled(state.working || controller == nil)
                    if state.working { ProgressView().controlSize(.small) }
                }
            }

            if let note = state.note {
                Text(note).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.load(record, modes: topBar.dictationModes) }
        .onChange(of: record.id) { state.load(record, modes: topBar.dictationModes) }
    }

    private var details: String {
        var parts = [record.modeName, record.datetime.formatted(date: .abbreviated, time: .shortened)]
        if let app = record.appName { parts.append(app) }
        if let engine = record.engine.flatMap(TranscriptionEngineKind.init(rawValue:)) { parts.append(engine.title) }
        parts.append("\(record.wordCount) words")
        return parts.joined(separator: " · ")
    }

    private func saveCorrection() {
        guard let controller else { return }
        let found = controller.correct(record.id, to: state.draft)
        state.suggestion = found.isEmpty ? nil : found
        state.note = found.isEmpty ? "Saved." : nil
    }

    private func reprocess() {
        guard let controller, !state.working else { return }
        // Everything the request needs is read now, before the task starts.
        let id = record.id
        let modeKey = state.modeKey
        let engine = state.engine
        let generation = state.editorGeneration
        state.working = true
        state.note = nil
        Task {
            let updated = await controller.reprocess(id, modeKey: modeKey, engine: engine)
            state.working = false
            // Another selection, or an edit of this draft, since the press: the editor is not ours to write.
            guard state.editorGeneration == generation, state.selection == id else { return }
            if let updated {
                state.draft = updated.result
                state.note = "Reprocessed with \(updated.modeName)."
            } else {
                state.note = "Could not reprocess this dictation."
            }
        }
    }
}
