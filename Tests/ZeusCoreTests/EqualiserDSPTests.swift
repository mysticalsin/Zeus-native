import Darwin
import Foundation
import Testing
@testable import ZeusCore

// MARK: - Helpers

private func amplitude(of signal: [Float], at frequency: Double, sampleRate: Double) -> Double {
    var re = 0.0
    var im = 0.0
    for (n, x) in signal.enumerated() {
        let phase = 2 * Double.pi * frequency * Double(n) / sampleRate
        re += Double(x) * cos(phase)
        im -= Double(x) * sin(phase)
    }
    return 2 * (re * re + im * im).squareRoot() / Double(signal.count)
}

private func decibels(_ ratio: Double) -> Double { 20 * log10(ratio) }

private func sine(_ frequency: Double, amplitude: Double, frames: Int, start: Int = 0, sampleRate: Double) -> [Float] {
    (0..<frames).map { Float(amplitude * sin(2 * Double.pi * frequency * Double(start + $0) / sampleRate)) }
}

private func rms(_ signal: [Float]) -> Double {
    guard !signal.isEmpty else { return 0 }
    return (signal.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(signal.count)).squareRoot()
}

/// A repeatable pseudo-random buffer, so two runs see the same noise.
private func noise(frames: Int, amplitude: Double, seed: UInt64) -> [Float] {
    var state = seed
    return (0..<frames).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Double(state >> 11) / Double(1 << 53)
        return Float(amplitude * (unit * 2 - 1))
    }
}

private func parameters(_ gains: [Int: Double] = [:], volume: Double = 1, bypass: Bool = false) -> EqualiserParameters {
    var values = [Double](repeating: 0, count: EqualiserParameters.bandCount)
    for (band, gain) in gains { values[band] = gain }
    return EqualiserParameters(gainsDB: values, volume: volume, bypass: bypass)
}

/// Runs `channels` signals through the kernel in buffers of `bufferFrames` and returns each channel's output.
private func render(
    _ kernel: EqualiserKernel,
    channels signals: [[Float]],
    bufferFrames: Int,
    interleaved: Bool,
    sampleRate: Double
) -> [[Float]] {
    let channels = signals.count
    let total = signals[0].count
    var outputs = [[Float]](repeating: [], count: channels)
    var offset = 0
    while offset < total {
        let frames = min(bufferFrames, total - offset)
        var buffer = [Float](repeating: 0, count: frames * channels)
        for c in 0..<channels {
            for f in 0..<frames {
                buffer[interleaved ? f * channels + c : c * frames + f] = signals[c][offset + f]
            }
        }
        buffer.withUnsafeMutableBufferPointer {
            kernel.process($0.baseAddress!, frames: frames, channels: channels, interleaved: interleaved, sampleRate: sampleRate)
        }
        for c in 0..<channels {
            for f in 0..<frames {
                outputs[c].append(buffer[interleaved ? f * channels + c : c * frames + f])
            }
        }
        offset += frames
    }
    return outputs
}

// MARK: - 1. Coefficients

@Suite struct EqualiserBiquadDesignTests {
    private struct Reference {
        let kind: BiquadKind
        let frequency: Double
        let gainDB: Double
        let q: Double
        let sampleRate: Double
        let expected: [Double]
    }

