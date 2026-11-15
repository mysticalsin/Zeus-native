import Darwin
import os

// The filter maths behind the per-app equaliser. Pure and `Sendable`: nothing here opens audio, touches the store or
// uses Swift concurrency. The render callback calls `EqualiserKernel.process`, which allocates nothing, takes no lock
// but the mailbox try-lock and uses no Foundation. Everything is sized once, in `init`.

// MARK: - Coefficients

/// One second-order section, every term already divided by `a0`.
public struct BiquadCoefficients: Sendable, Equatable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    /// Passes the signal through untouched.
    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    var isFinite: Bool { b0.isFinite && b1.isFinite && b2.isFinite && a1.isFinite && a2.isFinite }
}

public enum BiquadDesign {
    /// Filters whose centre sits at or above this share of the sample rate are skipped: the shape bends too far.
    public static let nyquistGuard = 0.45

    /// The peaking and shelving sections of the published audio-filter cookbook, with `A = 10^(dB / 40)`,
    /// `w0 = 2 pi f / fs` and `alpha = sin(w0) / (2 Q)`. Identity for a gain of 0, a centre at or above 0.45 of the
    /// sample rate, or any input that is not a finite, positive number where one is needed.
    public static func coefficients(
        kind: BiquadKind,
        frequency: Double,
        gainDB: Double,
        q: Double,
        sampleRate: Double
    ) -> BiquadCoefficients {
        guard gainDB.isFinite, gainDB != 0, frequency.isFinite, frequency > 0, q.isFinite, q > 0,
              sampleRate.isFinite, sampleRate > 0, frequency < nyquistGuard * sampleRate
        else { return .identity }

        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let root = 2 * a.squareRoot() * alpha

        let b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double
        switch kind {
        case .peaking:
            b0 = 1 + alpha * a
            b1 = -2 * cosW
            b2 = 1 - alpha * a
            a0 = 1 + alpha / a
            a1 = -2 * cosW
            a2 = 1 - alpha / a
        case .lowShelf:
            b0 = a * ((a + 1) - (a - 1) * cosW + root)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
            b2 = a * ((a + 1) - (a - 1) * cosW - root)
            a0 = (a + 1) + (a - 1) * cosW + root
            a1 = -2 * ((a - 1) + (a + 1) * cosW)
            a2 = (a + 1) + (a - 1) * cosW - root
        case .highShelf:
            b0 = a * ((a + 1) + (a - 1) * cosW + root)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
            b2 = a * ((a + 1) + (a - 1) * cosW - root)
            a0 = (a + 1) - (a - 1) * cosW + root
            a1 = 2 * ((a - 1) - (a + 1) * cosW)
            a2 = (a + 1) - (a - 1) * cosW - root
        }
        guard a0.isFinite, a0 != 0 else { return .identity }
        let result = BiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
        return result.isFinite ? result : .identity
    }

    /// The section's response in decibels at one frequency. 0 for a frequency or rate that is not usable.
    public static func magnitudeDB(_ c: BiquadCoefficients, frequency: Double, sampleRate: Double) -> Double {
        guard frequency.isFinite, frequency > 0, sampleRate.isFinite, sampleRate > 0, c.isFinite else { return 0 }
        let w = 2 * Double.pi * frequency / sampleRate
        let (c1, s1) = (cos(w), -sin(w))
        let (c2, s2) = (cos(2 * w), -sin(2 * w))
        let numRe = c.b0 + c.b1 * c1 + c.b2 * c2
        let numIm = c.b1 * s1 + c.b2 * s2
        let denRe = 1 + c.a1 * c1 + c.a2 * c2
        let denIm = c.a1 * s1 + c.a2 * s2
        let num = numRe * numRe + numIm * numIm
        let den = denRe * denRe + denIm * denIm
        guard num > 0, den > 0 else { return 0 }
        let db = 10 * log10(num / den)
        return db.isFinite ? db : 0
    }
}

// MARK: - Band layout

/// Where the ten octave bands sit and how wide each is: a low shelf at the bottom, a high shelf at the top, peaking
/// between. The shelves use Q 0.71 and the peaks Q 1.41.
public enum EqualiserBandLayout {
    /// ISO 266 octave centres, in hertz.
    public static let tenBandFrequencies: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let shelfQ = 0.71
    public static let peakQ = 1.41

    public static func frequency(at index: Int, count: Int) -> Double {
        if count == tenBandFrequencies.count, tenBandFrequencies.indices.contains(index) {
            return tenBandFrequencies[index]
        }
        guard count > 1 else { return 1000 }
        let low = tenBandFrequencies[0]
        let high = tenBandFrequencies[tenBandFrequencies.count - 1]
        return low * pow(high / low, Double(index) / Double(count - 1))
    }

