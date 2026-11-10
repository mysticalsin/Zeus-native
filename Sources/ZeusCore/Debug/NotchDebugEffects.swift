import Foundation

/// Names accepted by `zeus debug animate` for notch lights and mascot previews (QA22 silent checks).
public enum NotchDebugEffects {
    public static let lightNames: [String] = [
        "volume", "brightness", "keyboard", "mute", "glow", "pulse", "copy", "edge", "entrance",
        "airdrop", "capslock", "battery", "thinking",
    ]

    public static let mascotStateNames: [String] = [
        "idle", "working", "thinking", "approval_wait", "carrying", "celebrate", "error", "sleep", "wake",
        "listening", "speaking", "agent",
    ]

    public static func recognizes(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lightNames.contains(lower) || mascotStateNames.contains(lower)
            || ["caps-lock", "caps", "spark", "shiftcrest", "shift-crest", "charging", "bloom", "halo", "timer", "music"].contains(lower)
    }
}
