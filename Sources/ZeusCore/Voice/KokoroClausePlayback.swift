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

/// Result of the file path `Speaker.speakKokoro` calls.
public struct KokoroPlayReceipt: Equatable, Sendable {
    public var succeeded: Bool
    public var scheduledCount: Int
    /// True only when nothing was scheduled, so the speak chain may try the next engine.
    public var fallThrough: Bool
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
        var scheduledBuffers: [[Float]] = []
        let scheduled = ClauseSpeechScheduler.speak(
            text: text,
            sampleRate: sampleRate,
            clock: &clock,
            output: output,
            synthesize: synthesize,
            schedule: { samples, at in
                scheduledBuffers.append(samples)
                schedule(samples, at)
            })
        let joined = hardCeiling(scheduledBuffers.flatMap { $0 }, sampleRate: sampleRate)
        return KokoroClauseReceipt(
            accepted: true,
            chunks: scheduled.chunks,
            firstAudioAt: scheduled.scheduled > 0 ? scheduled.firstScheduledAt : nil,
            fullRenderCompletedAt: scheduled.fullRenderCompletedAt,
            scheduled: scheduledBuffers,
            joined: joined)
    }

    /// File path used by `Speaker.speakKokoro`. Rendering and playback are injected so tests drive this
    /// function directly. Shaping, the 90 ms gap, and the fade-in go through `ClauseSpeechScheduler`.
    public static func play(
        text: String,
        personaVoiceID: String,
        sampleRate: Double,
        clock: inout SpeechManualClock,
        output: any SpeechOutputProcessing,
        token: SpeechCancelToken,
        directory: URL,
        deadline: Double? = nil,
        render: (String, inout SpeechManualClock) -> URL?,
        play: (URL) -> Bool
    ) -> KokoroPlayReceipt {
        defer { removeFiles(in: directory) }
        guard OriginalSyntheticVoice.accepts(personaVoiceID) else {
            return KokoroPlayReceipt(succeeded: false, scheduledCount: 0, fallThrough: true)
        }
        var failed = false
        var scheduledCount = 0
        _ = ClauseSpeechScheduler.speak(
            text: text,
            sampleRate: sampleRate,
            clock: &clock,
            output: output,
            token: token,
            synthesize: { chunk, clock in
                if token.isCancelled {
                    failed = true
                    return []
                }
                guard let url = render(chunk, &clock) else {
                    failed = true
                    token.cancel()
                    return []
                }
                if let deadline, clock.seconds > deadline {
                    failed = true
                    token.cancel()
                    return []
                }
                guard let decoded = PCMWav.readFloats(from: url) else {
                    failed = true
                    token.cancel()
                    return []
                }
                return decoded.samples
            },
            schedule: { samples, _ in
                if failed || token.isCancelled { return }
                let file = directory.appendingPathComponent("shaped-\(UUID().uuidString).wav")
                guard PCMWav.write(samples, sampleRate: sampleRate, to: file) else {
                    failed = true
                    token.cancel()
                    return
                }
                if !play(file) {
                    failed = true
                    token.cancel()
                } else {
                    scheduledCount += 1
                }
            })
        let succeeded = !failed && !token.isCancelled && scheduledCount > 0
        return KokoroPlayReceipt(
            succeeded: succeeded,
            scheduledCount: scheduledCount,
            fallThrough: scheduledCount == 0)
    }

    /// Once any clause audio is scheduled, the speak chain must not start another engine.
    public static func holdsTheUtterance(_ receipt: KokoroPlayReceipt) -> Bool {
        receipt.scheduledCount > 0 || receipt.succeeded
    }

    public static func removeFiles(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
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
}

public enum PCMWav {
    public static func readFloats(from url: URL) -> (samples: [Float], sampleRate: Double)? {
        guard let data = try? Data(contentsOf: url), data.count >= 12 else { return nil }
        guard String(data: data.prefix(4), encoding: .ascii) == "RIFF" else { return nil }
        guard String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else { return nil }
        var cursor = 12
        var format: (audioFormat: UInt16, channels: UInt16, sampleRate: UInt32, bits: UInt16)?
        var payload: Data?
        while cursor + 8 <= data.count {
            let ident = String(data: data.subdata(in: cursor..<(cursor + 4)), encoding: .ascii) ?? ""
            let size = Int(readUInt32(data, cursor + 4))
            let start = cursor + 8
            let end = start + size
            guard end <= data.count else { return nil }
            if ident == "fmt ", size >= 16 {
                format = (
                    readUInt16(data, start),
                    readUInt16(data, start + 2),
                    readUInt32(data, start + 4),
                    readUInt16(data, start + 14))
            } else if ident == "data" {
                payload = data.subdata(in: start..<end)
            }
            cursor = end + (size % 2)
        }
        guard let format, format.audioFormat == 1, format.channels == 1, format.bits == 16, format.sampleRate > 0,
              let payload, payload.count >= 2 else { return nil }
        let count = payload.count / 2
        var samples = [Float]()
        samples.reserveCapacity(count)
        payload.withUnsafeBytes { raw in
            for index in 0..<count {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                samples.append(Float(sample) / 32_768)
            }
        }
        return (samples, Double(format.sampleRate))
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