    public static func kind(at index: Int, count: Int) -> BiquadKind {
        if count > 1, index == 0 { return .lowShelf }
        if count > 1, index == count - 1 { return .highShelf }
        return .peaking
    }

    public static func q(for kind: BiquadKind) -> Double {
        kind == .peaking ? peakQ : shelfQ
    }
}

// MARK: - Cascade

/// Second-order sections in series, one set of memory per channel, in transposed direct form II. The state is
/// allocated once. A section with identity coefficients is skipped, so a flat equaliser costs nothing. The cascade has
/// no gain staging of its own.
public final class BiquadCascade: @unchecked Sendable {
    public let channels: Int
    public let stages: Int

    private let coefficients: UnsafeMutablePointer<BiquadCoefficients>
    /// Indices of the sections that are not identity, in order.
    private let activeStages: UnsafeMutablePointer<Int>
    private var activeCount = 0
    /// Two memory cells per channel and section.
    private let memory: UnsafeMutablePointer<Double>

    public init(channels: Int, stages: Int) {
        self.channels = max(1, channels)
        self.stages = max(1, stages)
        coefficients = UnsafeMutablePointer<BiquadCoefficients>.allocate(capacity: self.stages)
        coefficients.initialize(repeating: .identity, count: self.stages)
        activeStages = UnsafeMutablePointer<Int>.allocate(capacity: self.stages)
        activeStages.initialize(repeating: 0, count: self.stages)
        let cells = self.channels * self.stages * 2
        memory = UnsafeMutablePointer<Double>.allocate(capacity: cells)
        memory.initialize(repeating: 0, count: cells)
    }

    deinit {
        coefficients.deallocate()
        activeStages.deallocate()
        memory.deallocate()
    }

    /// Sets one section for every channel. Keeps the memory of a section that stays active; clears it when the section
    /// becomes identity, so a later return starts clean.
    public func setCoefficients(_ value: BiquadCoefficients, stage: Int) {
        guard stage >= 0, stage < stages else { return }
        coefficients[stage] = value
        if value == .identity {
            for channel in 0..<channels {
                let base = (channel * stages + stage) * 2
                memory[base] = 0
                memory[base + 1] = 0
            }
        }
        var count = 0
        for index in 0..<stages where coefficients[index] != .identity {
            activeStages[count] = index
            count += 1
        }
        activeCount = count
    }

    /// Filters `count` samples of one channel in place. `stride` is the distance between its samples: 1 for a planar
    /// buffer, the channel count for an interleaved one.
    public func process(channel: Int, samples: UnsafeMutablePointer<Float>, count: Int, stride: Int) {
        guard channel >= 0, channel < channels, count > 0, stride > 0, activeCount > 0 else { return }
        let channelBase = channel * stages * 2
        for index in 0..<count {
            let slot = index * stride
            var x = Double(samples[slot])
            for k in 0..<activeCount {
                let stage = activeStages[k]
                let c = coefficients[stage]
                let cell = memory + channelBase + stage * 2
                let y = c.b0 * x + cell[0]
                cell[0] = c.b1 * x - c.a1 * y + cell[1]
                cell[1] = c.b2 * x - c.a2 * y
                x = y
            }
            samples[slot] = Float(x)
        }
    }

    /// Clears the memory of every section and channel. The coefficients stay.
    public func reset() {
        memory.update(repeating: 0, count: channels * stages * 2)
    }
}

// MARK: - Gain staging, smoothing

public enum GainStaging {
    /// Minus the largest positive band gain, so the loudest boost cannot push the signal past where it began. 0 when
    /// no band boosts.
    public static func preampDB(bandGainsDB: [Double]) -> Double {
        bandGainsDB.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            return preampDB(gains: base, count: buffer.count)
        }
    }

    static func preampDB(gains: UnsafePointer<Double>, count: Int) -> Double {
        var largest = 0.0
        for index in 0..<count where gains[index] > largest { largest = gains[index] }
        return 0 - largest
    }

    /// The linear gain for a volume from 0 to 1: its square, exactly 0 at 0 and exactly 1 at 1. A volume that is not a
    /// number counts as unchanged.
    public static func linear(volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        let clamped = min(1, max(0, volume))
        return clamped * clamped
    }
}

public enum ParameterSmoothing {
    /// Moves `current` toward `target` by at most `maxStep`, landing exactly on the target when it is that close.
    public static func step(current: Double, target: Double, maxStep: Double) -> Double {
        guard target.isFinite else { return current }
        guard current.isFinite else { return target }
        guard maxStep > 0 else { return current }
        let delta = target - current
        if abs(delta) <= maxStep { return target }
        return current + (delta > 0 ? maxStep : -maxStep)
    }
}

