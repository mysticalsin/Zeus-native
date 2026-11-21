import Foundation

/// The only persona voice id speakKokoro will play. Kokoro's engine voice
/// (`am_michael` and the rest of the pack) is not this id.
public enum OriginalSyntheticVoice {
    public static let id = "zeus.synthetic"

    public static func accepts(_ voiceID: String) -> Bool {
        voiceID == id
    }
}

public struct KokoroClauseReceipt: Equatable, Sendable {
    public var accepted: Bool
    public var chunks: [String]
    public var firstAudioAt: Double?
    public var fullRenderCompletedAt: Double
    public var scheduled: [[Float]]
    public var joined: [Float]
}

/// Per-clause Kokoro playback. The first clause is scheduled when its render finishes.
/// Later clauses render after that. Each clause, and the join, is held to -1 dBTP.
public enum KokoroClausePlayback {
    /// Proposed warm-Kokoro budget for the first clause. The injected clock must land inside it.
    public static let firstAudioBudgetSeconds = 1.0

    public static func speak(
        text: String,
        personaVoiceID: String,
        sampleRate: Double,
        clock: inout SpeechManualClock,
        output: any SpeechOutputProcessing,
        synthesize: (String, inout SpeechManualClock) -> [Float],
        schedule: ([Float], Double) -> Void
    ) -> KokoroClauseReceipt {
        guard OriginalSyntheticVoice.accepts(personaVoiceID) else {
            return KokoroClauseReceipt(
                accepted: false,
                chunks: [],
                firstAudioAt: nil,
                fullRenderCompletedAt: clock.seconds,
                scheduled: [],
                joined: [])
        }
        let chunks = SpeechClauseChunker.chunks(of: text)
        var scheduled: [[Float]] = []
        var firstAudioAt: Double?
        for (index, chunk) in chunks.enumerated() {
            let raw = synthesize(chunk, &clock)
            var shaped = shape(raw, sampleRate: sampleRate, output: output)
            if index + 1 < chunks.count {
                shaped = fadeOutAndPause(shaped, sampleRate: sampleRate)
            }
            let at = clock.seconds
            schedule(shaped, at)
            if firstAudioAt == nil { firstAudioAt = at }
            scheduled.append(shaped)
        }
        let joined = hardCeiling(scheduled.flatMap { $0 }, sampleRate: sampleRate)
        return KokoroClauseReceipt(
            accepted: true,
            chunks: chunks,
            firstAudioAt: firstAudioAt,
            fullRenderCompletedAt: clock.seconds,
            scheduled: scheduled,
            joined: joined)
    }

    /// Gain toward -16 LUFS, then the -1 dBTP ceiling. No onset primer: this is the full-reply loudness figure.
    public static func normalizedFullReply(_ samples: [Float], sampleRate: Double, output: any SpeechOutputProcessing) -> [Float] {
        _ = output
        var normalizer = LoudnessNormalizer()
        let gained = normalizer.normalize(samples, sampleRate: sampleRate)
        return hardCeiling(gained, sampleRate: sampleRate)
    }

    public static func shape(_ samples: [Float], sampleRate: Double, output: any SpeechOutputProcessing) -> [Float] {
        hardCeiling(output.process(samples, sampleRate: sampleRate), sampleRate: sampleRate)
    }

    public static func hardCeiling(_ samples: [Float], sampleRate: Double) -> [Float] {
        TruePeakLimiter.limit(samples, sampleRate: sampleRate)
    }

    private static func fadeOutAndPause(_ samples: [Float], sampleRate: Double) -> [Float] {
        var output = samples
        let fade = min(output.count, max(1, Int((sampleRate * ClauseSpeechScheduler.edgeFadeSeconds).rounded())))
        if fade > 1 {
            let start = output.count - fade
            for index in 0..<fade {
                let theta = Double(index) / Double(fade - 1) * Double.pi / 2
                output[start + index] *= Float(cos(theta))
            }
        }
        let pause = max(0, Int((sampleRate * ClauseSpeechScheduler.clausePauseSeconds).rounded()))
        if pause > 0 { output.append(contentsOf: [Float](repeating: 0, count: pause)) }
        return output
    }
}

public enum PCMWav {
    public static func readFloats(from url: URL) -> (samples: [Float], sampleRate: Double)? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        let sampleRate = Double(readUInt32(data, 24))
        let audioFormat = readUInt16(data, 20)
        let bits = readUInt16(data, 34)
        guard audioFormat == 1, bits == 16, sampleRate > 0 else { return nil }
        let dataOffset = 44
        let count = (data.count - dataOffset) / 2
        guard count > 0 else { return nil }
        var samples = [Float]()
        samples.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for index in 0..<count {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: dataOffset + index * 2, as: Int16.self))
                samples.append(Float(sample) / 32_768)
            }
        }
        return (samples, sampleRate)
    }

    public static func write(_ samples: [Float], sampleRate: Double, to url: URL) -> Bool {
        let rate = UInt32(sampleRate.rounded())
        guard rate > 0 else { return false }
        var bytes = Data()
        bytes.append(contentsOf: [UInt8]("RIFF".utf8))
        var chunkSize = UInt32(36 + samples.count * 2).littleEndian
        bytes.append(Data(bytes: &chunkSize, count: 4))
        bytes.append(contentsOf: [UInt8]("WAVEfmt ".utf8))
        var subchunk = UInt32(16).littleEndian
        bytes.append(Data(bytes: &subchunk, count: 4))
        var format = UInt16(1).littleEndian
        bytes.append(Data(bytes: &format, count: 2))
        var channels = UInt16(1).littleEndian
        bytes.append(Data(bytes: &channels, count: 2))
        var sampleRateBits = rate.littleEndian
        bytes.append(Data(bytes: &sampleRateBits, count: 4))
        var byteRate = (rate * 2).littleEndian
        bytes.append(Data(bytes: &byteRate, count: 4))
        var block = UInt16(2).littleEndian
        bytes.append(Data(bytes: &block, count: 2))
        var bits = UInt16(16).littleEndian
        bytes.append(Data(bytes: &bits, count: 2))
        bytes.append(contentsOf: [UInt8]("data".utf8))
        var dataSize = UInt32(samples.count * 2).littleEndian
        bytes.append(Data(bytes: &dataSize, count: 4))
        for sample in samples {
            var unit = Int16(max(-32_768, min(32_767, Int(sample * 32_768)))).littleEndian
            bytes.append(Data(bytes: &unit, count: 2))
        }
        do {
            try bytes.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { raw in raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }
}
