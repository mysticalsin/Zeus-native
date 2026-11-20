import Foundation
import Testing
@testable import ZeusCore

@Suite("Orb simulation")
struct OrbSimulationTests {
    @Test func quotedConstantsMatchTheSource() {
        #expect(OrbSimulation.particleCount == 2000)
        #expect(OrbSimulation.maxLines == 8000)
        #expect(OrbSimulation.lineDistance == 8)
        #expect(OrbSimulation.neighbourStride == 3)
        #expect(OrbSimulation.maxLiveElectrons == 3)
        #expect(OrbSimulation.electronSpawnGap == 1)
        #expect(OrbSimulation.damping == 0.992)
        #expect(OrbSimulation.fixedStepHz == 60)
        #expect(OrbSimulation.renderQuantumHz == 120)
        #expect(OrbSimulation.intentionalFrameRateDeviation.contains("60"))
        #expect(OrbSimulation.intentionalFrameRateDeviation.contains("120"))
        #expect(OrbSimulation.intentionalFrameRateDeviation.localizedCaseInsensitiveContains("intentional"))
    }

    @Test func seededSpawnMatchesTheHandComputedBall() {
        var rng = OrbUnitRNG(seed: 1)
        #expect(abs(rng.nextUnit() - 0.62707394058816135) < 1e-15)
        #expect(abs(rng.nextUnit() - 0.0027357211802154779) < 1e-15)
        #expect(abs(rng.nextUnit() - 0.52744703995995224) < 1e-15)
        #expect(abs(rng.nextUnit() - 0.98105096747167408) < 1e-15)

        let sim = OrbSimulation(seed: 1)
        #expect(sim.particles.count == 2000)
        let first = sim.particles[0]
        // r = 25*sqrt(U), phi = acos(2U-1), theta = 2πU. Seed 1, first particle.
        #expect(abs(first.x - -1.3235849442552023) < 1e-8)
        #expect(abs(first.y - -1.3585375347091695) < 1e-8)
        #expect(abs(first.z - -18.057045678546018) < 1e-8)
        #expect(abs(first.phase - 981.05096747167408) < 1e-8)

        let radii = sim.particles.map { ($0.x * $0.x + $0.y * $0.y + $0.z * $0.z).squareRoot() }
        let mean = radii.reduce(0, +) / Double(radii.count)
        #expect(abs(mean - 16.601961448295505) < 1e-6)
        #expect(radii.allSatisfy { $0 > 0 && $0 <= 25 })
        #expect(radii.filter { $0 < 12.5 }.count == 513)
        #expect(radii.filter { $0 > 24.5 }.count == 76)
    }

    @Test func pullAndDampingMatchTheHandComputedStep() {
        let stepped = OrbIntegrator.advance(
            x: 30, y: 0, z: 0, vx: 0, vy: 0, vz: 0, phase: 0, time: 0,
            currentRadius: 25, currentSpeed: 0, state: .idle, bass: 0, mid: 0)
        #expect(abs(stepped.vx - -0.0102176) < 1e-12)
        #expect(abs(stepped.vy) < 1e-15)
        #expect(abs(stepped.vz) < 1e-15)
        #expect(abs(stepped.x - 29.9897824) < 1e-12)
    }

    @Test func speakingMidPulseShovesXAndYOnly() {
        let stepped = OrbIntegrator.advance(
            x: 10, y: 0, z: 0, vx: 0, vy: 0, vz: 0, phase: 0, time: .pi / 16,
            currentRadius: 100, currentSpeed: 0, state: .speaking, bass: 0, mid: 1)
        #expect(abs(stepped.vx - 0.0116064) < 1e-12)
        #expect(abs(stepped.vy) < 1e-15)
        #expect(abs(stepped.vz) < 1e-15)
    }

