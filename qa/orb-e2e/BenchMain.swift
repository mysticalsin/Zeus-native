import Foundation

/// Fake-only bench for qa/orb-e2e/run.sh. No microphone, no provider, no network.
@main
struct OrbBench {
    static func main() {
        if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--idle-hold" {
            let seconds = Double(CommandLine.arguments.dropFirst(2).first ?? "1") ?? 1
            Thread.sleep(forTimeInterval: max(0, seconds))
            exit(0)
        }
        let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
        let report = makeReport()
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if destination.isEmpty {
            FileHandle.standardOutput.write(data)
        } else {
            try! data.write(to: URL(fileURLWithPath: destination))
        }
        let failed = (report["assertions"] as? [[String: Any]])?.contains { ($0["ok"] as? Bool) != true } ?? true
        exit(failed ? 1 : 0)
    }

    static func makeReport() -> [String: Any] {
        var assertions: [[String: Any]] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            assertions.append(["name": name, "ok": ok, "detail": detail])
        }

        let legal = OrbTurnOracle.legalApplications()
        check("legal_count", legal.count == 22 + OrbTurnOracle.phases.count, "\(legal.count)")
        let illegal = OrbTurnOracle.illegalPairs()
        check("illegal_rejected", illegal.allSatisfy { OrbTurnOracle.step($0.phase, $0.event) == nil }, "\(illegal.count)")
        check("unknown_event_rejected", OrbTurnOracle.step("speaking", "not_an_event") == nil)

        let hold = walk([
            ("key_confirmed", "listening"),
            ("key_up", "transcribing"),
            ("partial_committed_needs_brain", "thinking"),
            ("first_sentence_ready", "speaking"),
            ("playback_ended", "idle"),
        ], from: "idle")
        check("hold_to_talk", hold == ["idle", "listening", "transcribing", "thinking", "speaking", "idle"], hold.joined(separator: " "))

        let interrupt = OrbTurnOracle.step("speaking", "key_down")
        check("interrupt_effects", interrupt?.effects == ["stop speech", "stop flight", "stop capture"])
        check("interrupt_then_idle", OrbTurnOracle.step("interrupted", "cleanup_key_up")?.to == "idle")

        let denied = OrbTurnOracle.step("listening", "capture_denied_at_start")
        check("error_phase", denied?.to == "error")
        check("error_recovers", OrbTurnOracle.step("error", "line_spoken")?.to == "idle")
        check("error_has_no_orb_color", OrbVisualStateMap.visualState(forPhaseName: "error") == .idle)
        check("spoken_lines_ten_words", JarvisPersona.spokenLines.allSatisfy { $0.split(whereSeparator: \.isWhitespace).count <= 10 })

        let persona = personaReport()
        check("persona_relaunch", persona["relaunch_orb"] as? Bool == true && persona["relaunch_classic"] as? Bool == true)
        check("classic_prompt_identical", persona["classic_identical"] as? Bool == true)
        check("orb_adds_addendum", persona["orb_adds"] as? Bool == true)
        check("persona_scope", PersonaScope.affectsFaceUnlock == false && PersonaScope.affectsInstantCommands == false && PersonaScope.affectsLLMSystemPrompt)

        check("voice_resolves_synthetic", persona["voice_id"] as? String == "zeus.synthetic")
        check("classic_voice_resolves_synthetic", persona["classic_voice_id"] as? String == "zeus.synthetic")

        check("surface_two_displays", OrbTurnOracle.surface(displayCount: 2) == (2, 0))
        check("surface_three_displays", OrbTurnOracle.surface(displayCount: 3).extraWindows == 0)
        check("compacting_targets", OrbStateTargets.of(.compacting).radius == 12 && OrbStateTargets.of(.compacting).lineAmount == 0)

        let motion = reduceMotionReport()
        check("reduce_motion_frozen", motion["frozen"] as? Bool == true && motion["electrons"] as? Int == 0)

        let frames = frameReport()
        let particles = particleReport()

        return [
            "edges": legal.map { edge -> [String: Any] in
                ["from": edge.from, "event": edge.event, "to": edge.to, "effects": edge.effects]
            },
            "illegal_count": illegal.count,
            "hold": hold,
            "persona": persona,
            "motion": motion,
            "frames": frames,
            "particles": particles,
            "assertions": assertions,
        ]
    }

    static func walk(_ steps: [(String, String)], from start: String) -> [String] {
        var phase = start
        var seen = [start]
        for step in steps {
            guard let edge = OrbTurnOracle.step(phase, step.0), edge.to == step.1 else {
                seen.append("illegal:\(phase):\(step.0)")
                return seen
            }
            phase = edge.to
            seen.append(phase)
        }
        return seen
    }

    static func personaReport() -> [String: Any] {
        let name = "zeus.orb.bench." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let base = "BASE-PROMPT"
        let classicSame = CompanionPromptOverlay.applying(persona: PersonaCatalog.current(defaults), to: base) == base
        PersonaCatalog.select(id: OrbPersona.id, defaults: defaults)
        let relaunched = PersonaCatalog.current(defaults)
        let overlaid = CompanionPromptOverlay.applying(persona: relaunched, to: base)
        PersonaCatalog.select(id: MascotPersona.id, defaults: defaults)
        let classicAgain = PersonaCatalog.current(defaults).id == "classic"
        defaults.set(true, forKey: "companion.jarvisCloudVoice.enabled")
        defaults.set("preset-not-used", forKey: "companion.jarvisCloudVoice.id")
        let orbVoice = PersonaVoiceResolver.resolve(OrbPersona(), defaults: defaults).voiceID
        let classicVoice = PersonaVoiceResolver.resolve(MascotPersona(), defaults: defaults).voiceID
        return [
            "relaunch_orb": relaunched.id == "orb.jarvis",
            "relaunch_classic": classicAgain,
            "classic_identical": classicSame,
            "orb_adds": overlaid.hasPrefix(base + "\n\n") && overlaid.contains(JarvisPersona.addendum),
            "voice_id": orbVoice,
            "classic_voice_id": classicVoice,
        ]
    }

    static func reduceMotionReport() -> [String: Any] {
        var sim = OrbSimulation(seed: 4)
        let start = sim.particles[0]
        sim.setVisualState(.thinking)
        for _ in 0..<10 {
            sim.renderFrame(delta: 1.0 / 60.0, audio: OrbAudioBands(bass: 1, mid: 1), reduceMotion: true)
        }
        let end = sim.particles[0]
        return [
            "frozen": start.x == end.x && start.y == end.y && start.z == end.z && sim.spinX == 0 && sim.cameraX == 0,
            "electrons": sim.electrons.count,
        ]
    }

    static func frameReport() -> [String: Any] {
        var report: [String: Any] = [:]
        for (label, delta, count) in [("60", 1.0 / 60.0, 30), ("120", 1.0 / 120.0, 30)] {
            var byState: [String: [Double]] = [:]
            for state in OrbVisualState.allCases {
                byState[state.rawValue] = sample(state: state, delta: delta, count: count, reduceMotion: false)
            }
            byState["reduce_motion"] = sample(state: .idle, delta: delta, count: count, reduceMotion: true)
            report[label] = byState
        }
        var slow = OrbSimulation(seed: 7)
        var fast = OrbSimulation(seed: 7)
        slow.setVisualState(.speaking)
        fast.setVisualState(.speaking)
        let audio = OrbAudioBands(bass: 0.35, mid: 0.55)
        for _ in 0..<30 {
            slow.renderFrame(delta: 1.0 / 60.0, audio: audio, reduceMotion: false)
        }
        for _ in 0..<60 {
            fast.renderFrame(delta: 1.0 / 120.0, audio: audio, reduceMotion: false)
        }
        report["rates_match"] = slow == fast
        return report
    }

    static func sample(state: OrbVisualState, delta: Double, count: Int, reduceMotion: Bool) -> [Double] {
        var sim = OrbSimulation(seed: 11, state: state)
        let audio = state == .speaking ? OrbAudioBands(bass: 0.35, mid: 0.55) : .silent
        var times: [Double] = []
        times.reserveCapacity(count)
        for _ in 0..<count {
            let started = ContinuousClock.now
            sim.renderFrame(delta: delta, audio: audio, reduceMotion: reduceMotion)
            let elapsed = ContinuousClock.now - started
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            times.append(ms)
        }
        return times
    }

    static func particleReport() -> [String: Any] {
        var report: [String: [[Double]]] = [:]
        for state in OrbVisualState.allCases {
            var sim = OrbSimulation(seed: 3, state: state)
            let audio = state == .speaking ? OrbAudioBands(bass: 0.35, mid: 0.55) : .silent
            for _ in 0..<8 {
                sim.integrateFixedStep(audio: audio, reduceMotion: false)
            }
            report[state.rawValue] = stride(from: 0, to: sim.particles.count, by: 10).map { index in
                let particle = sim.particles[index]
                return [particle.x, particle.y]
            }
        }
        return report
    }
}
