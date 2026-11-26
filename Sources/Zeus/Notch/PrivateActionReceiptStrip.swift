import SwiftUI
import ZeusCore

/// The private receipt after a Zeus action. It uses the existing notch glass: a white hairline
/// capsule, the cloud title, and one Undo control. It does not restyle the tab row or the closed bar.
struct PrivateActionReceiptStrip: View {
    let receipt: PrivateActionReceipt
    /// The closed wing already has its own icon and shape, so it draws the words and Undo only.
    var compact = false
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !compact {
                Image(systemName: receipt.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.cloudPrimary)
                    .accessibilityHidden(true)
            }
            Text(receipt.notchLine)
                .font(TopBarStyle.label(11, .semibold))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(1)
            if !compact { Spacer(minLength: 4) }
            Button(receipt.undoLabel, action: undo)
                .buttonStyle(.plain)
                .font(TopBarStyle.label(10.5, .bold))
                .foregroundStyle(Theme.bolt)
                .accessibilityIdentifier(PrivateActionReceiptID.undo)
                .accessibilityLabel(receipt.undoLabel)
        }
        .padding(.horizontal, compact ? 0 : 10)
        .padding(.vertical, compact ? 0 : 6)
        .background {
            if !compact {
                Capsule().fill(Color.white.opacity(0.10))
            }
        }
        .overlay {
            if !compact {
                Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PrivateActionReceiptID.row)
        .accessibilityLabel(receipt.notchLine)
    }
}
