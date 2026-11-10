import SwiftUI
import ZeusCore

/// Colour and shape tokens from the ZEUS design spec.
/// App accent is purple lighting; yellow/gold is reserved for the mascot only (COLOR DIRECTION).
enum Theme {
    static let storm = Color(hex: 0x0E1116)
    static let cloudPrimary = Color(hex: 0xE9EDF2)
    static let cloudSecondary = Color(hex: 0xA3ADB8)
    static let cloudQuiet = Color(hex: 0x8A94A0) // 5.5:1 on cards, 6.2:1 on storm (HIG minimum 4.5:1)

    // MARK: Zeus purple lighting (app accent, glows, highlights) — ZeusThemeTokens
    /// Primary accent. Everywhere Glance uses accent/glow/lighting, use this.
    static let zeusPurple = Color(hex: ZeusThemeTokens.zeusPurple)
    /// Soft glow and lighting blooms.
    static let zeusPurpleGlow = Color(hex: ZeusThemeTokens.zeusPurpleGlow)
    /// Pressed / dark accents. Keep text contrast AA on this fill.
    static let zeusPurpleDeep = Color(hex: ZeusThemeTokens.zeusPurpleDeep)

    static let accent = zeusPurple
    static let glow = zeusPurpleGlow
    static let accentDeep = zeusPurpleDeep

    // MARK: Mascot only (design/mascot-v2 design-tokens.json)
    static let lightningGold = Color(hex: ZeusThemeTokens.lightningGold)
    static let cloudIvory = Color(hex: ZeusThemeTokens.cloudIvory)
    static let scarfCobalt = Color(hex: ZeusThemeTokens.scarfCobalt)
    /// Alias for mascot gold. Do not use as the app accent.
    static let bolt = lightningGold

    static let sky = Color(hex: 0x4DA3FF)
    static let ember = Color(hex: 0xFF8A3D)
    static let leaf = Color(hex: 0x3CCB7F)
    static let danger = Color(hex: 0xFF5A5F)

    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 12
    static let bubbleRadius: CGFloat = 8
    static let panelWidth: CGFloat = 320
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