    // Worked out apart from the Swift code, from the published cookbook formulas.
    private static let references: [Reference] = [
        Reference(kind: .peaking, frequency: 1000, gainDB: 6, q: 1.41, sampleRate: 48000, expected: [
            1.0315779106167673, -1.9199761435975966, 0.9049656314387664, -1.9199761435975966, 0.9365435420555338,
        ]),
        Reference(kind: .peaking, frequency: 4000, gainDB: -9.5, q: 1.41, sampleRate: 44100, expected: [
            0.834771572969507, -1.265538185544558, 0.6683266515159856, -1.265538185544558, 0.5030982244854925,
        ]),
        Reference(kind: .lowShelf, frequency: 100, gainDB: 9, q: 0.71, sampleRate: 44100, expected: [
            1.0052705923161476, -1.984402578137652, 0.9794701550146768, -1.984511669255456, 0.98463165621302,
        ]),
        Reference(kind: .lowShelf, frequency: 31.5, gainDB: -12, q: 0.71, sampleRate: 48000, expected: [
            0.9979560814248326, -1.991809089669404, 0.9938614945418194, -1.9917964405390987, 0.9918302250969574,
        ]),
        Reference(kind: .highShelf, frequency: 8000, gainDB: -7.5, q: 0.71, sampleRate: 48000, expected: [
            0.5682862132467318, -0.21929885539266047, 0.11359775252702778, -0.8372280678634696, 0.2998131782445685,
        ]),
        Reference(kind: .highShelf, frequency: 16000, gainDB: 12, q: 0.71, sampleRate: 96000, expected: [
            2.4657686379412085, -2.3570110585818944, 0.8367345103055925, -0.23805680242098204, 0.18354889208588868,
        ]),
    ]

    @Test func coefficientsMatchReferenceValues() {
        for ref in Self.references {
            let c = BiquadDesign.coefficients(
                kind: ref.kind, frequency: ref.frequency, gainDB: ref.gainDB, q: ref.q, sampleRate: ref.sampleRate
            )
            let got = [c.b0, c.b1, c.b2, c.a1, c.a2]
            for (index, value) in got.enumerated() {
                #expect(abs(value - ref.expected[index]) < 1e-9, "\(ref.kind) \(ref.frequency) Hz term \(index)")
            }
        }
    }

    @Test func magnitudeGivesTheGainAtTheCentreAndOnShelfPlateaus() {
        let peak = BiquadDesign.coefficients(kind: .peaking, frequency: 1000, gainDB: 6, q: 1.41, sampleRate: 48000)
        #expect(abs(BiquadDesign.magnitudeDB(peak, frequency: 1000, sampleRate: 48000) - 6) < 0.1)
        let cut = BiquadDesign.coefficients(kind: .peaking, frequency: 4000, gainDB: -9.5, q: 1.41, sampleRate: 44100)
        #expect(abs(BiquadDesign.magnitudeDB(cut, frequency: 4000, sampleRate: 44100) + 9.5) < 0.1)

        let low = BiquadDesign.coefficients(kind: .lowShelf, frequency: 100, gainDB: 9, q: 0.71, sampleRate: 44100)
        #expect(abs(BiquadDesign.magnitudeDB(low, frequency: 1, sampleRate: 44100) - 9) < 0.1)
        #expect(abs(BiquadDesign.magnitudeDB(low, frequency: 10000, sampleRate: 44100)) < 0.1)

        let high = BiquadDesign.coefficients(kind: .highShelf, frequency: 8000, gainDB: -7.5, q: 0.71, sampleRate: 48000)
        #expect(abs(BiquadDesign.magnitudeDB(high, frequency: 20000, sampleRate: 48000) + 7.5) < 0.1)
        #expect(abs(BiquadDesign.magnitudeDB(high, frequency: 100, sampleRate: 48000)) < 0.1)
    }

    @Test func magnitudeOfTheIdentityIsZero() {
        #expect(BiquadDesign.magnitudeDB(.identity, frequency: 1000, sampleRate: 48000) == 0)
    }

    @Test func gainZeroTheNyquistGuardAndNonFiniteInputsGiveIdentity() {
        let rate = 48000.0
        func design(
            _ kind: BiquadKind = .peaking, f: Double = 1000, g: Double = 6, q: Double = 1.41, fs: Double = rate
        ) -> BiquadCoefficients {
            BiquadDesign.coefficients(kind: kind, frequency: f, gainDB: g, q: q, sampleRate: fs)
        }
        for kind in BiquadKind.allCases {
            #expect(design(kind, g: 0) == .identity)
            #expect(design(kind, f: 0.45 * rate) == .identity)
            #expect(design(kind, f: 0.46 * rate) == .identity)
            #expect(design(kind, f: rate) == .identity)
            #expect(design(kind, f: 0) == .identity)
            #expect(design(kind, g: .nan) == .identity)
            #expect(design(kind, g: .infinity) == .identity)
            #expect(design(kind, f: .nan) == .identity)
            #expect(design(kind, f: .infinity) == .identity)
            #expect(design(kind, q: .nan) == .identity)
            #expect(design(kind, q: 0) == .identity)
            #expect(design(kind, fs: 0) == .identity)
            #expect(design(kind, fs: .nan) == .identity)
        }
        #expect(design() != .identity)
        #expect(design(f: 0.449 * rate) != .identity)
    }
}