// MARK: - Limiter

/// Catches what the preamp leaves. A gain that drops at once when a sample would pass the threshold (one decibel
/// below full scale) and recovers over about 50 ms. One gain serves every channel, so the stereo image holds. The
/// output is finite and never larger than 1.
public struct SoftLimiter: Sendable {
    public static let releaseSeconds = 0.05

    public let threshold: Double = pow(10, -1.0 / 20)
    public private(set) var sampleRate: Double
    private var gain = 1.0
    private var releaseStep: Double

    public init(sampleRate: Double) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48000
        self.sampleRate = rate
        releaseStep = 1 - exp(-1 / (Self.releaseSeconds * rate))
    }

    public mutating func setSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0, rate != sampleRate else { return }
        sampleRate = rate
        releaseStep = 1 - exp(-1 / (Self.releaseSeconds * rate))
    }

    public mutating func reset() { gain = 1 }

    /// The gain for one frame whose largest absolute sample is `peak`. A finite, non-negative peak is expected.
    public mutating func gain(forPeak peak: Double) -> Double {
        let needed = peak > threshold ? threshold / peak : 1
        if needed < gain {
            gain = needed
        } else {
            gain += (needed - gain) * releaseStep
        }
        return gain
    }

    /// One mono sample. Anything that is not finite becomes silence and leaves the state alone.
    public mutating func process(_ sample: Double) -> Double {
        guard sample.isFinite else { return 0 }
        let out = sample * gain(forPeak: abs(sample))
        return min(1, max(-1, out))
    }
}

// MARK: - Mailbox

/// What the render callback reads: band gains in a fixed block, so a copy allocates nothing.
public struct EqualiserTarget: Sendable, Equatable {
    /// The most bands the kernel can carry.
    public static let maxBands = 16
    /// The limits of a band gain in decibels.
    public static let gainLimitDB = 12.0

    public var gains: SIMD16<Double>
    /// 0 to 1.
    public var volume: Double
    public var bypass: Bool

    public init(gains: SIMD16<Double> = SIMD16<Double>(repeating: 0), volume: Double = 1, bypass: Bool = false) {
        self.gains = gains
        self.volume = volume
        self.bypass = bypass
    }

    /// The parameters with every gain clamped to plus or minus 12 dB (a gain that is not a number becomes 0), the
    /// volume clamped to 0...1 (not a number becomes 1), missing bands flat and extra bands dropped.
    init(sanitising parameters: EqualiserParameters) {
        var block = SIMD16<Double>(repeating: 0)
        for index in 0..<min(Self.maxBands, parameters.gainsDB.count) {
            let gain = parameters.gainsDB[index]
            block[index] = gain.isFinite ? min(Self.gainLimitDB, max(-Self.gainLimitDB, gain)) : 0
        }
        let volume = parameters.volume.isFinite ? min(1, max(0, parameters.volume)) : 1
        self.init(gains: block, volume: volume, bypass: parameters.bypass)
    }
}

/// Hands the latest parameters from the main thread to the render callback. The lock is a pointer allocated in `init`,
/// as in `ScribeSampleRing`, because a stored lock can move. The main thread waits for the lock; the render never
/// does: when the lock is busy it keeps its last values and tries again next buffer.
public final class EqualiserMailbox: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let slot: UnsafeMutablePointer<EqualiserTarget>

    public init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        slot = UnsafeMutablePointer<EqualiserTarget>.allocate(capacity: 1)
        slot.initialize(to: EqualiserTarget())
    }

    deinit {
        slot.deinitialize(count: 1)
        slot.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Main thread. Clamps the parameters and replaces the pending values.
    public func post(_ parameters: EqualiserParameters) {
        let value = EqualiserTarget(sanitising: parameters)
        os_unfair_lock_lock(lock)
        slot.pointee = value
        os_unfair_lock_unlock(lock)
    }

    /// Render thread. Copies the pending values into `target` and returns true, or returns false at once when the lock
    /// is busy and leaves `target` as it was.
    public func take(into target: inout EqualiserTarget) -> Bool {
        guard os_unfair_lock_trylock(lock) else { return false }
        target = slot.pointee
        os_unfair_lock_unlock(lock)
        return true
    }

    /// Holds the lock while `body` runs, so a test can see what the render does when the mailbox is busy.
    func withLockHeldForTesting<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body()
    }
}

// MARK: - Scratch

