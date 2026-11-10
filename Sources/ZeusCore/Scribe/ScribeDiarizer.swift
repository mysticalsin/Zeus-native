import Accelerate
import Foundation

// On-device speaker labelling for live Scribe. A voiceprint is a small hand-built feature vector (spectral shape of
// the voiced frames plus median pitch), not a trained model: it separates clearly different voices (a low and a
// high one, a dark and a bright one) and is weaker on similar ones. Nothing here leaves the process, and no audio
// is kept: a voiceprint cannot be turned back into speech.

// MARK: - Voiceprint

/// What one chunk of speech sounds like: 20 mel-band shape values and an 11-value pitch block, weighted and
/// L2-normalised together. Compare two with `distance(to:)`.
public struct ScribeVoiceprint: Equatable, Sendable {
    public let vector: [Float]

    static let bandCount = 20
    static let pitchCount = 11
    /// How much each block counts toward the distance; they sum to 1.
    static let spectralWeight: Float = 0.5
    static let pitchWeight: Float = 0.5
    /// Less voiced audio than this is not enough to describe a voice.
    static let minimumVoicedSeconds = 0.8

    private static let fftSize = 512
    private static let spectralFrameCap = 400
    private static let pitchFrameCount = 8
    private static let pitchLowHz = 70.0
    private static let pitchHighHz = 400.0
    /// Spacing and width (octaves) of the pitch block's overlapping bumps.
    private static let pitchSpacing = 0.25
    private static let pitchWidth = 0.25
    /// A flat tilt (natural-log power, band 0 minus the last band) removed so that what is left is how a voice
    /// differs from a typical one, not the shape every voice shares.
    private static let typicalTilt: Float = 8

    init(vector: [Float]) {
        self.vector = vector
    }

    /// Builds a voiceprint from block values. Each block is scaled to unit length first, so the means of many
    /// voiceprints can be recombined. `pitch == nil` leaves the pitch block empty.
    init(spectral: [Float], pitch: [Float]?) {
        var combined = Self.unit(spectral).map { $0 * Self.spectralWeight.squareRoot() }
        if let pitch {
            combined += Self.unit(pitch).map { $0 * Self.pitchWeight.squareRoot() }
        } else {
            combined += [Float](repeating: 0, count: Self.pitchCount)
        }
        self.vector = Self.unit(combined)
    }

    var spectralBlock: [Float] { Array(vector.prefix(Self.bandCount)) }

    /// Nil when the chunk had no usable pitch.
    var pitchBlock: [Float]? {
        guard vector.count == Self.bandCount + Self.pitchCount else { return nil }
        let block = Array(vector[Self.bandCount...])
        return Self.norm(block) > 1e-6 ? block : nil
    }

    /// 0 for the same voice up to 1 and beyond for opposite ones. Spectral shape and pitch each contribute their
    /// cosine distance; when either side has no pitch, shape alone decides.
    public func distance(to other: ScribeVoiceprint) -> Float {
        let total = Self.bandCount + Self.pitchCount
        guard vector.count == total, other.vector.count == total else { return 1 }
        let spectral = Self.cosine(vector, other.vector, 0..<Self.bandCount) ?? 0
        var similarity = spectral
        if let pitch = Self.cosine(vector, other.vector, Self.bandCount..<total) {
            similarity = Self.spectralWeight * spectral + Self.pitchWeight * pitch
        }
        return max(0, 1 - similarity)
    }

    /// Nil when under ~0.8 s of voiced audio (digital silence, a quiet room, a very short chunk).
    public static func make(samples: [Float], sampleRate: Int = ScribePCM.sampleRate) -> ScribeVoiceprint? {
        guard sampleRate >= 8_000, sampleRate <= 20_000 else { return nil }
        let frameLength = sampleRate * 25 / 1000
        let hop = sampleRate * 10 / 1000
        guard samples.count >= frameLength + hop else { return nil }
        let frameCount = (samples.count - frameLength) / hop + 1

        // Voiced frames: clearly above the floor and not far below the chunk's loudest frame.
        var frameLevels = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            for frame in 0..<frameCount {
                var level: Float = 0
                vDSP_rmsqv(base + frame * hop, 1, &level, vDSP_Length(frameLength))
                frameLevels[frame] = level
            }
        }
        let gate = max(0.003, 0.15 * (frameLevels.max() ?? 0))
        let voiced = frameLevels.indices.filter { frameLevels[$0] >= gate }
        guard Double(voiced.count * hop) / Double(sampleRate) >= minimumVoicedSeconds else { return nil }

