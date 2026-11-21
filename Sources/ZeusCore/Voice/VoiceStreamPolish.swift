import Foundation

/// Speech output polish plugged into `SpeechOutputProcessing`.
///
/// `pipeline` is the only stage order. Each case is handled in `apply`; there is no default.
/// Clause chunking is text. Loudness is measured on each rendered buffer and smoothed across
/// the buffers of one utterance, then those buffers are joined with an equal-power crossfade.
/// A near-silence primer is prepended once per utterance, and the limiter runs after the join
/// so the overlap cannot exceed -1 dBTP.
///
/// `process` is what the PCM feeder calls. Those frames are already one continuous render, so
/// it normalizes, primes, and limits a frame and does not overlap-add it into the next frame.
/// `render` joins separately rendered clause buffers, which is where the crossfade runs.
public final class VoiceStreamPolish: SpeechOutputProcessing, @unchecked Sendable {
    public static let pipeline: [SpeechPolishStage] = [
        .clauseChunk, .loudness, .crossfade, .primer, .limiter,
    ]

    private let lock = NSLock()
    private var token: SpeechCancelToken?
    private var primerPending = true
    private var normalizer = LoudnessNormalizer()
    public private(set) var lastTextChunks: [String] = []

    public init() {}

    /// Binds the cancel token for the utterance and clears gain smoothing and the primer.
    public func begin(_ token: SpeechCancelToken) {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
        primerPending = true
        normalizer.reset()
        lastTextChunks = []
    }

    public func chunks(of text: String) -> [String] {
        SpeechClauseChunker.chunks(of: text)
    }

    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if token?.isCancelled == true { return [] }
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let slice: [Float]
        let stopping: Bool
        if let stop = token?.cancelAfterSamples {
            if stop <= 0 {
                token?.cancel()
                return []
            }
            if stop < samples.count {
                slice = Array(samples.prefix(stop))
                stopping = true
            } else {
                slice = samples
                stopping = false
            }
        } else {
            slice = samples
            stopping = false
        }
        var context = PolishContext(text: "", buffers: [slice], sampleRate: sampleRate, prime: primerPending)
        for stage in Self.pipeline {
            apply(stage, to: &context)
        }
        primerPending = false
        if stopping { token?.cancel() }
        return context.audio
    }

    /// Joins one rendered buffer per clause. A cancel already in force yields an empty buffer.
    public func render(text: String = "", buffers: [[Float]], sampleRate: Double) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if token?.isCancelled == true { return [] }
        guard sampleRate > 0 else { return [] }
        var context = PolishContext(text: text, buffers: buffers, sampleRate: sampleRate, prime: primerPending)
        for stage in Self.pipeline {
            apply(stage, to: &context)
        }
        primerPending = false
        return context.audio
    }

    /// Contiguous feeder frames are not held back, so there is no crossfade tail to flush.
    /// A cancelled utterance returns nothing here as well.
    public func finish() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if token?.isCancelled == true { return [] }
        return []
    }

    private func apply(_ stage: SpeechPolishStage, to context: inout PolishContext) {
        switch stage {
        case .clauseChunk:
            let pieces = SpeechClauseChunker.chunks(of: context.text)
            context.textChunks = pieces
            lastTextChunks = pieces
        case .loudness:
            let rate = context.sampleRate
            context.buffers = context.buffers.map { normalizer.normalize($0, sampleRate: rate) }
        case .crossfade:
            context.audio = EqualPowerCrossfade.joinAll(context.buffers, sampleRate: context.sampleRate)
        case .primer:
            if context.prime {
                context.audio = WarmupPrimer.apply(context.audio, sampleRate: context.sampleRate)
            }
        case .limiter:
            context.audio = TruePeakLimiter.limit(context.audio, sampleRate: context.sampleRate)
        }
    }
}

public enum SpeechPolishStage: String, CaseIterable, Sendable {
    case clauseChunk
    case loudness
    case crossfade
    case primer
    case limiter
}

