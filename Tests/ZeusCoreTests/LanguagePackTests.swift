import Testing
import ZeusCore

@Suite("Language packs")
struct LanguagePackTests {
    private typealias S = LanguagePackState

    private func asset(_ pack: LanguagePackID) -> LanguageComponent {
        LanguagePackCatalog.components(of: pack).first { $0.kind == .appleSpeechAnalyzerAsset }!
    }

    /// Applies events in order and keeps every effect.
    private func run(_ start: S, _ events: [LanguagePackEvent]) -> (S, [LanguagePackEffect]) {
        var state = start
        var all: [LanguagePackEffect] = []
        for event in events {
            let (next, effects) = S.reduce(state, event)
            state = next
            all += effects
        }
        return (state, all)
    }

    private func tokens(_ effects: [LanguagePackEffect]) -> [UInt64] {
        effects.compactMap { if case .startInstall(let token, _) = $0 { token } else { nil } }
    }

    @Test func defaultsAreTheFourRequestedPacks() {
        #expect(LanguagePackID.defaults == [.english, .french, .spanish, .portuguese])
        #expect(LanguagePackID.allCases.map(\.locale) == ["en-US", "fr-FR", "es-ES", "pt-BR"])
    }

    @Test func nothingIsQueuedBeforeConsent() {
        let (state, effects) = S.reduce(S(), .launched(wanted: [], analyzerSupported: true, lowPower: false))
        #expect(effects.isEmpty)
        #expect(state.running == nil)
        #expect(!state.isBusy)
        for pack in LanguagePackID.allCases { #expect(state.status(of: pack) == .notInstalled) }
    }

    @Test func voiceComponentsNeedNoDownload() {
        let state = S()
        for pack in LanguagePackID.allCases {
            let voice = LanguagePackCatalog.components(of: pack).first { $0.kind == .systemVoice }!
            #expect(state.state(of: voice) == .notNeeded)
        }
    }

    @Test func defaultFourInstallOneAtATimeInOrder() {
        var state = S()
        var effects: [LanguagePackEffect]
        (state, effects) = S.reduce(state, .installRequested(LanguagePackID.defaults, source: .onboarding))
        #expect(effects == [.persistWanted(LanguagePackID.defaults), .startInstall(token: 1, component: asset(.english))])
        #expect(state.status(of: .french) == .queued)
        (state, effects) = S.reduce(state, .progress(token: 1, fraction: 0.5))
        #expect(state.status(of: .english) == .installing(progress: 0.5))
        (state, effects) = S.reduce(state, .succeeded(token: 1))
        #expect(tokens(effects) == [2])
        #expect(state.running?.component == asset(.french))
        for token: UInt64 in [2, 3, 4] { (state, _) = S.reduce(state, .succeeded(token: token)) }
        #expect(state.running == nil)
        for pack in LanguagePackID.allCases { #expect(state.status(of: pack) == .installed) }
    }

    @Test func staleCompletionsAreIgnored() {
        var (state, _) = S.reduce(S(), .installRequested([.english], source: .owner))
        (state, _) = S.reduce(state, .succeeded(token: 99))
        (state, _) = S.reduce(state, .progress(token: 99, fraction: 1))
        #expect(state.status(of: .english) == .installing(progress: 0))
    }

    @Test func aFailureStopsThatComponentOnlyAndTheQueueContinues() {
        var (state, _) = S.reduce(S(), .installRequested([.english, .french], source: .owner))
        let (after, effects) = S.reduce(state, .failed(token: 1, reason: "offline"))
        state = after
        #expect(state.status(of: .english) == .failed(reason: "offline"))
        #expect(tokens(effects) == [2])
        #expect(state.running?.component == asset(.french))
    }

    @Test func retryAfterFailureRequeues() {
        var (state, _) = S.reduce(S(), .installRequested([.english], source: .owner))
        (state, _) = S.reduce(state, .failed(token: 1, reason: "offline"))
        let (retry, effects) = S.reduce(state, .installRequested([.english], source: .owner))
        #expect(tokens(effects) == [2])
        #expect(retry.status(of: .english) == .installing(progress: 0))
    }

    @Test func resumeAfterInterruptionRequeuesOnlyWhatIsMissing() {
        // Quit while French was downloading: only the consent was saved.
        let wanted = LanguagePackID.defaults
        var (state, effects) = S.reduce(S(), .launched(wanted: wanted, analyzerSupported: true, lowPower: false))
        #expect(effects == [.probe([asset(.english), asset(.french), asset(.spanish), asset(.portuguese)])])
        #expect(state.running == nil)
        (state, effects) = S.reduce(state, .probed(asset(.english), .installed))
        #expect(effects.isEmpty)
        (state, effects) = S.reduce(state, .probed(asset(.french), .notInstalled))
        #expect(tokens(effects) == [1])
        #expect(state.running?.component == asset(.french))
        (state, _) = S.reduce(state, .probed(asset(.spanish), .notInstalled))
        (state, _) = S.reduce(state, .probed(asset(.portuguese), .notInstalled))
        #expect(state.status(of: .english) == .installed)
        #expect(state.status(of: .spanish) == .queued)
        #expect(state.status(of: .portuguese) == .queued)
    }

    @Test func cancelStopsTheRunningItemClearsTheQueueAndForgetsConsent() {
        var (state, _) = S.reduce(S(), .installRequested(LanguagePackID.defaults, source: .onboarding))
        (state, _) = S.reduce(state, .succeeded(token: 1))
        let (cancelled, effects) = S.reduce(state, .cancelRequested)
        #expect(effects == [.cancelInstall(token: 2), .persistWanted([.english])])
        #expect(cancelled.running == nil)
        #expect(cancelled.wanted == [.english])
        #expect(cancelled.status(of: .english) == .installed)
        #expect(cancelled.status(of: .french) == .notInstalled)
        #expect(cancelled.status(of: .portuguese) == .notInstalled)
        #expect(!cancelled.isBusy)
    }

    @Test func removeReleasesInstalledAssetsAndStopsWanting() {
        var (state, _) = S.reduce(S(), .installRequested([.spanish], source: .owner))
        (state, _) = S.reduce(state, .succeeded(token: 1))
        let (removed, effects) = S.reduce(state, .removeRequested(.spanish))
        #expect(effects == [.release(asset(.spanish)), .persistWanted([])])
        #expect(removed.status(of: .spanish) == .notInstalled)
        #expect(removed.wanted.isEmpty)
    }

    @Test func removingTheRunningPackCancelsItAndStartsTheNext() {
        var (state, _) = S.reduce(S(), .installRequested([.english, .french], source: .owner))
        let (removed, effects) = S.reduce(state, .removeRequested(.english))
        state = removed
        #expect(effects.contains(.cancelInstall(token: 1)))
        #expect(tokens(effects) == [2])
        #expect(state.running?.component == asset(.french))
    }

    @Test func unsupportedOSNeverQueuesAnything() {
        var (state, effects) = S.reduce(S(), .launched(wanted: LanguagePackID.defaults, analyzerSupported: false, lowPower: false))
        #expect(effects.isEmpty)
        (state, effects) = S.reduce(state, .installRequested(LanguagePackID.defaults, source: .owner))
        #expect(tokens(effects).isEmpty)
        #expect(state.running == nil)
        for pack in LanguagePackID.allCases { #expect(state.status(of: pack) == .unsupportedOnThisMac) }
    }

    @Test func lowPowerDefersOnboardingInstallsUntilInstallNow() {
        var (state, effects) = S.reduce(S(lowPower: true), .installRequested(LanguagePackID.defaults, source: .onboarding))
        #expect(tokens(effects).isEmpty)
        #expect(state.running == nil)
        #expect(state.status(of: .english) == .deferredForLowPower)
        (state, effects) = S.reduce(state, .installNowTapped)
        #expect(tokens(effects) == [1])
        #expect(state.status(of: .english) == .installing(progress: 0))
    }

    @Test func lowPowerDefersResumeToo() {
        var (state, _) = S.reduce(S(), .launched(wanted: [.french], analyzerSupported: true, lowPower: true))
        let effects: [LanguagePackEffect]
        (state, effects) = S.reduce(state, .probed(asset(.french), .notInstalled))
        #expect(tokens(effects).isEmpty)
        #expect(state.status(of: .french) == .deferredForLowPower)
    }

    @Test func ownerTapOverridesLowPowerWithoutInstallNow() {
        let (state, effects) = S.reduce(S(lowPower: true), .installRequested([.portuguese], source: .owner))
        #expect(tokens(effects) == [1])
        #expect(state.status(of: .portuguese) == .installing(progress: 0))
    }

    @Test func lowPowerTurningOnMidDownloadPausesAndRequeues() {
        var (state, _) = S.reduce(S(), .installRequested([.english, .french], source: .onboarding))
        var effects: [LanguagePackEffect]
        (state, effects) = S.reduce(state, .lowPowerChanged(true))
        #expect(effects == [.cancelInstall(token: 1)])
        #expect(state.running == nil)
        #expect(state.status(of: .english) == .deferredForLowPower)
        (state, effects) = S.reduce(state, .lowPowerChanged(false))
        #expect(tokens(effects) == [2])
        #expect(state.running?.component == asset(.english))
    }

    @Test func installNowOverrideEndsWhenLowPowerTurnsOff() {
        var (state, _) = S.reduce(S(lowPower: true), .installNowTapped)
        #expect(state.lowPowerOverride)
        (state, _) = S.reduce(state, .lowPowerChanged(false))
        #expect(!state.lowPowerOverride)
    }

    @Test func consentRoundTripsThroughStrings() {
        let raw = LanguagePackConsent.encode([.portuguese, .english])
        #expect(raw == ["en", "pt"])
        #expect(LanguagePackConsent.decode(raw + ["xx"]) == [.english, .portuguese])
        #expect(LanguagePackConsent.decode(nil).isEmpty)
    }

    @Test func sizesAreNilUntilAComponentDeclaresOne() {
        #expect(S().knownBytes(of: LanguagePackID.defaults) == nil)
    }
}
