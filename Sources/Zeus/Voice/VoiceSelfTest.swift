import AVFoundation
import Foundation
import Speech
import ZeusCore

/// `Zeus --voice-selftest file.wav [--transcript "hey zeus open spotify"] [--speak]`
///
/// Feeds a recording through the same stages a live "Hey Zeus" goes through, with no microphone:
/// speech activity (`VoiceActivity`) → the wake-word listener (`WakeWordListener.feed`, Apple's
/// on-device recogniser, paced like real time) → the wake phrase and same-breath request
/// (`WakePhrase`) → routing (`FastPath` rules) → the line Zeus would say, and optionally says it.
/// Nothing is executed and no model is called. `--transcript` replaces the recogniser stage when
/// Speech Recognition isn't allowed for this build yet. Every stage prints with its timing and is
/// also written to ~/Library/Logs/Zeus/voice.log. Exit 0 when the wake phrase was heard.
@MainActor
enum VoiceSelfTest {
    /// The fixed line every engine speaks in the engine self-test.
    static let engineTestLine = "Good evening, Tony. All systems are in order, and I am listening."

    /// `Zeus --voice-engine-selftest [--receipt <absolute path>] [--silent]`: speaks the fixed line through
    /// each available engine with the Ultron effect and writes a JSON receipt (engine, reason, time to
    /// first audio) to ~/AI-Brain-build/voice-selftest/ unless a path is given. Exit 0 when the Mac voice
    /// spoke through the effect and was not Samantha.
    static func runEngineTestIfRequested(_ arguments: [String]) -> Bool {
        guard arguments.contains("--voice-engine-selftest") else { return false }
        let receipt = arguments.firstIndex(of: "--receipt").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        let silent = arguments.contains("--silent")
        Task { @MainActor in exit(await runEngineTest(receiptPath: receipt, silent: silent)) }
        return true
    }