// MARK: - 2. Cascade

@Suite struct EqualiserCascadeTests {
    @Test func anImpulseThroughAFlatCascadeIsUnchanged() {
        let cascade = BiquadCascade(channels: 1, stages: 4)
        var signal = [Float](repeating: 0, count: 64)
        signal[3] = 0.25
        let original = signal
        signal.withUnsafeMutableBufferPointer {
            cascade.process(channel: 0, samples: $0.baseAddress!, count: $0.count, stride: 1)
        }
        #expect(signal == original)
    }

    @Test func aSineThroughPlusSixRisesSixDecibels() {
        let rate = 48000.0
        let cascade = BiquadCascade(channels: 1, stages: 1)
        cascade.setCoefficients(
            BiquadDesign.coefficients(kind: .peaking, frequency: 1000, gainDB: 6, q: 1.41, sampleRate: rate), stage: 0
        )
        var signal = sine(1000, amplitude: 0.1, frames: 9600, sampleRate: rate)
        signal.withUnsafeMutableBufferPointer {
            cascade.process(channel: 0, samples: $0.baseAddress!, count: $0.count, stride: 1)
        }
        let settled = Array(signal[4800...])
        let rise = decibels(amplitude(of: settled, at: 1000, sampleRate: rate) / 0.1)
        #expect(abs(rise - 6) < 0.1)
    }

    @Test func channelsKeepSeparateStateAndStrideReadsInterleavedSamples() {
        let rate = 48000.0
        let cascade = BiquadCascade(channels: 2, stages: 1)
        cascade.setCoefficients(
            BiquadDesign.coefficients(kind: .lowShelf, frequency: 200, gainDB: 8, q: 0.71, sampleRate: rate), stage: 0
        )
        let left = sine(300, amplitude: 0.2, frames: 512, sampleRate: rate)
        let right = sine(5000, amplitude: 0.1, frames: 512, sampleRate: rate)
        var inter = [Float](repeating: 0, count: 1024)
        for f in 0..<512 {
            inter[2 * f] = left[f]
            inter[2 * f + 1] = right[f]
        }
        inter.withUnsafeMutableBufferPointer {
            cascade.process(channel: 0, samples: $0.baseAddress!, count: 512, stride: 2)
            cascade.process(channel: 1, samples: $0.baseAddress! + 1, count: 512, stride: 2)
        }
        var oneL = left
        var oneR = right
        let solo = BiquadCascade(channels: 1, stages: 1)
        solo.setCoefficients(
            BiquadDesign.coefficients(kind: .lowShelf, frequency: 200, gainDB: 8, q: 0.71, sampleRate: rate), stage: 0
        )
        oneL.withUnsafeMutableBufferPointer { solo.process(channel: 0, samples: $0.baseAddress!, count: 512, stride: 1) }
        solo.reset()
        oneR.withUnsafeMutableBufferPointer { solo.process(channel: 0, samples: $0.baseAddress!, count: 512, stride: 1) }
        for f in 0..<512 {
            #expect(inter[2 * f] == oneL[f])
            #expect(inter[2 * f + 1] == oneR[f])
        }
    }

    @Test func resetClearsTheFilterMemory() {
        let rate = 48000.0
        let cascade = BiquadCascade(channels: 1, stages: 1)
        cascade.setCoefficients(
            BiquadDesign.coefficients(kind: .peaking, frequency: 500, gainDB: 12, q: 1.41, sampleRate: rate), stage: 0
        )
        var first = [Float](repeating: 0, count: 32)
        first[0] = 1
        first.withUnsafeMutableBufferPointer { cascade.process(channel: 0, samples: $0.baseAddress!, count: 32, stride: 1) }
        cascade.reset()
        var second = [Float](repeating: 0, count: 32)
        second[0] = 1
        second.withUnsafeMutableBufferPointer { cascade.process(channel: 0, samples: $0.baseAddress!, count: 32, stride: 1) }
        #expect(first == second)
    }
}

