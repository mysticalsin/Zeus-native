import Foundation
import Testing
@testable import ZeusCore

@Suite("Persona swap")
struct PersonaSwapTests {
    @Test func classicLeavesThePromptByteIdentical() {
        let prompt = "You are ZEUS, a voice assistant that lives on Tony's Mac.\nKeep every byte."
        let overlaid = CompanionPromptOverlay.applying(persona: MascotPersona(), to: prompt)
        #expect(overlaid == prompt)
        #expect(Array(overlaid.utf8) == Array(prompt.utf8))
        #expect(MascotPersona().systemPromptAddendum.isEmpty)
    }

    @Test func orbAddsTheAddendumWithoutRewritingTheBase() {
        let prompt = "BASE-PROMPT"
        let persona = OrbPersona()
        let overlaid = CompanionPromptOverlay.applying(persona: persona, to: prompt)
        #expect(overlaid.hasPrefix(prompt + "\n\n"))
        #expect(overlaid.hasSuffix(persona.systemPromptAddendum))
        #expect(overlaid.count == (prompt + "\n\n" + persona.systemPromptAddendum).count)
        #expect(!persona.systemPromptAddendum.isEmpty)
    }

    @Test func defaultPersonaIsTheClassicMascot() throws {
        let defaults = try freshDefaults()
        let persona = PersonaCatalog.current(defaults)
        #expect(persona.id == MascotPersona.id)
        #expect(persona.id == "classic")
        #expect(persona.displayName == "Classic")
        #expect(persona.mascotKind == .classic)
        #expect(persona.voicePreference == .zeusDefault)
        #expect(persona.systemPromptAddendum.isEmpty)
        #expect(defaults.string(forKey: PersonaCatalog.defaultsKey) == nil)
    }

    @Test func selectingOrbThenClassicRoundTrips() throws {
        let defaults = try freshDefaults()
        PersonaCatalog.select(id: OrbPersona.id, defaults: defaults)
        let orb = PersonaCatalog.current(defaults)
        #expect(orb.id == "orb.jarvis")
        #expect(orb.displayName == "Orb (Jarvis)")
        #expect(orb.mascotKind == .orb)
        let prompt = "unchanged-base"
        #expect(CompanionPromptOverlay.applying(persona: orb, to: prompt) != prompt)

        PersonaCatalog.select(id: MascotPersona.id, defaults: defaults)
        let classic = PersonaCatalog.current(defaults)
        #expect(classic.id == "classic")
        #expect(CompanionPromptOverlay.applying(persona: classic, to: prompt) == prompt)
    }

    @Test func unknownIdFallsBackToClassic() throws {
        let defaults = try freshDefaults()
        PersonaCatalog.select(id: "not-a-persona", defaults: defaults)
        #expect(PersonaCatalog.current(defaults).id == "classic")
    }

    @Test func voiceFlagDefaultsOffAndUnconfiguredFallsBack() throws {
        let defaults = try freshDefaults()
        #expect(JarvisCloudVoice.isEnabled(defaults) == false)
        #expect(JarvisCloudVoice.selectedID(defaults) == nil)
        #expect(PersonaVoiceResolver.resolve(OrbPersona(), defaults: defaults) == .zeusDefault)
        #expect(PersonaVoiceResolver.resolve(MascotPersona(), defaults: defaults) == .zeusDefault)

        defaults.set(true, forKey: JarvisCloudVoice.enabledKey)
        #expect(JarvisCloudVoice.isEnabled(defaults))
        #expect(JarvisCloudVoice.selectedID(defaults) == nil)
        #expect(PersonaVoiceResolver.resolve(OrbPersona(), defaults: defaults) == .zeusDefault)
    }

