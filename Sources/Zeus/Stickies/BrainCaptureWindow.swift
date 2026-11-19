import AppKit
import Observation
import SwiftUI
import ZeusCore

/// "Save to brain": shows exactly what will be written and where, and writes only on Save.
@MainActor
@Observable
final class BrainCaptureModel {
    var title: String {
        didSet { target = connection.flatMap { BrainCapture.plannedURL(connection: $0, title: title, created: created) } }
    }
    var body: String
    let source: String
    let connection: BrainConnection?
    let created: Date
    private let currentConnection: () -> BrainConnection?
    var vault: URL? { connection?.source.url }
    private(set) var target: URL?
    var saved: URL?
    var problem: String?

    init(title: String, body: String, source: String, created: Date = Date(),
         currentConnection: @escaping () -> BrainConnection? = { BrainCaptureModel.selectedConnection() }) {
        self.title = title
        self.body = body
        self.source = source
        self.created = created
        self.currentConnection = currentConnection
        let selected = currentConnection()
        connection = selected
        target = selected.flatMap { BrainCapture.plannedURL(connection: $0, title: title, created: created) }
    }

    private static func selectedConnection() -> BrainConnection? {
        // Do not even inspect the legacy choice when Memory already has a selected destination.
        if let configured = TodoController.shared.connection { return configured }
        return BrainCapture.connection(configured: nil, legacyVault: AboutYouModel.savedVault())
    }

    var preview: String { BrainCapture.note(title: title, body: body, source: source, created: created) }

    func save() {
        guard currentConnection() == connection else {
            problem = "Your vault selection or access changed. Close this preview and open Save to Brain again."
            return
        }
        guard let connection, let target else {
            problem = BrainCapture.WriteError.unavailableDestination.localizedDescription
            return
        }
        do {
            let text = preview
            saved = try AboutYouModel.withAccess(to: connection.source.url) {
                try BrainCapture.write(text, to: target, connection: connection)
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

@MainActor
final class BrainCaptureWindow {
    static let shared = BrainCaptureWindow()
    private var window: NSWindow?

    func show(title: String, body: String, source: String) {
        let model = BrainCaptureModel(title: title, body: body, source: source)
        let window = self.window ?? {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 420),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Save to Brain"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.backgroundColor = NSColor(Theme.storm)
            window.center()
            return window
        }()
        window.contentView = NSHostingView(rootView: BrainCaptureView(model: model, close: { [weak window] in window?.close() }))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}

struct BrainCaptureView: View {
    let model: BrainCaptureModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save to brain").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                .accessibilityAddTraits(.isHeader)
            if model.saved != nil {
                Label("Saved in your vault's inbox.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.leaf)
                HStack {
                    Button("Show in Finder") { model.saved.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) } }
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
            } else if model.vault == nil {
                Text("Choose a vault in Settings › Memory, or set one up with Teach Zeus About You.")
                    .font(TopBarStyle.label(12.5)).foregroundStyle(Theme.cloudSecondary)
                HStack {
                    Spacer()
                    Button("Set Up…") { close(); AboutYouWindow.shared.show() }
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                }
            } else {
                TextField("Title", text: Binding(get: { model.title }, set: { model.title = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Note title")
                if let target = model.target {
                    Text("New note: \(target.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                        .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet).textSelection(.enabled)
                }
                ScrollView {
                    Text(model.preview)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.cloudSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .accessibilityLabel("Note preview")
                if let problem = model.problem {
                    Text(problem).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.danger)
                }
                if model.target == nil {
                    Text("This vault is read-only or its inbox is unavailable. Check Settings › Memory.")
                        .font(TopBarStyle.label(11.5)).foregroundStyle(Theme.danger)
                }
                HStack {
                    Label("Only this note is written to your chosen inbox.", systemImage: "lock.fill")
                        .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.leaf)
                    Spacer()
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                    Button("Save Note") { model.save() }.keyboardShortcut(.defaultAction)
                        .disabled(model.target == nil)
                }
            }
        }
        .padding(20)
        .padding(.top, 12)
        .frame(minWidth: 420, minHeight: 300)
        .background(Theme.storm)
        .preferredColorScheme(.dark)
    }
}
