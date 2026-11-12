import AVFoundation
import Foundation
import Testing
@testable import ZeusCore

/// Drives DictationFlow the way DictationController does (begin, finish, cancel) and records every
/// cue and the moment the microphone opens, in order.
private struct CueHarness {
    var state: DictationFlow.State = .idle
    var log: [String] = []
    var turn: UInt64 = 0

    var isDictating: Bool { state.isActive }

    mutating func apply(_ event: DictationFlow.Event) {
        let cue = DictationCueRule.cue(for: event, before: state)
        state = DictationFlow.reduce(state, event).0
        if let cue { log.append("cue \(cue)") }
    }

    mutating func begin() {
        guard state.canStartJob else { return }
        turn += 1
        var steps: [String] = []
        DictationCueRule.beginCapture(cue: { steps.append("cue \($0)") }, open: { steps.append("mic open") })
        log += steps
        apply(.micOpened(turn: turn))
    }

    mutating func finish() {
        guard state.isListening else { return }
        apply(.finishRequested)
    }

    mutating func deliver() { apply(.succeeded(turn: turn)) }
}

/// One way to start and stop a dictation, as the key monitor, the top bar or a link reports it.
private enum Gesture { case press, release }

@Suite("Dictation cue timing")
struct DictationCueRuleTests {
    /// Runs presses and releases through a behavior exactly as DictationController's key handlers do.
    private func run(_ behavior: DictationBehavior, _ gestures: [Gesture]) -> [String] {
        var harness = CueHarness()
        for gesture in gestures {
            switch gesture {
            case .press:
                switch behavior.actionOnPress(isDictating: harness.isDictating) {
                case .begin: harness.begin()
                case .finish: harness.finish()
                }
            case .release:
                if behavior.finishesOnRelease { harness.finish() }
            }
        }
        harness.deliver()
        return harness.log
    }

    @Test func everyKeyPathPlaysStartBeforeTheMicAndStopOnRelease() {
        let expected = ["cue start", "mic open", "cue stop"]
        // Hold to speak: any dedicated key (Fn, Right Command, a chord), a shared Command key held,
        // and the double-tap latch, whose second tap is reported as the release.
        let hold = run(.holdToSpeak, [.press, .release])
        #expect(hold == expected)
        // Press to start and stop on its own key: the release in between does nothing.
        let toggle = run(.pressToToggle, [.press, .release, .press, .release])
        #expect(toggle == expected)
        // A key shared with Talk to Zeus only offers hold to speak.
        #expect(DictationBehavior.choices(sharedWithTalkKey: true) == [.holdToSpeak])
    }

    @Test func topBarButtonAndLinksPlayBothCues() {
        // AppDelegate.toggleDictation and DictationController.toggle: begin when idle, finish when listening.
        var harness = CueHarness()
        for _ in 0..<2 {
            if harness.state.isListening { harness.finish() } else { harness.begin() }
        }
        harness.deliver()
        #expect(harness.log == ["cue start", "mic open", "cue stop"])
    }

    @Test func stopCueSoundsOnReleaseNotAfterDelivery() {
        var harness = CueHarness()
        harness.begin()
        harness.finish()
        let atRelease = harness.log
        harness.apply(.rewriteStarted(turn: harness.turn, source: .live))
        harness.deliver()
        #expect(atRelease.last == "cue stop")
        #expect(harness.log == atRelease)
    }

    @Test func cancelAndErrorsPlayTheLowBlipOnce() {
        var cancelled = CueHarness()
        cancelled.begin()
        cancelled.apply(.cancelRequested)
        cancelled.apply(.cancelRequested)
        #expect(cancelled.log == ["cue start", "mic open", "cue cancel"])

        var empty = CueHarness()
        empty.begin()
        empty.finish()
        empty.apply(.failed(turn: empty.turn, reason: "No speech was heard."))
        #expect(empty.log == ["cue start", "mic open", "cue stop", "cue cancel"])

        #expect(DictationCueRule.cue(for: .startFailed(reason: "no mic"), before: .idle) == .cancel)
        #expect(DictationCueRule.cue(for: .startFailed(reason: "busy"), before: .listening(turn: 1)) == nil)
    }

