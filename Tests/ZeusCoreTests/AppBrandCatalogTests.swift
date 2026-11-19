import Foundation
import Testing
@testable import ZeusCore

@Suite("App brand catalog")
struct AppBrandCatalogTests {
    @Test func everyBundleIdBelongsToOneBrand() {
        let ids = AppBrandCatalog.brands.flatMap { $0.bundleIDs.map { $0.lowercased() } }
        #expect(ids.count == Set(ids).count)
    }

    @Test func coversTheLogosTheLedgerListed() {
        for id in ["com.spotify.client", "com.google.Chrome", "notion.id", "com.getdropbox.dropbox", "com.apple.Terminal",
                   "com.googlecode.iterm2", "us.zoom.xos", "com.microsoft.teams2", "Cisco-Systems.Spark"] {
            #expect(AppBrandCatalog.brand(for: id) != nil, "\(id)")
        }
    }

    @Test func lookupIgnoresCaseAndListsSiblingBuilds() {
        let ids = AppBrandCatalog.candidateBundleIDs(for: "COM.GOOGLE.CHROME.BETA")
        #expect(ids.first == "COM.GOOGLE.CHROME.BETA")
        #expect(ids.contains("com.google.Chrome"))
        #expect(!ids.dropFirst().contains { $0.lowercased() == "com.google.chrome.beta" })
    }

    @Test func anUnknownAppKeepsItsOwnIdOnly() {
        #expect(AppBrandCatalog.candidateBundleIDs(for: "org.example.thing") == ["org.example.thing"])
        #expect(AppBrandCatalog.fallbackPaths(for: "org.example.thing").isEmpty)
        #expect(AppBrandCatalog.glyph(for: "org.example.thing") == nil)
    }

    @Test func fallbackPathsAreAbsoluteAppBundles() {
        for brand in AppBrandCatalog.brands {
            #expect(brand.paths.allSatisfy { $0.hasPrefix("/") && $0.hasSuffix(".app") }, "\(brand.name)")
            #expect(!brand.glyph.isEmpty)
        }
    }

    @Test func alertGlyphUsesTheCatalogOnlyForKnownApps() {
        #expect(AlertAppGlyph.symbol(for: "com.spotify.client") == "music.note")
        #expect(AlertAppGlyph.symbol(for: "com.microsoft.teams2") == "person.2.fill")
        #expect(AlertAppGlyph.symbol(for: "unknown.app") == "app.fill")
    }
}
