import Foundation
import Testing
@testable import ZeusCore

@Suite("Dictation cue sounds")
struct DictationCueTests {
    private let synthesized: [DictationCueStyle] = [.glass, .pop, .airy]

    /// Zero crossings between two times, a rough measure of pitch.
    private func crossings(_ signal: [Float], from start: Double, to end: Double) -> Int {
        let rate = Double(DictationCueSynth.sampleRate)
        let range = Int(start * rate)..<min(signal.count, Int(end * rate))
        var count = 0
        for index in range.dropFirst() where (signal[index - 1] < 0) != (signal[index] < 0) { count += 1 }
        return count
    }

    @Test func airyIsTheDefault() {
        #expect(DictationCueStyle.defaultStyle == .airy)
        #expect(DictationCueStyle(saved: nil) == .airy)
        #expect(DictationCueStyle(saved: "Not a style") == .airy)
        #expect(DictationCueStyle(saved: "Glass") == .glass)
    }

    @Test func presetsAreTheFiveRequested() {
        #expect(DictationCueStyle.allCases.map(\.title) == ["Soft click", "Glass", "Pop", "Airy", "None"])
    }

    @Test func softClickAndNoneMakeNoSynthesizedAudio() {
        for style in [DictationCueStyle.softClick, .none] {
            #expect(DictationCueSynth.samples(style, .start).isEmpty)
            #expect(DictationCueSynth.wav(style, .stop) == nil)
        }
    }

    @Test func everySynthesizedSoundIsShortAudibleAndWithinRange() {
        for style in synthesized {
            for phase in [DictationCuePhase.start, .stop] {
                let signal = DictationCueSynth.samples(style, phase)
                let seconds = Double(signal.count) / Double(DictationCueSynth.sampleRate)
                #expect(seconds > 0.05 && seconds < 0.6)
                let peak = signal.map { abs($0) }.max() ?? 0
                #expect(peak > 0.3 && peak <= 0.9)
                #expect(signal.allSatisfy { $0.isFinite })
                #expect(abs(signal.last ?? 1) < 0.01)
            }
        }
    }

    @Test func airyRisesOnStartAndFallsOnStop() {
        let start = DictationCueSynth.samples(.airy, .start)
        #expect(crossings(start, from: 0.06, to: 0.09) > crossings(start, from: 0.005, to: 0.035))
        let stop = DictationCueSynth.samples(.airy, .stop)
        #expect(crossings(stop, from: 0.06, to: 0.09) < crossings(stop, from: 0.005, to: 0.035))
    }

    @Test func startAndStopDiffer() {
        for style in synthesized {
            #expect(DictationCueSynth.samples(style, .start) != DictationCueSynth.samples(style, .stop))
        }
    }

    @Test func stylesDifferFromEachOther() {
        let sounds = synthesized.map { DictationCueSynth.samples($0, .start) }
        #expect(sounds[0] != sounds[1] && sounds[1] != sounds[2] && sounds[0] != sounds[2])
    }

    @Test func soundsAreDeterministic() {
        for style in synthesized {
            #expect(DictationCueSynth.samples(style, .start) == DictationCueSynth.samples(style, .start))
        }
    }

    @Test func wavHasAValidHeaderAndMatchingLength() throws {
        let wav = try #require(DictationCueSynth.wav(.airy, .start))
        let signal = DictationCueSynth.samples(.airy, .start)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: wav[36..<40], as: UTF8.self) == "data")
        #expect(wav.count == 44 + signal.count * 2)
    }

    @Test func volumeIsClampedToAPercent() {
        #expect(DictationCueSynth.clampedVolume(-5) == 0)
        #expect(DictationCueSynth.clampedVolume(250) == 100)
        #expect(DictationCueSynth.clampedVolume(40) == 40)
        #expect(DictationCueSynth.defaultVolume == 70)
    }
}
