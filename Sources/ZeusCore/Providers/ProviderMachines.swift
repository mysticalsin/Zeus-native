import Foundation

public enum ProviderReadiness: Equatable, Sendable, Hashable {
    case unset
    case validating
    case ready
    case error(ProviderFailure)
}

public enum ProviderReadinessEvent: Equatable, Sendable, Hashable {
    case saveCredential
    case validationStarted
    case validationSucceeded
    case validationFailed(ProviderFailure)
    case remove
    case runtimeFailure(ProviderFailure)
    case retry
}

public enum ProviderReadinessEffect: Equatable, Sendable, Hashable {
    case beginValidation
    case deleteCredential
    case ignored
}

/// One machine per provider. Illegal events leave the state alone.
///
/// - remove, from anywhere, returns to unset and deletes the credential.
/// - saveCredential, from anywhere, starts validation.
/// - retry starts validation from error or validating, and is ignored otherwise.
/// - validationSucceeded and validationFailed apply only while validating.
/// - runtimeFailure applies only while ready.
public struct ProviderReadinessMachine: Equatable, Sendable {
    public var state: ProviderReadiness
    public init(state: ProviderReadiness = .unset) { self.state = state }

    public mutating func reduce(_ event: ProviderReadinessEvent) -> ProviderReadinessEffect {
        switch event {
        case .remove:
            state = .unset
            return .deleteCredential
        case .saveCredential:
            state = .validating
            return .beginValidation
        case .retry:
            switch state {
            case .error, .validating:
                state = .validating
                return .beginValidation
            case .unset, .ready:
                return .ignored
            }
        case .validationStarted:
            return .ignored
        case .validationSucceeded:
            if case .validating = state { state = .ready }
            return .ignored
        case .validationFailed(let reason):
            if case .validating = state { state = .error(reason) }
            return .ignored
        case .runtimeFailure(let reason):
            if case .ready = state { state = .error(reason) }
            return .ignored
        }
    }
}

/// Which voice speaks. The default is Zeus's local voice.
public struct VoiceProviderSelectionMachine: Equatable, Sendable {
    public private(set) var choice: VoiceProviderChoice
    public private(set) var voiceIDs: [String: String]

    public enum Event: Equatable, Sendable {
        case selectLocal
        case select(String)
        case chooseVoice(providerID: String, voiceID: String)
        case remove(String)
    }

    public init(choice: VoiceProviderChoice = .local, voiceIDs: [String: String] = [:]) {
        self.choice = choice
        self.voiceIDs = voiceIDs
    }

    public mutating func reduce(_ event: Event) {
        switch event {
        case .selectLocal:
            choice = .local
        case .select(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == VoiceProviderChoice.localID {
                choice = .local
            } else {
                choice = .provider(trimmed)
            }
        case .chooseVoice(let providerID, let voiceID):
            let trimmed = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            voiceIDs[providerID] = trimmed
        case .remove(let id):
            voiceIDs[id] = nil
            if case .provider(let selected) = choice, selected == id { choice = .local }
        }
    }

    public func voiceID(for providerID: String) -> String? { voiceIDs[providerID] }
}
