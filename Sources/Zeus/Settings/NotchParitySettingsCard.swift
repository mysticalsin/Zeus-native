import SwiftUI
import ZeusCore

/// One plain row per notch contract. Held rows show the unavailable phrase and are not controls.
struct NotchParitySettingsCard: View {
    var body: some View {
        GSCard("Notch contracts") {
            ForEach(Array(NotchParitySettings.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { GSDivider() }
                GSRow(symbol: "circle", title: row.title, text: row.status) {
                    Text(row.status)
                        .font(GS.rowText)
                        .foregroundStyle(GS.secondary)
                        .accessibilityLabel(row.status)
                }
            }
        }
    }
}
