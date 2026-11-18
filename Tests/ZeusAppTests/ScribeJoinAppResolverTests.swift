import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The apps a call link opens in, read from a described Mac and not from this one.
@MainActor
@Suite("Join app resolver")
struct ScribeJoinAppResolverTests {
    private final class Mac {
        var installed: [String: URL] = [:]
        var browsers: [URL] = []
        var opened: [(link: URL, app: URL)] = []
        var browserQueries = 0

        func workspace() -> ScribeJoinAppResolver.Workspace {
            .init(applicationURL: { self.installed[$0] },
                  browsers: { _ in self.browserQueries += 1; return self.browsers },
                  displayName: { $0.deletingPathExtension().lastPathComponent },
                  bundleID: { url in self.installed.first { $0.value == url }?.key },
                  open: { self.opened.append(($0, $1)) })
        }
    }

    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Applications/\(name).app") }

    /// A link on the first call brand's own host, and that brand's first bundle id.
    private var brand: AppBrandCatalog.Brand { AppBrandCatalog.brands.first { !$0.linkHosts.isEmpty }! }
    private var link: URL { URL(string: "https://\(brand.linkHosts[0])/j/1")! }

    private func meeting(link: URL?) -> ScribeMeeting {
        let slot = ScribeCalendarSlot(id: "m", title: "M", start: Date(timeIntervalSince1970: 1_800_000_000),
                                      hasCallLink: link != nil, callLink: link)
        return ScribeMeeting(key: "m", title: "M", callApp: .other("Synthetic"), slot: slot)
    }

    @Test func theInstalledProviderAppComesFirstThenTheBrowsersTheDefaultFirst() {
        let mac = Mac()
        mac.installed = [brand.bundleIDs[0]: url("Provider"), "b.one": url("One"), "b.two": url("Two")]
        mac.browsers = [url("One"), url("Two")]
        let apps = ScribeJoinAppResolver(workspace: mac.workspace()).apps(for: link)
        #expect(apps.map(\.bundleID) == [brand.bundleIDs[0], "b.one", "b.two"])
        #expect(apps.first?.name == brand.name)
        #expect(apps.dropFirst().map(\.name) == ["One", "Two"])
    }

    @Test func aProviderAppThatIsNotInstalledIsLeftOut() {
        let mac = Mac()
        mac.installed = ["b.one": url("One")]
        mac.browsers = [url("One")]
        #expect(ScribeJoinAppResolver(workspace: mac.workspace()).apps(for: link).map(\.bundleID) == ["b.one"])
    }

    @Test func aLinkNoCallBrandOwnsOffersOnlyTheBrowsers() {
        let mac = Mac()
        mac.installed = ["b.one": url("One")]
        mac.browsers = [url("One")]
        let other = URL(string: "https://example.org/room")!
        #expect(ScribeJoinAppResolver(workspace: mac.workspace()).apps(for: other).map(\.bundleID) == ["b.one"])
    }

    @Test func atMostFourAreOffered() {
        let mac = Mac()
        for index in 1...6 { mac.installed["b.\(index)"] = url("B\(index)") }
        mac.browsers = (1...6).map { url("B\($0)") }
        #expect(ScribeJoinAppResolver(workspace: mac.workspace()).apps(for: link).count == 4)
    }

    @Test func aMeetingWithNoLinkHasNoAppsAndNothingIsAsked() {
        let mac = Mac()
        let resolver = ScribeJoinAppResolver(workspace: mac.workspace())
        #expect(resolver.apps(for: meeting(link: nil)).isEmpty)
        #expect(mac.browserQueries == 0)
    }

    @Test func theAnswerIsRememberedPerLink() {
        let mac = Mac()
        mac.installed = ["b.one": url("One")]
        mac.browsers = [url("One")]
        let resolver = ScribeJoinAppResolver(workspace: mac.workspace())
        _ = resolver.apps(for: link)
        _ = resolver.apps(for: link)
        #expect(mac.browserQueries == 1)
    }

    @Test func openingHandsTheCardsLinkToTheChosenApp() {
        let mac = Mac()
        mac.installed = ["b.one": url("One")]
        let resolver = ScribeJoinAppResolver(workspace: mac.workspace())
        let app = ScribeJoinApp(name: "One", bundleID: "b.one")
        resolver.open(.offer(meeting(link: link), blocked: nil), in: app)
        #expect(mac.opened.count == 1 && mac.opened.first?.link == link && mac.opened.first?.app == url("One"))
    }

    @Test func openingDoesNothingWithoutALinkOrWithAnAppThatIsGone() {
        let mac = Mac()
        mac.installed = ["b.one": url("One")]
        let resolver = ScribeJoinAppResolver(workspace: mac.workspace())
        resolver.open(.offer(meeting(link: nil), blocked: nil), in: ScribeJoinApp(name: "One", bundleID: "b.one"))
        resolver.open(.offer(meeting(link: link), blocked: nil), in: ScribeJoinApp(name: "Gone", bundleID: "b.gone"))
        #expect(mac.opened.isEmpty)
    }
}
