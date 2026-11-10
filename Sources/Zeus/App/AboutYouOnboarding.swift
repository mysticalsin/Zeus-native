import AppKit
import Observation
import SwiftUI
import ZeusCore

/// "Teach ZEUS about you": find the second brain, ask three short questions, and (only after
/// the person confirms) write one profile note into the vault's inbox.
@MainActor
@Observable
final class AboutYouModel {
    enum Step: Int, CaseIterable {
        case intro, vault, questions, review, done
    }

    var step: Step = .intro
    var vault: URL?
    var summary: SecondBrain.Summary?
    var profile = AboutYouProfile()
    var written: URL?
    var problem: String?
    var scanning = false

    private let defaults = UserDefaults.standard
    static let bookmarkKey = "aboutYou.vaultBookmark"

    init() {
        vault = Self.savedVault() ?? SecondBrain.detect()
        profile.name = defaults.string(forKey: "aboutYou.name") ?? NSFullUserName()
        if let vault { scan(vault) }
    }

    var notePreview: String {
        profile.markdown(created: Date(), vaultSummary: summary)
    }

    var plannedNote: URL? {
        vault.map { ProfileNoteWriter.plannedURL(in: $0, created: Date()) }
    }

    func next() {
        problem = nil
        if let following = Step(rawValue: step.rawValue + 1) { step = following }
    }

    func back() {
        problem = nil
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Vault"
        panel.message = "Choose your notes folder. ZEUS reads it and never changes your notes."
        panel.directoryURL = vault ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SecondBrain.looksLikeVault(url) else {
            problem = "That folder has no Markdown notes. Pick the folder that holds your vault."
            return
        }
        vault = url
        remember(url)
        scan(url)
    }

    /// Counts notes off the main thread; only file names are read.
    func scan(_ url: URL) {
        scanning = true
        Task.detached(priority: .utility) {
            let summary = Self.withAccess(to: url) { SecondBrain.summarize(url) }
            await MainActor.run {
                self.summary = summary
                self.scanning = false
            }
        }
    }

    func save() {
        guard let vault, let target = plannedNote else { return }
        do {
            let text = notePreview
            written = try Self.withAccess(to: vault) { try ProfileNoteWriter.write(text, to: target, vault: vault) }
            defaults.set(profile.name.trimmingCharacters(in: .whitespaces), forKey: "aboutYou.name")
            step = .done
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: Bookmarks

    /// A security-scoped bookmark keeps access to a chosen folder across launches. Plain
    /// bookmarks are the fallback, since ZEUS runs outside the App Sandbox.
    private func remember(_ url: URL) {
        let data = (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]))
            ?? (try? url.bookmarkData())
        defaults.set(data, forKey: Self.bookmarkKey)
    }

    static func savedVault() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], bookmarkDataIsStale: &stale))
        return url.flatMap { SecondBrain.looksLikeVault($0) ? $0 : nil }
    }

    nonisolated static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

@MainActor
final class AboutYouWindow {
    static let shared = AboutYouWindow()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 470),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Teach ZEUS About You"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.storm)
        window.contentView = NSHostingView(rootView: AboutYouView(model: AboutYouModel(), close: { [weak window] in window?.close() }))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}

struct AboutYouView: View {
    let model: AboutYouModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            progress
            Group {
                switch model.step {
                case .intro: intro
                case .vault: vaultStep
                case .questions: questions
                case .review: review
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 16)), removal: .opacity))
            .id(model.step)
            if let problem = model.problem {
                Text(problem).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.danger)
            }
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .background(Theme.storm)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.36, dampingFraction: 0.85), value: model.step)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(AboutYouModel.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= model.step.rawValue ? Theme.bolt : Color.white.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(model.step.rawValue + 1) of \(AboutYouModel.Step.allCases.count)")
    }

    // MARK: Slides

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "bolt.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.bolt)
                .accessibilityHidden(true)
            title("Teach ZEUS about you")
            body("A minute of setup so ZEUS answers like it knows you: who you are, what you work on, and where your notes live.")
            privacyLine
        }
    }

    private var vaultStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Your second brain")
            body("ZEUS reads your notes folder to learn context. It never edits your notes.")
            Tile(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if let vault = model.vault {
                        Label(vault.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder.fill")
                            .font(TopBarStyle.label(12.5, .semibold)).foregroundStyle(Theme.cloudPrimary)
                        if model.scanning {
                            ProgressView().controlSize(.small)
                        } else if let summary = model.summary {
                            Text("\(summary.notes)\(summary.truncated ? "+" : "") notes"
                                 + (summary.folders.isEmpty ? "" : " · \(summary.folders.prefix(3).joined(separator: ", "))"))
                                .font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudSecondary)
                        }
                    } else {
                        Text("No vault found at ~/Documents/brain.").font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary)
                    }
                    Button(model.vault == nil ? "Choose Vault Folder…" : "Choose Another Folder…") { model.chooseVault() }
                }
            }
            .frame(height: 112)
            privacyLine
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("A few quick questions")
            field("What should ZEUS call you?", text: Binding(get: { model.profile.name }, set: { model.profile.name = $0 }), prompt: "Your name")
            field("What do you work on?", text: Binding(get: { model.profile.work }, set: { model.profile.work = $0 }), prompt: "e.g. founder, building a Mac app")
            field("What should ZEUS help you with most?", text: Binding(get: { model.profile.helpWith }, set: { model.profile.helpWith = $0 }),
                  prompt: "e.g. mornings, email, coding agents")
            field("Anything else? (optional)", text: Binding(get: { model.profile.notes }, set: { model.profile.notes = $0 }), prompt: "Preferences, languages, people")
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("Save your profile note?")
            if let target = model.plannedNote {
                body("ZEUS will add this one note to your vault, at \(target.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Nothing else is written.")
            } else {
                body("Choose a vault first to save a profile note.")
            }
            ScrollView {
                Text(model.notePreview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.cloudSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityLabel("Note preview")
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.leaf)
                .accessibilityHidden(true)
            title("Thanks, \(model.profile.name.trimmingCharacters(in: .whitespaces))")
            body("Your profile note is in your vault's inbox. You can come back here any time from Settings.")
            if let written = model.written {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([written]) }
            }
        }
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            if model.step != .intro, model.step != .done {
                Button("Back") { model.back() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            switch model.step {
            case .intro:
                Button("Not Now", action: close)
                Button("Get Started") { model.next() }.keyboardShortcut(.defaultAction)
            case .vault:
                Button(model.vault == nil ? "Skip" : "Continue") { model.next() }.keyboardShortcut(.defaultAction)
            case .questions:
                Button("Continue") { model.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.profile.isComplete)
            case .review:
                Button("Don't Save") { close() }
                Button("Save Note") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.vault == nil)
            case .done:
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private var privacyLine: some View {
        Label("Nothing leaves this Mac.", systemImage: "lock.fill")
            .font(TopBarStyle.label(11.5, .semibold))
            .foregroundStyle(Theme.leaf)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func body(_ text: String) -> some View {
        Text(text).font(TopBarStyle.label(13)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudSecondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}

/// Settings › General: re-open the flow.
struct AboutYouSettingsRow: View {
    var body: some View {
        Section("You") {
            Button("Teach ZEUS About You…") { AboutYouWindow.shared.show() }
            Text("Your name, your work and where your notes live. Nothing leaves this Mac.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
