import Foundation
import Testing
import ZeusCore

@Suite("Scribe diarizer")
struct ScribeDiarizerTests {
    private let rate = Double(ScribePCM.sampleRate)

    /// A synthetic voice: a harmonic stack at `f0` whose harmonics fall off by `tilt` and are boosted near `formant`.
    private struct Voice {
        let f0: Double
        let tilt: Double
        let formant: Double
    }

    private let low = Voice(f0: 110, tilt: 1.2, formant: 500)
    private let high = Voice(f0: 220, tilt: 0.6, formant: 2_200)
    private let highest = Voice(f0: 330, tilt: 0.8, formant: 1_500)

    /// Deterministic: `seed` picks the noise and the stretch of the waveform; `drift` nudges the pitch.
    private func speech(_ voice: Voice, seconds: Double = 2.5, seed: UInt64 = 1, drift: Double = 1) -> [Float] {
        let count = Int(seconds * rate)
        let f0 = voice.f0 * drift
        var harmonics: [(frequency: Double, amplitude: Double)] = []
        var number = 1
        while Double(number) * f0 < 4_000 {
            let frequency = Double(number) * f0
            let offset = (frequency - voice.formant) / 300
            let boost = 1 + 3 * exp(-offset * offset)
            harmonics.append((frequency, pow(Double(number), -voice.tilt) * boost))
            number += 1
        }
        let origin = Double(seed) * 977
        var wave = [Double](repeating: 0, count: count)
        var energy = 0.0
        for index in 0..<count {
            let time = (Double(index) + origin) / rate
            var sum = 0.0
            for harmonic in harmonics { sum += harmonic.amplitude * sin(2 * Double.pi * harmonic.frequency * time) }
            wave[index] = sum
            energy += sum * sum
        }
        let gain = 0.1 / max(1e-9, (energy / Double(max(1, count))).squareRoot())
        var state = (seed &* 0x9E37_79B9_7F4A_7C15) | 1
        return wave.map { value -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double(state >> 11) / Double(1 << 53) - 0.5
            return Float(value * gain + noise * 0.01)
        }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int((seconds * rate).rounded()))
    }

    // MARK: Voiceprint

    @Test func silenceAndShortAudioHaveNoVoiceprint() {
        #expect(ScribeVoiceprint.make(samples: []) == nil)
        #expect(ScribeVoiceprint.make(samples: silence(seconds: 3)) == nil)
        #expect(ScribeVoiceprint.make(samples: Array(speech(low).prefix(Int(0.5 * rate)))) == nil)
        #expect(ScribeVoiceprint.make(samples: speech(low), sampleRate: 100) == nil)
    }

    @Test func aVoiceHasAUnitLengthVoiceprint() throws {
        let print = try #require(ScribeVoiceprint.make(samples: speech(low)))
        let length = print.vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(length - 1) < 1e-3)
        #expect(print.distance(to: print) < 1e-4)
    }

    @Test func theSameVoiceIsCloseAndDifferentVoicesAreFar() throws {
        let first = try #require(ScribeVoiceprint.make(samples: speech(low, seed: 1)))
        let again = try #require(ScribeVoiceprint.make(samples: speech(low, seed: 2, drift: 1.015)))
        let other = try #require(ScribeVoiceprint.make(samples: speech(high, seed: 3)))
        let same = first.distance(to: again)
        let different = first.distance(to: other)
        #expect(same < 0.15)
        #expect(different > 0.35)
        #expect(abs(different - other.distance(to: first)) < 1e-5)
        // The default threshold sits between the two with room on both sides.
        #expect(same < ScribeDiarizer.defaultThreshold * 0.7)
        #expect(different > ScribeDiarizer.defaultThreshold * 1.5)
    }

    @Test func loudnessDoesNotChangeWhoItSoundsLike() throws {
        let quiet = speech(low, seed: 1).map { $0 * 0.4 }
        let loud = speech(low, seed: 1).map { $0 * 2 }
        let first = try #require(ScribeVoiceprint.make(samples: quiet))
        let second = try #require(ScribeVoiceprint.make(samples: loud))
        #expect(first.distance(to: second) < 0.1)
    }

    @Test func aLongChunkIsCheapToDescribe() throws {
        let chunk = speech(low, seconds: 8)
        let clock = ContinuousClock()
        var print: ScribeVoiceprint?
        let elapsed = clock.measure { print = ScribeVoiceprint.make(samples: chunk) }
        #expect(print != nil)
        // Generous: a release build takes a few milliseconds.
        #expect(elapsed < .seconds(3))
    }

    // MARK: Diarizer

    @Test func twoVoicesGetDifferentLabelsAndRepeatsKeepTheirs() {
        var diarizer = ScribeDiarizer()
        let first = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        let second = diarizer.assign(source: .system, samples: speech(high, seed: 2))
        let firstAgain = diarizer.assign(source: .system, samples: speech(low, seed: 3, drift: 1.01))
        let secondAgain = diarizer.assign(source: .system, samples: speech(high, seed: 4, drift: 0.99))
        #expect(first == .participant("Speaker 1"))
        #expect(second == .participant("Speaker 2"))
        #expect(firstAgain == first)
        #expect(secondAgain == second)
        #expect(diarizer.speakerCount == 2)
    }

    @Test func theFirstMicrophoneVoiceIsYouAndOthersInTheRoomAreParticipants() {
        var diarizer = ScribeDiarizer()
        let me = diarizer.assign(source: .microphone, samples: speech(low, seed: 1))
        let visitor = diarizer.assign(source: .microphone, samples: speech(high, seed: 2))
        let meAgain = diarizer.assign(source: .microphone, samples: speech(low, seed: 3, drift: 1.01))
        let remote = diarizer.assign(source: .system, samples: speech(highest, seed: 4))
        #expect(me == .you)
        #expect(visitor == .participant("Speaker 1"))
        #expect(meAgain == .you)
        // One counter across both sources, in order of first appearance.
        #expect(remote == .participant("Speaker 2"))
        #expect(diarizer.speakerCount == 3)
    }

    @Test func aSystemVoiceIsNeverMergedIntoTheMicrophoneUser() {
        var diarizer = ScribeDiarizer()
        let me = diarizer.assign(source: .microphone, samples: speech(low, seed: 1))
        let remote = diarizer.assign(source: .system, samples: speech(low, seed: 2))
        #expect(me == .you)
        #expect(remote == .participant("Speaker 1"))
        #expect(diarizer.speakerCount == 2)
    }

    @Test func aSilentOrShortChunkContinuesThePreviousSpeaker() {
        var diarizer = ScribeDiarizer()
        // Nobody heard yet: the defaults.
        let micDefault = diarizer.assign(source: .microphone, samples: silence(seconds: 2))
        let systemDefault = diarizer.assign(source: .system, samples: silence(seconds: 2))
        #expect(micDefault == .you)
        #expect(systemDefault == .participant("Speaker 1"))
        #expect(diarizer.speakerCount == 0)

        _ = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        let heardSecond = diarizer.assign(source: .system, samples: speech(high, seed: 2))
        let afterSilence = diarizer.assign(source: .system, samples: silence(seconds: 2))
        let afterShort = diarizer.assign(source: .system, samples: Array(speech(low, seed: 3).prefix(Int(0.3 * rate))))
        #expect(heardSecond == .participant("Speaker 2"))
        #expect(afterSilence == heardSecond)
        #expect(afterShort == heardSecond)
        #expect(diarizer.speakerCount == 2)
        // The microphone's memory is separate.
        let mic = diarizer.assign(source: .microphone, samples: silence(seconds: 1))
        #expect(mic == .you)
    }

    @Test func noMoreThanMaxSpeakersAreCreatedFromOneSource() {
        var diarizer = ScribeDiarizer(maxSpeakers: 2)
        let first = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        let second = diarizer.assign(source: .system, samples: speech(high, seed: 2))
        let third = diarizer.assign(source: .system, samples: speech(highest, seed: 3))
        #expect(first == .participant("Speaker 1"))
        #expect(second == .participant("Speaker 2"))
        #expect(third == first || third == second)
        #expect(diarizer.speakerCount == 2)
        #expect(diarizer.maxSpeakers == 2)
    }

    @Test func aThirdVoiceIsANewSpeakerWhenThereIsRoom() {
        var diarizer = ScribeDiarizer()
        _ = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        _ = diarizer.assign(source: .system, samples: speech(high, seed: 2))
        let third = diarizer.assign(source: .system, samples: speech(highest, seed: 3))
        #expect(third == .participant("Speaker 3"))
        #expect(diarizer.speakerCount == 3)
    }

    @Test func theSameInputAlwaysGivesTheSameLabels() {
        func run() -> [ScribeSpeaker] {
            var diarizer = ScribeDiarizer()
            var labels: [ScribeSpeaker] = []
            let steps: [(ScribeAudioSource, Voice, UInt64)] = [
                (.microphone, low, 1), (.system, high, 2), (.microphone, low, 3), (.system, highest, 4), (.system, high, 5),
            ]
            for (source, voice, seed) in steps {
                labels.append(diarizer.assign(source: source, samples: speech(voice, seed: seed)))
            }
            return labels
        }
        let first = run()
        let second = run()
        #expect(first == second)
        #expect(first == [.you, .participant("Speaker 1"), .you, .participant("Speaker 2"), .participant("Speaker 1")])
    }

    // MARK: Classify

    @Test func classifyIsNilBeforeAnyoneIsHeardAndForUnusableAudio() {
        var diarizer = ScribeDiarizer()
        #expect(diarizer.classify(source: .system, samples: speech(low)) == nil)
        _ = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        #expect(diarizer.classify(source: .system, samples: silence(seconds: 2)) == nil)
        #expect(diarizer.classify(source: .system, samples: Array(speech(low).prefix(Int(0.3 * rate)))) == nil)
    }

    @Test func classifyFindsTheNearestKnownVoiceAndNilForANewOne() {
        var diarizer = ScribeDiarizer()
        let first = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        let second = diarizer.assign(source: .system, samples: speech(high, seed: 2))
        #expect(diarizer.classify(source: .system, samples: speech(low, seed: 3, drift: 1.01)) == first)
        #expect(diarizer.classify(source: .system, samples: speech(high, seed: 4, drift: 0.99)) == second)
        #expect(diarizer.classify(source: .system, samples: speech(highest, seed: 5)) == nil)
    }

    @Test func classifyOnlyLooksAtTheSameSource() {
        var diarizer = ScribeDiarizer()
        _ = diarizer.assign(source: .microphone, samples: speech(low, seed: 1))
        #expect(diarizer.classify(source: .system, samples: speech(low, seed: 2)) == nil)
        #expect(diarizer.classify(source: .microphone, samples: speech(low, seed: 3)) == .you)
    }

    @Test func classifyNeverLearnsOrChangesLabels() {
        var diarizer = ScribeDiarizer()
        _ = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        let count = diarizer.speakerCount
        for seed in 2...5 {
            _ = diarizer.classify(source: .system, samples: speech(highest, seed: UInt64(seed)))
        }
        #expect(diarizer.speakerCount == count)
        // The unseen voice is still new to assign: classify created no cluster for it.
        let next = diarizer.assign(source: .system, samples: speech(highest, seed: 6))
        #expect(next == .participant("Speaker 2"))
        // And a silent assign still continues the speaker assigned last, untouched by classify.
        _ = diarizer.classify(source: .system, samples: speech(low, seed: 7))
        #expect(diarizer.assign(source: .system, samples: silence(seconds: 1)) == next)
    }

    @Test func resetForgetsEveryone() {
        var diarizer = ScribeDiarizer()
        _ = diarizer.assign(source: .system, samples: speech(low, seed: 1))
        _ = diarizer.assign(source: .system, samples: speech(high, seed: 2))
        diarizer.reset()
        #expect(diarizer.speakerCount == 0)
        let again = diarizer.assign(source: .system, samples: speech(high, seed: 3))
        #expect(again == .participant("Speaker 1"))
    }

    @Test func maxSpeakersIsAtLeastOne() {
        #expect(ScribeDiarizer(maxSpeakers: 0).maxSpeakers == 1)
    }
}