/// Per-utterance cancel. `cancelAfterSamples` stops inside the buffer that is being rendered:
/// samples at and after that index are dropped, and nothing is faded out after the cut.
public final class SpeechCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var stopAfter: Int?

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// When set, `process` keeps only this many samples of the current buffer, then cancels.
    public var cancelAfterSamples: Int? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stopAfter
        }
        set {
            lock.lock()
            stopAfter = newValue
            lock.unlock()
        }
    }
}

private struct PolishContext {
    var text: String
    var textChunks: [String] = []
    var buffers: [[Float]]
    var audio: [Float] = []
    var sampleRate: Double
    var prime: Bool
}

/// Splits spoken text so the first piece is a short clause and the rest are whole sentences.
public enum SpeechClauseChunker {
    public static let minimumFirstChunk = 40
    public static let maximumFirstChunk = 90

    public static func chunks(of text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sentences = splitSentences(trimmed)
        guard let first = sentences.first else { return [] }
        if first.count <= maximumFirstChunk { return sentences }
        let breakAt = clauseBreak(in: first) ?? wordBreak(in: first)
        let chars = Array(first)
        let head = String(chars.prefix(breakAt)).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(chars.dropFirst(breakAt)).trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        if !head.isEmpty { result.append(head) }
        if !tail.isEmpty { result.append(tail) }
        result.append(contentsOf: sentences.dropFirst())
        return result
    }

    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc",
        "eg", "ie", "e.g", "i.e", "am", "pm", "a.m", "p.m",
        "us", "u.s", "uk", "u.k", "inc", "ltd", "fig", "vol",
        "gen", "col", "capt", "approx", "dept", "est",
        "mme", "mlle", "pr", "mgr", "cie", "me",
        "av", "bd", "cf", "c.-à-d", "c-à-d",
    ]
    private static let quotes: Set<Character> = ["\"", "'", "»", "”", "’"]
    private static let closingAfterSpace: Set<Character> = ["»", "”", "’"]
    private static let clauseMarks: Set<Character> = [",", ";", ":", "—", "–"]
    private static let conjunctions = [" and ", " but ", " or ", " et ", " mais ", " ou "]

    private static func splitSentences(_ text: String) -> [String] {
        let chars = Array(text)
        let urls = urlIndices(chars)
        var sentences: [String] = []
        var start = 0
        var index = 0
        while index < chars.count {
            if isBoundary(chars, index, urls) {
                let end = absorbEnd(chars, from: index)
                let sentence = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                var next = end
                while next < chars.count && chars[next].isWhitespace { next += 1 }
                start = next
                index = next
                continue
            }
            index += 1
        }
        if start < chars.count {
            let tail = String(chars[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { sentences.append(tail) }
        }
        return sentences
    }

    private static func isBoundary(_ chars: [Character], _ index: Int, _ urls: Set<Int>) -> Bool {
        if urls.contains(index) { return false }
        let character = chars[index]
        if character == "." {
            if index + 1 < chars.count && chars[index + 1] == "." { return false }
            if index > 0, index + 1 < chars.count, isDigit(chars[index - 1]), isDigit(chars[index + 1]) { return false }
            if index + 1 < chars.count, isDigit(chars[index + 1]), index > 0, chars[index - 1] == "." { return false }
            let word = wordBefore(chars, index)
            if isAbbreviation(word) || isInitial(word) { return false }
        } else if character == "…" {
            if index > 0, index + 1 < chars.count, isDigit(chars[index - 1]), isDigit(chars[index + 1]) { return false }
        } else if character != "!" && character != "?" {
            return false
        }
        var cursor = index + 1
        while cursor < chars.count && quotes.contains(chars[cursor]) { cursor += 1 }
        return cursor >= chars.count || chars[cursor].isWhitespace
    }

    private static func absorbEnd(_ chars: [Character], from index: Int) -> Int {
        var end = index + 1
        while end < chars.count {
            if quotes.contains(chars[end]) {
                end += 1
                continue
            }
            if chars[end].isWhitespace {
                var cursor = end
                while cursor < chars.count && chars[cursor].isWhitespace { cursor += 1 }
                if cursor < chars.count && closingAfterSpace.contains(chars[cursor]) {
                    end = cursor + 1
                    continue
                }
            }
            break
        }
        return end
    }

    private static func wordBefore(_ chars: [Character], _ index: Int) -> String {
        var cursor = index - 1
        while cursor >= 0 && !chars[cursor].isWhitespace { cursor -= 1 }
        return String(chars[(cursor + 1)..<index])
    }

    private static func isAbbreviation(_ word: String) -> Bool {
        if word == "No" { return true }
        return abbreviations.contains(word.lowercased())
    }

    private static func isInitial(_ word: String) -> Bool {
        guard word.count == 1, let character = word.first, character.isUppercase, character != "I" else { return false }
        return true
    }

    private static func clauseBreak(in sentence: String) -> Int? {
        let chars = Array(sentence)
        var best: Int?
        for index in chars.indices {
            let mark = chars[index]
            guard clauseMarks.contains(mark) else { continue }
            if mark == ",", index > 0, index + 1 < chars.count, isDigit(chars[index - 1]), isDigit(chars[index + 1]) {
                continue
            }
            let length = index + 1
            if length >= minimumFirstChunk && length <= maximumFirstChunk { best = length }
        }
        let lowered = Array(sentence.lowercased())
        guard lowered.count == chars.count else { return best }
        for phrase in conjunctions {
            let needle = Array(phrase)
            var start = 0
            while let found = firstIndex(of: needle, in: lowered, from: start) {
                if found >= minimumFirstChunk && found <= maximumFirstChunk {
                    best = max(best ?? found, found)
                }
                start = found + needle.count
            }
        }
        return best
    }

    private static func wordBreak(in sentence: String) -> Int {
        let chars = Array(sentence)
        var best: Int?
        for index in chars.indices where chars[index].isWhitespace && index >= minimumFirstChunk && index <= maximumFirstChunk {
            best = index
        }
        if let best { return best }
        return min(maximumFirstChunk, chars.count)
    }

    private static func urlIndices(_ chars: [Character]) -> Set<Int> {
        let schemes: [[Character]] = [Array("https://"), Array("http://"), Array("www.")]
        var indices = Set<Int>()
        var index = 0
        while index < chars.count {
            var matched = 0
            for scheme in schemes where starts(chars, at: index, with: scheme) {
                matched = scheme.count
                break
            }
            if matched > 0 {
                var end = index
                while end < chars.count && !chars[end].isWhitespace { end += 1 }
                for cursor in index..<end { indices.insert(cursor) }
                index = end
            } else {
                index += 1
            }
        }
        return indices
    }

    private static func starts(_ chars: [Character], at index: Int, with prefix: [Character]) -> Bool {
        guard index + prefix.count <= chars.count else { return false }
        for offset in prefix.indices where chars[index + offset] != prefix[offset] { return false }
        return true
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= haystack.count - needle.count else { return nil }
        var index = max(0, start)
        let last = haystack.count - needle.count
        while index <= last {
            var matched = true
            for offset in needle.indices where haystack[index + offset] != needle[offset] {
                matched = false
                break
            }
            if matched { return index }
            index += 1
        }
        return nil
    }

    private static func isDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }
}

