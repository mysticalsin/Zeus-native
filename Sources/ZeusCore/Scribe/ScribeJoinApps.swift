import Foundation

// Which apps the meeting card offers to open a call link in. Pure: the app layer reads the installed apps and
// hands them over; this file only says which brand a link belongs to and how the list is ordered and capped.

/// An installed app the link can be opened in. The icon is read from the app itself at run time.
public struct ScribeJoinApp: Equatable, Hashable, Sendable {
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

public enum ScribeJoinApps {
    public static let maxApps = ScribeMeetingCardMetrics.maxApps

    /// The call app whose own links these are, or nil for a link no call brand owns.
    public static func providerBrand(for url: URL) -> AppBrandCatalog.Brand? {
        guard let host = url.host?.lowercased() else { return nil }
        return AppBrandCatalog.brands.first { brand in
            brand.linkHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// The provider's own app first, then the browsers that open the link (the default one first), each app once,
    /// at most `maxApps`.
    public static func choose(provider: [ScribeJoinApp], browsers: [ScribeJoinApp]) -> [ScribeJoinApp] {
        var seen = Set<String>()
        var chosen: [ScribeJoinApp] = []
        for app in provider + browsers where seen.insert(app.bundleID.lowercased()).inserted {
            chosen.append(app)
            if chosen.count == maxApps { break }
        }
        return chosen
    }
}
