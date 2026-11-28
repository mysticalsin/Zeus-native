import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

@Suite struct PersonaSpeakRouteTests {
    private static let choices = PersonaSpeakChoice.allCases
    private static let secrets = ["sk-live-DO-NOT-LOG-9911", "xi-test-key-should-not-appear"]

    @Test func thePersonaVoiceIsZeusSynthetic() {
        let classic = PersonaVoiceResolver.resolve(MascotPersona())
        let orb = PersonaVoiceResolver.resolve(OrbPersona())
        #expect(classic.voiceID == "zeus.synthetic")
        #expect(orb.voiceID == "zeus.synthetic")
        #expect(PersonaSpeakRoute.resolvedVoiceID(for: MascotPersona()) == classic.voiceID)
        #expect(PersonaSpeakRoute.resolvedVoiceID(for: OrbPersona()) == orb.voiceID)
    }

    @Test func selectionTableOverChoiceKeysAndFailure() {
        for choice in Self.choices {
            for keys in PersonaSpeakKeys.everyPattern {
                for failed in [false, true] {
                    let actual = PersonaSpeakRoute.chain(choice: choice, keys: keys, providerFailed: failed)
                    let expected = Self.expected(choice: choice, keys: keys, providerFailed: failed)
                    #expect(actual == expected, "\(choice) keys=\(keys) failed=\(failed)")
                    let clouds = actual.filter(\.isCloud)
                    #expect(clouds.count <= 1)
                    if choice == .automatic || failed {
                        #expect(clouds.isEmpty)
                    }
                }
            }
        }
    }

    @Test func theDefaultWithEveryKeyMakesNoNetworkCall() async {
        PersonaSpeakHitCounter.reset()
        let keys = PersonaSpeakKeys(elevenLabs: true, openAI: true, gemini: true, googleCloud: true, kokoroReady: true)
        let steps = PersonaSpeakRoute.chain(choice: .automatic, keys: keys, providerFailed: false)
        #expect(steps.allSatisfy { !$0.isCloud })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PersonaSpeakHitCounter.self]
        let session = URLSession(configuration: configuration)
        await PersonaSpeakRoute.exercise(choice: .automatic, keys: keys, providerFailed: false, session: session)
        #expect(PersonaSpeakHitCounter.count == 0)
    }

    @Test func theRouteLogNamesThePersonaVoiceAndNoSecret() {
        let keys = PersonaSpeakKeys(elevenLabs: true, openAI: true, gemini: true, googleCloud: true, kokoroReady: true)
        let steps = PersonaSpeakRoute.chain(choice: .automatic, keys: keys, providerFailed: false)
        let line = PersonaSpeakRoute.logLine(voiceID: PersonaSpeakRoute.resolvedVoiceID(for: MascotPersona()), steps: steps)
        #expect(line.contains("zeus.synthetic"))
        #expect(PersonaSpeakRoute.logOmitsSecrets(line, secrets: Self.secrets))
        for secret in Self.secrets {
            #expect(!line.contains(secret))
        }
        #expect(PersonaSpeakRoute.preservedTuning.contains("am_michael"))
        #expect(PersonaSpeakRoute.preservedTuning.contains("0.88"))
        #expect(PersonaSpeakRoute.preservedTuning.contains("0.92"))
        #expect(PersonaSpeakRoute.preservedTuning.contains("0.82"))
        #expect(UltronCloudVoice.kokoroVoice == "am_michael")
        #expect(UltronCloudVoice.kokoroSpeed == 0.88)
        #expect(UltronSystemVoicePick.pitchMultiplier == 0.82)
    }

    private static func expected(choice: PersonaSpeakChoice, keys: PersonaSpeakKeys, providerFailed: Bool) -> [PersonaSpeakStep] {
        let local = keys.kokoroReady ? [PersonaSpeakStep.synthetic, .kokoro, .mac] : [.synthetic, .mac]
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
}

final class PersonaSpeakHitCounter: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var hits = 0
    static func reset() { lock.lock(); hits = 0; lock.unlock() }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return hits }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.hits += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://voice.invalid/")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
