import Foundation
import Observation
import SwiftUI
import ZeusCore

/// Settings state for the Updates card. Checks run only after the person asks, or after they turn automatic checks on.
@MainActor
@Observable
final class UpdatesSessionModel {
    var state: UpdateSessionState
    var lastChecked: Date?
    var confirming = false
    var context: UpdateContext
    private var schedule: Task<Void, Never>?
    private var fetchToken = UUID()

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = UpdateVersions.release(info["CFBundleShortVersionString"] as? String ?? "")
        let store = SettingsStore.shared
        var configuration = UpdateConfiguration.resolve(
            automaticChecks: store.bool(UpdateConfiguration.automaticChecksKey),
            feedSetting: store.string(UpdateConfiguration.feedURLKey),
            bundleInfo: info
        )
        if version == nil { configuration.automaticChecks = false }
        context = UpdateContext(
            configuration: configuration,
            currentVersion: version ?? ZeusVersion(major: 0, minor: 0, patch: 0),
            duringTests: UpdateTestGuard.isRunningTests(),
            disposableCopy: false,
            now: Date(),
            reduceMotion: Motion.reduced,
            acceptsUpdates: version != nil
        )
        state = UpdateSession.initial(context)
    }

    var card: UpdatesCardModel {
        context.reduceMotion = Motion.reduced
        return UpdatesCard.model(state: state, context: context, lastChecked: lastChecked, confirmingInstall: confirming)
    }

    func appear() {
        reloadConfiguration()
        SettingsStore.shared.actions[UpdateConfiguration.checkNowKey] = { [weak self] in self?.checkNow() }
        guard context.canAct, context.configuration.automaticChecks else { return }
        checkNow()
        startSchedule()
    }

    func setAutomatic(_ enabled: Bool) {
        guard context.canAct else { return }
        SettingsStore.shared.set(UpdateConfiguration.automaticChecksKey, enabled ? "true" : "false")
        context.configuration.automaticChecks = enabled
        if !enabled {
            schedule?.cancel()
            schedule = nil
        }
        for event in UpdateCommands.events(forAutomaticChecks: enabled, configured: true) {
            apply(event)
        }
        if enabled { startSchedule() }
    }

    func setFeed(_ value: String) {
        SettingsStore.shared.set(UpdateConfiguration.feedURLKey, value)
        reloadConfiguration()
    }

    func checkNow() {
        confirming = false
        apply(.checkRequested)
    }

    func download() {
        apply(.downloadRequested)
    }

    func beginInstall() {
        guard case .readyToInstall = state else { return }
        confirming = true
    }

    func confirmInstall() {
        apply(.installRequested)
        confirming = false
    }

    func cancelInstall() {
        confirming = false
    }

    private func reloadConfiguration() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = UpdateVersions.release(info["CFBundleShortVersionString"] as? String ?? "")
        context.configuration = UpdateConfiguration.resolve(
            automaticChecks: SettingsStore.shared.bool(UpdateConfiguration.automaticChecksKey),
            feedSetting: SettingsStore.shared.string(UpdateConfiguration.feedURLKey),
            bundleInfo: info
        )
        context.acceptsUpdates = version != nil
        context.duringTests = UpdateTestGuard.isRunningTests()
        if let version { context.currentVersion = version }
        if !context.canAct {
            state = .disabled
            confirming = false
        }
    }

    private func apply(_ event: UpdateEvent) {
        context.now = Date()
        context.reduceMotion = Motion.reduced
        let step = UpdateSession.reduce(state, event, context)
        state = step.state
        if step.recordCheck { lastChecked = context.now }
        if case .failed = state { confirming = false }
        perform(step.effects)
    }

    private func perform(_ effects: [UpdateEffect]) {
        for effect in effects {
            switch effect {
            case .fetchFeed:
                guard let url = context.configuration.secureFeedURL else { continue }
                let token = UUID()
                fetchToken = token
                Task { await self.fetch(url, token: token) }
            case .cancelNetwork:
                fetchToken = UUID()
                SignedUpdateBridge.shared.cancel()
            case .download:
                guard case .downloading(let candidate) = state else { continue }
                SignedUpdateBridge.shared.beginDownload(candidate: candidate, context: context) { [weak self] event in
                    Task { @MainActor in self?.apply(event) }
                }
            case .install:
                SignedUpdateBridge.shared.confirmInstall { [weak self] event in
                    Task { @MainActor in self?.apply(event) }
                }
            case .relaunch:
                SignedUpdateBridge.shared.relaunchIfAllowed(context)
            case .discardStagedUpdate, .rollback:
                SignedUpdateBridge.shared.cancel()
            case .verify, .armAutomaticChecks:
                break
            }
        }
    }

    private func fetch(_ url: URL, token: UUID) async {
        let result = await UpdateFeedTransport.load(url)
        guard fetchToken == token else { return }
        switch result {
        case .failure(let reason):
            apply(.checkFailed(reason))
        case .success(let data):
            switch UpdateFeedDocument.candidates(from: data) {
            case .failure(let reason):
                apply(.checkFailed(reason))
            case .success(let items):
                if let best = UpdateFeedDocument.best(items) {
                    apply(.checkOffer(best))
                } else {
                    apply(.checkUpToDate)
                }
            }
        }
    }

    private func startSchedule() {
        schedule?.cancel()
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled, let self else { return }
                guard self.context.canAct, self.context.configuration.automaticChecks else { return }
                self.checkNow()
            }
        }
    }
}
