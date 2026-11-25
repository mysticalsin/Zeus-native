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
                let state = status[row.kind] ?? .unknown
                let described = PermissionDesk.can(resource: row.kind, action: .describe, status: state)
                let advance = PermissionDesk.can(resource: row.kind, action: .advance, status: state)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.system(size: 13, weight: .semibold))
                        Text(described.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(advance.reason) { allow(row.kind) }
                        .disabled(!advance.can)
                }
            }
            Button("Grant everything") { grantRemaining() }
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .frame(maxWidth: 480, alignment: .leading)
    }
}