        guard let spectral = spectralShape(samples: samples, voiced: voiced, frameLength: frameLength, hop: hop, sampleRate: sampleRate)
        else { return nil }
        let pitch = pitchFeatures(samples: samples, voiced: voiced, frameLength: frameLength, hop: hop, sampleRate: sampleRate)
        return ScribeVoiceprint(spectral: spectral, pitch: pitch)
    }

    // MARK: Spectral shape

    /// Mean natural-log mel energy of the voiced frames per band, centred across bands (so loudness drops out)
    /// with the typical tilt removed.
    private static func spectralShape(
        samples: [Float], voiced: [Int], frameLength: Int, hop: Int, sampleRate: Int
    ) -> [Float]? {
        let log2n = vDSP_Length(9)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }
        let half = fftSize / 2
        let bank = MelBank(
            bands: bandCount, sampleRate: sampleRate, fftSize: fftSize,
            lowHz: 120, highHz: min(7_000, Double(sampleRate) * 0.44)
        )
        let span = Double(max(1, frameLength - 1))
        var window = [Float](repeating: 0, count: frameLength)
        for index in 0..<frameLength {
            let phase: Double = 2 * Double.pi * Double(index) / span
            window[index] = Float(0.5 - 0.5 * cos(phase))
        }
        let step = max(1, voiced.count / spectralFrameCap)
        let chosen = voiced.enumerated().filter { $0.offset % step == 0 }.map(\.element)
        guard !chosen.isEmpty else { return nil }

        var windowed = [Float](repeating: 0, count: fftSize)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        var sums = [Double](repeating: 0, count: bandCount)
        for frame in chosen {
            let start = frame * hop
            for index in 0..<frameLength { windowed[index] = samples[start + index] * window[index] }
            real.withUnsafeMutableBufferPointer { realBuffer in
                imag.withUnsafeMutableBufferPointer { imagBuffer in
                    var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                    windowed.withUnsafeBufferPointer { input in
                        input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    power.withUnsafeMutableBufferPointer { output in
                        vDSP_zvmags(&split, 1, output.baseAddress!, 1, vDSP_Length(half))
                    }
                }
            }
            // Bin 0 holds DC and Nyquist packed together; neither says anything about a voice.
            power[0] = 0
            for band in 0..<bandCount {
                var energy: Float = 0
                let first = bank.starts[band]
                for (offset, weight) in bank.weights[band].enumerated() { energy += weight * power[first + offset] }
                sums[band] += Double(log(max(energy, 1e-10)))
            }
        }

        let means = sums.map { Float($0 / Double(chosen.count)) }
        let average = means.reduce(0, +) / Float(bandCount)
        return means.indices.map { band -> Float in
            let tilt = typicalTilt * (0.5 - Float(band) / Float(bandCount - 1))
            return means[band] - average - tilt
        }
    }

    // MARK: Pitch

    /// Median pitch of a few voiced frames as a block of overlapping bumps over log2(Hz): two pitches an octave
    /// apart barely overlap, one a few percent apart almost fully do. Nil when too few frames are pitched.
    private static func pitchFeatures(samples: [Float], voiced: [Int], frameLength: Int, hop: Int, sampleRate: Int) -> [Float]? {
        let windowLength = sampleRate * 64 / 1000
        guard samples.count >= windowLength, !voiced.isEmpty else { return nil }
        let picks = min(pitchFrameCount, voiced.count)
        var found: [Float] = []
        for pick in 0..<picks {
            let frame = voiced[picks == 1 ? 0 : pick * (voiced.count - 1) / (picks - 1)]
            let center = frame * hop + frameLength / 2
            let begin = min(max(0, center - windowLength / 2), samples.count - windowLength)
            if let hz = estimatePitch(Array(samples[begin..<(begin + windowLength)]), sampleRate: sampleRate) {
                found.append(hz)
            }
        }
        guard found.count >= 2 else { return nil }
        found.sort()
        let median = Double(found[found.count / 2])
        let position = log2(median)
        let origin = log2(pitchLowHz)
        return (0..<pitchCount).map { index -> Float in
            let distance = position - (origin + Double(index) * pitchSpacing)
            return Float(exp(-distance * distance / (2 * pitchWidth * pitchWidth)))
        }
    }

    /// Normalised autocorrelation over the lags of 70...400 Hz. Takes the shortest lag that is nearly as strong
    /// as the strongest (so a voice is not read an octave low), refined by a parabola through its neighbours.
    private static func estimatePitch(_ window: [Float], sampleRate: Int) -> Float? {
        let count = window.count
        let minLag = sampleRate / Int(pitchHighHz)
        let maxLag = min(sampleRate / Int(pitchLowHz), count / 2)
        guard minLag >= 2, maxLag > minLag + 2 else { return nil }
        let mean = window.reduce(0, +) / Float(count)
        let x = window.map { $0 - mean }
        var energy = [Float](repeating: 0, count: count + 1)
        for index in 0..<count { energy[index + 1] = energy[index] + x[index] * x[index] }
        guard energy[count] > 1e-9 else { return nil }

        var correlation = [Float](repeating: 0, count: maxLag + 2)
        x.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            for lag in (minLag - 1)...(maxLag + 1) {
                var dot: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &dot, vDSP_Length(count - lag))
                let head = energy[count - lag]
                let tail = energy[count] - energy[lag]
                correlation[lag] = dot / ((head * tail).squareRoot() + 1e-12)
            }
        }
        var best: Float = 0
        for lag in minLag...maxLag { best = max(best, correlation[lag]) }
        guard best >= 0.35 else { return nil }
        for lag in minLag...maxLag
        where correlation[lag] >= 0.9 * best && correlation[lag] >= correlation[lag - 1] && correlation[lag] >= correlation[lag + 1] {
            let before = correlation[lag - 1]
            let here = correlation[lag]
            let after = correlation[lag + 1]
            let denominator = before - 2 * here + after
            let shift = denominator == 0 ? 0 : min(0.5, max(-0.5, 0.5 * (before - after) / denominator))
            return Float(sampleRate) / (Float(lag) + shift)
        }
        return nil
    }

    // MARK: Vector math

    private static func norm(_ values: [Float]) -> Float {
        var sum: Float = 0
        for value in values { sum += value * value }
        return sum.squareRoot()
    }

    private static func unit(_ values: [Float]) -> [Float] {
        let length = norm(values)
        guard length > 1e-9 else { return [Float](repeating: 0, count: values.count) }
        return values.map { $0 / length }
    }

    /// Nil when either block is empty (zero length), which is how a missing pitch shows.
    private static func cosine(_ a: [Float], _ b: [Float], _ range: Range<Int>) -> Float? {
        var dot: Float = 0
        var lengthA: Float = 0
        var lengthB: Float = 0
        for index in range {
            dot += a[index] * b[index]
            lengthA += a[index] * a[index]
            lengthB += b[index] * b[index]
        }
        guard lengthA > 1e-12, lengthB > 1e-12 else { return nil }
        return dot / (lengthA.squareRoot() * lengthB.squareRoot())
    }
}