    @Test func filesAndHistoryRunsStayQuiet() {
        let file = DictationFlow.State.transcribing(turn: 3, source: .file)
        #expect(DictationCueRule.cue(for: .failed(turn: 3, reason: "x"), before: file) == nil)
        #expect(DictationCueRule.cue(for: .cancelRequested, before: file) == nil)
        #expect(DictationCueRule.cue(for: .succeeded(turn: 3), before: file) == nil)
        #expect(DictationCueRule.cue(for: .fileRequested(turn: 3), before: .idle) == nil)
        #expect(DictationCueRule.cue(for: .finishRequested, before: .idle) == nil)
        #expect(DictationCueRule.cue(for: .micOpened(turn: 1), before: .idle) == nil)
    }

    @Test func startCueHasAlreadyPlayedWhenTheMicFailsToOpen() {
        struct MicError: Error {}
        var steps: [String] = []
        var threw = false
        do {
            _ = try DictationCueRule.beginCapture(cue: { steps.append("cue \($0)") }, open: { () throws -> Int in throw MicError() })
        } catch {
            threw = error is MicError
        }
        #expect(threw)
        #expect(steps == ["cue start"])
    }

    @Test func noneIsSilentAndCancelIsSharedByEveryStyle() {
        for phase in DictationCuePhase.allCases {
            #expect(DictationCueSource.resolve(DictationCueStyle.none, phase) == .silent)
        }
        for style in DictationCueStyle.allCases where style != DictationCueStyle.none {
            #expect(DictationCueSource.resolve(style, .cancel) == .bundled(.dictationCancel, style: "Dictation cancel"))
        }
        #expect(DictationCueSource.resolve(.crystal, .start) == .bundled(.dictationBegin, style: "Crystal"))
        #expect(DictationCueSource.resolve(.crystal, .stop) == .bundled(.dictationEnd, style: "Crystal"))
        #expect(DictationCueSource.resolve(.airy, .start) == .synthesized(.airy, .start))
        // A nil style (ZeusSound's own dictation events) still means the original click.
        #expect(SoundCatalog.spec(.dictationBegin, style: nil)?.file == "dictation_begin")
    }

    @Test func everyBundledCueIsCataloguedAndInTheSoundsFolder() {
        for style in DictationCueStyle.allCases {
            for phase in DictationCuePhase.allCases {
                guard case .bundled(let slot, let name) = DictationCueSource.resolve(style, phase) else { continue }
                let spec = SoundCatalog.spec(slot, style: name)
                #expect(spec?.style == name, "\(style) \(phase)")
                let path = spec.map { SoundCatalogTests.folder.appendingPathComponent($0.fileName).path } ?? ""
                #expect(FileManager.default.fileExists(atPath: path), "\(style) \(phase) missing")
            }
        }
    }

    /// Zero crossings in a window of a signal, a rough measure of pitch.
    private func crossings(_ samples: [Float], rate: Double, from start: Double, to end: Double) -> Int {
        let range = Int(start * rate)..<min(samples.count, Int(end * rate))
        var count = 0
        for index in range.dropFirst() where (samples[index - 1] < 0) != (samples[index] < 0) { count += 1 }
        return count
    }

    private func read(_ file: String) throws -> (samples: [Float], rate: Double) {
        let audio = try AVAudioFile(forReading: SoundCatalogTests.folder.appendingPathComponent(file))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        let channel = try #require(buffer.floatChannelData)
        return (Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))), audio.processingFormat.sampleRate)
    }

    @Test func crystalChimesAreShortSoftAndRiseThenFall() throws {
        let start = try read("dictation_crystal_start.wav")
        let stop = try read("dictation_crystal_stop.wav")
        let cancel = try read("dictation_cancel.wav")
        for sound in [start, stop, cancel] {
            #expect(sound.rate == 44_100)
            let seconds = Double(sound.samples.count) / sound.rate
            #expect(seconds > 0.12 && seconds < 0.3)
            // -16 dBFS peak, a soft cue.
            let peak = sound.samples.map(abs).max() ?? 0
            #expect(peak > 0.14 && peak < 0.18)
        }
        // Start: the second note is higher. Stop: lower.
        #expect(crossings(start.samples, rate: start.rate, from: 0.08, to: 0.13) > crossings(start.samples, rate: start.rate, from: 0.005, to: 0.055))
        #expect(crossings(stop.samples, rate: stop.rate, from: 0.08, to: 0.13) < crossings(stop.samples, rate: stop.rate, from: 0.005, to: 0.055))
        // Cancel is low: well under the chime's first note.
        #expect(crossings(cancel.samples, rate: cancel.rate, from: 0.005, to: 0.055) < crossings(stop.samples, rate: stop.rate, from: 0.08, to: 0.13) / 2)
    }
}
