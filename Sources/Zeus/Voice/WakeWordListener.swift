import Accelerate
import AVFoundation
import Speech
import ZeusCore

/// The audio side of "Hey Zeus". The microphone tap only measures loudness (one vDSP call per
/// ~85 ms buffer); Apple's on-device recogniser (`requiresOnDeviceRecognition`, nothing leaves the
/// Mac) runs only while someone is talking, fed with ~0.7 s of audio from just before speech began
/// so "hey" isn't clipped. A recognition window ends after 1.2 s of quiet or 50 s, whichever comes
/// first. When the transcript contains the wake phrase it waits for the request after it to settle
/// (0.8 s unchanged and quiet), then calls `onWake` with that request ("open Spotify", or "").
/// Voice-activity gating in front of recognition is an idea from openWakeWord (Apache-2.0); no code.
final class WakeWordListener: @unchecked Sendable {
    /// Called once per wake phrase, on an arbitrary thread.
    var onWake: (@Sendable (String) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private let lock = NSLock()
    private var vad = VoiceActivity()
    private var preroll: [AVAudioPCMBuffer] = []
    private var prerollSeconds = 0.0
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var windowStarted: Date?
    private var spotted: (at: Date, request: String, changedAt: Date)?
    private var generation = 0
    private var fired = false
    private var unavailableLogged = false
    private var closingAt: Date?
    // Measurements for the log.
    private(set) var audioSeconds = 0.0
    private(set) var recognizingSeconds = 0.0

    static let windowLimit: TimeInterval = 50

    /// The wake phrase itself ("Hey Zeus") is English, and nothing may leave the Mac: pin the
    /// recogniser to English (US) so the wake phrase is heard reliably regardless of the person's
    /// own dictation language, falling back to their locale only when en-US has no on-device model
    /// on this Mac (item 6, QA7 -- a non-English on-device model was degrading wake-phrase
    /// recognition). A language without on-device support used to leave the listener silently off.
    init(localeIdentifier: String) {
        let english = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        if let english, english.supportsOnDeviceRecognition {
            recognizer = english
        } else {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) ?? english
        }
    }

    var localeIdentifier: String { recognizer?.locale.identifier ?? "none" }

    /// Nothing may leave the Mac: without on-device support the listener stays off.
    var onDeviceSupported: Bool { recognizer?.supportsOnDeviceRecognition == true }

