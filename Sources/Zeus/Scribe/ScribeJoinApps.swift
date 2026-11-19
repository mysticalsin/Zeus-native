import AppKit
import ZeusCore

/// Reads the installed apps a call link can be opened in, and opens it in one of them. The icons come from the
/// apps themselves (`AppIconCache`), so nothing is bundled. The choice and the order are `ScribeJoinApps` in core.
@MainActor
final class ScribeJoinAppResolver {
    static let shared = ScribeJoinAppResolver()

    /// The seams to Launch Services, so a test can describe a Mac without touching this one.
    struct Workspace {
        /// The app with this bundle id, if installed.
        var applicationURL: (String) -> URL?
        /// The apps that open this link, the default one first.
        var browsers: (URL) -> [URL]
        /// The name the person sees for the app at this URL.
        var displayName: (URL) -> String
        var bundleID: (URL) -> String?
        var open: (URL, URL) -> Void

        static var live: Workspace { Workspace(
            applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            browsers: { link in
                var urls = NSWorkspace.shared.urlsForApplications(toOpen: link)
                if let preferred = NSWorkspace.shared.urlForApplication(toOpen: link) {
                    urls.removeAll { $0 == preferred }
                    urls.insert(preferred, at: 0)
                }
                return urls
            },
            displayName: { FileManager.default.displayName(atPath: $0.path) },
            bundleID: { Bundle(url: $0)?.bundleIdentifier },
            open: { link, app in
                NSWorkspace.shared.open([link], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }) }
    }

    private let workspace: Workspace
    private var cache: [URL: [ScribeJoinApp]] = [:]

    init(workspace: Workspace = .live) { self.workspace = workspace }

    /// The apps to offer for this meeting: none without a link. Remembered per link, since the card asks on
    /// every redraw and the installed apps do not change while a card is up.
    func apps(for meeting: ScribeMeeting) -> [ScribeJoinApp] {
        guard let link = meeting.slot?.callLink else { return [] }
        return apps(for: link)
    }

    func apps(for link: URL) -> [ScribeJoinApp] {
        if let cached = cache[link] { return cached }
        var provider: [ScribeJoinApp] = []
        if let brand = ScribeJoinApps.providerBrand(for: link),
           let id = brand.bundleIDs.first(where: { workspace.applicationURL($0) != nil }) {
            provider = [ScribeJoinApp(name: brand.name, bundleID: id)]
        }
        let browsers = workspace.browsers(link).compactMap { url -> ScribeJoinApp? in
            guard let id = workspace.bundleID(url) else { return nil }
            return ScribeJoinApp(name: workspace.displayName(url), bundleID: id)
        }
        let chosen = ScribeJoinApps.choose(provider: provider, browsers: browsers)
        cache[link] = chosen
        return chosen
    }

    /// Opens the card's link in `app`. Nothing happens for a card with no link.
    func open(_ card: ScribeMeetingCard, in app: ScribeJoinApp) {
        guard let link = card.meeting?.slot?.callLink, let appURL = workspace.applicationURL(app.bundleID) else { return }
        workspace.open(link, appURL)
    }
}
