import AppKit
import Foundation
import Observation
import ZeusCore

/// N6: resolves whether an update badge should show and handles dismiss / install.
@MainActor
@Observable
final class UpdateCoordinator {
    static let shared = UpdateCoordinator()

    private(set) var badgeState: UpdateBadgeState = .hidden
    var onBadgeDidChange: (() -> Void)?
    private let source: BundleUpdateSource
    private let defaults: UserDefaults
    private var pollTask: Task<Void, Never>?
    private var refreshState = UpdateRefresh.State.idle
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshToken: UInt64 = 0

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        source = BundleUpdateSource(bundleShortVersion: version)
        refreshBadge()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollFeedIfNeeded()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func refreshBadge() {
        let current = source.currentVersion()
        let feedOn = SettingsStore.shared.bool("about.autoUpdate")
        let feedURL = SettingsStore.shared.string("about.updateFeedURL")
        let fake = defaults.string(forKey: DebugUpdateFake.defaultsKey)
        lastRefreshToken &+= 1
        let token = lastRefreshToken
        let (next, effects) = UpdateRefresh.reduce(refreshState, .requested(token: token))
        refreshState = next
        for effect in effects {
            switch effect {
            case .cancelFetch:
                refreshTask?.cancel()
                refreshTask = nil
            case .startFetch:
                refreshTask = Task { @MainActor [weak self] in
                    await self?.fetch(token: token, current: current, feedOn: feedOn, feedURL: feedURL, fake: fake)
                }
            case .apply:
                break
            }
        }
    }

    /// Only the newest request writes the badge: an older check that finishes late is dropped.
    private func fetch(token: UInt64, current: ZeusVersion, feedOn: Bool, feedURL: String, fake: String?) async {
        var offer = await source.latestOffer(feedEnabled: feedOn, feedURL: feedURL)
        if offer == nil, let fake, let v = ZeusVersion(parsing: fake) {
            offer = UpdateOffer(latest: v)
        }
        let (next, effects) = UpdateRefresh.reduce(refreshState, .completed(token: token))
        refreshState = next
        guard effects.contains(.apply(token: token)) else { return }
        refreshTask = nil
        badgeState = UpdateBadgeLogic.badgeState(
            current: current,
            offer: offer,
            feedEnabled: feedOn,
            debugFake: fake,
            defaults: defaults
        )
        onBadgeDidChange?()
        maybePresentHUD()
    }

    @MainActor
    func refreshBadgeSync(offer: UpdateOffer? = nil) {
        // This write is the newest word on the badge: a feed check still in flight must not overwrite it.
        let (next, _) = UpdateRefresh.reduce(refreshState, .invalidated)
        refreshState = next
        refreshTask?.cancel()
        refreshTask = nil
        let current = source.currentVersion()
        let feedOn = SettingsStore.shared.bool("about.autoUpdate")
        let fake = defaults.string(forKey: DebugUpdateFake.defaultsKey)
        badgeState = UpdateBadgeLogic.badgeState(
            current: current,
            offer: offer,
            feedEnabled: feedOn,
            debugFake: fake,
            defaults: defaults
        )
        onBadgeDidChange?()
    }

    func setDebugFakeVersion(_ version: String?) {
        if let version, !version.isEmpty {
            defaults.set(version, forKey: DebugUpdateFake.defaultsKey)
        } else {
            defaults.removeObject(forKey: DebugUpdateFake.defaultsKey)
        }
        refreshBadge()
    }

    func dismissCurrent() {
        guard case .available(let offer, _) = badgeState else { return }
        UpdateDismissalStore.dismiss(offer.latest, defaults: defaults)
        refreshBadge()
    }

    func performUpdate() {
        guard case .available(let offer, _) = badgeState else { return }
        // The offer's link is re-checked here: only HTTPS ever reaches the browser.
        if let url = offer.downloadURL, UpdateFeedPolicy.isSecure(url) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://zeus.app") {
            NSWorkspace.shared.open(url)
        }
    }

    var menuBarBadgeText: String? {
        guard case .available(let offer, _) = badgeState else { return nil }
        return UpdateBadgeLogic.rollLabel(from: nil, to: offer.latest)
    }

    private func pollFeedIfNeeded() async {
        await MainActor.run { refreshBadge() }
    }

    private func maybePresentHUD() {
        guard case .available(let offer, _) = badgeState else { return }
        guard UpdateHUDPresentation.shouldShowHUD(for: offer, defaults: defaults) else { return }
        UpdateHUDPresentation.markHUDShown(for: offer, defaults: defaults)
        NotchControllerBridge.controller?.showUpdateBadge(offer: offer)
    }
}

extension NotchController {
    func showUpdateBadge(offer: UpdateOffer) {
        let line = NotchModel.NotificationLine(
            id: Int64(offer.latest.major * 10_000 + offer.latest.minor * 100 + offer.latest.patch),
            app: "Zeus",
            title: UpdateBadgeLogic.rollLabel(from: nil, to: offer.latest),
            detail: ""
        )
        showNotificationLine(line)
    }
}