    var stats: (audio: Double, recognizing: Double) { lock.withLock { (audioSeconds, recognizingSeconds) } }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechInput.InputError.recognizerUnavailable }
        lock.withLock { fired = false; vad = VoiceActivity(); preroll = []; prerollSeconds = 0 }
        input.removeTap(onBus: 0)
        // ~85 ms per buffer at 48 kHz: few wake-ups, still quick to react.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.feed(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        let (request, task) = lock.withLock { () -> (SFSpeechAudioBufferRecognitionRequest?, SFSpeechRecognitionTask?) in
            defer { endWindowLocked() }
            return (self.request, self.task)
        }
        request?.endAudio()
        task?.cancel()
    }

    // MARK: Audio thread

    /// One buffer of microphone audio (or of a WAV file, for the offline self-test).
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        var toCancel: (SFSpeechAudioBufferRecognitionRequest?, SFSpeechRecognitionTask?) = (nil, nil)
        var wake: String?
        var toEnd: SFSpeechAudioBufferRecognitionRequest?
        lock.lock()
        audioSeconds += seconds
        let speaking = vad.feed(rms: rms, seconds: seconds)
        if let request {
            let now = Date()
            if closingAt == nil {
                recognizingSeconds += seconds
                request.append(buffer)
            }
            if let closingAt {
                // Quiet again: audio ended, waiting for the recogniser's final words (up to 2 s).
                if now.timeIntervalSince(closingAt) > 2 {
                    if let spotted, !fired { fired = true; wake = spotted.request }
                    toCancel = (request, task)
                    endWindowLocked()
                }
            } else if let spotted {
                // Speech after the wake phrase went quiet: end the audio and let the recogniser
                // deliver its final result, which carries the last words ("open" → "open
                // Calculator"). The final result, or the 2 s closing fallback above, fires the wake;
                // acting on the settled partial here clipped requests.
                let settled = now.timeIntervalSince(spotted.changedAt) > 0.8 && vad.silence > 0.5
                if !fired, settled || now.timeIntervalSince(spotted.at) > 8 {
                    toEnd = request
                    closingAt = now
                    VoiceLog.log("wake", "speech ended after \"\(spotted.request)\", waiting for the final words")
                }
            } else if !speaking || now.timeIntervalSince(windowStarted ?? now) > Self.windowLimit {
                // Let the recogniser finish what it heard instead of cancelling: the last words
                // ("Hey Zeus") often only arrive in the final result.
                toEnd = request
                closingAt = now
            }
        } else {
            if let copy = Self.copy(buffer) {
                preroll.append(copy)
                prerollSeconds += seconds
                while prerollSeconds > 0.7, preroll.count > 1 {
                    let first = preroll.removeFirst()
                    prerollSeconds -= Double(first.frameLength) / first.format.sampleRate
                }
            }
            if speaking, !fired { beginWindowLocked() }
        }
        lock.unlock()
        toEnd?.endAudio()
        toCancel.0?.endAudio()
        toCancel.1?.cancel()
        if let wake { onWake?(wake) }
    }

    /// Starts a recognition window with the buffered pre-roll. Called with the lock held.
    private func beginWindowLocked() {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            if !unavailableLogged { unavailableLogged = true; VoiceLog.log("error", "wake recogniser unavailable (locale \(localeIdentifier))") }
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.contextualStrings = ["Hey Zeus", "Zeus", "Hey, Zeus", "heyzeus"]
        for buffer in preroll { request.append(buffer) }
        preroll = []
        prerollSeconds = 0
        generation += 1
        let current = generation
        self.request = request
        windowStarted = Date()
        spotted = nil
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.recognized(result, error: error, generation: current)
        }
    }

    private func endWindowLocked() {
        closingAt = nil
        request = nil
        task = nil
        windowStarted = nil
        spotted = nil
        generation += 1
    }

    private func recognized(_ result: SFSpeechRecognitionResult?, error: Error?, generation current: Int) {
        var wake: String?
        var toCancel: SFSpeechRecognitionTask?
        lock.lock()
        guard current == generation else { lock.unlock(); return }
        if let result, let match = WakePhrase.spot(result.bestTranscription.formattedString) {
            let now = Date()
            if let previous = spotted {
                if previous.request != match.request { spotted = (previous.at, match.request, now) }
            } else {
                spotted = (now, match.request, now)
                VoiceLog.log("wake", "phrase heard in \"\(result.bestTranscription.formattedString)\"")
            }
            if result.isFinal, !fired {
                fired = true
                wake = spotted?.request
                toCancel = task
                endWindowLocked()
            }
        } else if error != nil || result?.isFinal == true {
            if let error { VoiceLog.log("error", "wake recogniser: \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)") }
            // The final pass can re-punctuate or re-segment ("Hey, Zeus. Open…") so the phrase no
            // longer matches. The wake was already heard: go with the longest request seen
            // (the final text after the first "zeus"-like word, else the last partial).
            if let heard = spotted, !fired {
                fired = true
                let finalText = result?.bestTranscription.formattedString ?? ""
                let tail = WakePhrase.spot("hey zeus " + (Self.afterZeus(finalText) ?? ""))?.request ?? ""
                wake = tail.count > heard.request.count ? tail : heard.request
                VoiceLog.log("wake", "final text \"\(finalText)\", using \"\(wake ?? "")\"")
            }
            endWindowLocked()
        }
        lock.unlock()
        toCancel?.cancel()
        if let wake { onWake?(wake) }
    }

    /// The words after the first "zeus"-sounding word, punctuation stripped; nil if there is none.
    static func afterZeus(_ text: String) -> String? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        guard let index = words.firstIndex(where: { ["zeus", "zoos", "seuss", "zues", "zus", "siri", "juice"].contains($0) }) else { return nil }
        return words[(index + 1)...].joined(separator: " ")
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = copy.floatChannelData else { return nil }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        let stride = buffer.format.isInterleaved ? channels : 1
        let perChannel = buffer.format.isInterleaved ? 1 : channels
        for channel in 0..<perChannel {
            target[channel].update(from: source[channel], count: frames * stride)
        }
        return copy
    }
}