/// 20 ms equal-power crossfade. Overlap uses sin/cos so the join keeps constant power.
public enum EqualPowerCrossfade {
    public static let durationSeconds = 0.020

    public static func fadeSamples(sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int((sampleRate * durationSeconds).rounded())
    }

    public static func join(_ left: [Float], _ right: [Float], sampleRate: Double) -> [Float] {
        let fade = fadeSamples(sampleRate: sampleRate)
        guard fade > 1, left.count > fade, right.count > fade else { return left + right }
        var mixed = [Float]()
        mixed.reserveCapacity(fade)
        let tailStart = left.count - fade
        for index in 0..<fade {
            let theta = Double(index) / Double(fade - 1) * Double.pi / 2
            let sample = Float(cos(theta)) * left[tailStart + index] + Float(sin(theta)) * right[index]
            mixed.append(sample)
        }
        return Array(left.prefix(tailStart)) + mixed + Array(right.dropFirst(fade))
    }

    public static func joinAll(_ buffers: [[Float]], sampleRate: Double) -> [Float] {
        guard let first = buffers.first else { return [] }
        return buffers.dropFirst().reduce(first) { join($0, $1, sampleRate: sampleRate) }
    }
}

/// 60 ms of silence, then a 10 ms quarter-sine fade-in, so the route can open before the first word.
public enum WarmupPrimer {
    public static let durationSeconds = 0.060
    public static let fadeInSeconds = 0.010

