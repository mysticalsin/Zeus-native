import AppKit
import Foundation
import Observation
import SwiftUI
import ZeusCore

extension MCPStdioClient: WikiExportToolClient {
    func exportTools() async throws -> [MCPToolInfo] {
        try Task.checkCancellation()
        return try await listTools(timeout: 10)
    }

    func exportCall(_ name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        try Task.checkCancellation()
        return try await callTool(name, arguments: arguments, timeout: 15)
    }
}

/// One user-opened selection/review transaction. The helper is never launched by learning or sync.
@MainActor @Observable
final class WikiMCPExportModel: Identifiable {
    let id = UUID()
    let pages: [WikiPage]
    var selectedIDs: Set<String>
    var acknowledgedSensitive = false
    var confirmingAbandon = false
    private(set) var draft: WikiExportDraft?
    private(set) var busy = false
    private(set) var message: String?
    private(set) var outcome: WikiExportJournal.Entry?
    private(set) var mayRetry = false
    @ObservationIgnored private let transaction: WikiExportTransaction
    @ObservationIgnored private let current: @MainActor () throws -> WikiExportSnapshot
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var client: MCPStdioClient?
    @ObservationIgnored private var scopedURL: URL?

    init(snapshot: WikiExportSnapshot, selectedID: String?, journal: WikiExportJournal,
         current: @escaping @MainActor () throws -> WikiExportSnapshot) throws {
        pages = snapshot.pages.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if let selectedID, snapshot.pages.contains(where: { $0.id == selectedID && !$0.needsReview }) {
            selectedIDs = [selectedID]
        } else { selectedIDs = [] }
        self.current = current
        transaction = try WikiExportTransaction(journal: journal)
        if let pending = transaction.entry, pending.state != .verified {
            outcome = pending
            draft = pending.draft
            acknowledgedSensitive = pending.acknowledgedSensitive
            message = pending.state == .invalidated
                ? "A previous export was invalidated. Its draft was erased. A copy may already exist in the vault; Zeus never deletes exported notes."
                : "The previous export was interrupted. Check its result before sending again."
        }
    }

    func select(_ id: String, included: Bool) {
        guard draft == nil, !busy else { return }
        if included { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }

    func preview() {
        do {
            let snapshot = try current()
            try beginScope(connection: snapshot.connection)
            draft = try WikiExportDraft.make(selectedIDs: selectedIDs, snapshot: snapshot)
            acknowledgedSensitive = false
            message = nil
        } catch { message = error.localizedDescription }
    }

    func back() {
        guard !busy, outcome == nil else { return }
        draft = nil
        acknowledgedSensitive = false
        message = nil
    }

    func newSelection() {
        guard !busy, outcome?.state != .uncertain else { return }
        outcome = nil
        draft = nil
        message = nil
        acknowledgedSensitive = false
    }

    func send() { run(inspecting: false) }
    func check() { run(inspecting: true) }

    func abandonRecovery() {
        guard !busy, outcome?.state == .uncertain else { return }
        do {
            try transaction.invalidate()
            draft = nil
            outcome = transaction.entry
            mayRetry = false
            message = "Recovery abandoned; its private draft was erased. The previous note may already exist. A new export will create a different note."
        } catch { message = error.localizedDescription }
        confirmingAbandon = false
    }

    private func run(inspecting: Bool) {
        guard !busy, let draft else { return }
        busy = true
        message = inspecting ? "Checking the existing export…" : "Sending the reviewed selection…"
        operation = Task { [weak self] in
            guard let self else { return }
            var helper: MCPStdioClient?
            do {
                let snapshot = try self.current()
                try self.beginScope(connection: snapshot.connection)
                try draft.destination.validate(current: snapshot.connection)
                try Task.checkCancellation()
                let transport = try Self.makeClient(destination: draft.destination)
                helper = transport
                self.client = transport
                let info = try await transport.start(timeout: 10)
                guard info.name == WikiExportMCP.serverName, info.version == "1",
                      info.protocolVersion == MCPCodec.protocolVersion else { throw WikiExportError.protocolMismatch }
                if inspecting {
                    let result = try await self.transaction.check(client: transport, current: self.current)
                    self.message = result == .missing ? "No note with this export ID exists. You can retry the same reviewed export." : "Export verified against the exact preview."
                } else {
                    try await self.transaction.send(draft, acknowledgedSensitive: self.acknowledgedSensitive,
                                                    client: transport, current: self.current)
                    self.message = "Export verified against the exact preview."
                }
            } catch {
                let activeOutcome = self.transaction.outcome(for: draft.id)
                if activeOutcome?.state == .uncertain {
                    self.message = "The result is uncertain. Check the result before retrying. " + Self.explanation(error)
                } else if activeOutcome?.state == .invalidated {
                    self.message = "The export was invalidated and its draft erased. A copy may already exist in the vault."
                } else { self.message = Self.explanation(error) }
            }
            if let helper { await helper.close() }
            self.client = nil
            self.outcome = self.transaction.outcome(for: draft.id)
            self.mayRetry = self.outcome?.state == .uncertain && self.transaction.mayRetry
            if self.outcome?.state != .uncertain, self.outcome != nil { self.draft = nil }
            self.busy = false
            self.operation = nil
        }
    }

    /// Called after the controller durably invalidates a forgotten source. It also stops a live helper.
    func invalidate() {
        operation?.cancel()
        if let client { Task { await client.close() } }
        do { try transaction.invalidate() } catch { message = error.localizedDescription }
        draft = nil
        outcome = transaction.entry
        mayRetry = false
        message = "The export was invalidated and its draft erased. A copy may already exist in the vault."
    }

    func cancel() {
        operation?.cancel()
        if let client {
            // Keep the security scope alive until the child has stopped, even when the sheet closes.
            let url = scopedURL
            scopedURL = nil
            Task { await client.close(); url?.stopAccessingSecurityScopedResource() }
        } else {
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = nil
        }
    }

    private func beginScope(connection: BrainConnection?) throws {
        guard let connection else { throw WikiExportError.destination("Choose a vault in Settings › Memory first.") }
        if let scopedURL {
            guard scopedURL.resolvingSymlinksInPath().standardizedFileURL.path == connection.source.url.resolvingSymlinksInPath().standardizedFileURL.path else { throw WikiExportError.staleDraft }
            return
        }
        guard let data = UserDefaults.standard.data(forKey: "todo.vaultBookmark") else { return }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        guard !stale, url.resolvingSymlinksInPath().standardizedFileURL.path == connection.source.url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw WikiExportError.destination("Choose the vault again in Settings › Memory to renew its saved access.")
        }
        // Unsandboxed builds may return false even when the explicitly chosen folder is accessible.
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
    }

