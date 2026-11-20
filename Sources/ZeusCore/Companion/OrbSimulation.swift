import Foundation

// Ported from github.com/mysticalsin/jarvis2.0
// Source path: frontend/src/orb.ts
// Source commit: 16e37bd801eb797798e02540665f8b3804b0fe14
// Copyright (c) 2026 Ethan Rogers
// License: personal non-commercial grant. Full text: LICENSES/jarvis2.0-LICENSE
//
// Deviation, intentional: frontend/src/orb.ts integrates once per animation frame and assumes 60 Hz.
// A 120 Hz ProMotion display would otherwise run the motion twice as fast. This simulation advances
// on a fixed 60 Hz step. Render deltas are quantized to 120 Hz quanta and two quanta make one step,
// so 120 render frames at 60 Hz and 240 render frames at 120 Hz land on the same state.

public struct OrbRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static func hex(_ value: UInt32) -> OrbRGB {
        OrbRGB(
            r: Double((value >> 16) & 0xff) / 255,
            g: Double((value >> 8) & 0xff) / 255,
            b: Double(value & 0xff) / 255)
    }

    public func lerp(toward target: OrbRGB, amount: Double) -> OrbRGB {
        OrbRGB(
            r: r + (target.r - r) * amount,
            g: g + (target.g - g) * amount,
            b: b + (target.b - b) * amount)
    }
}

/// Per-state targets from frontend/src/orb.ts:134-149.
public struct OrbStateTargets: Equatable, Sendable {
    public var radius: Double
    public var speed: Double
    public var bright: Double
    public var size: Double
    public var lineAmount: Double
    public var electronRate: Double

    public init(radius: Double, speed: Double, bright: Double, size: Double, lineAmount: Double, electronRate: Double) {
        self.radius = radius
        self.speed = speed
        self.bright = bright
        self.size = size
        self.lineAmount = lineAmount
        self.electronRate = electronRate
    }

    public static func of(_ state: OrbVisualState) -> OrbStateTargets {
        switch state {
        case .idle:
            OrbStateTargets(radius: 28, speed: 0.2, bright: 0.5, size: 0.35, lineAmount: 0.15, electronRate: 0)
        case .listening:
            OrbStateTargets(radius: 22, speed: 0.3, bright: 0.65, size: 0.4, lineAmount: 0.4, electronRate: 0)
        case .thinking:
            OrbStateTargets(radius: 16, speed: 0.5, bright: 0.7, size: 0.3, lineAmount: 1, electronRate: 0.015)
        case .speaking:
            OrbStateTargets(radius: 18, speed: 0.2, bright: 0.7, size: 0.4, lineAmount: 0.8, electronRate: 0)
        case .compacting:
            OrbStateTargets(radius: 12, speed: 0.08, bright: 0.28, size: 0.28, lineAmount: 0, electronRate: 0)
        }
    }
}

public struct OrbParticle: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var vx: Double
    public var vy: Double
    public var vz: Double
    public var phase: Double
}

public struct OrbLine: Equatable, Sendable {
    public var x1, y1, z1, x2, y2, z2: Double
}

public struct OrbElectron: Equatable, Sendable {
    public var sx, sy, sz, ex, ey, ez: Double
    public var travel: Double
    public var speed: Double
}

/// Mulberry32. The upstream `Math.random()` stream is not seedable; tests need a fixed stream
/// with the same uniform range, [0, 1).
public struct OrbUnitRNG: Equatable, Sendable {
    public var state: UInt32

    public init(seed: UInt32) { state = seed }

    public mutating func nextUnit() -> Double {
        state = state &+ 0x6D2B79F5
        let mixed = state ^ (state >> 15)
        let first = Self.imul(mixed, state | 1)
        let mixedAgain = first ^ (first >> 7)
        let second = (first &+ Self.imul(mixedAgain, first | 61)) ^ first
        return Double(second ^ (second >> 14)) / 4294967296
    }

    private static func imul(_ a: UInt32, _ b: UInt32) -> UInt32 {
        UInt32(bitPattern: Int32(bitPattern: a) &* Int32(bitPattern: b))
    }
}