/// Triangular mel filters over the positive FFT bins (bin 0 and the Nyquist bin excluded).
private struct MelBank {
    let starts: [Int]
    let weights: [[Float]]

    init(bands: Int, sampleRate: Int, fftSize: Int, lowHz: Double, highHz: Double) {
        func toMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func toHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
        let lowMel = toMel(lowHz)
        let highMel = toMel(highHz)
        let edges = (0...(bands + 1)).map { toHz(lowMel + (highMel - lowMel) * Double($0) / Double(bands + 1)) }
        let binHz = Double(sampleRate) / Double(fftSize)
        let maxBin = fftSize / 2 - 1
        var starts: [Int] = []
        var weights: [[Float]] = []
        for band in 0..<bands {
            let left = edges[band]
            let center = edges[band + 1]
            let right = edges[band + 2]
            let first = max(1, Int((left / binHz).rounded(.up)))
            let last = min(maxBin, Int((right / binHz).rounded(.down)))
            var row: [Float] = []
            if first <= last {
                for bin in first...last {
                    let hz = Double(bin) * binHz
                    let value = hz <= center ? (hz - left) / (center - left) : (right - hz) / (right - center)
                    row.append(Float(max(0, value)))
                }
            }
            if row.allSatisfy({ $0 == 0 }) {
                // A filter narrower than one bin takes the nearest bin whole.
                starts.append(min(maxBin, max(1, Int((center / binHz).rounded()))))
                weights.append([1])
            } else {
                starts.append(first)
                weights.append(row)
            }
        }
        self.starts = starts
        self.weights = weights
    }
}

// MARK: - Diarizer

/// Online speaker clustering for one meeting. Each chunk's voiceprint joins the nearest cluster of its own source
/// when it is within `threshold`, otherwise it starts a new one; a cluster's centroid is the running mean of its
/// members. The first microphone cluster is the person at the keyboard (`.you`). Every other cluster, a second
/// voice on the microphone or any voice in the system audio, is `.participant("Speaker N")`, numbered in order of
/// first appearance across both sources. A microphone voice and a system voice are never merged: they come
/// through different channels, and the microphone is only ever admitted for the user and the room.
public struct ScribeDiarizer: Sendable {
    /// Voiceprint distance up to which a chunk is the same voice (0 identical, about 0.5 for a low and a high
    /// voice). See the tests for the synthetic cases it separates; real voices are unverified.
    public static let defaultThreshold: Float = 0.22

    public let threshold: Float
    public let maxSpeakers: Int
    /// Clusters so far, across both sources.
    public private(set) var speakerCount = 0