// MARK: - Gain staging, smoothing, limiter

@Suite struct EqualiserGainStagingTests {
    @Test func preampLowersTheSignalByTheLargestBoost() {
        #expect(GainStaging.preampDB(bandGainsDB: [0, 3, -6, 4.5, 0]) == -4.5)
        #expect(GainStaging.preampDB(bandGainsDB: [12, 12, 12]) == -12)
        #expect(GainStaging.preampDB(bandGainsDB: [-3, -6, 0]) == 0)
        #expect(GainStaging.preampDB(bandGainsDB: [-3, -6]) == 0)
        #expect(GainStaging.preampDB(bandGainsDB: []) == 0)
        #expect(GainStaging.preampDB(bandGainsDB: [Double](repeating: 0, count: 10)) == 0)
    }

    @Test func volumeIsSquaredAndExactAtTheEnds() {
        #expect(GainStaging.linear(volume: 0) == 0)
        #expect(GainStaging.linear(volume: 1) == 1)
        #expect(GainStaging.linear(volume: 0.5) == 0.25)
        #expect(GainStaging.linear(volume: -0.5) == 0)
        #expect(GainStaging.linear(volume: 2) == 1)
        #expect(GainStaging.linear(volume: .nan) == 1)
    }

    @Test func aSmoothingStepMovesAtMostMaxStepTowardTheTarget() {
        #expect(ParameterSmoothing.step(current: 0, target: 12, maxStep: 1.5) == 1.5)
        #expect(ParameterSmoothing.step(current: 0, target: -12, maxStep: 1.5) == -1.5)
        #expect(ParameterSmoothing.step(current: 11, target: 12, maxStep: 1.5) == 12)
        #expect(ParameterSmoothing.step(current: 5, target: 5, maxStep: 1.5) == 5)
        #expect(ParameterSmoothing.step(current: 0, target: 12, maxStep: 0) == 0)
        #expect(ParameterSmoothing.step(current: 3, target: .nan, maxStep: 1.5) == 3)
        var value = 0.0
        var steps = 0
        while value != 12 {
            let next = ParameterSmoothing.step(current: value, target: 12, maxStep: 1.5)
            #expect(next - value <= 1.5 + 1e-12)
            value = next
            steps += 1
        }
        #expect(steps == 8)
    }
}

@Suite struct EqualiserLimiterTests {
    @Test func thresholdIsOneDecibelBelowFullScale() {
        #expect(abs(SoftLimiter(sampleRate: 48000).threshold - pow(10, -1.0 / 20)) < 1e-12)
    }

    @Test func attackIsInstantAndTheOutputNeverPassesFullScale() {
        var limiter = SoftLimiter(sampleRate: 48000)
        let loud = limiter.process(1.0)
        #expect(abs(loud) <= limiter.threshold + 1e-12)
        var limiter2 = SoftLimiter(sampleRate: 48000)
        for value in [0.1, 4.0, -8.0, 0.2, 100.0, -0.5, 1e9] {
            let out = limiter2.process(value)
            #expect(abs(out) <= 1)
        }
    }