    @Test func firstIdleFrameMatchesTheHandComputedScalarsAndParticle() {
        var sim = OrbSimulation(seed: 1)
        sim.integrateFixedStep(audio: .silent, reduceMotion: false)
        #expect(abs(sim.currentRadius - 25.06) < 1e-12)
        #expect(abs(sim.currentSpeed - 0.298) < 1e-12)
        #expect(abs(sim.currentBright - 0.598) < 1e-12)
        #expect(abs(sim.currentSize - 0.399) < 1e-12)
        #expect(abs(sim.lineAmount - 0.003) < 1e-12)
        #expect(sim.lineCount == 0)
        #expect(abs(sim.cameraX) < 1e-15)
        #expect(abs(sim.cameraY - 3) < 1e-12)
        #expect(sim.cameraZ == 80)
        let first = sim.particles[0]
        #expect(abs(first.x - -1.3235084047067744) < 1e-7)
        #expect(abs(first.y - -1.3580817050291483) < 1e-7)
        #expect(abs(first.z - -18.05647323497066) < 1e-7)
    }

    @Test func stateTargetsMatchTheSourceTable() {
        #expect(OrbStateTargets.of(.idle) == OrbStateTargets(radius: 28, speed: 0.2, bright: 0.5, size: 0.35, lineAmount: 0.15, electronRate: 0))
        #expect(OrbStateTargets.of(.listening) == OrbStateTargets(radius: 22, speed: 0.3, bright: 0.65, size: 0.4, lineAmount: 0.4, electronRate: 0))
        #expect(OrbStateTargets.of(.thinking) == OrbStateTargets(radius: 16, speed: 0.5, bright: 0.7, size: 0.3, lineAmount: 1, electronRate: 0.015))
        #expect(OrbStateTargets.of(.speaking) == OrbStateTargets(radius: 18, speed: 0.2, bright: 0.7, size: 0.4, lineAmount: 0.8, electronRate: 0))
        #expect(OrbStateTargets.of(.compacting) == OrbStateTargets(radius: 12, speed: 0.08, bright: 0.28, size: 0.28, lineAmount: 0, electronRate: 0))
    }

    @Test func lineCountStaysInsideTheCap() {
        var clustered = OrbSimulation(seed: 9, distribution: .originCluster)
        clustered.setVisualState(.thinking)
        clustered.integrateFixedStep(audio: .silent, reduceMotion: false)
        #expect(clustered.lineCount == 8000)
        #expect(clustered.lines.count == 8000)

        var filled = OrbSimulation(seed: 11)
        filled.setVisualState(.thinking)
        for _ in 0..<5 {
            filled.integrateFixedStep(audio: OrbAudioBands(bass: 1, mid: 1), reduceMotion: false)
            #expect(filled.lineCount <= 8000)
            #expect(filled.lineCount == filled.lines.count)
        }
    }

    @Test func electronsStayCappedAndRespectTheSpawnGap() {
        var sim = OrbSimulation(seed: 2, distribution: .originCluster)
        sim.setVisualState(.thinking)
        var maxAlive = 0
        for _ in 0..<700 {
            sim.integrateFixedStep(audio: .silent, reduceMotion: false)
            #expect(sim.electrons.count <= 3)
            maxAlive = max(maxAlive, sim.electrons.count)
        }
        #expect(maxAlive >= 1)
        #expect(maxAlive <= 3)
        #expect(sim.electronSpawnTimes.count >= 3)
        for pair in zip(sim.electronSpawnTimes, sim.electronSpawnTimes.dropFirst()) {
            #expect(pair.1 - pair.0 > 1)
        }
        #expect(sim.electronSpawnSpeeds.allSatisfy { $0 >= 0.003 && $0 <= 0.006 })
    }

    @Test func oneHundredTwentyHertzMatchesSixtyHertzAfterTheSameSimulatedTime() {
        var slow = OrbSimulation(seed: 7)
        var fast = OrbSimulation(seed: 7)
        slow.setVisualState(.speaking)
        fast.setVisualState(.speaking)
        let audio = OrbAudioBands(bass: 0.2, mid: 0.4)
        for _ in 0..<120 {
            slow.renderFrame(delta: 1.0 / 60.0, audio: audio, reduceMotion: false)
        }
        for _ in 0..<240 {
            fast.renderFrame(delta: 1.0 / 120.0, audio: audio, reduceMotion: false)
        }
        #expect(slow == fast)
        #expect(abs(slow.simulatedTime - 2) < 1e-9)
    }

