import SwiftUI

/// One row per capability. Allow asks the system when it can, and opens the pane when it cannot.
struct PermissionDeskView: View {
    var status: [PermissionDesk.Kind: PermissionDesk.Status]
    var allow: (PermissionDesk.Kind) -> Void
    var grantRemaining: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.system(size: 16, weight: .semibold))
            ForEach(PermissionDesk.rows, id: \.kind) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.system(size: 13, weight: .semibold))
                        Text(label(status[row.kind] ?? .unknown)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(row.canPrompt ? "Allow" : "Open Settings") { allow(row.kind) }
                        .disabled(status[row.kind] == .allowed)
                }
            }
            Button("Grant everything") { grantRemaining() }
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func label(_ status: PermissionDesk.Status) -> String {
        switch status {
        case .unknown: "Not asked"
        case .allowed: "Allowed"
        case .denied: "Not allowed"
        case .unavailable: "Unavailable"
        }
    }
}
