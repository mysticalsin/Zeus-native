import Foundation

/// Echo plugs a processor in here. The default leaves every sample as it arrived.
public protocol SpeechOutputProcessing: Sendable {
    func process(_ samples: [Float], sampleRate: Double) -> [Float]
}

public struct IdentitySpeechOutput: SpeechOutputProcessing {
    public init() {}
    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        _ = sampleRate
        return samples
    }
}

/// The only voice id the speak path may send to a provider.
public enum VoiceSpeakAllowlist {
    public static let syntheticID = "zeus.synthetic"

    public static func accepts(_ voiceID: String) -> Bool {
        voiceID == syntheticID
    }
}

/// The live first-audio abort. This is the declared 700 ms budget.
/// It does not change the 8 s provider HTTP timeout, or the 20 s and 45 s ceilings.
public enum ProviderSpeakAbort {
    public static var milliseconds: Int { ProviderLatencyVerdict.firstAudioP50Ms }

    public static func shouldAbort(elapsedMs: Int, heardAudio: Bool, budgetMs: Int = milliseconds) -> Bool {
        !heardAudio && elapsedMs > budgetMs
    }
}

public struct SpeechPCMFrame: Equatable, Sendable {
    public static let sampleRate = 24_000
    public static let sampleCount = 3_200
    public static var byteCount: Int { sampleCount * 2 }
    public var samples: [Float]
    public var sampleRate: Int { Self.sampleRate }
}

/// Splits little-endian 16-bit mono PCM into 24 kHz frames of 3,200 samples.
public struct PCM24kAssembler: Equatable, Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ pcm16: Data) -> [SpeechPCMFrame] {
        pending.append(pcm16)
        var frames: [SpeechPCMFrame] = []
        while pending.count >= SpeechPCMFrame.byteCount {
            let chunk = pending.prefix(SpeechPCMFrame.byteCount)
            pending.removeFirst(SpeechPCMFrame.byteCount)
            var samples = [Float]()
            samples.reserveCapacity(SpeechPCMFrame.sampleCount)
            chunk.withUnsafeBytes { raw in
                for index in 0..<SpeechPCMFrame.sampleCount {
                    let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                    samples.append(Float(sample) / 32_768)
                }
            }
            frames.append(SpeechPCMFrame(samples: samples))
        }
        return frames
    }
}

/// Local voice, then the Mac voice. The reference-clip engine is never in this list.
public enum SyntheticFallbackOrder {
    public static let engines = ["kokoro", "system"]
}

/// Shared by the speak watchdog and the audio thread. Not a lock: one writer flips each flag.
final class AbortFlag: @unchecked Sendable {
    var value = false
    var fired = false
}
