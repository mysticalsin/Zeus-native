import Foundation
import Testing
@testable import ZeusCore

struct SpectrumTests {
    private func sine(_ hz: Double, rate: Double = 48_000, amplitude: Float = 0.5, count: Int = SpectrumMath.fftSize) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    @Test func bandEdgesAreLogSpacedAndCoverTheRange() {
        let edges = SpectrumMath.bandEdges(sampleRate: 48_000)
        #expect(edges.count == SpectrumMath.bandCount + 1)
        #expect(abs(edges[0] - 40) < 0.001)
        #expect(edges.last! <= 16_000.001)
        let ratios = zip(edges, edges.dropFirst()).map { $1 / $0 }
        #expect(ratios.allSatisfy { abs($0 - ratios[0]) < 1e-9 })
    }

    @Test(arguments: [100.0, 440.0, 1_000.0, 3_000.0, 8_000.0, 12_000.0])
    func theRightBandPeaksForASine(hz: Double) {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        let levels = analyzer.levels(samples: sine(hz))
        let peak = levels.indices.max { levels[$0] < levels[$1] }!
        let expected = SpectrumMath.band(forFrequency: hz, sampleRate: 48_000)!
        #expect(abs(peak - expected) <= 1, "\(hz) Hz peaked in band \(peak), expected \(expected)")
        #expect(levels[peak] > 0.7)
        // Far-away bands stay near the floor.
        let far = levels.indices.filter { abs($0 - expected) > 6 }
        #expect(far.allSatisfy { levels[$0] < 0.45 })
    }

    @Test func silenceIsZeroAndLouderIsHigher() {
        let analyzer = SpectrumAnalyzer(sampleRate: 44_100)
        #expect(analyzer.levels(samples: [Float](repeating: 0, count: 2048)).allSatisfy { $0 == 0 })
        let quiet = analyzer.levels(samples: sine(1_000, rate: 44_100, amplitude: 0.01)).max()!
        let loud = analyzer.levels(samples: sine(1_000, rate: 44_100, amplitude: 0.5)).max()!
        #expect(loud > quiet)
    }

    @Test func shortInputIsPaddedNotACrash() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        #expect(analyzer.levels(samples: sine(1_000, count: 300)).count == SpectrumMath.bandCount)
    }

    @Test func smoothingRisesFastAndFallsSlowly() {
        let zero = [Float](repeating: 0, count: 4), one = [Float](repeating: 1, count: 4)
        let rise = SpectrumMath.smooth(previous: zero, target: one, dt: 1 / 60)
        let fall = SpectrumMath.smooth(previous: one, target: zero, dt: 1 / 60)
        #expect(rise[0] > 0.2)
        #expect(1 - fall[0] < rise[0]) // the drop after one frame is smaller than the rise
        // Same result at half the rate twice: it does not depend on the frame rate.
        let half = SpectrumMath.smooth(previous: SpectrumMath.smooth(previous: zero, target: one, dt: 1 / 120), target: one, dt: 1 / 120)
        #expect(abs(half[0] - SpectrumMath.smooth(previous: zero, target: one, dt: 1 / 60)[0]) < 0.001)
        // It converges and never overshoots.
        var level = zero
        for _ in 0..<600 { level = SpectrumMath.smooth(previous: level, target: one, dt: 1 / 60); #expect(level[0] <= 1) }
        #expect(level[0] > 0.999)
    }

    @Test func ringKeepsTheNewestSamples() {
        let ring = SampleRing(capacity: 8)
        let data: [Float] = (1...12).map(Float.init)
        data.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 12) }
        #expect(ring.latest(4) == [9, 10, 11, 12])
        #expect(ring.latest(10).prefix(2) == [0, 0]) // only 8 are kept
    }

    @Test func zeroWorkUnlessSomethingNeedsIt() {
        #expect(!SpectrumGate.shouldRun(wavesVisible: false, closedSpectrumOn: false, musicPlaying: false))
        #expect(!SpectrumGate.shouldRun(wavesVisible: false, closedSpectrumOn: false, musicPlaying: true))
        #expect(!SpectrumGate.shouldRun(wavesVisible: false, closedSpectrumOn: true, musicPlaying: false))
        #expect(SpectrumGate.shouldRun(wavesVisible: false, closedSpectrumOn: true, musicPlaying: true))
        #expect(SpectrumGate.shouldRun(wavesVisible: true, closedSpectrumOn: false, musicPlaying: false))
        #expect(SpectrumGate.framesPerSecond(wavesVisible: true) == 60)
        #expect(SpectrumGate.framesPerSecond(wavesVisible: false) == 30)
    }

    @Test func permissionDecidesWhetherToCapture() {
        #expect(SpectrumGate.decision(permission: .allowed, personAsked: false) == .capture)
        #expect(SpectrumGate.decision(permission: .notAsked, personAsked: false) == .wait) // never a surprise prompt
        #expect(SpectrumGate.decision(permission: .notAsked, personAsked: true) == .capture)
        #expect(SpectrumGate.decision(permission: .refused, personAsked: true) == .needsSettings)
        #expect(SpectrumGate.decision(permission: .refused, personAsked: false) == .needsSettings)
    }

    @Test func sensitivityIsAClampedGain() {
        #expect(SpectrumMath.gain(sensitivityPercent: 100) == 1)
        #expect(SpectrumMath.gain(sensitivityPercent: 5) == 0.25)
        #expect(SpectrumMath.gain(sensitivityPercent: 999) == 3)
    }

    @Test func liveMusicWaveGrowsWithLevel() {
        let quiet = NotchLightMath.musicWave(time: 1, level: 0), loud = NotchLightMath.musicWave(time: 1, level: 1)
        #expect(loud.opacity > quiet.opacity)
        #expect(loud.to - loud.from > quiet.to - quiet.from)
    }

    @Test func theWavesTabIsOffByDefaultButCanBeSwitchedOn() {
        #expect(!TopBarLayout.standard.contains(.waves))
        #expect(!TopBarLayout.defaultRow.contains(.waves))
        #expect(TopBarTab.allCases.last == .waves)
        #expect(TopBarTab.waves.symbol == "waveform")
        var layout = TopBarLayout.standard
        layout.toggle(.waves)
        #expect(layout.contains(.waves))
    }
}