    @Test func quietSignalsPassUnchanged() {
        var limiter = SoftLimiter(sampleRate: 48000)
        for value in [0.0, 0.3, -0.5, 0.85] { #expect(limiter.process(value) == value) }
    }

    @Test func releaseTakesAboutFiftyMilliseconds() {
        let rate = 48000.0
        var limiter = SoftLimiter(sampleRate: rate)
        _ = limiter.process(4.0)
        let reduced = limiter.process(0.1) / 0.1
        #expect(reduced < 0.3)
        for _ in 0..<Int(0.05 * rate) - 1 { _ = limiter.process(0.1) }
        let afterFifty = limiter.process(0.1) / 0.1
        let recovered = (afterFifty - reduced) / (1 - reduced)
        #expect(recovered > 0.55 && recovered < 0.70)
        for _ in 0..<Int(0.5 * rate) { _ = limiter.process(0.1) }
        #expect(limiter.process(0.1) / 0.1 > 0.999)
    }

    @Test func nonFiniteInputGivesSilenceAndKeepsTheStateUsable() {
        var limiter = SoftLimiter(sampleRate: 48000)
        #expect(limiter.process(.nan) == 0)
        #expect(limiter.process(.infinity) == 0)
        #expect(limiter.process(0.25) == 0.25)
    }
}

// MARK: - Mailbox, scratch

@Suite struct EqualiserMailboxTests {
    @Test func aPostedValueIsTakenAndClamped() {
        let mailbox = EqualiserMailbox()
        var target = EqualiserTarget()
        #expect(mailbox.take(into: &target))
        #expect(target.volume == 1 && !target.bypass)
        var gains = [Double](repeating: 0, count: 10)
        gains[2] = 40
        gains[4] = -40
        gains[6] = .nan
        gains[8] = 3
        mailbox.post(EqualiserParameters(gainsDB: gains, volume: 7, bypass: true))
        #expect(mailbox.take(into: &target))
        #expect(target.gains[2] == 12)
        #expect(target.gains[4] == -12)
        #expect(target.gains[6] == 0)
        #expect(target.gains[8] == 3)
        #expect(target.volume == 1)
        #expect(target.bypass)
    }

    @Test func aShortGainListFillsTheRestWithZero() {
        let mailbox = EqualiserMailbox()
        mailbox.post(EqualiserParameters(gainsDB: [5, 6], volume: 0.5, bypass: false))
        var target = EqualiserTarget()
        #expect(mailbox.take(into: &target))
        #expect(target.gains[0] == 5 && target.gains[1] == 6 && target.gains[2] == 0)
        #expect(target.volume == 0.5)
    }

    @Test func takeReturnsFalseWhileTheLockIsHeldAndLeavesTheTargetAlone() {
        let mailbox = EqualiserMailbox()
        mailbox.post(parameters([3: 6], volume: 0.4))
        var target = EqualiserTarget()
        let busy = mailbox.withLockHeldForTesting { mailbox.take(into: &target) }
        #expect(busy == false)
        #expect(target == EqualiserTarget())
        #expect(mailbox.take(into: &target))
        #expect(target.gains[3] == 6 && target.volume == 0.4)
    }
}

@Suite struct EqualiserScratchTests {
    @Test func scratchOwnsZeroedSamplesForTheKernel() {
        let scratch = RenderScratch(maxChannels: 2, maxFrames: 256)
        #expect(scratch.maxChannels == 2 && scratch.maxFrames == 256)
        #expect(scratch.samples[0] == 0 && scratch.samples[511] == 0)
        for i in 0..<512 { scratch.samples[i] = 0.1 }
        let kernel = EqualiserKernel(maxChannels: 2, maxFrames: 256, bandCount: 10)
        kernel.process(scratch.samples, frames: 256, channels: 2, interleaved: true, sampleRate: 48000)
        #expect(abs(scratch.samples[300] - 0.1) < 1e-6)
    }
}

// MARK: - 3 to 7. Kernel

@Suite struct EqualiserKernelTests {
    private let rate = 48000.0

    private func kernel(channels: Int = 2, frames: Int = 512) -> EqualiserKernel {
        EqualiserKernel(maxChannels: channels, maxFrames: frames, bandCount: 10)
    }

    /// Plays a tone through a fresh kernel and returns its settled amplitude.
    private func settledLevel(_ params: EqualiserParameters, tone: Double, amplitude amp: Double) -> Double {
        let k = kernel(channels: 1)
        k.mailbox.post(params)
        let signal = sine(tone, amplitude: amp, frames: 512 * 20, sampleRate: rate)
        let out = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate)[0]
        return amplitude(of: Array(out[(512 * 20 - 4800)...]), at: tone, sampleRate: rate)
    }

