import Foundation

public struct VoiceProviderPreferences: @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var choice: VoiceProviderChoice {
        get {
            let raw = defaults.string(forKey: Self.selectionKey) ?? VoiceProviderChoice.localID
            if raw.isEmpty || raw == VoiceProviderChoice.localID { return .local }
            return .provider(raw)
        }
        nonmutating set { defaults.set(newValue.id, forKey: Self.selectionKey) }
    }

    public func voiceID(for providerID: String) -> String? {
        defaults.string(forKey: Self.voiceKey(providerID))
    }

    public func setVoiceID(_ voiceID: String?, for providerID: String) {
        let key = Self.voiceKey(providerID)
        if let voiceID, !voiceID.isEmpty { defaults.set(voiceID, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    public static let selectionKey = "voice.providers.selection"
    public static func voiceKey(_ providerID: String) -> String { "voice.providers.voice.\(providerID)" }
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
    private var selection: VoiceProviderSelectionMachine
    private var readiness: [String: ProviderReadiness] = [:]
    private var catalog: [String: [ProviderVoice]] = [:]
    private var generation: [String: Int] = [:]
    private var currentCancel: (@Sendable () -> Void)?
    private var speakCancelled = false
    private var statusLine = "Speaking with the local voice."

    public init(store: any CredentialStore, transport: any ProviderHTTPTransport, local: any LocalVoiceSpeaking,
                preferences: VoiceProviderPreferences, log: ProviderLog = ProviderLog(), signposter: ProviderSignposter = ProviderSignposter(),
                adapters: [any TTSProvider]? = nil,
                serviceName: @escaping @Sendable (String) -> String = ProviderCredentialLocation.service(for:)) {
        self.store = store
        self.transport = transport
        self.local = local
        self.preferences = preferences
        self.log = log
        self.signposter = signposter
        self.adapters = adapters ?? ProviderRegistry.entries.map { $0.make() }
        self.serviceName = serviceName
        var machine = VoiceProviderSelectionMachine(choice: preferences.choice)
        for entry in ProviderRegistry.entries {
            if let voice = preferences.voiceID(for: entry.descriptor.id) {
                machine.reduce(.chooseVoice(providerID: entry.descriptor.id, voiceID: voice))
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
        preferences.setVoiceID(selection.voiceID(for: providerID), for: providerID)
    }

    public func remove(providerID: String) {
        let service = serviceName(providerID)
        guard store.delete(service: service) else {
            log.record("provider=\(providerID) remove failed")
            return
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
        guard !trimmed.isEmpty else { return }
        let service = serviceName(providerID)
        guard store.write(trimmed, service: service, account: ProviderCredentialLocation.account) else { return }
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
            if selection.voiceID(for: providerID) == nil, let first = voices.first {
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
            guard let voiceID = selection.voiceID(for: id), !voiceID.isEmpty else {
                return await finishLocal(.missingVoice, text: trimmed, providerID: id, started: started, routeName: "local-fallback")
            }
            guard let key = store.read(service: serviceName(id), account: ProviderCredentialLocation.account),
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
                let interval = signposter.begin()
                for try await chunk in synthesis.chunks {
                    if speakCancelled { throw ProviderFailure.cancelled }
                    if audio.isEmpty {
                        first = signposter.end(interval, metadata: ["provider": id, "route": "cloud"])
                    }
                    audio.append(chunk.data)
                }
                currentCancel = nil
                guard !audio.isEmpty, let first else { throw ProviderFailure.invalidResponse }
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
                hasKey: store.read(service: serviceName(id), account: ProviderCredentialLocation.account) != nil
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
        if failure == .timedOut {
            return await finishLocal(.timedOut, text: text, providerID: providerID, started: started, routeName: "local-fallback")
        }
        if failure == .unauthorized || failure == .rateLimited {
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
        let audio = text.isEmpty ? Data() : await local.speak(text)
        let milliseconds = signposter.end(interval, metadata: ["provider": providerID, "route": routeName])
        let name = providerID == VoiceProviderChoice.localID ? "Local voice" : (ProviderRegistry.descriptor(providerID)?.displayName ?? providerID)
        let line: String
        switch reason {
        case .selected: line = "Speaking with the local voice."
        case .notReady: line = "\(name) is not ready. Speaking with the local voice."
        case .missingVoice: line = "\(name) has no voice yet. Speaking with the local voice."
        case .timedOut: line = "\(name) timed out. Speaking with the local voice."
        case .failed: line = "\(name) could not speak. Speaking with the local voice."
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