    static func defaultReceiptURL(now: Date = Date()) -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AI-Brain-build/voice-selftest/receipt-\(stamp).json")
    }

    static func runEngineTest(receiptPath: String?, silent: Bool) async -> Int32 {
        VoiceLog.echo = true
        let speaker = Speaker(languageCode: Locale.current.identifier)
        let rows = await speaker.selfTest(line: engineTestLine, muted: silent)
        let receipt = VoiceSelfTestReceipt(created: ISO8601DateFormatter().string(from: Date()), line: engineTestLine,
                                           systemVoice: speaker.systemVoiceName, rows: rows)
        let url = receiptPath.map { URL(fileURLWithPath: $0) } ?? defaultReceiptURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? receipt.json().write(to: url, options: .atomic)
        for row in rows {
            print("\(row.engine): \(row.spoke ? "spoke" : row.available ? "FAILED" : "skipped"), \(row.reason), first audio \(row.firstAudioMs.map { "\($0) ms" } ?? "none")")
        }
        print("system voice: \(receipt.systemVoice)")
        print("receipt: \(url.path)")
        return receipt.passed ? 0 : 1
    }

    static func runIfRequested(_ arguments: [String]) -> Bool {
        if runEngineTestIfRequested(arguments) { return true }
        guard let flag = arguments.firstIndex(of: "--voice-selftest"), flag + 1 < arguments.count else { return false }
        let url = URL(fileURLWithPath: arguments[flag + 1])
        let override = arguments.firstIndex(of: "--transcript").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        let speak = arguments.contains("--speak")
        Task { @MainActor in exit(await run(wav: url, transcript: override, speak: speak)) }
        return true
    }

    private static let started = ContinuousClock.now
    private static func stage(_ name: String, _ detail: String) {
        let elapsed = (ContinuousClock.now - started).components
        let ms = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        VoiceLog.log("selftest", "[\(name)] +\(ms) ms  \(detail)")
    }

    static func run(wav: URL, transcript override: String?, speak: Bool) async -> Int32 {
        VoiceLog.echo = true
        stage("start", wav.lastPathComponent)
        // 1. The file.
        guard let file = try? AVAudioFile(forReading: wav),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0] else {
            stage("load", "FAILED: can't read \(wav.path)")
            return 2
        }
        let rate = file.processingFormat.sampleRate
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        stage("load", String(format: "%.2f s, %.0f Hz, %d channel(s)", Double(samples.count) / rate, rate, file.processingFormat.channelCount))

        // 2. Speech activity.
        let segments = VoiceSegments.find(samples: samples, sampleRate: rate)
        stage("vad", segments.isEmpty ? "no speech found" : segments.map { String(format: "%.2f-%.2f s", $0.start, $0.end) }.joined(separator: ", "))

        // 3. Permissions and the recogniser.
        stage("access", "mic \(VoicePermissions.mic), speech \(VoicePermissions.speech) (a file needs only speech)")
        var heard: String? = override
        if let override {
            stage("recognise", "SKIPPED, using --transcript: \"\(override)\"")
        } else if VoicePermissions.speech != .authorized {
            stage("recognise", "SKIPPED: Speech Recognition isn't allowed for this build. Open Zeus once and allow it, or pass --transcript.")
        } else {
            heard = await listen(samples: samples, format: file.processingFormat)
        }

        // 4. The wake phrase and the request spoken in the same breath.
        guard let heard else { stage("wake", "NOT heard"); return 1 }
        guard let match = WakePhrase.spot(heard) else {
            stage("wake", "no wake phrase in \"\(heard)\"")
            return 1
        }
        stage("wake", match.request.isEmpty ? "heard; no request yet (Zeus would listen hands-free)" : "heard; request \"\(match.request)\"")
        guard !match.request.isEmpty else { return 0 }

        // 5. Routing (nothing runs).
        var line = ""
        switch FastPath.shared.rules(match.request) {
        case .hit(let plan, let engine):
            stage("route", "fast via \(engine): \(plan.intent.intentLabel)")
            stage("action", "would run: \(plan.summary) (not executed)")
            line = plan.ack ?? plan.summary
        case .ask(let question, let engine):
            stage("route", "fast via \(engine) asks back")
            line = question
        case .miss:
            stage("route", "no local rule: Jev, then the Claude brain (not called here)")
        }
        if !line.isEmpty {
            stage("spoken", "would say \"\(line)\"")
            if speak {
                let speaker = Speaker(languageCode: Locale.current.identifier)
                speaker.speak(line)
                let begun = ContinuousClock.now
                while speaker.isSpeaking, ContinuousClock.now - begun < .seconds(20) { try? await Task.sleep(for: .milliseconds(100)) }
                stage("tts", "finished")
            }
        }
        return 0
    }

    /// Plays the recording into a real `WakeWordListener` at real-time pace, then 3 s of quiet.
    private static func listen(samples: [Float], format: AVAudioFormat) async -> String? {
        let rate = format.sampleRate
        let listener = WakeWordListener(localeIdentifier: Locale.current.identifier)
        stage("recognise", "on-device \(listener.onDeviceSupported), locale \(listener.localeIdentifier)")
        guard listener.onDeviceSupported else { return nil }
        let box = WakeBox()
        listener.onWake = { request in box.set(request) }
        let step = 4096
        var index = 0
        let begun = ContinuousClock.now
        let total = samples.count + Int(rate * 3)
        while index < total, box.value == nil {
            let count = min(step, total - index)
            guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let target = chunk.floatChannelData else { break }
            chunk.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<count { target[channel][i] = index + i < samples.count ? samples[index + i] : 0 }
            }
            listener.feed(chunk)
            index += count
            try? await Task.sleep(for: .seconds(Double(count) / rate))
        }
        // The recogniser may still be finishing its last words.
        var waited = 0
        while box.value == nil, waited < 40 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
        listener.stop()
        guard let request = box.value else { stage("recognise", "no wake callback after \(index) frames"); return nil }
        stage("recognise", "wake callback after \((ContinuousClock.now - begun).formatted()) with request \"\(request)\"")
        return "Hey Zeus " + request
    }

    private final class WakeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        var value: String? { lock.withLock { stored } }
        func set(_ text: String) { lock.withLock { stored = text } }
    }
}
