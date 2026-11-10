import Foundation

/// Central colour tokens (COLOR DIRECTION). App UI reads these via `Theme` in the Zeus target.
/// Yellow/gold is for the mascot only — never the app accent.
public enum ZeusThemeTokens: Sendable {
    public static let zeusPurple: UInt32 = 0x8B5CF6
    public static let zeusPurpleGlow: UInt32 = 0xA78BFA
    public static let zeusPurpleDeep: UInt32 = 0x5B21B6
    public static let lightningGold: UInt32 = 0xF5BA32
    public static let cloudIvory: UInt32 = 0xFFF3E0
    public static let scarfCobalt: UInt32 = 0x1557E7

    /// Accents that must never equal mascot gold.
    public static var accentTokens: [UInt32] { [zeusPurple, zeusPurpleGlow, zeusPurpleDeep] }
}
