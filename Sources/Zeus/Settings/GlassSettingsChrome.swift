import SwiftUI
import ZeusCore

/// Translucent settings material. Reduce Motion, Reduce Transparency, and Increase Contrast are read, never written.
struct GlassSettingsChrome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let material = GlassSettingsMaterialRules.resolve(GlassSettingsAccess(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased
        ))
        let solid = material.solidFallback || TopBarStyle.isSnapshot
        ZStack {
            if solid {
                GS.window
            } else {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.white.opacity(material.highlightOpacity), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .shadow(color: Color.black.opacity(solid ? 0 : 0.24), radius: solid ? 0 : material.depth, y: solid ? 0 : 10)
        .animation(material.animationDuration == 0 ? nil : .easeOut(duration: material.animationDuration), value: solid)
        .accessibilityHidden(true)
    }
}

/// Soft top highlight on the settings panel. Hidden when the material falls back to solid.
struct GlassSettingsPanelHighlight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let material = GlassSettingsMaterialRules.resolve(GlassSettingsAccess(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased
        ))
        RoundedRectangle(cornerRadius: GS.panelRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(material.solidFallback || TopBarStyle.isSnapshot ? 0 : material.highlightOpacity),
                        Color.white.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: material.solidFallback ? 1 : 1.5
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