    private struct Cluster: Sendable {
        let source: ScribeAudioSource
        let speaker: ScribeSpeaker
        var spectral: [Float]
        var pitch: [Float]
        var count = 1
        var pitchCount: Int

        init(source: ScribeAudioSource, speaker: ScribeSpeaker, print: ScribeVoiceprint) {
            self.source = source
            self.speaker = speaker
            self.spectral = print.spectralBlock
            if let block = print.pitchBlock {
                self.pitch = block
                self.pitchCount = 1
            } else {
                self.pitch = [Float](repeating: 0, count: ScribeVoiceprint.pitchCount)
                self.pitchCount = 0
            }
        }

        var voiceprint: ScribeVoiceprint {
            ScribeVoiceprint(spectral: spectral, pitch: pitchCount > 0 ? pitch : nil)
        }

        /// Running mean; the pitch block only averages the members that had a pitch.
        mutating func absorb(_ print: ScribeVoiceprint) {
            count += 1
            let spectralBlock = print.spectralBlock
            for index in spectral.indices { spectral[index] += (spectralBlock[index] - spectral[index]) / Float(count) }
            if let block = print.pitchBlock {
                pitchCount += 1
                for index in pitch.indices { pitch[index] += (block[index] - pitch[index]) / Float(pitchCount) }
            }
        }
    }

    private var clusters: [Cluster] = []
    private var nextParticipant = 1
    private var lastMicrophone: ScribeSpeaker = .you
    private var lastSystem: ScribeSpeaker = .participant("Speaker 1")

    public init(threshold: Float = ScribeDiarizer.defaultThreshold, maxSpeakers: Int = 8) {
        self.threshold = threshold
        self.maxSpeakers = max(1, maxSpeakers)
    }

    /// Who spoke this chunk. A chunk with no usable voiceprint (silent, too short, or too little voiced audio)
    /// continues that source's previous speaker: `.you` on the microphone, "Speaker 1" on system audio until
    /// someone has been heard. Once `maxSpeakers` clusters exist a chunk joins the nearest cluster of its source
    /// whatever the distance; a source's first cluster is always allowed so the microphone can still be `.you`.
    public mutating func assign(source: ScribeAudioSource, samples: [Float]) -> ScribeSpeaker {
        guard let print = ScribeVoiceprint.make(samples: samples) else { return previous(for: source) }

        var nearest: (index: Int, distance: Float)?
        for (index, cluster) in clusters.enumerated() where cluster.source == source {
            let distance = cluster.voiceprint.distance(to: print)
            if nearest == nil || distance < nearest!.distance { nearest = (index, distance) }
        }
        if let nearest, nearest.distance <= threshold || speakerCount >= maxSpeakers {
            clusters[nearest.index].absorb(print)
            return remember(clusters[nearest.index].speaker, for: source)
        }

        let speaker: ScribeSpeaker
        if source == .microphone, !clusters.contains(where: { $0.source == .microphone }) {
            speaker = .you
        } else {
            speaker = .participant("Speaker \(nextParticipant)")
            nextParticipant += 1
        }
        clusters.append(Cluster(source: source, speaker: speaker, print: print))
        speakerCount = clusters.count
        return remember(speaker, for: source)
    }

    /// Who this audio sounds like, without learning from it: the nearest existing cluster of the source when it
    /// is within `threshold`, otherwise nil (no usable voiceprint, no clusters yet, or a voice not heard before).
    /// Never creates a cluster, moves a centroid or changes the remembered speaker, so a rolling preview of a
    /// turn can be classified again and again without skewing the finals.
    public func classify(source: ScribeAudioSource, samples: [Float]) -> ScribeSpeaker? {
        guard let print = ScribeVoiceprint.make(samples: samples) else { return nil }
        var nearest: (speaker: ScribeSpeaker, distance: Float)?
        for cluster in clusters where cluster.source == source {
            let distance = cluster.voiceprint.distance(to: print)
            if nearest == nil || distance < nearest!.distance { nearest = (cluster.speaker, distance) }
        }
        guard let nearest, nearest.distance <= threshold else { return nil }
        return nearest.speaker
    }

    /// Forget everyone (a new meeting).
    public mutating func reset() {
        clusters.removeAll()
        speakerCount = 0
        nextParticipant = 1
        lastMicrophone = .you
        lastSystem = .participant("Speaker 1")
    }

    private func previous(for source: ScribeAudioSource) -> ScribeSpeaker {
        source == .microphone ? lastMicrophone : lastSystem
    }

    private mutating func remember(_ speaker: ScribeSpeaker, for source: ScribeAudioSource) -> ScribeSpeaker {
        if source == .microphone { lastMicrophone = speaker } else { lastSystem = speaker }
        return speaker
    }
}
