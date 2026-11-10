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
        guard feedEnabled, let feedURL, let url = URL(string: feedURL), !feedURL.isEmpty else { return nil }
        return await FeedUpdateFetcher.fetch(from: url)
    }
}

public enum FeedUpdateFetcher {
    public static func fetch(from url: URL) async -> UpdateOffer? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versionString = json["version"] as? String,
                  let latest = ZeusVersion(parsing: versionString) else { return nil }
            let link = (json["downloadURL"] as? String).flatMap(URL.init(string:))
            return UpdateOffer(latest: latest, downloadURL: link)
        } catch {
            return nil
        }
    }
}

public enum DebugUpdateFake {
    public static let defaultsKey = "debug.updateFakeVersion"
}
