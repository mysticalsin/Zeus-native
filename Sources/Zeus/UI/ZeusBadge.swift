import SwiftUI
import ZeusCore

/// N6: native badge inspired by easyui (MIT, https://easyui.site/).
struct ZeusBadge: View {
    enum Variant { case accent, muted, danger }

    let text: String
    var variant: Variant = .accent
    var pulsingDot = false
    var dismiss: (() -> Void)?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if pulsingDot {
                Circle()
                    .fill(Color(red: 0.55, green: 0.95, blue: 0.75))
                    .frame(width: 6, height: 6)
            }
            Button {
                action?()
            } label: {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(foreground.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(foreground)
        .background(Capsule(style: .continuous).fill(background))
        .overlay(Capsule(style: .continuous).strokeBorder(foreground.opacity(0.15), lineWidth: 0.5))
    }

    private var foreground: Color {
        switch variant {
        case .accent: Color(red: 0.96, green: 0.98, blue: 1)
        case .muted: Color.white.opacity(0.85)
        case .danger: Color(red: 1, green: 0.92, blue: 0.92)
        }
    }

    private var background: Color {
        switch variant {
        case .accent: Color(red: 0.35, green: 0.55, blue: 0.98)
        case .muted: Color.white.opacity(0.12)
        case .danger: Color(red: 0.72, green: 0.18, blue: 0.22)
        }
    }
}

struct SettingsUpdateBadgeRow: View {
    @Bindable var updates = UpdateCoordinator.shared

    var body: some View {
        if case .available(let offer, _) = updates.badgeState {
            ZeusBadge(
                text: UpdateBadgeLogic.rollLabel(from: nil, to: offer.latest),
                pulsingDot: true,
                dismiss: { updates.dismissCurrent() },
                action: { updates.performUpdate() }
            )
            .padding(.bottom, 8)
        }
    }
}

struct MenuBarUpdateBadge: View {
    @Bindable var updates = UpdateCoordinator.shared

    var body: some View {
        if case .available(let offer, _) = updates.badgeState {
            ZeusBadge(
                text: UpdateBadgeLogic.rollLabel(from: nil, to: offer.latest),
                pulsingDot: true,
                action: { updates.performUpdate() }
            )
            .fixedSize()
        }
    }
}
