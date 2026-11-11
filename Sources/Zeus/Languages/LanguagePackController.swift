import AppKit
import Observation
import ZeusCore

/// Performs the effects of the pure `LanguagePackState` reducer: asks macOS for language assets, one at a
/// time, at utility priority. It only ever acts on languages the owner ticked (the `wanted` consent), and
/// never at launch before that consent exists. See docs/LANGUAGE-PACKS.md.
@MainActor
@Observable
final class LanguagePackController {
    static let shared = LanguagePackController()
    static let wantedKey = "zeus.languagePacks.wanted"

    private(set) var state: LanguagePackState
    /// The ticks on the onboarding step. All four start ticked.
    var onboardingChoice: Set<LanguagePackID> = LanguagePackID.defaults

    @ObservationIgnored private var pendingAfterOnboarding: Set<LanguagePackID>?
    @ObservationIgnored private var installTasks: [UInt64: Task<Void, Never>] = [:]
    @ObservationIgnored private var powerWatch: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = LanguagePackState(analyzerSupported: LanguageAssets.isSupportedOS,
                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    // MARK: Launch

    /// Called once after startup. Reads the saved consent, asks macOS what is already installed and
    /// continues what an earlier quit interrupted. Returns immediately; the work runs off the main actor.
    func resumeOnLaunch() {
        let wanted = LanguagePackConsent.decode(defaults.stringArray(forKey: Self.wantedKey))
        send(.launched(wanted: wanted, analyzerSupported: LanguageAssets.isSupportedOS,
                       lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
        if !wanted.isEmpty { watchPower() }
    }

    // MARK: Onboarding

    /// "Continue" on the Languages step: remember the ticks. Nothing downloads yet.
    func confirmOnboardingChoice() { pendingAfterOnboarding = onboardingChoice }

    /// "Set up later" on the Languages step: no consent was given.
    func declineOnboardingChoice() { pendingAfterOnboarding = nil }

    /// The guide has finished: only now does the chosen set start installing.
    func startAfterOnboarding() {
        guard let chosen = pendingAfterOnboarding, !chosen.isEmpty else { return }
        pendingAfterOnboarding = nil
        watchPower()
        send(.installRequested(chosen, source: .onboarding))
    }

    // MARK: Settings actions (the owner tapped them)

    func install(_ pack: LanguagePackID) { installOwner([pack]) }
    func installAll() { installOwner(LanguagePackID.defaults) }
    func remove(_ pack: LanguagePackID) { send(.removeRequested(pack)) }
    func cancel() { send(.cancelRequested) }
    func installNow() { send(.installNowTapped) }

    /// macOS manages Apple's older on-device dictation languages; this only opens its pane.
    func openDictationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Dictation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installOwner(_ packs: Set<LanguagePackID>) {
        watchPower()
        send(.installRequested(packs, source: .owner))
    }

    // MARK: Reducer plumbing

    private func send(_ event: LanguagePackEvent) {
        let (next, effects) = LanguagePackState.reduce(state, event)
        state = next
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: LanguagePackEffect) {
        switch effect {
        case .probe(let components):
            let locales = components.map { ($0, $0.locale) }
            Task(priority: .utility) { [weak self] in
                for (component, locale) in locales {
                    let result = await LanguageAssets.probe(locale: locale)
                    self?.send(.probed(component, result))
                }
            }
        case .startInstall(let token, let component):
            let report = Self.progressSink(self, token: token)
            let locale = component.locale
            installTasks[token] = Task(priority: .utility) { [weak self] in
                do {
                    try await LanguageAssets.install(locale: locale, progress: report)
                    self?.finished(token) { $0.send(.succeeded(token: token)) }
                } catch is CancellationError {
                    self?.finished(token) { _ in }
                } catch {
                    let reason = error.localizedDescription
                    self?.finished(token) { $0.send(.failed(token: token, reason: reason)) }
                }
            }
        case .cancelInstall(let token):
            installTasks.removeValue(forKey: token)?.cancel()
        case .release(let component):
            let locale = component.locale
            Task(priority: .utility) { await LanguageAssets.release(locale: locale) }
        case .persistWanted(let wanted):
            defaults.set(LanguagePackConsent.encode(wanted), forKey: Self.wantedKey)
        }
    }

    private func finished(_ token: UInt64, then action: (LanguagePackController) -> Void) {
        installTasks.removeValue(forKey: token)
        action(self)
    }

    /// Progress arrives on a background queue; hop to the main actor from a nonisolated function.
    private nonisolated static func progressSink(_ controller: LanguagePackController, token: UInt64) -> @Sendable (Double) -> Void {
        { fraction in
            Task { @MainActor in controller.send(.progress(token: token, fraction: fraction)) }
        }
    }

    private func watchPower() {
        guard powerWatch == nil else { return }
        powerWatch = Task { [weak self] in
            for await lowPower in LanguageAssets.lowPowerChanges() {
                self?.send(.lowPowerChanged(lowPower))
            }
        }
    }
}