    public static func sampleCount(sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int((sampleRate * durationSeconds).rounded())
    }

    public static func apply(_ samples: [Float], sampleRate: Double) -> [Float] {
        let primer = sampleCount(sampleRate: sampleRate)
        guard primer > 0 else { return samples }
        var output = [Float](repeating: 0, count: primer)
        output.append(contentsOf: samples)
        let fade = max(1, Int((sampleRate * fadeInSeconds).rounded()))
        let count = min(fade, samples.count)
        for index in 0..<count {
            let theta = Double(index) / Double(max(fade - 1, 1)) * Double.pi / 2
            output[primer + index] *= Float(sin(theta))
        }
        return output
    }
}

/// Integrated loudness matched to pyloudnorm 0.1.1's default K-weighting meter (ITU-R BS.1770 gating).
/// Gain for a new utterance starts at the buffer's own target. Later buffers move 25% of the way
/// toward the new target so a loud clause cannot pump the level in one step.
public struct LoudnessNormalizer: Sendable {
    public static let targetLUFS = -16.0
    public static let smoothing: Float = 0.25
    public private(set) var appliedGain: Float = 1
    private var lastGain: Float?

    public init() {}

    public mutating func reset() {
        lastGain = nil
        appliedGain = 1
    }

    public static func targetGain(for samples: [Float], sampleRate: Double) -> Float {
        let measured = measureIntegratedLUFS(samples, sampleRate: sampleRate)
        guard measured.isFinite, measured > -70 else { return 1 }
        return Float(pow(10, (targetLUFS - measured) / 20))
    }

