import Observation
import SwiftUI
import ZeusCore

/// Settings > Integrations > AI Connections. The rows come from `AIConnectionRegistry`.
/// A pasted key is handed to `Keychain.store` and cleared from the draft. The draft is not saved.
@MainActor
@Observable
final class DirectConnectionsModel {
    static let shared = DirectConnectionsModel()

    private var session: AIConnectionSession
    private let store: KeychainStore
    private(set) var notice: String?

    init(session: AIConnectionSession? = nil, store: KeychainStore = Keychain.store) {
        self.session = session ?? AIConnectionSession(defaults: .standard)
        self.store = store
    }

    var rows: [AIConnectionSectionRow] { session.rows }

    func draft(for plugID: String) -> String { session.draft(for: plugID) }

    func setDraft(_ value: String, plugID: String) {
        var next = session
        next.setDraft(value, plugID: plugID)
        session = next
    }

    func status(for kind: AIConnectionKind) -> AIConnectionStatus { session.status(for: kind, store: store) }

    func secretSaved(_ plug: AIConnectionPlug) -> Bool { session.secretSaved(plug, store: store) }

    func save(_ plug: AIConnectionPlug) {
        var next = session
        let result = next.saveDraft(plugID: plug.id, store: store)
        session = next
        switch result {
        case .saved, .empty: notice = nil
        case .refused: notice = "Couldn't save the key. Check Keychain access and try again."
        }
    }

    func remove(_ plug: AIConnectionPlug) {
        var next = session
        let result = next.removeSecret(plugID: plug.id, store: store)
        session = next
        notice = result == .removed ? nil : "Couldn't remove the key. Check Keychain access and try again."
    }
}

struct DirectConnectionsCard: View {
    private var model: DirectConnectionsModel { .shared }

    var body: some View {
        GSCard("AI Connections") {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { GSDivider() }
                connection(row)
            }
            if let notice = model.notice, !notice.isEmpty { GSInfo(text: notice) }
            GSInfo(text: "Nothing is sent from this page. A saved key stays in the Keychain.")
        }
    }

    private func connection(_ row: AIConnectionSectionRow) -> some View {
        let status = model.status(for: row.kind)
        let names = row.plugs.map(\.title).joined(separator: ", ")
        let text = names.isEmpty ? row.kind.summary : "\(names). \(row.kind.summary)"
        return VStack(spacing: 0) {
            GSRow(symbol: symbol(row.kind), title: row.kind.title, text: text) {
                GSStatus(ok: status.saved, text: status.label)
            }
            ForEach(row.secretPlugs) { plug in
                GSDivider()
                keyRow(plug)
            }
        }
    }

    private func keyRow(_ plug: AIConnectionPlug) -> some View {
        let saved = model.secretSaved(plug)
        let draft = model.draft(for: plug.id)
        let placeholder = saved && draft.isEmpty ? "Saved" : "Paste a key"
        return GSRow(title: "API key", text: saved
                     ? "Saved in the Keychain for \(plug.title). This page does not send it."
                     : "Paste a key. It is saved in the Keychain and not in settings.") {
            HStack(spacing: 10) {
                SecureField(placeholder, text: Binding(get: { model.draft(for: plug.id) }, set: { model.setDraft($0, plugID: plug.id) }))
                    .textFieldStyle(.plain)
                    .snapshotSafeText(draft, placeholder: placeholder, secure: true)
                    .font(OB.font(13.5)).foregroundStyle(GS.text)
                    .padding(.horizontal, 10).frame(width: 220, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                    .accessibilityLabel("\(plug.title) API key")
                    .onSubmit { model.save(plug) }
                Button("Save key") { model.save(plug) }
                    .buttonStyle(GSButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Save \(plug.title) key")
                if saved {
                    Button("Remove") { model.remove(plug) }
                        .buttonStyle(GSButtonStyle())
                        .accessibilityLabel("Remove \(plug.title) key")
                }
            }
        }
    }

    private func symbol(_ kind: AIConnectionKind) -> String {
        switch kind {
        case .cloudProtocol: "cloud"
        case .cli: "terminal"
        case .cursor: "cursorarrow"
        case .elevenLabsAPI: "waveform"
        case .modelAPI: "square.stack.3d.up"
        case .voiceChat: "bubble.left.and.bubble.right"
        }
    }
}
