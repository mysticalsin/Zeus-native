import Foundation

public struct VoiceProviderPreferences: @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var choice: VoiceProviderChoice {
        get { VoiceProviderAccounts.choice(fromTTSProvider: defaults.string(forKey: Self.selectionKey)) }
        nonmutating set { defaults.set(VoiceProviderAccounts.ttsProviderRaw(for: newValue), forKey: Self.selectionKey) }
    }

    public func voiceID(for providerID: String) -> String? {
        defaults.string(forKey: Self.voiceKey(providerID))
    }

    public func setVoiceID(_ voiceID: String?, for providerID: String) {
        let key = Self.voiceKey(providerID)
        if let voiceID, !voiceID.isEmpty { defaults.set(voiceID, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    /// The existing Settings key `voice.ttsProvider`. Local stays `kokoro`.
    public static let selectionKey = "voice.ttsProvider"
    public static func voiceKey(_ providerID: String) -> String { VoiceProviderAccounts.voiceDefaultsKey(for: providerID) }
}

/// Existing Keychain accounts and settings keys. ElevenLabs reuses `elevenlabs.api-key` and
/// `elevenlabs.voice-id` on `com.zeus.app`. Google Cloud has no older account, so it uses the
/// same service and the same `voice.*` shape as `voice.gemini.voice`.
public enum VoiceProviderAccounts {
    public static let service = VoiceProviderKeychain.service

    public static func keyAccount(for providerID: String) -> String {
        switch providerID {
        case ElevenLabsTTSAdapter.id: VoiceTTSProvider.elevenLabs.keychainAccount
        case GoogleCloudTTSAdapter.id: VoiceTTSProvider.googleCloud.keychainAccount
        default: ProviderCredentialLocation.account
        }
    }

    public static func voiceAccount(for providerID: String) -> String? {
        providerID == ElevenLabsTTSAdapter.id ? "elevenlabs.voice-id" : nil
    }

    public static func voiceDefaultsKey(for providerID: String) -> String {
        switch providerID {
        case GoogleCloudTTSAdapter.id: "voice.googleCloud.voice"
        case ElevenLabsTTSAdapter.id: "voice.elevenlabs.voice"
        default: "voice.providers.voice.\(providerID)"
        }
    }

    public static func choice(fromTTSProvider raw: String?) -> VoiceProviderChoice {
        switch raw {
        case VoiceTTSProvider.elevenLabs.rawValue: .provider(ElevenLabsTTSAdapter.id)
        case VoiceTTSProvider.googleCloud.rawValue: .provider(GoogleCloudTTSAdapter.id)
        default: .local
        }
    }

    public static func ttsProviderRaw(for choice: VoiceProviderChoice) -> String {
        switch choice {
        case .local: VoiceTTSProvider.kokoro.rawValue
        case .provider(let id) where id == ElevenLabsTTSAdapter.id: VoiceTTSProvider.elevenLabs.rawValue
        case .provider(let id) where id == GoogleCloudTTSAdapter.id: VoiceTTSProvider.googleCloud.rawValue
        case .provider: VoiceTTSProvider.kokoro.rawValue
        }
    }
}

/// Offline speech order: Zeus's existing local voice, then the Mac voice. The list is never empty.
public enum OfflineVoiceStep: String, Equatable, Sendable {
    case local
    case systemSpeech
}

public enum OfflineVoiceChain {
    public static func route(localReady: Bool, systemReady: Bool = true) -> [OfflineVoiceStep] {
        var steps: [OfflineVoiceStep] = []
        if localReady { steps.append(.local) }
        if systemReady || steps.isEmpty { steps.append(.systemSpeech) }
        return steps
    }
}

public enum OfflineVoicePlayback {
    public static func speak(text: String, localReady: Bool,
                              local: (String) async -> Data,
                              system: (String) async -> Data) async -> (step: OfflineVoiceStep, audio: Data) {
        for step in OfflineVoiceChain.route(localReady: localReady) {
            let audio = step == .local ? await local(text) : await system(text)
            if !audio.isEmpty { return (step, audio) }
        }
        let audio = await system(text)
        return (.systemSpeech, audio.isEmpty ? Data([0x00]) : audio)
    }
}

public struct VoiceProviderMetrics: Equatable, Sendable {
    public var rowHeight: Double
    public var padding: Double
    public var cardGap: Double
    public static let standard = VoiceProviderMetrics(rowHeight: 52, padding: 32, cardGap: 28)
}

public struct VoiceProviderRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: String
    public var isSelected: Bool
    public var voices: [ProviderVoice]
    public var selectedVoiceID: String?
    public var hasKey: Bool
    public init(id: String, title: String, status: String, isSelected: Bool, voices: [ProviderVoice], selectedVoiceID: String?, hasKey: Bool) {
        self.id = id
        self.title = title
        self.status = status
        self.isSelected = isSelected
        self.voices = voices
        self.selectedVoiceID = selectedVoiceID
        self.hasKey = hasKey
    }
}

public struct VoiceProvidersCardModel: Equatable, Sendable {
    public var rows: [VoiceProviderRow]
    public var keyIsMasked: Bool
    public var onboarding: String
    public var helper: String
    public var maskingNote: String
    public var metrics: VoiceProviderMetrics
    public var statusLine: String
    public init(rows: [VoiceProviderRow], keyIsMasked: Bool, onboarding: String, helper: String, maskingNote: String, metrics: VoiceProviderMetrics, statusLine: String) {
        self.rows = rows
        self.keyIsMasked = keyIsMasked
        self.onboarding = onboarding
        self.helper = helper
        self.maskingNote = maskingNote
        self.metrics = metrics
        self.statusLine = statusLine
    }

    public var publicText: String {
        ([onboarding, helper, maskingNote, statusLine] + rows.flatMap { [$0.title, $0.status] }).joined(separator: "\n")
    }
}

public struct SpeakOutcome: Equatable, Sendable {
    public enum LocalFallback: Equatable, Sendable {
        case selected
        case notReady
        case missingVoice
        case failed(ProviderFailure)
        case timedOut
    }

    public enum Route: Equatable, Sendable {
        case cloud(providerID: String, voiceID: String)
        case local(LocalFallback)
        case cancelled
    }

    public var route: Route
    public var audio: Data
    public var firstAudioMs: Int
    public var metVoiceLegBudget: Bool
    public var metDirectStreamP95: Bool
    public var signpostName: String
    public var statusLine: String
}

/// Adds a provider, validates it, and speaks. Text is sent only when that provider is selected and ready.
/// A rejected key or a rate limit stays in error until Validate is pressed again. A timeout or a 5xx
/// uses the local voice for that turn and leaves the provider ready for the next one.
public actor VoiceProviderSession {
    private let store: any CredentialStore
    private let transport: any ProviderHTTPTransport
    private let local: any LocalVoiceSpeaking
    private let preferences: VoiceProviderPreferences
    private let log: ProviderLog
    private let signposter: ProviderSignposter
    private let adapters: [any TTSProvider]
    private let serviceName: @Sendable (String) -> String
    private let keyAccount: @Sendable (String) -> String
    private let system: any SystemSpeechSpeaking
    private var selection: VoiceProviderSelectionMachine
    private var readiness: [String: ProviderReadiness] = [:]
    private var catalog: [String: [ProviderVoice]] = [:]
    private var generation: [String: Int] = [:]
    private var currentCancel: (@Sendable () -> Void)?
    private var speakCancelled = false
    private var statusLine = "Speaking with the local voice."
    private var firstAudioBudgetMs = ProviderSpeakAbort.milliseconds

    public func setFirstAudioBudget(ms: Int) { firstAudioBudgetMs = ms }

    public init(store: any CredentialStore, transport: any ProviderHTTPTransport, local: any LocalVoiceSpeaking,
                preferences: VoiceProviderPreferences, log: ProviderLog = ProviderLog(), signposter: ProviderSignposter = ProviderSignposter(),
                adapters: [any TTSProvider]? = nil,
                serviceName: @escaping @Sendable (String) -> String = { _ in VoiceProviderAccounts.service },
                keyAccount: @escaping @Sendable (String) -> String = VoiceProviderAccounts.keyAccount(for:),
                system: any SystemSpeechSpeaking = SilentSystemSpeech()) {
        self.store = store
        self.transport = transport
        self.local = local
        self.preferences = preferences
        self.log = log
        self.signposter = signposter
        self.adapters = adapters ?? ProviderRegistry.entries.map { $0.make() }
        self.serviceName = serviceName
        self.keyAccount = keyAccount
        self.system = system
        var machine = VoiceProviderSelectionMachine(choice: preferences.choice)
        for entry in ProviderRegistry.entries {
            let id = entry.descriptor.id
            if let account = VoiceProviderAccounts.voiceAccount(for: id),
               let voice = store.read(service: serviceName(id), account: account), !voice.isEmpty {
                machine.reduce(.chooseVoice(providerID: id, voiceID: voice))
            } else if let voice = preferences.voiceID(for: id) {
                machine.reduce(.chooseVoice(providerID: id, voiceID: voice))
            }
        }
        self.selection = machine
    }

    public var choice: VoiceProviderChoice { selection.choice }

    public func readiness(for providerID: String) -> ProviderReadiness { readiness[providerID] ?? .unset }

    public func select(_ choice: VoiceProviderChoice) {
        switch choice {
        case .local: selection.reduce(.selectLocal)
        case .provider(let id): selection.reduce(.select(id))
        }
        preferences.choice = selection.choice
    }

    public func chooseVoice(providerID: String, voiceID: String) {
        selection.reduce(.chooseVoice(providerID: providerID, voiceID: voiceID))
        if let account = VoiceProviderAccounts.voiceAccount(for: providerID), let voice = selection.voiceID(for: providerID) {
            _ = store.write(voice, service: serviceName(providerID), account: account)
        }
        preferences.setVoiceID(selection.voiceID(for: providerID), for: providerID)
    }

    public func remove(providerID: String) {
        let service = serviceName(providerID)
        guard store.delete(service: service, account: keyAccount(providerID)) else {
            log.record("provider=\(providerID) remove failed")
            return
        }
        if let account = VoiceProviderAccounts.voiceAccount(for: providerID) {
            _ = store.delete(service: service, account: account)
        }
        preferences.setVoiceID(nil, for: providerID)
        var machine = ProviderReadinessMachine(state: readiness[providerID] ?? .unset)
        _ = machine.reduce(.remove)
        readiness[providerID] = machine.state
        catalog[providerID] = nil
        selection.reduce(.remove(providerID))
        preferences.choice = selection.choice
        log.record("provider=\(providerID) removed")
    }

    public func saveKey(providerID: String, key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let descriptor = ProviderRegistry.descriptor(providerID) else {
            log.record("provider rejected unregistered id")
            return
        }
        guard VoiceProviderKeyPolicy.accepts(trimmed) else {
            log.record("provider=\(providerID) rejected key")
            statusLine = "\(descriptor.displayName): the key is not valid."
            return
        }
        let service = serviceName(providerID)
        guard store.write(trimmed, service: service, account: keyAccount(providerID)) else { return }
        var machine = ProviderReadinessMachine(state: readiness[providerID] ?? .unset)
        _ = machine.reduce(.saveCredential)
        readiness[providerID] = machine.state
        generation[providerID, default: 0] += 1
        let token = generation[providerID] ?? 0
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: trimmed])
        guard let adapter = adapters.first(where: { $0.descriptor.id == providerID }) else { return }
        do {
            try await adapter.validate(credential: credential, using: transport)
            let voices = try await adapter.listVoices(credential: credential, using: transport)
            guard generation[providerID] == token else { return }
            _ = machine.reduce(.validationSucceeded)
            readiness[providerID] = machine.state
            catalog[providerID] = voices
            if selection.voiceID(for: providerID) == nil,
               let first = voices.first(where: { VoiceSpeakAllowlist.accepts($0.id) }) {
                selection.reduce(.chooseVoice(providerID: providerID, voiceID: first.id))
                preferences.setVoiceID(first.id, for: providerID)
            }
            log.record("provider=\(providerID) ready voices=\(voices.count)", secrets: [trimmed])
            statusLine = "\(descriptor.displayName) is ready."
        } catch {
            guard generation[providerID] == token else { return }
            let failure = ProviderFailure.wrap(error)
            _ = machine.reduce(.validationFailed(failure))
            readiness[providerID] = machine.state
            log.record("provider=\(providerID) validate \(failure.logName)", secrets: [trimmed])
            statusLine = "\(descriptor.displayName): \(failure.pill)."
        }
    }

    public func cancel() {
        speakCancelled = true
        currentCancel?()
        currentCancel = nil
    }

    public func speak(_ text: String) async -> SpeakOutcome {
        let started = ContinuousClock.now
        speakCancelled = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return await finishLocal(.selected, text: "", providerID: VoiceProviderChoice.localID, started: started, routeName: "local")
        }
        switch selection.choice {
        case .local:
            return await finishLocal(.selected, text: trimmed, providerID: VoiceProviderChoice.localID, started: started, routeName: "local")
        case .provider(let id):
            let state = readiness[id] ?? .unset
            guard case .ready = state else {
                return await finishLocal(.notReady, text: trimmed, providerID: id, started: started, routeName: "local-fallback")
            }
            guard let voiceID = selection.voiceID(for: id), VoiceSpeakAllowlist.accepts(voiceID) else {
                return await finishLocal(.missingVoice, text: trimmed, providerID: id, started: started, routeName: "local-fallback")
            }
            guard let key = store.read(service: serviceName(id), account: keyAccount(id)),
                  !key.isEmpty,
                  let adapter = adapters.first(where: { $0.descriptor.id == id }),
                  let synthesis = adapter.synthesize(text: trimmed, voice: ProviderVoice(id: voiceID, name: voiceID, language: catalog[id]?.first { $0.id == voiceID }?.language), credential: ProviderCredential(fields: [ProviderCredentialLocation.account: key]), using: transport) else {
                return await finishLocal(.notReady, text: trimmed, providerID: id, started: started, routeName: "local-fallback")
            }
            currentCancel = synthesis.cancel
            if speakCancelled {
                synthesis.cancel()
                return cancelled(started: started, providerID: id)
            }
            do {
                var audio = Data()
                var first: Int?
                var assembler = PCM24kAssembler()
                let interval = signposter.begin()
                let budget = firstAudioBudgetMs
                let heard = AbortFlag()
                let watchdog = Task {
                    try? await Task.sleep(for: .milliseconds(budget))
                    if !heard.value {
                        heard.fired = true
                        synthesis.cancel()
                    }
                }
                defer { watchdog.cancel() }
                for try await chunk in synthesis.chunks {
                    if speakCancelled { throw ProviderFailure.cancelled }
                    if heard.fired { throw ProviderFailure.timedOut }
                    if audio.isEmpty {
                        heard.value = true
                        first = signposter.end(interval, metadata: ["provider": id, "route": "cloud"])
                        if ProviderSpeakAbort.shouldAbort(elapsedMs: first ?? 0, heardAudio: false, budgetMs: budget) {
                            synthesis.cancel()
                            throw ProviderFailure.timedOut
                        }
                    }
                    audio.append(chunk.data)
                    if !chunk.data.starts(with: Data("RIFF".utf8)), !chunk.data.starts(with: Data("ID3".utf8)) {
                        _ = assembler.append(chunk.data)
                    }
                }
                if heard.fired { throw ProviderFailure.timedOut }
                currentCancel = nil
                guard !audio.isEmpty, let first else { throw ProviderFailure.invalidResponse }
                guard VoiceAudioValidity.isPlayable(audio) else { throw ProviderFailure.invalidResponse }
                let name = ProviderRegistry.descriptor(id)?.displayName ?? id
                let line = "\(name) is speaking."
                statusLine = line
                log.record("speak route=cloud provider=\(id) bytes=\(audio.count) first_audio_ms=\(first)", secrets: [key])
                return SpeakOutcome(route: .cloud(providerID: id, voiceID: voiceID), audio: audio, firstAudioMs: first,
                                    metVoiceLegBudget: ProviderLatencyVerdict.meetsVoiceLeg(first),
                                    metDirectStreamP95: ProviderLatencyVerdict.meetsDirectStreamP95(first),
                                    signpostName: ProviderSignpostName.firstAudio, statusLine: line)
            } catch {
                currentCancel = nil
                let failure = ProviderFailure.wrap(error)
                return await fallback(failure, providerID: id, text: trimmed, started: started, secret: key)
            }
        }
    }

    public func card() -> VoiceProvidersCardModel {
        var rows = [VoiceProviderRow(id: VoiceProviderChoice.localID, title: "Local voice", status: "On this Mac",
                                     isSelected: selection.choice == .local, voices: [], selectedVoiceID: nil, hasKey: false)]
        for entry in ProviderRegistry.entries {
            let id = entry.descriptor.id
            let state = readiness[id] ?? .unset
            rows.append(VoiceProviderRow(
                id: id,
                title: entry.descriptor.displayName,
                status: pill(state),
                isSelected: selection.choice == .provider(id),
                voices: catalog[id] ?? [],
                selectedVoiceID: selection.voiceID(for: id),
                hasKey: store.read(service: serviceName(id), account: keyAccount(id)) != nil
            ))
        }
        return VoiceProvidersCardModel(rows: rows, keyIsMasked: true, onboarding: VoiceProviderCopy.onboarding,
                                       helper: VoiceProviderCopy.helper, maskingNote: VoiceProviderCopy.maskingNote,
                                       metrics: .standard, statusLine: statusLine)
    }

    private func fallback(_ failure: ProviderFailure, providerID: String, text: String, started: ContinuousClock.Instant, secret: String) async -> SpeakOutcome {
        log.record("speak fallback provider=\(providerID) failure=\(failure.logName)", secrets: [secret])
        if failure == .cancelled || speakCancelled {
            return cancelled(started: started, providerID: providerID)
        }
        if failure == .timedOut || failure == .offline {
            return await finishLocal(failure == .offline ? .failed(.offline) : .timedOut, text: text, providerID: providerID, started: started, routeName: "local-fallback")
        }
        if failure == .unauthorized || failure == .rateLimited || failure == .creditsUsedUp || failure == .badVoice {
            noteRuntime(failure, providerID: providerID)
        }
        if case .server = failure {
            return await finishLocal(.failed(failure), text: text, providerID: providerID, started: started, routeName: "local-fallback")
        }
        return await finishLocal(.failed(failure), text: text, providerID: providerID, started: started, routeName: "local-fallback")
    }

    private func noteRuntime(_ failure: ProviderFailure, providerID: String) {
        var machine = ProviderReadinessMachine(state: readiness[providerID] ?? .unset)
        _ = machine.reduce(.runtimeFailure(failure))
        readiness[providerID] = machine.state
    }

    private func finishLocal(_ reason: SpeakOutcome.LocalFallback, text: String, providerID: String, started: ContinuousClock.Instant, routeName: String) async -> SpeakOutcome {
        let interval = signposter.begin()
        var audio = Data()
        var spokeWithMac = false
        if !text.isEmpty {
            audio = await local.speak(text)
            if audio.isEmpty {
                spokeWithMac = true
                audio = await system.speak(text)
                if audio.isEmpty { audio = Data([0x00]) }
            }
        }
        let milliseconds = signposter.end(interval, metadata: ["provider": providerID, "route": spokeWithMac ? "system-speech" : routeName])
        let name = providerID == VoiceProviderChoice.localID ? "Local voice" : (ProviderRegistry.descriptor(providerID)?.displayName ?? providerID)
        let voiceName = spokeWithMac ? "Mac voice" : "local voice"
        let line: String
        switch reason {
        case .selected: line = "Speaking with the \(voiceName)."
        case .notReady: line = "\(name) is not ready. Speaking with the \(voiceName)."
        case .missingVoice: line = "\(name) has no voice yet. Speaking with the \(voiceName)."
        case .timedOut: line = "\(name) timed out. Speaking with the \(voiceName)."
        case .failed(let failure): line = "\(name): \(failure.pill). Speaking with the \(voiceName)."
        }
        statusLine = line
        log.record("speak route=\(routeName) provider=\(providerID) bytes=\(audio.count) first_audio_ms=\(milliseconds)")
        return SpeakOutcome(route: .local(reason), audio: audio, firstAudioMs: milliseconds,
                            metVoiceLegBudget: ProviderLatencyVerdict.meetsVoiceLeg(milliseconds),
                            metDirectStreamP95: ProviderLatencyVerdict.meetsDirectStreamP95(milliseconds),
                            signpostName: ProviderSignpostName.firstAudio, statusLine: line)
    }

    private func cancelled(started: ContinuousClock.Instant, providerID: String) -> SpeakOutcome {
        let milliseconds = ProviderClock.milliseconds(since: started)
        let line = "Speaking cancelled."
        statusLine = line
        log.record("speak route=cancelled provider=\(providerID)")
        return SpeakOutcome(route: .cancelled, audio: Data(), firstAudioMs: milliseconds,
                            metVoiceLegBudget: ProviderLatencyVerdict.meetsVoiceLeg(milliseconds),
                            metDirectStreamP95: ProviderLatencyVerdict.meetsDirectStreamP95(milliseconds),
                            signpostName: ProviderSignpostName.firstAudio, statusLine: line)
    }

    private func pill(_ state: ProviderReadiness) -> String {
        switch state {
        case .unset: "Not added"
        case .validating: "Checking"
        case .ready: "Ready"
        case .error(let reason): reason.pill
        }
    }
}
