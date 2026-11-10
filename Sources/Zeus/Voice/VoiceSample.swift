import AVFoundation
import Foundation

/// `Zeus --tts-sample <out.wav> [--engine system] [--text "..."]`: renders one reply through the
/// same voice route the app uses (ElevenLabs direct or via the ZEUS worker `/tts`, else the best
/// system voice) into a WAV file, then prints a JSON line with the engine, timing and peak level.
/// Never prints a key or token. Exits before any window exists.
enum VoiceSample {
    static let defaultText = "Hi Tony. Your next meeting starts in ten minutes, and I pulled the speaker notes for slide one."

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--tts-sample"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let text = args.firstIndex(of: "--text").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? defaultText
        let forceSystem = args.firstIndex(of: "--engine").map { $0 + 1 < args.count && args[$0 + 1] == "system" } ?? false
        // The system engine needs no Keychain, so an unsigned debug build can render it without a prompt.
        if !forceSystem { Keychain.store.load() }
        if !forceSystem {
            for route in ElevenLabsVoice.loadRoutes() where renderEleven(text, route, out) { exit(0) }
        }
        exit(system(text, out) ? 0 : 1)
    }

    private static func renderEleven(_ text: String, _ voice: ElevenLabsVoice, _ out: URL) -> Bool {
        let started = Date()
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var pcm = Data()
        nonisolated(unsafe) var status = 0
        nonisolated(unsafe) var firstByteMs = -1
        Task.detached {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: voice.request(for: text))
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                for try await byte in bytes {
                    if firstByteMs < 0 { firstByteMs = Int(Date().timeIntervalSince(started) * 1000) }
                    pcm.append(byte)
                }
            } catch {}
            done.signal()
        }
        done.wait()
        let route = voice.engineName
        guard status == 200, pcm.count > 1_000 else {
            print("{\"engine\":\"\(route)\",\"ok\":false,\"status\":\(status),\"bytes\":\(pcm.count)}")
            return false
        }
        let samples = pcm.count / 2
        let peak = pcm.withUnsafeBytes { raw in
            (0..<samples).reduce(0) { max($0, abs(Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $1 * 2, as: Int16.self))))) }
        }
        do { try wav(pcm: pcm.prefix(samples * 2), sampleRate: 24_000).write(to: out) } catch { return false }
        print("[ZEUS] voice: engine=\(route) model=\(ElevenLabsVoice.model) chars=\(text.count) ok=1 ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        report(route, model: ElevenLabsVoice.model, seconds: Double(samples) / 24_000, peak: Double(peak) / 32_768,
               firstByteMs: firstByteMs, totalMs: Int(Date().timeIntervalSince(started) * 1000), out: out)
        return true
    }

    private static func system(_ text: String, _ out: URL) -> Bool {
        let started = Date()
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        let voice = Speaker.bestVoice(for: Locale.preferredLanguages.first ?? "en-US")
        utterance.voice = voice
        utterance.rate = Speaker.systemRate
        var file: AVAudioFile?
        var peak: Float = 0
        var frames: AVAudioFramePosition = 0
        var finished = false
        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { finished = true; return }
            if file == nil { file = try? AVAudioFile(forWriting: out, settings: pcm.format.settings) }
            try? file?.write(from: pcm)
            frames += AVAudioFramePosition(pcm.frameLength)
            if let ch = pcm.floatChannelData?[0] {
                for k in 0..<Int(pcm.frameLength) { peak = max(peak, abs(ch[k])) }
            } else if let ch = pcm.int16ChannelData?[0] {
                for k in 0..<Int(pcm.frameLength) { peak = max(peak, abs(Float(ch[k]) / 32_768)) }
            }
            if file == nil { finished = true }
        }
        while !finished, Date().timeIntervalSince(started) < 30 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let rate = file?.processingFormat.sampleRate ?? 22_050
        file = nil
        guard frames > 0 else { print("{\"engine\":\"system\",\"ok\":false}"); return false }
        print("[ZEUS] voice: engine=system voice=\(voice.map { "\($0.name) \(Speaker.qualityName($0.quality))" } ?? "default") chars=\(text.count)")
        let name = voice.map { "\($0.name) \(Speaker.qualityName($0.quality))" } ?? "default"
        report("system", model: name, seconds: Double(frames) / rate, peak: Double(peak), firstByteMs: -1,
               totalMs: Int(Date().timeIntervalSince(started) * 1000), out: out)
        return true
    }

    private static func report(_ engine: String, model: String, seconds: Double, peak: Double, firstByteMs: Int, totalMs: Int, out: URL) {
        let dbfs = peak > 0 ? 20 * log10(peak) : -120
        let line: [String: Any] = ["engine": engine, "ok": true, "model": model, "seconds": (seconds * 100).rounded() / 100,
                                   "peakDbfs": (dbfs * 10).rounded() / 10, "clipped": peak >= 0.999, "firstByteMs": firstByteMs,
                                   "totalMs": totalMs, "file": out.path]
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
    }

    /// 16-bit mono PCM WAV.
    static func wav(pcm: Data, sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + pcm.count); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(pcm.count); d.append(pcm)
        return d
    }
}