    @Test func plusSixAtOneKilohertzKeepsThatToneLevelAndLowersTheRest() {
        let params = parameters([5: 6])
        let at1k = settledLevel(params, tone: 1000, amplitude: 0.2)
        let at100 = settledLevel(params, tone: 100, amplitude: 0.2)
        #expect(abs(decibels(at1k / 0.2)) < 0.2)
        #expect(abs(decibels(at1k / at100) - 6) < 0.2)
    }

    @Test func aFullScaleSineWithEveryBandAtPlusTwelveNeverPassesFullScale() {
        for tone in [60.0, 1000, 5000, 12000] {
            let k = kernel()
            k.mailbox.post(parameters(Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, 12.0) })))
            let signal = sine(tone, amplitude: 1, frames: 512 * 24, sampleRate: rate)
            let out = render(k, channels: [signal, signal], bufferFrames: 512, interleaved: false, sampleRate: rate)
            for channel in out {
                #expect(channel.allSatisfy { $0.isFinite && abs($0) <= 1 })
                #expect((channel.map { abs($0) }.max() ?? 0) > 0.1)
            }
        }
    }

    @Test func aNaNInTheMiddleOfABufferGivesOneSilentBuffer() {
        let k = kernel(channels: 1)
        k.mailbox.post(parameters([5: 6]))
        let warm = sine(1000, amplitude: 0.2, frames: 512 * 12, sampleRate: rate)
        _ = render(k, channels: [warm], bufferFrames: 512, interleaved: true, sampleRate: rate)
        var bad = sine(1000, amplitude: 0.2, frames: 512, start: 512 * 12, sampleRate: rate)
        bad[100] = .nan
        let silent = render(k, channels: [bad], bufferFrames: 512, interleaved: true, sampleRate: rate)[0]
        #expect(silent.count == 512 && silent.allSatisfy { $0 == 0 })
        let next = sine(1000, amplitude: 0.2, frames: 512, start: 512 * 13, sampleRate: rate)
        let after = render(k, channels: [next], bufferFrames: 512, interleaved: true, sampleRate: rate)[0]
        #expect(after.allSatisfy { $0.isFinite && abs($0) <= 1 })
        #expect((after.map { abs($0) }.max() ?? 0) > 0.1)

        var infinite = sine(1000, amplitude: 0.2, frames: 512, start: 512 * 14, sampleRate: rate)
        infinite[7] = .infinity
        let second = render(k, channels: [infinite], bufferFrames: 512, interleaved: true, sampleRate: rate)[0]
        #expect(second.allSatisfy { $0 == 0 })
    }

    @Test func aBandJumpTakesEightBuffersWithNoStepAboveOnePointFiveDecibels() {
        let frames = 480
        let k = kernel(channels: 1, frames: frames)
        let burst = noise(frames: frames, amplitude: 0.05, seed: 7)
        func play() -> Double {
            rms(render(k, channels: [burst], bufferFrames: frames, interleaved: true, sampleRate: rate)[0])
        }
        k.mailbox.post(parameters())
        _ = play()
        var previousLevel = play()
        var previousGain = k.smoothedGainDB(band: 5)
        #expect(previousGain == 0)
        k.mailbox.post(parameters([5: 12]))
        var settledAfter: Int?
        for buffer in 1...12 {
            let level = play()
            let gain = k.smoothedGainDB(band: 5)
            #expect(gain - previousGain <= 1.5 + 1e-9)
            #expect(decibels(level / previousLevel) >= -1.5)
            if gain == 12, settledAfter == nil { settledAfter = buffer }
            previousLevel = level
            previousGain = gain
        }
        #expect(settledAfter == 8)
    }

    @Test func thePreampFollowsTheSmoothedGains() {
        let k = kernel(channels: 1)
        k.mailbox.post(parameters([2: 9, 7: 3]))
        let signal = sine(500, amplitude: 0.1, frames: 512, sampleRate: rate)
        _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate)
        #expect(k.smoothedGainDB(band: 2) == 1.5)
        #expect(k.preampDB == -1.5)
        for _ in 0..<7 { _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate) }
        #expect(k.smoothedGainDB(band: 2) == 9)
        #expect(k.smoothedGainDB(band: 7) == 3)
        #expect(k.preampDB == -9)
    }

    @Test func coefficientsAreDesignedOncePerBufferAndNotAtAllWhenSteady() {
        let k = kernel(channels: 2)
        k.mailbox.post(parameters([1: 12, 4: -6]))
        let signal = sine(500, amplitude: 0.1, frames: 512, sampleRate: rate)
        var counts: [Int] = []
        for _ in 0..<12 {
            let before = k.designCount
            _ = render(k, channels: [signal, signal], bufferFrames: 512, interleaved: true, sampleRate: rate)
            counts.append(k.designCount - before)
        }
        // Band 4 reaches minus 6 after four buffers and band 1 reaches plus 12 after eight; flat bands cost nothing.
        #expect(counts == [2, 2, 2, 2, 1, 1, 1, 1, 0, 0, 0, 0])
    }

    @Test func volumeZeroGivesExactZerosOnceTheRampCompletes() {
        for fs in [44100.0, 48000, 96000] {
            let k = kernel(channels: 1)
            k.mailbox.post(parameters(volume: 0))
            let frames = Int(0.02 * fs) + 1500
            let dc = [Float](repeating: 0.5, count: frames)
            let out = render(k, channels: [dc], bufferFrames: 512, interleaved: true, sampleRate: fs)[0]
            let ramp = Int((0.02 * fs).rounded())
            #expect(out[ramp - 10] > 0, "the ramp is not instant at \(fs)")
            #expect(out[10] < 0.5 && out[10] > 0.4, "the ramp starts at once at \(fs)")
            for i in 1..<frames { #expect(out[i] <= out[i - 1], "monotonic at \(fs), sample \(i)") }
            #expect(out[(ramp + 2)...].allSatisfy { $0 == 0 }, "exact zeros at \(fs)")
        }
    }

    @Test func volumeRampsAcrossBufferEdgesWithoutAJump() {
        let k = kernel(channels: 1)
        k.mailbox.post(parameters(volume: 0))
        let dc = [Float](repeating: 0.5, count: 512 * 3)
        let small = render(k, channels: [dc], bufferFrames: 64, interleaved: true, sampleRate: rate)[0]
        let step = 0.5 / (0.02 * rate)
        for i in 1..<small.count { #expect(Double(small[i - 1] - small[i]) <= step * 1.05 + 1e-7) }
    }

    @Test func monoStereoInterleavedAndPlanarAgreePerChannel() {
        let left = sine(440, amplitude: 0.2, frames: 512 * 6, sampleRate: rate)
        let right = sine(2200, amplitude: 0.1, frames: 512 * 6, sampleRate: rate)
        let params = parameters([0: 6, 3: -4, 5: 6, 9: 3])
        func run(_ signals: [[Float]], interleaved: Bool, buffer: Int = 512) -> [[Float]] {
            let k = kernel(channels: signals.count)
            k.mailbox.post(params)
            return render(k, channels: signals, bufferFrames: buffer, interleaved: interleaved, sampleRate: rate)
        }
        let stereoInterleaved = run([left, right], interleaved: true)
        let stereoPlanar = run([left, right], interleaved: false)
        let monoLeft = run([left], interleaved: true)
        let monoRight = run([right], interleaved: false)
        let uneven = run([left, right], interleaved: false, buffer: 300)
        for i in 0..<left.count {
            #expect(abs(stereoInterleaved[0][i] - stereoPlanar[0][i]) < 1e-6)
            #expect(abs(stereoInterleaved[1][i] - stereoPlanar[1][i]) < 1e-6)
            #expect(abs(stereoInterleaved[0][i] - monoLeft[0][i]) < 1e-6)
            #expect(abs(stereoInterleaved[1][i] - monoRight[0][i]) < 1e-6)
        }
        // Different buffer sizes change the glide timing, so only the settled tail must agree.
        for i in (left.count - 400)..<left.count {
            #expect(abs(stereoInterleaved[0][i] - uneven[0][i]) < 1e-3)
        }
    }

    @Test func aBusyMailboxKeepsThePreviousValues() {
        let k = kernel(channels: 1)
        let signal = sine(500, amplitude: 0.1, frames: 512, sampleRate: rate)
        k.mailbox.post(parameters([5: 6]))
        _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate)
        #expect(k.smoothedGainDB(band: 5) == 1.5)
        k.mailbox.post(parameters([5: -12], volume: 0))
        k.mailbox.withLockHeldForTesting {
            for _ in 0..<5 { _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate) }
        }
        // The old target (plus 6) kept steering the glide, and the volume never moved.
        #expect(k.smoothedGainDB(band: 5) == 6)
        #expect(k.volumeGain == 1)
        _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate)
        #expect(k.smoothedGainDB(band: 5) == 4.5)
        #expect(k.volumeGain < 1)
    }

    @Test func bypassGlidesTheBandsBackToFlatAndKeepsTheVolume() {
        let k = kernel(channels: 1)
        let signal = sine(500, amplitude: 0.1, frames: 512, sampleRate: rate)
        k.mailbox.post(parameters([5: 6], volume: 0.5))
        for _ in 0..<10 { _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate) }
        #expect(k.smoothedGainDB(band: 5) == 6)
        k.mailbox.post(parameters([5: 6], volume: 0.5, bypass: true))
        for _ in 0..<6 { _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate) }
        #expect(k.smoothedGainDB(band: 5) == 0)
        #expect(k.volumeGain == 0.25)
    }

    @Test func aRateChangeRedesignsEveryActiveBand() {
        let k = kernel(channels: 1)
        k.mailbox.post(parameters([5: 6]))
        let signal = sine(500, amplitude: 0.1, frames: 512, sampleRate: rate)
        for _ in 0..<5 { _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: rate) }
        let before = k.designCount
        _ = render(k, channels: [signal], bufferFrames: 512, interleaved: true, sampleRate: 44100)
        #expect(k.designCount - before == 1)
    }

    @Test func channelsBeyondTheMaximumAreSilencedAndLongCallbacksRunInChunks() {
        let k = kernel(channels: 2, frames: 128)
        let a = sine(300, amplitude: 0.1, frames: 1000, sampleRate: rate)
        let out = render(k, channels: [a, a, a], bufferFrames: 1000, interleaved: false, sampleRate: rate)
        #expect(out[2].allSatisfy { $0 == 0 })
        #expect(abs(out[0][999] - a[999]) < 1e-6)
        #expect(abs(out[1][999] - a[999]) < 1e-6)
    }
}