/// Owns the sample memory a render block works in, so the `@Sendable` block captures one class and not raw pointers,
/// which Swift 6 rejects. Zeroed, never resized.
public final class RenderScratch: @unchecked Sendable {
    public let maxChannels: Int
    public let maxFrames: Int
    public let samples: UnsafeMutablePointer<Float>

    public init(maxChannels: Int, maxFrames: Int) {
        self.maxChannels = max(1, maxChannels)
        self.maxFrames = max(1, maxFrames)
        let total = self.maxChannels * self.maxFrames
        samples = UnsafeMutablePointer<Float>.allocate(capacity: total)
        samples.initialize(repeating: 0, count: total)
    }

    deinit { samples.deallocate() }
}

// MARK: - Kernel

/// The whole signal path for one tap: take the latest parameters, glide the band gains, design the sections that moved,
/// run the cascade, apply the preamp and the volume, limit. Works in place on Float samples.
///
/// A buffer is either interleaved (frame after frame, channels side by side) or planar (channel after channel, each
/// `frames` long). A callback longer than `maxFrames` runs in chunks, each a buffer for the glide. Channels beyond
/// `maxChannels` are silenced. A non-finite sample anywhere in a chunk silences that chunk and clears the filter and
/// limiter memory.
///
/// The render thread owns every method here except `mailbox.post`. `reset()` is for the build, before the device starts.
public final class EqualiserKernel: @unchecked Sendable {
    /// The most a band gain moves in one buffer.
    public static let maxGainStepDB = 1.5
    /// How long the volume takes to travel its whole range.
    public static let volumeRampSeconds = 0.02

    public let mailbox = EqualiserMailbox()
    public let maxChannels: Int
    public let maxFrames: Int
    public let bandCount: Int

    private let cascade: BiquadCascade
    private let frequencies: UnsafeMutablePointer<Double>
    private let kinds: UnsafeMutablePointer<BiquadKind>
    private let qualities: UnsafeMutablePointer<Double>
    private let smoothed: UnsafeMutablePointer<Double>
    private let designed: UnsafeMutablePointer<Double>

    private var target = EqualiserTarget()
    private var designedRate = 0.0
    private var limiter = SoftLimiter(sampleRate: 48000)
    private var preampLinear = 1.0
    private var volumeLinear = 1.0
    private(set) var designCount = 0

    public init(maxChannels: Int, maxFrames: Int, bandCount: Int) {
        self.maxChannels = max(1, maxChannels)
        self.maxFrames = max(1, maxFrames)
        let bands = min(EqualiserTarget.maxBands, max(1, bandCount))
        self.bandCount = bands
        cascade = BiquadCascade(channels: self.maxChannels, stages: bands)
        frequencies = UnsafeMutablePointer<Double>.allocate(capacity: bands)
        kinds = UnsafeMutablePointer<BiquadKind>.allocate(capacity: bands)
        qualities = UnsafeMutablePointer<Double>.allocate(capacity: bands)
        smoothed = UnsafeMutablePointer<Double>.allocate(capacity: bands)
        designed = UnsafeMutablePointer<Double>.allocate(capacity: bands)
        for band in 0..<bands {
            let kind = EqualiserBandLayout.kind(at: band, count: bands)
            (frequencies + band).initialize(to: EqualiserBandLayout.frequency(at: band, count: bands))
            (kinds + band).initialize(to: kind)
            (qualities + band).initialize(to: EqualiserBandLayout.q(for: kind))
        }
        smoothed.initialize(repeating: 0, count: bands)
        designed.initialize(repeating: 0, count: bands)
    }

    deinit {
        frequencies.deallocate()
        kinds.deallocate()
        qualities.deallocate()
        smoothed.deallocate()
        designed.deallocate()
    }

    /// The band gain the kernel is using now, after smoothing.
    public func smoothedGainDB(band: Int) -> Double {
        band >= 0 && band < bandCount ? smoothed[band] : 0
    }

    /// The preamp in use now, in decibels, worked out from the smoothed gains.
    public var preampDB: Double {
        GainStaging.preampDB(gains: smoothed, count: bandCount)
    }

    /// The linear volume gain in use now, after its ramp.
    public var volumeGain: Double { volumeLinear }

    /// Back to a fresh start: flat, unity volume, empty filter memory. Not for the render thread.
    public func reset() {
        smoothed.update(repeating: 0, count: bandCount)
        designed.update(repeating: 0, count: bandCount)
        designedRate = 0
        preampLinear = 1
        volumeLinear = 1
        target = EqualiserTarget()
        clearFilterState()
    }

    private func clearFilterState() {
        cascade.reset()
        limiter.reset()
    }