    public mutating func normalize(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }
        let target = Self.targetGain(for: samples, sampleRate: sampleRate)
        let gain: Float
        if let lastGain {
            gain = lastGain + Self.smoothing * (target - lastGain)
        } else {
            gain = target
        }
        lastGain = gain
        appliedGain = gain
        if gain == 1 { return samples }
        return samples.map { Float(Double($0) * Double(gain)) }
    }

    /// One second at 48 kHz matches pyloudnorm's gated integrated loudness.
    /// Shorter buffers use a single K-weighted block so a clause still has a gain.
    public static func measureIntegratedLUFS(_ samples: [Float], sampleRate: Double) -> Double {
        guard !samples.isEmpty, sampleRate > 0 else { return -.infinity }
        let filtered = kWeighted(samples, sampleRate: sampleRate)
        let block = 0.400
        let step = 0.25
        let duration = Double(filtered.count) / sampleRate
        if duration < block {
            let energy = filtered.reduce(0.0) { $0 + $1 * $1 }
            let mean = energy / Double(filtered.count)
            guard mean > 0 else { return -.infinity }
            return -0.691 + 10 * log10(mean)
        }
        let numBlocks = numpyRound((duration - block) / (block * step)) + 1
        var energies = [Double]()
        var loudnesses = [Double]()
        energies.reserveCapacity(numBlocks)
        for index in 0..<numBlocks {
            let lower = Int(block * (Double(index) * step) * sampleRate)
            let upper = Int(block * (Double(index) * step + 1) * sampleRate)
            var sum = 0.0
            if lower < filtered.count {
                let end = min(upper, filtered.count)
                if lower < end {
                    for sample in filtered[lower..<end] { sum += sample * sample }
                }
            }
            let energy = sum / (block * sampleRate)
            energies.append(energy)
            loudnesses.append(energy > 0 ? -0.691 + 10 * log10(energy) : -.infinity)
        }
        let absolute = loudnesses.indices.filter { loudnesses[$0] >= -70 }
        guard !absolute.isEmpty else { return -.infinity }
        let absoluteMean = average(energies, indices: absolute)
        guard absoluteMean > 0 else { return -.infinity }
        let relativeGate = -0.691 + 10 * log10(absoluteMean) - 10
        let gated = loudnesses.indices.filter { loudnesses[$0] > relativeGate && loudnesses[$0] > -70 }
        guard !gated.isEmpty else { return -.infinity }
        let mean = average(energies, indices: gated)
        guard mean > 0 else { return -.infinity }
        return -0.691 + 10 * log10(mean)
    }

    private static func average(_ values: [Double], indices: [Int]) -> Double {
        var sum = 0.0
        for index in indices { sum += values[index] }
        return sum / Double(indices.count)
    }

    /// Numpy's `round` is half-to-even. pyloudnorm does `int(round(blocks)) + 1`.
    private static func numpyRound(_ value: Double) -> Int {
        let base = floor(value)
        let fraction = value - base
        if fraction > 0.5 { return Int(base) + 1 }
        if fraction < 0.5 { return Int(base) }
        let whole = Int(base)
        return whole % 2 == 0 ? whole : whole + 1
    }

    private static func kWeighted(_ samples: [Float], sampleRate: Double) -> [Double] {
        var shelf = Biquad.highShelf(rate: sampleRate)
        var highPass = Biquad.highPass(rate: sampleRate)
        var filtered = [Double]()
        filtered.reserveCapacity(samples.count)
        for sample in samples {
            filtered.append(highPass.process(shelf.process(Double(sample))))
        }
        return filtered
    }
}

