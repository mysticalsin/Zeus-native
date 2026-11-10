import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The fast path's app-side pieces against fake data. Nothing here launches, quits or controls a real app.
@Suite("Fast path")
struct FastPathTests {
    static let index = AppIndex(entries: [
        AppEntry(name: "Spotify", bundleID: "com.spotify.client", path: "/Applications/Spotify.app"),
        AppEntry(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", path: "/Applications/Visual Studio Code.app"),
        AppEntry(name: "Google Chrome", bundleID: "com.google.Chrome", path: "/Applications/Google Chrome.app"),
        AppEntry(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", path: "/Applications/Slack.app"),
        AppEntry(name: "Photos", bundleID: "com.apple.Photos", path: "/System/Applications/Photos.app"),
        AppEntry(name: "Photo Booth", bundleID: "com.apple.PhotoBooth", path: "/System/Applications/Photo Booth.app"),
    ])

    @Test func lookupFindsInstalledApps() {
        guard case .app(let code) = Self.index.lookup("VS Code") else { Issue.record("no match"); return }
        #expect(code.bundleID == "com.microsoft.VSCode")
        guard case .app(let chrome) = Self.index.lookup("chrome") else { Issue.record("no match"); return }
        #expect(chrome.name == "Google Chrome")
        #expect(Self.index.lookup("pod bay doors") == .none)
    }

    @Test func lookupAsksWhenTwoAppsFitEqually() {
        guard case .ambiguous(let a, let b) = Self.index.lookup("photo") else { Issue.record("expected a question"); return }
        #expect(Set([a.name, b.name]) == ["Photos", "Photo Booth"])
    }

    @Test @MainActor func resolveOpensAppsAndAsksOrPassesOtherwise() {
        let actions = FastActions(apps: Self.index)
        guard case .plan(let plan) = actions.resolve(.openApp("spotify", website: nil)) else { Issue.record("no plan"); return }
        #expect(plan.summary.hasSuffix("Spotify"))
        guard case .ask(let question) = actions.resolve(.openApp("photo", website: nil)) else { Issue.record("no question"); return }
        #expect(question.contains("Photos") && question.contains("Photo Booth"))
        guard case .pass = actions.resolve(.openApp("Figma", website: nil)) else { Issue.record("Figma isn't in the fake list"); return }
        guard case .plan(let site) = actions.resolve(.openApp("YouTube", website: URL(string: "https://www.youtube.com"))) else {
            Issue.record("expected the website fallback"); return
        }
        #expect(site.summary == "Open youtube.com")
    }

    @Test func spotifyPlayLabels() {
        #expect(SpotifyAXFinder.playTarget("Play Daft Punk") == "Daft Punk")
        #expect(SpotifyAXFinder.playTarget("Tocar Anitta") == "Anitta")
        #expect(SpotifyAXFinder.playTarget("Play") == nil)
        #expect(SpotifyAXFinder.playTarget("Pause") == nil)
        #expect(SpotifyAXFinder.playTarget("Play (Space)") == nil)
        #expect(SpotifyPlayer.searchURL("Daft Punk & friends")?.absoluteString == "spotify:search:Daft%20Punk%20%26%20friends")
    }

    @Test func scanReadsAppBundlesFromAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-appindex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, id) in [("Fake One", "test.fake.one"), ("Vendor/Fake Two", "test.fake.two")] {
            let contents = folder.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: NSDictionary = ["CFBundleIdentifier": id, "CFBundleName": name.components(separatedBy: "/").last!]
            plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        }
        let found = AppIndex.scan(folders: [folder])
        #expect(found.contains { $0.bundleID == "test.fake.one" && $0.name == "Fake One" })
        #expect(found.contains { $0.bundleID == "test.fake.two" })
    }
}