public enum OrbIntegrator {
    public static func advance(
        x: Double, y: Double, z: Double,
        vx: Double, vy: Double, vz: Double,
        phase: Double, time: Double,
        currentRadius: Double, currentSpeed: Double,
        state: OrbVisualState, bass: Double, mid: Double
    ) -> (x: Double, y: Double, z: Double, vx: Double, vy: Double, vz: Double) {
        var vx = vx
        var vy = vy
        var vz = vz
        // frontend/src/orb.ts:201-206, two sine drift layers.
        vx += sin(time * 0.05 + phase) * 0.001 * currentSpeed
        vy += cos(time * 0.06 + phase * 1.3) * 0.001 * currentSpeed
        vz += sin(time * 0.055 + phase * 0.7) * 0.001 * currentSpeed
        vx += sin(time * 0.02 + phase * 2.1 + y * 0.1) * 0.0008 * currentSpeed
        vy += cos(time * 0.025 + phase * 1.7 + z * 0.1) * 0.0008 * currentSpeed
        vz += sin(time * 0.022 + phase * 0.9 + x * 0.1) * 0.0008 * currentSpeed

        // frontend/src/orb.ts:208-212. A zero distance uses 0.01.
        let raw = (x * x + y * y + z * z).squareRoot()
        let dist = raw == 0 ? 0.01 : raw
        let pull = max(0, dist - currentRadius) * 0.002 + 0.0003
        vx -= (x / dist) * pull
        vy -= (y / dist) * pull
        vz -= (z / dist) * pull

        // frontend/src/orb.ts:214-217, bass shove.
        if bass > 0.05 {
            vx += (x / dist) * bass * 0.02
            vy += (y / dist) * bass * 0.02
            vz += (z / dist) * bass * 0.02
        }
        // frontend/src/orb.ts:219-222. Speaking mid pulse does not touch z.
        if state == .speaking && mid > 0.1 {
            let pulse = sin(time * 8 + phase)
            vx += (x / dist) * mid * 0.012 * pulse
            vy += (y / dist) * mid * 0.012 * pulse
        }

        // frontend/src/orb.ts:225, damping 0.992, then integrate.
        vx *= 0.992
        vy *= 0.992
        vz *= 0.992
        return (x + vx, y + vy, z + vz, vx, vy, vz)
    }
}

public struct OrbSimulation: Equatable, Sendable {
    /// frontend/src/orb.ts:26
    public static let particleCount = 2000
    /// frontend/src/orb.ts:64
    public static let maxLines = 8000
    /// frontend/src/orb.ts:110
    public static let lineDistance = 8.0
    /// frontend/src/orb.ts:237, floor(N / 600) with N = 2000.
    public static let neighbourStride = 3
    /// frontend/src/orb.ts:274, alive cap. The geometry allocation at line 79 is 200 and is not the cap.
    public static let maxLiveElectrons = 3
    /// frontend/src/orb.ts:274
    public static let electronSpawnGap = 1.0
    /// frontend/src/orb.ts:225
    public static let damping = 0.992
    public static let fixedStepHz = 60.0
    public static let renderQuantumHz = 120.0
    public static let intentionalFrameRateDeviation = "Intentional deviation from frontend/src/orb.ts: the original integrates once per animation frame and assumes 60 Hz. A fixed 60 Hz step with an accumulator keeps 120 Hz ProMotion from running the motion twice as fast."

    public private(set) var particles: [OrbParticle]
    public private(set) var lines: [OrbLine]
    public private(set) var electrons: [OrbElectron]
    public private(set) var electronSpawnTimes: [Double]
    public private(set) var electronSpawnSpeeds: [Double]
    public private(set) var visualState: OrbVisualState
    public private(set) var currentRadius: Double
    public private(set) var currentSpeed: Double
    public private(set) var currentBright: Double
    public private(set) var currentSize: Double
    public private(set) var lineAmount: Double
    public private(set) var electronSpawnRate: Double
    public private(set) var transitionEnergy: Double
    public private(set) var spinX: Double
    public private(set) var spinY: Double
    public private(set) var spinZ: Double
    public private(set) var cloudZ: Double
    public private(set) var cloudZVel: Double
    public private(set) var cameraX: Double
    public private(set) var cameraY: Double
    /// frontend/src/orb.ts:35
    public private(set) var cameraZ: Double
    public private(set) var lookAtZ: Double
    public private(set) var color: OrbRGB
    public private(set) var displayedOpacity: Double
    public private(set) var pointSize: Double
    public private(set) var lineOpacity: Double
    public private(set) var simulatedTime: Double
    public private(set) var lineCount: Int

    public enum Distribution: Sendable {
        /// frontend/src/orb.ts:44-49, filled ball, r = 25 * sqrt(U), not a shell.
        case filledBall
        case originCluster
    }

    private var rng: OrbUnitRNG
    private var lastAppliedState: OrbVisualState
    private var lastElectronSpawn: Double
    private var pendingQuanta: Int
    private var reduceMotion: Bool

