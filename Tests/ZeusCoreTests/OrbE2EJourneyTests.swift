import Foundation
import Testing
@testable import ZeusCore

@Suite("Orb end-to-end journeys")
struct OrbE2EJourneyTests {
    @Test func everyLegalTransitionAndEveryIllegalPair() {
        let legal = OrbTurnOracle.legalApplications()
        #expect(legal.count == 22 + OrbTurnOracle.phases.count)
        for edge in legal {
            let stepped = OrbTurnOracle.step(edge.from, edge.event)
            #expect(stepped == edge)
        }
        let illegal = OrbTurnOracle.illegalPairs()
        #expect(!illegal.isEmpty)
        for pair in illegal {
            #expect(OrbTurnOracle.step(pair.phase, pair.event) == nil)
        }
        #expect(OrbTurnOracle.step("speaking", "not_an_event") == nil)
    }

    @Test func holdToTalkWalksIdleListeningThinkingSpeakingIdle() {
        let script = [
            ("idle", "key_confirmed", "listening"),
            ("listening", "key_up", "transcribing"),
            ("transcribing", "partial_committed_needs_brain", "thinking"),
            ("thinking", "first_sentence_ready", "speaking"),
            ("speaking", "playback_ended", "idle"),
        ]
        var phase = "idle"
        for row in script {
            #expect(phase == row.0)
            let edge = OrbTurnOracle.step(phase, row.1)
            #expect(edge?.to == row.2)
            phase = edge?.to ?? "stuck"
        }
        #expect(phase == "idle")
        #expect(OrbVisualStateMap.visualState(forPhaseName: "listening") == .listening)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "thinking") == .thinking)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "speaking") == .speaking)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "idle") == .idle)
    }

    @Test func speakingInterruptStopsSpeechFlightAndCapture() {
        let edge = OrbTurnOracle.step("speaking", "key_down")
        #expect(edge?.to == "interrupted")
        #expect(edge?.effects == ["stop speech", "stop flight", "stop capture"])
        let back = OrbTurnOracle.step("interrupted", "cleanup_key_up")
        #expect(back?.to == "idle")
        let again = OrbTurnOracle.step("interrupted", "cleanup_key_held")
        #expect(again?.to == "listening")
    }

    @Test func errorRecoversToIdleAndDoesNotInventAnOrbColor() {
        let denied = OrbTurnOracle.step("listening", "capture_denied_at_start")
        #expect(denied?.to == "error")
        #expect(denied?.effects == ["speak the short line"])
        let recovered = OrbTurnOracle.step("error", "line_spoken")
        #expect(recovered?.to == "idle")
        #expect(OrbVisualStateMap.visualState(forPhaseName: "error") == .idle)
        for line in JarvisPersona.spokenLines {
            #expect(line.split(whereSeparator: \.isWhitespace).count <= 10)
        }
    }

    @Test func personaSurvivesARelaunchAndOnlyChangesTheLLMPrompt() throws {
        let name = "zeus.orb.e2e." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        #expect(PersonaCatalog.current(defaults).id == "classic")
        let base = "BASE-PROMPT"
        #expect(CompanionPromptOverlay.applying(persona: PersonaCatalog.current(defaults), to: base) == base)
        PersonaCatalog.select(id: OrbPersona.id, defaults: defaults)
        let relaunched = PersonaCatalog.current(defaults)
        #expect(relaunched.id == "orb.jarvis")
        let overlaid = CompanionPromptOverlay.applying(persona: relaunched, to: base)
        #expect(overlaid.hasPrefix(base + "\n\n"))
        PersonaCatalog.select(id: MascotPersona.id, defaults: defaults)
        #expect(PersonaCatalog.current(defaults).id == "classic")
        #expect(CompanionPromptOverlay.applying(persona: PersonaCatalog.current(defaults), to: base) == base)
        #expect(PersonaScope.affectsFaceUnlock == false)
        #expect(PersonaScope.affectsInstantCommands == false)
        #expect(PersonaScope.affectsLLMSystemPrompt == true)
    }

    @Test func characterVoiceIdIsIgnoredEvenWhenTheFlagIsOn() throws {
        let name = "zeus.orb.voice." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: "companion.jarvisCloudVoice.enabled")
        defaults.set("JARVIS (MCU)", forKey: "companion.jarvisCloudVoice.id")
        #expect(PersonaVoiceResolver.resolve(OrbPersona(), defaults: defaults).voiceID == "zeus.synthetic")
        #expect(PersonaVoiceResolver.resolve(MascotPersona(), defaults: defaults).voiceID == "zeus.synthetic")
    }

    @Test func compactingAndReduceMotionAndSurfaces() {
        #expect(OrbStateTargets.of(.compacting).radius == 12)
        #expect(OrbStateTargets.of(.compacting).electronRate == 0)
        #expect(OrbStateTargets.of(.compacting).lineAmount == 0)
        var sim = OrbSimulation(seed: 4)
        let start = sim.particles
        sim.setVisualState(.compacting)
        sim.integrateFixedStep(audio: .silent, reduceMotion: true)
        #expect(sim.particles.map(\.x) == start.map(\.x))
        #expect(sim.electrons.isEmpty)
        #expect(sim.spinX == 0 && sim.cameraX == 0 && sim.cameraY == 0)
        #expect(OrbTurnOracle.surface(displayCount: 1).topBars == 1)
        #expect(OrbTurnOracle.surface(displayCount: 2).topBars == 2)
        #expect(OrbTurnOracle.surface(displayCount: 3).extraWindows == 0)
        #expect(OrbTurnOracle.surface(displayCount: 0).topBars == 0)
    }
}
