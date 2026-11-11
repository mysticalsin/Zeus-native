import Foundation
import NaturalLanguage

/// Settings > Voice > Voice quality for ElevenLabs. One model speaks a whole answer so the timbre never
/// changes mid-reply.
public enum ElevenLabsQuality: String, CaseIterable, Sendable {
    case fastest, studio

    /// Verified in the ElevenLabs models page (2026-11-11): the fastest v2.5 model, about 100 ms, 32 languages.
    public static let fastModel = "eleven_flash_v2_5"
    /// The models page lists `eleven_v4` as the highest quality and most expressive model. The page does not
    /// say whether it streams on `/v1/text-to-speech/{voice}/stream`, so this is UNVERIFIED: the app falls
    /// back to `fastModel` for the answer (and the rest of the launch) when ElevenLabs rejects it.
    public static let studioModel = "eleven_v4"

    public static let defaultsKey = "voice.elevenlabs.quality"

    public var title: String { self == .fastest ? "Fastest" : "Studio" }

    public var detail: String {
        self == .fastest
            ? "Lowest delay (about 100 ms to start). The default for talking to Zeus."
            : "The most expressive ElevenLabs model. Richer, a little slower to start."
    }

    public var modelID: String { self == .fastest ? Self.fastModel : Self.studioModel }

    public static func resolve(stored: String?) -> ElevenLabsQuality {
        stored.flatMap(ElevenLabsQuality.init(rawValue:)) ?? .fastest
    }
}

/// The ElevenLabs model for one answer, fixed at its first sentence.
public struct AnswerModelPin: Sendable, Equatable {
    public private(set) var model: String?

    public init() {}

    /// The model for this answer: the pinned one, else the chosen quality (fast when Studio is known unsupported).
    public mutating func resolve(quality: ElevenLabsQuality, studioUnsupported: Bool) -> String {
        if let model { return model }
        let chosen = (quality == .studio && studioUnsupported) ? ElevenLabsQuality.fastModel : quality.modelID
        model = chosen
        return chosen
    }

    /// Studio was rejected before any audio of this answer played: the whole answer uses the fast model.
    public mutating func fallBackToFast() { model = ElevenLabsQuality.fastModel }

    /// Whether a rejection can be a "model not available for streaming" answer.
    public static func isModelRejection(status: Int) -> Bool { [400, 404, 422].contains(status) }

    public mutating func reset() { model = nil }
}

/// The language of a reply, so the macOS fallback can pick the best installed voice for it.
public enum SpokenLanguage {
    public static let candidates: [NLLanguage] = [.english, .french, .spanish, .portuguese, .german, .italian]

    /// A two-letter code ("en", "fr") or nil when the text is too short or ambiguous.
    public static func detect(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.6 else { return nil }
        return language.rawValue
    }
}

/// Joins sentences without clicks. A fade of a few milliseconds is applied at a buffer edge only when
/// that edge does not already sit near zero; an edge near zero is left bit-identical.
public enum AudioEdge {
    public static let fadeMs = 4.0
    public static let silenceThreshold: Float = 0.002

    public static func needsFade(_ edgeSample: Float) -> Bool { abs(edgeSample) > silenceThreshold }

    public static func fadeSamples(sampleRate: Double) -> Int { max(1, Int((fadeMs / 1_000 * sampleRate).rounded())) }

    public static func applyFades(_ samples: inout [Float], sampleRate: Double, head: Bool, tail: Bool) {
        guard !samples.isEmpty else { return }
        let count = min(fadeSamples(sampleRate: sampleRate), samples.count)
        if head, needsFade(samples[0]) {
            for index in 0..<count { samples[index] *= Float(index) / Float(count) }
        }
        if tail, needsFade(samples[samples.count - 1]) {
            for index in 0..<count {
                samples[samples.count - 1 - index] *= Float(index) / Float(count)
            }
        }
    }
}
