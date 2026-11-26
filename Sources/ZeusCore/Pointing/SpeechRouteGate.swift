import Foundation

/// Decides whether one pointing turn speaks on the device or through a cloud voice.
///
/// On-device speech runs when that route is selected. A cloud route runs only
/// when it is the selected route, a key is present, and the network answers.
/// The key string never enters this type. `network` is a fact the caller
/// already has. Deciding never opens a connection, and the result is not
/// applied to the provider list or the pointing session.
public enum SpeechRouteGate {
    /// Zeus setup speaks with the installed system voice. The two vendor
    /// paths speak through their own cloud route.
    public static func choice(for path: PointingProviderPath) -> SpeechRouteChoice {
        switch path {
        case .zeusSetup:
            return .onDevice
        case .anthropicElevenLabs:
            return .cloud(.elevenLabs)
        case .openAI:
            return .cloud(.openAI)
        }
    }

    public static func decide(path: PointingProviderPath, key: SpeechKeyFact, network: SpeechNetworkFact) -> SpeechRouteDecision {
        decide(choice: choice(for: path), key: key, network: network)
    }

    public static func decide(choice: SpeechRouteChoice, key: SpeechKeyFact, network: SpeechNetworkFact) -> SpeechRouteDecision {
        switch choice {
        case .onDevice:
            return .onDevice
        case .cloud(let route):
            if key != .present { return .refused(.missingKey) }
            if network != .answers { return .refused(.networkSilent) }
            return .cloud(route)
        }
    }
}

/// The speech route a caller selected before asking the gate.
public enum SpeechRouteChoice: Equatable, Sendable {
    case onDevice
    case cloud(SpeechCloudRoute)
}

/// Cloud speech routes. Each one stays on its own path.
public enum SpeechCloudRoute: String, CaseIterable, Equatable, Sendable {
    case elevenLabs
    case openAI
}

/// Presence only. The key string stays with the caller.
public enum SpeechKeyFact: Equatable, Sendable {
    case present
    case missing
}

/// Whether the caller has already been told that the network answered.
public enum SpeechNetworkFact: Equatable, Sendable {
    case answers
    case silent
}

public enum SpeechRouteRefusal: Equatable, Sendable {
    case missingKey
    case networkSilent
}

public enum SpeechRouteDecision: Equatable, Sendable {
    case onDevice
    case cloud(SpeechCloudRoute)
    case refused(SpeechRouteRefusal)
}