    public func process(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        channels: Int,
        interleaved: Bool,
        sampleRate: Double
    ) {
        guard frames > 0, channels > 0 else { return }
        let live = min(channels, maxChannels)
        guard sampleRate.isFinite, sampleRate > 0 else {
            silence(samples, from: 0, chunk: frames, frames: frames, channels: channels, interleaved: interleaved)
            return
        }
        if live < channels {
            for channel in live..<channels {
                for frame in 0..<frames {
                    samples[interleaved ? frame * channels + channel : channel * frames + frame] = 0
                }
            }
        }
        var offset = 0
        while offset < frames {
            let chunk = min(maxFrames, frames - offset)
            processChunk(
                samples, offset: offset, chunk: chunk, frames: frames, channels: channels, live: live,
                interleaved: interleaved, sampleRate: sampleRate
            )
            offset += chunk
        }
    }

    private func silence(
        _ samples: UnsafeMutablePointer<Float>, from offset: Int, chunk: Int, frames: Int, channels: Int, interleaved: Bool
    ) {
        for channel in 0..<channels {
            for frame in offset..<(offset + chunk) {
                samples[interleaved ? frame * channels + channel : channel * frames + frame] = 0
            }
        }
    }

    private func processChunk(
        _ samples: UnsafeMutablePointer<Float>,
        offset: Int,
        chunk: Int,
        frames: Int,
        channels: Int,
        live: Int,
        interleaved: Bool,
        sampleRate: Double
    ) {
        // 1. Newest values, or the last ones when the mailbox is busy.
        _ = mailbox.take(into: &target)

        // 2. Glide the gains and design only the sections that moved (or all, when the rate changed).
        let rateChanged = sampleRate != designedRate
        if rateChanged {
            designedRate = sampleRate
            limiter.setSampleRate(sampleRate)
        }
        for band in 0..<bandCount {
            let goal = target.bypass ? 0 : target.gains[band]
            let gain = ParameterSmoothing.step(current: smoothed[band], target: goal, maxStep: Self.maxGainStepDB)
            smoothed[band] = gain
            guard gain != designed[band] || rateChanged else { continue }
            designed[band] = gain
            if gain == 0 {
                cascade.setCoefficients(.identity, stage: band)
            } else {
                designCount += 1
                cascade.setCoefficients(
                    BiquadDesign.coefficients(
                        kind: kinds[band], frequency: frequencies[band], gainDB: gain, q: qualities[band],
                        sampleRate: sampleRate
                    ),
                    stage: band
                )
            }
        }

        // 3. Filter in place, then look for anything that is not a number.
        var clean = true
        for channel in 0..<live {
            let start = interleaved ? samples + offset * channels + channel : samples + channel * frames + offset
            let stride = interleaved ? channels : 1
            cascade.process(channel: channel, samples: start, count: chunk, stride: stride)
            for index in 0..<chunk where !start[index * stride].isFinite { clean = false }
        }
        guard clean else {
            silence(samples, from: offset, chunk: chunk, frames: frames, channels: live, interleaved: interleaved)
            clearFilterState()
            preampLinear = pow(10, GainStaging.preampDB(gains: smoothed, count: bandCount) / 20)
            return
        }

        // 4. Preamp from the smoothed gains and the volume, each ramped inside the buffer, then the limiter.
        let preampTarget = pow(10, GainStaging.preampDB(gains: smoothed, count: bandCount) / 20)
        let preampStart = preampLinear
        let preampSlope = (preampTarget - preampStart) / Double(chunk)
        let volumeTarget = GainStaging.linear(volume: target.volume)
        let volumeStep = 1 / (Self.volumeRampSeconds * sampleRate)
        var volume = volumeLinear
        for frame in 0..<chunk {
            let preamp = preampStart + preampSlope * Double(frame + 1)
            if volume < volumeTarget {
                volume = min(volumeTarget, volume + volumeStep)
            } else if volume > volumeTarget {
                volume = max(volumeTarget, volume - volumeStep)
            }
            let scale = preamp * volume
            var peak = 0.0
            for channel in 0..<live {
                let slot = interleaved ? (offset + frame) * channels + channel : channel * frames + offset + frame
                peak = max(peak, abs(Double(samples[slot]) * scale))
            }
            let limit = limiter.gain(forPeak: peak) * scale
            for channel in 0..<live {
                let slot = interleaved ? (offset + frame) * channels + channel : channel * frames + offset + frame
                samples[slot] = Float(min(1, max(-1, Double(samples[slot]) * limit)))
            }
        }
        preampLinear = preampTarget
        volumeLinear = volume
    }
}