    private static func makeClient(destination: WikiExportDestination) throws -> MCPStdioClient {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/zeus")
        let development = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("zeus-cli")
        let url = Bundle.main.bundleURL.pathExtension == "app" ? bundled : development
        guard let url, FileManager.default.isExecutableFile(atPath: url.path) else {
            throw WikiExportError.destination("The bundled Memory export helper is missing. Rebuild or update Zeus before exporting.")
        }
        return MCPStdioClient(launch: .init(executable: url.path,
            arguments: ["memory-mcp", "--vault", destination.rootPath, "--inbox", destination.inbox, "--identity", destination.rootIdentity],
            environment: ["LANG": "en_US.UTF-8"], currentDirectory: nil))
    }

    private static func explanation(_ error: Error) -> String {
        if error is CancellationError { return "Export stopped." }
        if error is MCPClientError { return "The local export helper stopped or did not respond in time." }
        return error.localizedDescription
    }
}

struct WikiMCPExportSheet: View {
    let model: WikiMCPExportModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send selected Memory to your vault").font(.title2.weight(.semibold))
            Text("Review one new Markdown note. Existing notes stay unchanged. Nothing is sent automatically.")
                .font(.callout).foregroundStyle(.secondary)
            if let draft = model.draft {
                Text(draft.destination.displayName).font(.headline)
                Text(draft.destination.relativePath(exportID: draft.id)).font(.caption).textSelection(.enabled)
                Text("\(draft.pages.count) selected pages · \(draft.markdown.utf8.count) bytes").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Text(draft.markdown).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                if draft.sensitiveFindingCount > 0 {
                    Toggle("I reviewed the \(draft.sensitiveFindingCount) sensitive item(s) in this preview", isOn: Binding(
                        get: { model.acknowledgedSensitive }, set: { model.acknowledgedSensitive = $0 }))
                        .disabled(model.busy || model.outcome != nil)
                }
            } else if let outcome = model.outcome {
                Label(outcome.state == .verified ? "Export verified" : "Export invalidated",
                      systemImage: outcome.state == .verified ? "checkmark.circle" : "exclamationmark.circle")
                Text(outcome.destination.displayName).font(.headline)
                Text(outcome.relativePath).font(.caption).textSelection(.enabled)
                Spacer()
            } else {
                Text("Choose up to \(WikiExportDraft.maxPages) pages").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.pages) { page in
                            Toggle(isOn: Binding(get: { model.selectedIDs.contains(page.id) },
                                set: { model.select(page.id, included: $0) })) {
                                    VStack(alignment: .leading) {
                                        Text(page.title)
                                        if page.needsReview { Text("Review this page in Memory first").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.disabled(page.needsReview)
                        }
                    }
                }
            }
            if let message = model.message { Text(message).font(.callout).accessibilityLabel(message) }
            HStack {
                Button(model.busy ? "Stop" : "Close") { model.cancel(); close() }.keyboardShortcut(.cancelAction)
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                if !model.busy {
                    if model.outcome?.state == .uncertain {
                        Button("Abandon recovery…") { model.confirmingAbandon = true }
                        Button("Check result") { model.check() }
                        if model.mayRetry { Button("Retry same export") { model.send() }.buttonStyle(.borderedProminent) }
                    } else if model.outcome != nil {
                        Button("New selection") { model.newSelection() }
                    } else if let draft = model.draft {
                        Button("Back") { model.back() }
                        Button("Export selected") { model.send() }.buttonStyle(.borderedProminent)
                            .disabled(draft.sensitiveFindingCount > 0 && !model.acknowledgedSensitive)
                    } else {
                        Button("Review export") { model.preview() }.buttonStyle(.borderedProminent)
                            .disabled(model.selectedIDs.isEmpty || model.selectedIDs.count > WikiExportDraft.maxPages)
                    }
                }
            }
        }.padding(24).frame(width: 660, height: 620)
            .interactiveDismissDisabled(model.busy)
            .onDisappear { model.cancel() }
            .confirmationDialog("Abandon this export's recovery?", isPresented: Binding(
                get: { model.confirmingAbandon }, set: { model.confirmingAbandon = $0 }), titleVisibility: .visible) {
                    Button("Abandon recovery", role: .destructive) { model.abandonRecovery() }
                    Button("Keep recovery", role: .cancel) { model.confirmingAbandon = false }
                } message: {
                    Text("The note may already exist in your vault. Zeus will erase its private recovery draft and keep the export ID and destination. A future export creates a different note and could duplicate that content.")
                }
    }
}