/// RBJ biquads, the same shapes pyloudnorm 0.1.1 builds for its default K-weighting.
private struct Biquad {
    var b0: Double
    var b1: Double
    var b2: Double
    var a1: Double
    var a2: Double
    var z1 = 0.0
    var z2 = 0.0

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }

    static func highShelf(rate: Double) -> Biquad {
        let gain = 4.0
        let q = 1.0 / sqrt(2.0)
        let frequency = 1500.0
        let a = pow(10.0, gain / 40.0)
        let omega = 2.0 * Double.pi * (frequency / rate)
        let alpha = sin(omega) / (2.0 * q)
        let cosine = cos(omega)
        let root = sqrt(a)
        let b0 = a * ((a + 1) + (a - 1) * cosine + 2 * root * alpha)
        let b1 = -2 * a * ((a - 1) + (a + 1) * cosine)
        let b2 = a * ((a + 1) + (a - 1) * cosine - 2 * root * alpha)
        let a0 = (a + 1) - (a - 1) * cosine + 2 * root * alpha
        let a1 = 2 * ((a - 1) - (a + 1) * cosine)
        let a2 = (a + 1) - (a - 1) * cosine - 2 * root * alpha
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highPass(rate: Double) -> Biquad {
        let q = 0.5
        let frequency = 38.0
        let omega = 2.0 * Double.pi * (frequency / rate)
        let alpha = sin(omega) / (2.0 * q)
        let cosine = cos(omega)
        let b0 = (1 + cosine) / 2
        let b1 = -(1 + cosine)
        let b2 = (1 + cosine) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosine
        let a2 = 1 - alpha
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

/// Limits the 4× true peak to -1 dBTP. The oversampler is scipy's `resample_poly` 4× Kaiser FIR
/// (`firwin(81, 0.25, window=('kaiser', 5)) * 4`, one leading zero, drop 41 samples).
public enum TruePeakLimiter {
    public static let ceilingDBTP = -1.0

    public static func limit(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard sampleRate > 0, !samples.isEmpty else { return samples }
        let ceiling = pow(10.0, ceilingDBTP / 20.0)
        var audio = samples
        for _ in 0..<2 {
            let peak = truePeak(audio)
            if !peak.isFinite || peak == 0 || peak <= ceiling { return audio }
            let gain = ceiling * (1 - 1e-6) / peak
            audio = audio.map { Float(Double($0) * gain) }
        }
        return audio
    }

    public static func truePeakDBTP(_ samples: [Float], sampleRate: Double) -> Double {
        guard sampleRate > 0 else { return -.infinity }
        let peak = truePeak(samples)
        guard peak > 0 else { return -.infinity }
        return 20 * log10(peak)
    }

    public static func truePeak(_ samples: [Float]) -> Double {
        let count = samples.count
        guard count > 0 else { return 0 }
        let up = 4
        let start = 41
        let end = start + count * up
        var peak = 0.0
        for index in start..<end {
            var sum = 0.0
            var tap = index % up
            if tap == 0 { tap = up }
            while tap <= fir.count {
                let source = index - tap
                if source >= 0 && source % up == 0 {
                    let sampleIndex = source / up
                    if sampleIndex < count {
                        sum += fir[tap - 1] * Double(samples[sampleIndex])
                    }
                }
                tap += up
            }
            let magnitude = abs(sum)
            if magnitude > peak { peak = magnitude }
        }
        return peak
    }

    /// scipy 1.18 `firwin(81, 0.25, window=("kaiser", 5.0)) * 4`.
    private static let fir: [Double] = [
        -1.4319646207876959e-18, -0.001130597579184462, -0.0021031678617178763,
        -0.0019016679348927714, 3.7090410940238969e-18, 0.002926514108961888,
        0.0050185309234718218, 0.0042523190668551066, -6.9891223043616017e-18,
        -0.0059320518437837163, -0.0097908339711988944, -0.0080261254612654948,
        1.1214237028997423e-17, 0.010605090076805452, 0.017115155028976117,
        0.013753959070631754, -1.6183952382363033e-17, -0.017579165251157446,
        -0.027983277010958117, -0.02221988556769976, 2.1564830647503023e-17,
        0.02786691635952088, 0.044051484099836266, 0.034795254750361125,
        -2.6922559134588193e-17, -0.043423086442114851, -0.068688534985681379,
        -0.054425491068782521, 3.1772982945983186e-17, 0.068972338798174979,
        0.11058973007292547, 0.089283348532046169, -3.5644656557647819e-17,
        -0.12013435015454692, -0.20188442282305535, -0.17397774297154053,
        3.8143133424221195e-17, 0.29654281960437517, 0.63347608687987345,
        0.89963257101020855, 1.000636565089112, 0.89963257101020855,
        0.63347608687987345, 0.29654281960437517, 3.8143133424221195e-17,
        -0.17397774297154053, -0.20188442282305535, -0.12013435015454692,
        -3.5644656557647819e-17, 0.089283348532046169, 0.11058973007292547,
        0.068972338798174979, 3.1772982945983186e-17, -0.054425491068782521,
        -0.068688534985681379, -0.043423086442114851, -2.6922559134588193e-17,
        0.034795254750361125, 0.044051484099836266, 0.02786691635952088,
        2.1564830647503023e-17, -0.02221988556769976, -0.027983277010958117,
        -0.017579165251157446, -1.6183952382363033e-17, 0.013753959070631754,
        0.017115155028976117, 0.010605090076805452, 1.1214237028997423e-17,
        -0.0080261254612654948, -0.0097908339711988944, -0.0059320518437837163,
        -6.9891223043616017e-18, 0.0042523190668551066, 0.0050185309234718218,
        0.002926514108961888, 3.7090410940238969e-18, -0.0019016679348927714,
        -0.0021031678617178763, -0.001130597579184462, -1.4319646207876959e-18,
    ]
}
