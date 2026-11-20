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
        defaults.set(ZeusPersonality.plain.rawValue, forKey: ZeusPersonality.defaultsKey)
        PersonaCatalog.select(id: OrbPersona.id, defaults: defaults)
        #expect(defaults.string(forKey: ZeusPersonality.defaultsKey) == ZeusPersonality.plain.rawValue)
        #expect(PersonaCatalog.defaultsKey != ZeusPersonality.defaultsKey)
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