    public init(seed: UInt32, state: OrbVisualState = .idle, distribution: Distribution = .filledBall) {
        var rng = OrbUnitRNG(seed: seed)
        var spawned: [OrbParticle] = []
        spawned.reserveCapacity(Self.particleCount)
        for _ in 0..<Self.particleCount {
            let theta = rng.nextUnit() * Double.pi * 2
            let phi = acos(2 * rng.nextUnit() - 1)
            let radius = rng.nextUnit().squareRoot() * 25
            let phase = rng.nextUnit() * 1000
            let placedRadius = distribution == .originCluster ? 0 : radius
            let x = placedRadius * sin(phi) * cos(theta)
            let y = placedRadius * sin(phi) * sin(theta)
            let z = placedRadius * cos(phi)
            if distribution == .originCluster {
                spawned.append(OrbParticle(x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, phase: phase))
            } else {
                spawned.append(OrbParticle(x: x, y: y, z: z, vx: 0, vy: 0, vz: 0, phase: phase))
            }
        }
        self.rng = rng
        particles = spawned
        lines = []
        electrons = []
        electronSpawnTimes = []
        electronSpawnSpeeds = []
        visualState = state
        // frontend/src/orb.ts:105-110
        currentRadius = 25
        currentSpeed = 0.3
        currentBright = 0.6
        currentSize = 0.4
        lineAmount = 0
        electronSpawnRate = 0
        transitionEnergy = 0
        spinX = 0
        spinY = 0
        spinZ = 0
        cloudZ = 0
        cloudZVel = 0
        cameraX = 0
        cameraY = 0
        cameraZ = 80
        lookAtZ = 0
        color = .hex(0x4ca8e8)
        displayedOpacity = 0.6
        pointSize = 0.4
        lineOpacity = 0
        simulatedTime = 0
        lineCount = 0
        lastAppliedState = state
        lastElectronSpawn = 0
        pendingQuanta = 0
        reduceMotion = false
    }

    public mutating func setVisualState(_ state: OrbVisualState) {
        visualState = state
    }

    /// One render frame. `delta` is seconds of display time. Quanta are rounded to 1/120 s.
    /// A hitch is capped at eight simulation steps so one late frame cannot run the solver unbound.
    public mutating func renderFrame(delta: Double, audio: OrbAudioBands, reduceMotion: Bool) {
        let quanta: Int
        if delta.isFinite, delta > 0 {
            let scaled = (delta * Self.renderQuantumHz).rounded()
            quanta = max(0, min(16, Int(scaled)))
        } else {
            quanta = 0
        }
        pendingQuanta += quanta
        var steps = 0
        while pendingQuanta >= 2, steps < 8 {
            integrateFixedStep(audio: audio, reduceMotion: reduceMotion)
            pendingQuanta -= 2
            steps += 1
        }
    }