    @Test func extremeAudioCannotProduceNonFinitePositions() {
        var sim = OrbSimulation(seed: 3)
        sim.setVisualState(.speaking)
        let nasty = [
            OrbAudioBands(bass: .infinity, mid: .nan),
            OrbAudioBands(bass: -.greatestFiniteMagnitude, mid: .greatestFiniteMagnitude),
            OrbAudioBands(bass: 1e20, mid: -1e20),
            OrbAudioBands(bass: .signalingNaN, mid: .infinity),
        ]
        for bands in nasty {
            for _ in 0..<40 {
                sim.renderFrame(delta: 1.0 / 60.0, audio: bands, reduceMotion: false)
            }
        }
        for particle in sim.particles {
            #expect(particle.x.isFinite && particle.y.isFinite && particle.z.isFinite)
            #expect(particle.vx.isFinite && particle.vy.isFinite && particle.vz.isFinite)
        }
        #expect(sim.lineCount <= 8000)
        #expect(sim.electrons.count <= 3)
    }

    @Test func reduceMotionFreezesTravelAndOnlyBreathesOpacity() {
        var held = OrbSimulation(seed: 4)
        let start = held.particles
        held.setVisualState(.thinking)
        var opacities: [Double] = []
        for frame in 0..<90 {
            held.renderFrame(delta: 1.0 / 60.0, audio: OrbAudioBands(bass: 1, mid: 1), reduceMotion: true)
            if frame == 0 || frame == 45 || frame == 89 { opacities.append(held.displayedOpacity) }
        }
        #expect(held.particles.map(\.x) == start.map(\.x))
        #expect(held.particles.map(\.y) == start.map(\.y))
        #expect(held.particles.map(\.z) == start.map(\.z))
        #expect(held.spinX == 0 && held.spinY == 0 && held.spinZ == 0)
        #expect(held.cameraX == 0 && held.cameraY == 0)
        #expect(held.cloudZ == 0)
        #expect(held.electrons.isEmpty)
        #expect(held.electronSpawnTimes.isEmpty)
        #expect(Set(opacities.map { ($0 * 1_000_000).rounded() }).count >= 2)
    }

    @Test func sanitizedBandsStayInsideTheAnalyserRange() {
        #expect(OrbAudioBands.sanitized(.infinity, .nan) == .silent)
        #expect(OrbAudioBands.sanitized(4, -2) == OrbAudioBands(bass: 1, mid: 0))
        #expect(OrbAudioBands.sanitized(0.25, 0.5) == OrbAudioBands(bass: 0.25, mid: 0.5))
    }

    @Test func aLowSineLandsInTheBassBins() {
        let count = OrbAnalyser.fftSize
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = sin(2 * .pi * 2 * Float(index) / Float(count))
        }
        let raw = OrbAnalyser.rawBands(samples: samples, sampleRate: 24_000)
        // Bass is the mean of bins 0..<8, so one sine in bin 2 is about an eighth of full scale.
        #expect(raw.bass > raw.mid)
        #expect(raw.bass > 0.05)
        #expect(raw.mid < 0.05)
    }

    @Test func clearAndParticleColorsMatchTheSourceHexes() {
        #expect(OrbRGB.hex(0x050508) == OrbRGB(r: 5.0 / 255, g: 5.0 / 255, b: 8.0 / 255))
        #expect(OrbRGB.hex(0x4ca8e8) == OrbRGB(r: 76.0 / 255, g: 168.0 / 255, b: 232.0 / 255))
        #expect(OrbRGB.hex(0x6ec4ff) == OrbRGB(r: 110.0 / 255, g: 196.0 / 255, b: 255.0 / 255))
        #expect(OrbRGB.hex(0x5ab8f0) == OrbRGB(r: 90.0 / 255, g: 184.0 / 255, b: 240.0 / 255))
        #expect(OrbRGB.hex(0x3a5f8a) == OrbRGB(r: 58.0 / 255, g: 95.0 / 255, b: 138.0 / 255))
        #expect(OrbRGB.hex(0xffffff) == OrbRGB(r: 1, g: 1, b: 1))
    }
}
