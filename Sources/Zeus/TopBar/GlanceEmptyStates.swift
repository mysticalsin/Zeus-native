import SwiftUI
import ZeusCore

/// Glance's two-panel empty / permission layout (Chat, Alerts): a quiet left ornament card and a
/// right card with title, one line, and primary actions. Zeus branding only (bolt avatar, Zeus copy).
struct GlanceSplitEmpty: View {
    var leftTitle: String
    var left: AnyView
    var title: String
    var detail: String
    var primary: String?
    var primaryAction: () -> Void = {}
    var secondary: String? = nil
    var secondaryAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(leftTitle)
                    .font(TopBarStyle.label(12, .semibold))
                    .foregroundStyle(Theme.cloudPrimary)
                Spacer(minLength: 0)
                left
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 210)
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }

            VStack(spacing: 12) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(TopBarStyle.label(12))
                    .foregroundStyle(Theme.cloudSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack(spacing: 10) {
                    if let primary {
                        Button(action: primaryAction) {
                            Text(primary)
                                .font(TopBarStyle.label(12, .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .frame(height: 34)
                                .background(Capsule().fill(.white))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if let secondary {
                        Button(action: secondaryAction) {
                            Text(secondary)
                                .font(TopBarStyle.label(12, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 34)
                                .background(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