    /// Devin's gate: no actor or film-character voice id, for every persona, with the
    /// third-party-voice flag off and on, and in the shipped persona strings and resources.
    @Test func noActorOrCharacterVoiceIdShipsUnderAnyFlag() throws {
        let banned = [
            "JARVIS (MCU)", "JARVIS MCU", "JARVIS voice", "Paul Bettany", "Bettany", "MCU",
        ]
        let personas: [any Persona] = [MascotPersona(), OrbPersona()]
        let flags: [Bool?] = [nil, false, true]
        let storedIDs: [String?] = [nil, "", "JARVIS (MCU)", "JARVIS MCU", "Paul Bettany", "Bettany", "MCU", "zeus.synthetic"]
        for flag in flags {
            for stored in storedIDs {
                let defaults = try freshDefaults()
                if let flag {
                    defaults.set(flag, forKey: JarvisCloudVoice.enabledKey)
                }
                if let stored {
                    defaults.set(stored, forKey: JarvisCloudVoice.configurationKey)
                }
                for persona in personas {
                    let resolved = PersonaVoiceResolver.resolve(persona, defaults: defaults)
                    let id = Self.resolvedVoiceID(resolved)
                    #expect(id == "zeus.synthetic")
                    for token in banned {
                        #expect(!id.localizedCaseInsensitiveContains(token))
                    }
                }
            }
        }
        let hits = Self.characterVoiceHits(banned: banned)
        #expect(hits == [])
    }

    private static func resolvedVoiceID(_ voice: ResolvedVoice) -> String {
        switch voice {
        case .zeusDefault: ""
        case .cloud(let id): id
        }
    }

    private static func characterVoiceHits(banned: [String]) -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Sources/ZeusCore/Companion",
            "Sources/Zeus/Companion",
            "specs/007-companion-parity",
            "qa/orb-e2e",
            "Resources/NOTICES.txt",
            "LICENSES/jarvis2.0-LICENSE",
        ].flatMap { relative -> [URL] in
            let url = root.appendingPathComponent(relative)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
            if !isDir.boolValue { return [url] }
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }
            return enumerator.compactMap { item in
                let file = item as? URL
                guard let file, file.pathExtension == "swift" || file.pathExtension == "md" || file.pathExtension == "py" || file.pathExtension == "txt" else { return nil }
                return file
            }
        }
        var hits: [String] = []
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let lineText = String(line)
                if lineText == "JARVIS Voice AI Assistant" { continue }
                for token in banned where lineText.localizedCaseInsensitiveContains(token) {
                    hits.append("\(url.lastPathComponent):\(index + 1): \(token)")
                }
            }
        }
        return hits
    }

    @Test func configuredCloudVoiceIdIsUsedOnlyWhenTheFlagIsOn() throws {
        let defaults = try freshDefaults()
        defaults.set(JarvisCloudVoice.cloudVoiceID, forKey: JarvisCloudVoice.configurationKey)
        #expect(JarvisCloudVoice.selectedID(defaults) == nil)

        defaults.set(true, forKey: JarvisCloudVoice.enabledKey)
        #expect(JarvisCloudVoice.selectedID(defaults) == "JARVIS (MCU)")
        #expect(PersonaVoiceResolver.resolve(OrbPersona(), defaults: defaults) == .cloud(id: "JARVIS (MCU)"))
        #expect(PersonaVoiceResolver.resolve(MascotPersona(), defaults: defaults) == .zeusDefault)

        defaults.set("some-other-voice", forKey: JarvisCloudVoice.configurationKey)
        #expect(JarvisCloudVoice.selectedID(defaults) == nil)
    }

    @Test func personaDoesNotTouchTheExistingPersonalityKeyOrNonLLMPaths() throws {
        let defaults = try freshDefaults()
        defaults.set("plain", forKey: "voice.personality")
        PersonaCatalog.select(id: OrbPersona.id, defaults: defaults)
        #expect(defaults.string(forKey: "voice.personality") == "plain")
        #expect(PersonaCatalog.defaultsKey != "voice.personality")
        #expect(PersonaScope.affectsFaceUnlock == false)
        #expect(PersonaScope.affectsInstantCommands == false)
        #expect(PersonaScope.affectsLLMSystemPrompt == true)
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "zeus.persona.swap." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
