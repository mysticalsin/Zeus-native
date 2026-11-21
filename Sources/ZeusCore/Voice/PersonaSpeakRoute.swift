import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Who Zeus tries, in order. Cloud steps appear only after an explicit selection with a key.
public enum PersonaSpeakChoice: String, CaseIterable, Sendable, Equatable {
    case automatic
    case elevenLabs
    case openAI
    case gemini
    case googleCloud
    case kokoro
    case mac
    case chatterbox
}

public struct PersonaSpeakKeys: Equatable, Sendable {
    public var elevenLabs: Bool
    public var openAI: Bool
    public var gemini: Bool
    public var googleCloud: Bool
    public var kokoroReady: Bool

    public init(elevenLabs: Bool = false, openAI: Bool = false, gemini: Bool = false, googleCloud: Bool = false, kokoroReady: Bool = false) {
        self.elevenLabs = elevenLabs
        self.openAI = openAI
        self.gemini = gemini
        self.googleCloud = googleCloud
        self.kokoroReady = kokoroReady
    }

    /// Every combination of the four cloud keys and whether Kokoro is ready.
    public static var everyPattern: [PersonaSpeakKeys] {
        var all: [PersonaSpeakKeys] = []
        for eleven in [false, true] {
            for open in [false, true] {
                for gemini in [false, true] {
                    for google in [false, true] {
                        for kokoro in [false, true] {
                            all.append(PersonaSpeakKeys(elevenLabs: eleven, openAI: open, gemini: gemini, googleCloud: google, kokoroReady: kokoro))
                        }
                    }
                }
            }
        }
        return all
    }
}

public enum PersonaSpeakStep: Equatable, Sendable {
    case synthetic
    case kokoro
    case mac
    case elevenLabs
    case openAI
    case gemini
    case googleCloud
    case chatterbox

    public var isCloud: Bool {
        switch self {
        case .elevenLabs, .openAI, .gemini, .googleCloud: true
        case .synthetic, .kokoro, .mac, .chatterbox: false
        }
    }

    public var wireName: String {
        switch self {
        case .synthetic: "synthetic"
        case .kokoro: "kokoro"
        case .mac: "mac"
        case .elevenLabs: "elevenlabs"
        case .openAI: "openai"
        case .gemini: "gemini"
        case .googleCloud: "google"
        case .chatterbox: "chatterbox"
        }
    }
}

/// The speak order. Automatic is local even when every cloud key is present.
public enum PersonaSpeakRoute {
    /// Kokoro stays `am_michael` at 0.88. The Mac fallback stays at 0.92 of the default rate and pitch 0.82.
    /// `VoiceTurnController.voiced` still runs `PersonaCompliance.stripOminousHedges` and `UltronSpeechText.prepared`.
    /// Those tunings belong to the voice-polish work and are not changed here.
    public static let preservedTuning = "Kokoro am_michael at 0.88. Mac voice rate 0.92 and pitch 0.82 through the effect chain. Ultron text prep stripOminousHedges and UltronSpeechText stays on the speak path."

    public static func resolvedVoiceID(for persona: any Persona) -> String {
        PersonaVoiceResolver.resolve(persona).voiceID
    }

    public static func chain(choice: PersonaSpeakChoice, keys: PersonaSpeakKeys, providerFailed: Bool) -> [PersonaSpeakStep] {
        let local: [PersonaSpeakStep] = keys.kokoroReady ? [.synthetic, .kokoro, .mac] : [.synthetic, .mac]
        switch choice {
        case .automatic:
            return local
        case .mac:
            return [.mac]
        case .kokoro:
            return keys.kokoroReady ? [.kokoro, .mac] : local
        case .chatterbox:
            return providerFailed ? local : [.chatterbox] + local
        case .elevenLabs:
            return (!providerFailed && keys.elevenLabs) ? [.elevenLabs] + local : local
        case .openAI:
            return (!providerFailed && keys.openAI) ? [.openAI] + local : local
        case .gemini:
            return (!providerFailed && keys.gemini) ? [.gemini] + local : local
        case .googleCloud:
            return (!providerFailed && keys.googleCloud) ? [.googleCloud] + local : local
        }
    }

    public static func logLine(voiceID: String, steps: [PersonaSpeakStep]) -> String {
        "voice=\(voiceID) engines=\(steps.map(\.wireName).joined(separator: ","))"
    }

    public static func logOmitsSecrets(_ line: String, secrets: [String]) -> Bool {
        secrets.allSatisfy { secret in !secret.isEmpty && !line.contains(secret) }
    }

    /// Issues a request only for a cloud step. The automatic chain has none, so the session is idle.
    public static func exercise(choice: PersonaSpeakChoice, keys: PersonaSpeakKeys, providerFailed: Bool, session: URLSession) async {
        let steps = chain(choice: choice, keys: keys, providerFailed: providerFailed)
        for step in steps where step.isCloud {
            guard let url = URL(string: "https://voice.invalid/\(step.wireName)") else { continue }
            _ = try? await session.data(from: url)
        }
    }
}