    public mutating func integrateFixedStep(audio: OrbAudioBands, reduceMotion: Bool) {
        let bands = OrbAudioBands.sanitized(audio.bass, audio.mid)
        let time = simulatedTime
        self.reduceMotion = reduceMotion
        let targets = OrbStateTargets.of(visualState)

        if reduceMotion {
            // Freeze the tumble, the camera drift, the depth spring, the particles and the electrons.
            // The only motion is a gentle opacity breathe. A state change cuts to its targets.
            currentRadius = targets.radius
            currentSpeed = targets.speed
            currentBright = targets.bright
            currentSize = targets.size
            lineAmount = targets.lineAmount
            electronSpawnRate = 0
            transitionEnergy = 0
            spinX = 0
            spinY = 0
            spinZ = 0
            cloudZ = 0
            cloudZVel = 0
            cameraX = 0
            cameraY = 0
            lookAtZ = 0
            color = Self.colorTarget(visualState)
            displayedOpacity = targets.bright * (0.92 + 0.08 * sin(time * 0.7))
            pointSize = targets.size
            lastAppliedState = visualState
            rebuildLines(bass: 0)
            simulatedTime += 1 / Self.fixedStepHz
            return
        }

        // frontend/src/orb.ts:152-157
        currentRadius += (targets.radius - currentRadius) * 0.02
        currentSpeed += (targets.speed - currentSpeed) * 0.02
        currentBright += (targets.bright - currentBright) * 0.02
        currentSize += (targets.size - currentSize) * 0.02
        lineAmount += (targets.lineAmount - lineAmount) * 0.02
        electronSpawnRate += (targets.electronRate - electronSpawnRate) * 0.02

        // frontend/src/orb.ts:160-165
        if visualState != lastAppliedState {
            transitionEnergy = 1
            lastAppliedState = visualState
        }
        transitionEnergy *= 0.985
        if transitionEnergy > 0.05 {
            spinX += transitionEnergy * 0.012 * sin(time * 1.7)
            spinY += transitionEnergy * 0.015
            spinZ += transitionEnergy * 0.008 * cos(time * 1.3)
        }

        // frontend/src/orb.ts:179-185
        var zTarget = sin(time * 0.12) * 8
        if visualState == .thinking {
            zTarget = sin(time * 0.3) * 15 + sin(time * 0.9) * 6
        } else if visualState == .speaking {
            zTarget = sin(time * 0.15) * 6 - bands.bass * 10
        } else if visualState == .compacting {
            zTarget = -20 + sin(time * 0.08) * 3
        }
        cloudZVel += (zTarget - cloudZ) * 0.008
        cloudZVel *= 0.94
        cloudZ += cloudZVel

        for index in particles.indices {
            let particle = particles[index]
            let stepped = OrbIntegrator.advance(
                x: particle.x, y: particle.y, z: particle.z,
                vx: particle.vx, vy: particle.vy, vz: particle.vz,
                phase: particle.phase, time: time,
                currentRadius: currentRadius, currentSpeed: currentSpeed,
                state: visualState, bass: bands.bass, mid: bands.mid)
            particles[index].x = stepped.x
            particles[index].y = stepped.y
            particles[index].z = stepped.z
            particles[index].vx = stepped.vx
            particles[index].vy = stepped.vy
            particles[index].vz = stepped.vz
        }

        rebuildLines(bass: bands.bass)
        updateElectrons(time: time)

        // frontend/src/orb.ts:313-323
        displayedOpacity = currentBright + bands.bass * 0.08
        pointSize = currentSize + bands.bass * 0.05
        let chroma = Self.colorTarget(visualState)
        let chromaRate = visualState == .compacting ? 0.03 : 0.015
        color = color.lerp(toward: chroma, amount: chromaRate)
        cameraX = sin(time * 0.02) * 5
        cameraY = cos(time * 0.03) * 3
        cameraZ = 80
        lookAtZ = cloudZ * 0.2
        simulatedTime += 1 / Self.fixedStepHz
    }

    private mutating func rebuildLines(bass: Double) {
        // frontend/src/orb.ts:231-255. Opacity is lineAmount * 0.12.
        lineOpacity = lineAmount * 0.12
        guard lineAmount > 0.01 else {
            lines = []
            lineCount = 0
            return
        }
        let step = max(1, Self.particleCount / 600)
        let maxDist = Self.lineDistance * (1 + bass * 0.5)
        let maxDistSq = maxDist * maxDist
        var built: [OrbLine] = []
        built.reserveCapacity(256)
        var i = 0
        while i < particles.count, built.count < Self.maxLines {
            let a = particles[i]
            var j = i + step
            while j < particles.count, built.count < Self.maxLines {
                let b = particles[j]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let dz = b.z - a.z
                if dx * dx + dy * dy + dz * dz < maxDistSq {
                    built.append(OrbLine(x1: a.x, y1: a.y, z1: a.z, x2: b.x, y2: b.y, z2: b.z))
                }
                j += step
            }
            i += step
        }
        lines = built
        lineCount = built.count
    }

    private mutating func updateElectrons(time: Double) {
        // frontend/src/orb.ts:271-283. Spawn only while connections exist and the rate has risen.
        let connectionCount = min(lines.count, 500)
        if connectionCount > 0, electronSpawnRate > 0.005,
           electrons.count < Self.maxLiveElectrons, (time - lastElectronSpawn) > Self.electronSpawnGap {
            let pick = min(connectionCount - 1, Int(rng.nextUnit() * Double(connectionCount)))
            let line = lines[pick]
            let speed = 0.003 + rng.nextUnit() * 0.003
            electrons.append(OrbElectron(
                sx: line.x1, sy: line.y1, sz: line.z1,
                ex: line.x2, ey: line.y2, ez: line.z2,
                travel: 0, speed: speed))
            electronSpawnTimes.append(time)
            electronSpawnSpeeds.append(speed)
            lastElectronSpawn = time
        }

        var alive: [OrbElectron] = []
        alive.reserveCapacity(electrons.count)
        for var electron in electrons {
            electron.travel += electron.speed
            if electron.travel < 1 { alive.append(electron) }
        }
        electrons = alive
    }

    private static func colorTarget(_ state: OrbVisualState) -> OrbRGB {
        switch state {
        case .thinking: .hex(0x6ec4ff)
        case .speaking: .hex(0x5ab8f0)
        case .compacting: .hex(0x3a5f8a)
        case .idle, .listening: .hex(0x4ca8e8)
        }
    }
}
