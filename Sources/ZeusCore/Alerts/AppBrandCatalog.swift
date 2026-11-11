import Foundation

/// Apps whose own icon Zeus shows (alerts, lists), identified by bundle id. The icon itself is read from
/// the installed app at runtime (`NSWorkspace.icon(forFile:)`), so no trademark artwork is bundled. This
/// table only says which bundle ids are the same app (stable, beta and renamed builds), where the app
/// usually lives when launch services cannot find it, and a neutral symbol for when it is not installed.
public enum AppBrandCatalog {
    public struct Brand: Equatable, Sendable {
        public var name: String
        public var bundleIDs: [String]
        /// Absolute paths tried when no bundle id resolves.
        public var paths: [String]
        /// An SF Symbol, never a brand mark.
        public var glyph: String
    }

    public static let brands: [Brand] = [
        Brand(name: "Spotify", bundleIDs: ["com.spotify.client"], paths: ["/Applications/Spotify.app"], glyph: "music.note"),
        Brand(name: "Google Chrome",
              bundleIDs: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"],
              paths: ["/Applications/Google Chrome.app"], glyph: "globe"),
        Brand(name: "Notion", bundleIDs: ["notion.id", "com.notion.desktop"], paths: ["/Applications/Notion.app"], glyph: "doc.text"),
        Brand(name: "Notion Calendar", bundleIDs: ["com.cron.electron", "notion.calendar"],
              paths: ["/Applications/Notion Calendar.app"], glyph: "calendar"),
        Brand(name: "Dropbox", bundleIDs: ["com.getdropbox.dropbox"], paths: ["/Applications/Dropbox.app"], glyph: "shippingbox"),
        Brand(name: "Terminal", bundleIDs: ["com.apple.Terminal"], paths: ["/System/Applications/Utilities/Terminal.app"], glyph: "terminal"),
        Brand(name: "iTerm", bundleIDs: ["com.googlecode.iterm2"], paths: ["/Applications/iTerm.app"], glyph: "terminal"),
        Brand(name: "Ghostty", bundleIDs: ["com.mitchellh.ghostty"], paths: ["/Applications/Ghostty.app"], glyph: "terminal"),
        Brand(name: "Warp", bundleIDs: ["dev.warp.Warp-Stable", "dev.warp.Warp"], paths: ["/Applications/Warp.app"], glyph: "terminal"),
        Brand(name: "Alacritty", bundleIDs: ["org.alacritty"], paths: ["/Applications/Alacritty.app"], glyph: "terminal"),
        Brand(name: "kitty", bundleIDs: ["net.kovidgoyal.kitty"], paths: ["/Applications/kitty.app"], glyph: "terminal"),
        Brand(name: "WezTerm", bundleIDs: ["com.github.wez.wezterm"], paths: ["/Applications/WezTerm.app"], glyph: "terminal"),
        Brand(name: "Zoom", bundleIDs: ["us.zoom.xos"], paths: ["/Applications/zoom.us.app"], glyph: "video"),
        Brand(name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
              paths: ["/Applications/Microsoft Teams.app"], glyph: "person.2"),
        Brand(name: "Webex", bundleIDs: ["Cisco-Systems.Spark", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager"],
              paths: ["/Applications/Webex.app"], glyph: "video"),
        Brand(name: "Google Meet", bundleIDs: ["com.google.meet"], paths: ["/Applications/Google Meet.app"], glyph: "video"),
    ]

    public static func brand(for bundleID: String) -> Brand? {
        let key = bundleID.lowercased()
        return brands.first { $0.bundleIDs.contains { $0.lowercased() == key } }
    }

    /// The id itself first, then the other bundle ids of the same app. Always at least `[bundleID]`.
    public static func candidateBundleIDs(for bundleID: String) -> [String] {
        guard let brand = brand(for: bundleID) else { return [bundleID] }
        return [bundleID] + brand.bundleIDs.filter { $0.lowercased() != bundleID.lowercased() }
    }

    public static func fallbackPaths(for bundleID: String) -> [String] { brand(for: bundleID)?.paths ?? [] }

    /// A neutral symbol for a known app, or nil.
    public static func glyph(for bundleID: String) -> String? { brand(for: bundleID)?.glyph }
}