// MARK: - 8. Allocation

@Suite(.serialized) struct EqualiserKernelAllocationTests {
    private static func blocksInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.blocks_in_use)
    }

    @Test func aThousandBuffersAllocateNothing() {
        // A disabled test is recorded as skipped, and the feature map rejects a skipped suite.
        // The allocation check still runs only when it is asked for.
        guard ProcessInfo.processInfo.environment["ZEUS_ALLOC_CHECK"] == "1" else { return }
        let frames = 512
        let rate = 48000.0
        let kernel = EqualiserKernel(maxChannels: 2, maxFrames: frames, bandCount: 10)
        let loud = parameters(Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, 9.0) }), volume: 0.7)
        let quiet = parameters([2: -5, 6: 4], volume: 1)
        var buffer = sine(300, amplitude: 1, frames: frames, sampleRate: rate)
        buffer += buffer
        buffer.withUnsafeMutableBufferPointer { pointer in
            let base = pointer.baseAddress!
            for _ in 0..<40 {
                kernel.process(base, frames: frames, channels: 2, interleaved: false, sampleRate: rate)
            }
            let before = Self.blocksInUse()
            for index in 0..<1000 {
                if index % 100 == 0 { kernel.mailbox.post(index % 200 == 0 ? loud : quiet) }
                if index == 500 { base[10] = .nan }
                kernel.process(base, frames: frames, channels: 2, interleaved: index % 2 == 0, sampleRate: rate)
            }
            let after = Self.blocksInUse()
            #expect(after == before)
        }
    }
}
