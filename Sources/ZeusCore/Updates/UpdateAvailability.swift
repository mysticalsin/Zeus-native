import Foundation

/// N6: version compare and update badge state (no network in tests).
public struct ZeusVersion: Equatable, Sendable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).prefix(3)
        guard !parts.isEmpty else { return nil }
        let nums = parts.map { Int($0) ?? 0 }
        self.major = nums[safe: 0] ?? 0
        self.minor = nums[safe: 1] ?? 0
        self.patch = nums[safe: 2] ?? 0
    }

    public static func < (lhs: ZeusVersion, rhs: ZeusVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public var displayShort: String { "\(major).\(minor)" }
    public var displayFull: String { "\(major).\(minor).\(patch)" }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public struct UpdateOffer: Equatable, Sendable {
    public var latest: ZeusVersion
    public var downloadURL: URL?
    public init(latest: ZeusVersion, downloadURL: URL? = nil) {
        self.latest = latest
        self.downloadURL = downloadURL
    }
}

/// When feed is off and no debug fake, no badge.
public enum UpdateBadgeState: Equatable, Sendable {
    case hidden
    case available(UpdateOffer, current: ZeusVersion)
}

public enum UpdateDismissalStore {
    public static let key = "updates.dismissedVersion"

    public static func dismissedVersion(from defaults: UserDefaults) -> String? {
        defaults.string(forKey: key)
    }

    public static func dismiss(_ version: ZeusVersion, defaults: UserDefaults) {
        defaults.set(version.displayFull, forKey: key)
    }

    public static func isDismissed(_ offer: UpdateOffer, defaults: UserDefaults) -> Bool {
        dismissedVersion(from: defaults) == offer.latest.displayFull
    }
}

public enum UpdateHUDPresentation {
    public static let shownKey = "updates.hudShownVersion"

    public static func shouldShowHUD(for offer: UpdateOffer, defaults: UserDefaults) -> Bool {
        defaults.string(forKey: shownKey) != offer.latest.displayFull
    }

    public static func markHUDShown(for offer: UpdateOffer, defaults: UserDefaults) {
        defaults.set(offer.latest.displayFull, forKey: shownKey)
    }
}

public enum UpdateBadgeLogic {
    public static func badgeState(current: ZeusVersion, offer: UpdateOffer?, feedEnabled: Bool, debugFake: String?, defaults: UserDefaults) -> UpdateBadgeState {
        let effective: UpdateOffer?
        if let debugFake, let v = ZeusVersion(parsing: debugFake) {
            effective = UpdateOffer(latest: v)
        } else if feedEnabled, let offer {
            effective = offer
        } else {
            effective = nil
        }
        guard let effective, effective.latest > current else { return .hidden }
        if UpdateDismissalStore.isDismissed(effective, defaults: defaults) { return .hidden }
        return .available(effective, current: current)
    }

    public static func rollLabel(from old: ZeusVersion?, to new: ZeusVersion) -> String {
        "Update \(new.displayShort)"
    }
}

public protocol UpdateSource: Sendable {
    func currentVersion() -> ZeusVersion
    func latestOffer(feedEnabled: Bool, feedURL: String?) async -> UpdateOffer?
}

public struct BundleUpdateSource: UpdateSource {
    public let bundleShortVersion: String
    public init(bundleShortVersion: String) { self.bundleShortVersion = bundleShortVersion }
    public func currentVersion() -> ZeusVersion { ZeusVersion(parsing: bundleShortVersion) ?? ZeusVersion(major: 0, minor: 0, patch: 0) }
    public func latestOffer(feedEnabled: Bool, feedURL: String?) async -> UpdateOffer? {
        guard feedEnabled, let feedURL, let url = UpdateFeedPolicy.feedURL(from: feedURL) else { return nil }
        return await FeedUpdateFetcher.fetch(from: url)
    }
}

/// What an update feed and the link inside it may be. There is no signature or hash in the feed
/// format, so the one guarantee is the transport: HTTPS only, no credentials in the URL, and no
/// redirect that leaves HTTPS. The download link only opens in the browser; Zeus never installs it.
public enum UpdateFeedPolicy {
    public static let maximumFeedBytes = 256 * 1024

    public static func isSecure(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return false }
        return url.user == nil && url.password == nil
    }

    /// The feed address typed in Settings, or nil when it is empty, malformed or not HTTPS.
    public static func feedURL(from string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let url = URL(string: trimmed), isSecure(url) else { return nil }
        return url
    }

    /// The download link from the feed; anything but HTTPS is dropped (no file:, http: or app schemes).
    public static func downloadURL(from string: String?) -> URL? {
        feedURL(from: string)
    }
}

/// Refuses any redirect that would leave HTTPS.
final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(UpdateFeedPolicy.isSecure) == true ? request : nil)
    }
}

public enum FeedUpdateFetcher {
    public static func fetch(from url: URL) async -> UpdateOffer? {
        guard UpdateFeedPolicy.isSecure(url) else { return nil }
        let session = URLSession(configuration: .ephemeral, delegate: HTTPSOnlyRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpShouldHandleCookies = false
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.url.map(UpdateFeedPolicy.isSecure) == true,
                  data.count <= UpdateFeedPolicy.maximumFeedBytes else { return nil }
            return offer(from: data)
        } catch {
            return nil
        }
    }

    /// Parses the feed JSON. A bad or non-HTTPS download link is dropped; the version still counts.
    public static func offer(from data: Data) -> UpdateOffer? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let versionString = json["version"] as? String,
              let latest = ZeusVersion(parsing: versionString) else { return nil }
        return UpdateOffer(latest: latest, downloadURL: UpdateFeedPolicy.downloadURL(from: json["downloadURL"] as? String))
    }
}

public enum DebugUpdateFake {
    public static let defaultsKey = "debug.updateFakeVersion"
}
