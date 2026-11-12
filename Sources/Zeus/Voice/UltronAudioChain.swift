import AudioToolbox
import AVFoundation
import Foundation
import ZeusCore
import ZeusObjCGuard

/// The effect nodes for one AVAudioEngine: pitch down, EQ, a little radio-tower distortion, a short
/// comb for the metallic sheen, and a small room. All wet amounts come from `UltronEffectParameters`.
final class UltronEffectGraph {
    let timePitch = AVAudioUnitTimePitch()
    let eq = AVAudioUnitEQ(numberOfBands: 2)
    let distortion = AVAudioUnitDistortion()
    let comb = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()
    /// Peak limiter last in the chain, so the added warmth and edge can never clip the output.
    let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))

    var nodes: [AVAudioNode] { [timePitch, eq, distortion, comb, reverb, limiter] }

    init() {
        distortion.loadFactoryPreset(.speechRadioTower)
        distortion.preGain = -3
        reverb.loadFactoryPreset(.plate)
        // The highest overlap AVAudioUnitTimePitch offers: the cleanest pitch shift, at a little more CPU.
        timePitch.overlap = 32
        comb.lowPassCutoff = 8_000
        let low = eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 140
        low.bypass = false
        let high = eq.bands[1]
        high.filterType = .highShelf
        high.frequency = 4_500
        high.bypass = false
    }

    func attach(to engine: AVAudioEngine) {
        for node in nodes { engine.attach(node) }
    }

    /// Whether `format` can be handed to AVAudioEngine.connect. An invalid format makes AVFAudio raise an
    /// Objective-C exception (error -10868), which Swift cannot catch and which ends the process.
    nonisolated static func isConnectable(_ format: AVAudioFormat) -> Bool {
        format.sampleRate >= 8_000 && format.sampleRate <= 384_000
            && format.channelCount >= 1 && format.channelCount <= 8
            && format.commonFormat == .pcmFormatFloat32
    }

    /// Why the engine cannot take this chain right now, or nil when it can. Live engines need an output
    /// device with a sane format (a Mac without one, or mid device change, reports 0 Hz); manual
    /// (offline) rendering mode never touches hardware.
    static func unavailableReason(engine: AVAudioEngine, format: AVAudioFormat) -> String? {
        guard isConnectable(format) else {
            return "chain format \(format.sampleRate) Hz x \(format.channelCount) is not connectable"
        }
        if engine.isInManualRenderingMode { return nil }
        let output = engine.outputNode.outputFormat(forBus: 0)
        guard output.sampleRate > 0, output.channelCount > 0 else { return "no usable audio output device" }
        return nil
    }

    /// Wires source -> effects -> main mixer. Returns the reason it did not (nothing is connected then
    /// and the caller falls back to passthrough); it never reaches AVAudioEngine.connect with a format
    /// or device AVFAudio would reject. For offline use call `enableManualRenderingMode` first.
    @discardableResult
    func connect(from source: AVAudioNode, format: AVAudioFormat, engine: AVAudioEngine) -> String? {
        if let reason = Self.unavailableReason(engine: engine, format: format) { return reason }
        let destination = engine.mainMixerNode
        let chain = nodes
        // AVFAudio raises (not throws) when a unit refuses the format, for example -10868 on a Mac
        // whose output device vanished. Caught here, the partial wiring is undone and the caller
        // falls back to passthrough instead of the process ending.
        let failure = ZeusCatchObjCException {
            var previous = source
            for node in chain {
                engine.connect(previous, to: node, format: format)
                previous = node
            }
            engine.connect(previous, to: destination, format: format)
        }
        guard let failure else { return nil }
        for node in [source] + chain { engine.disconnectNodeOutput(node) }
        return "audio engine refused the chain (\(failure))"
    }

    func apply(_ p: UltronEffectParameters) {
        timePitch.pitch = p.pitchCents
        timePitch.bypass = p.pitchCents == 0
        eq.bands[0].gain = p.lowShelfGainDB
        eq.bands[1].gain = p.highShelfGainDB
        eq.globalGain = p.outputGainDB
        eq.bypass = p.lowShelfGainDB == 0 && p.highShelfGainDB == 0 && p.outputGainDB == 0
        distortion.wetDryMix = p.distortionWetPercent
        distortion.bypass = p.distortionWetPercent == 0
        comb.delayTime = p.combDelaySeconds
        comb.feedback = p.combFeedbackPercent
        comb.wetDryMix = p.combWetPercent
        comb.bypass = p.combWetPercent == 0
        reverb.wetDryMix = p.reverbWetPercent
        reverb.bypass = p.reverbWetPercent == 0
        // At 0 % every node is bypassed: the voice passes through untouched.
        limiter.bypass = p.isNeutral
    }
}

/// Thread-safe count of scheduled buffers. A completion from before `reset()` is ignored.
final class PendingBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var generation = 0

    var value: Int { lock.withLock { count } }
    func increment() -> Int { lock.withLock { count += 1; return generation } }
    func decrement(generation made: Int) { lock.withLock { if made == generation { count = max(0, count - 1) } } }
    func reset() { lock.withLock { generation += 1; count = 0 } }
}

/// Every engine's audio goes through here: one player node into the Ultron effect graph into the
/// speakers. Buffers of any format are converted to 24 kHz mono float first.
@MainActor
final class UltronAudioChain {
    nonisolated static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let graph = UltronEffectGraph()
    private let pending = PendingBuffers()
    private var carry: UInt8?
    private var wired = false
    private var configObserver: NSObjectProtocol?

    /// Silent runs (the owner's quiet mode, tests) go through the whole chain with the volume at zero.
    var muted = false { didSet { player.volume = muted ? 0 : 1 } }
    private(set) var firstScheduledAt: Date?

    init() {
        engine.attach(player)
        graph.attach(to: engine)
        graph.apply(UltronVoiceEffect.parameters)
        // A device change stops the engine and can change the output format; the next prepare()
        // re-validates the output and restarts. The wiring uses the fixed chain format, so it stays.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.player.stop(); self?.pending.reset() }
        }
    }

    isolated deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    var isPlaying: Bool { pending.value > 0 }

    /// Connects the graph on first use, once an output device exists (never at construction, so a Mac
    /// without one cannot crash the app). False, with a logged reason, when nothing can be wired; the
    /// caller then reports no audio output and the spoken line falls back to its other paths.
    private func wire() -> Bool {
        if wired { return true }
        if let reason = graph.connect(from: player, format: Self.format, engine: engine) {
            NSLog("[ZEUS] voice: effect graph not connected (%@); no audio output", reason)
            return false
        }
        wired = true
        return true
    }

    /// Applies the current Settings values and starts the engine. False when no output is available.
    @discardableResult
    func prepare() -> Bool {
        graph.apply(UltronVoiceEffect.parameters)
        guard wire() else { return false }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        return true
    }

    @discardableResult
    func schedule(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard buffer.frameLength > 0, let converted = Self.convert(buffer), prepare() else { return false }
        if firstScheduledAt == nil { firstScheduledAt = Date() }
        let generation = pending.increment()
        let counter = pending
        player.scheduleBuffer(converted) { counter.decrement(generation: generation) }
        if !player.isPlaying { player.play() }
        return true
    }

    /// 16-bit little-endian mono PCM at 24 kHz, as ElevenLabs and OpenAI stream it.
    @discardableResult
    func scheduleInt16(_ data: Data, fadeHead: Bool = false, fadeTail: Bool = false) -> Bool {
        var bytes = data
        if let carry { bytes.insert(carry, at: 0); self.carry = nil }
        if bytes.count % 2 == 1 { carry = bytes.removeLast() }
        guard let buffer = Self.buffer(fromInt16: bytes) else { return false }
        if fadeHead || fadeTail { Self.fadeEdges(buffer, head: fadeHead, tail: fadeTail) }
        // A sentence ends here: an odd leftover byte must not leak into the next sentence's first sample.
        if fadeTail { carry = nil }
        return schedule(buffer)
    }

    /// A few milliseconds of fade at a sentence's first or last buffer, only where that edge is not already
    /// near zero (`AudioEdge`), so consecutive sentences join without a click.
    nonisolated static func fadeEdges(_ buffer: AVAudioPCMBuffer, head: Bool, tail: Bool) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        var samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        AudioEdge.applyFades(&samples, sampleRate: buffer.format.sampleRate, head: head, tail: tail)
        for index in 0..<samples.count { channel[index] = samples[index] }
    }

    /// A WAV (or raw .pcm) file; the file is deleted afterwards.
    @discardableResult
    func scheduleFile(_ url: URL) -> Bool {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let buffer = Self.read(url) else { return false }
        return schedule(buffer)
    }

    func drained() async {
        while pending.value > 0, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(40)) }
    }

    func stop() {
        player.stop()
        pending.reset()
        carry = nil
        firstScheduledAt = nil
    }

    func resetFirstAudioClock() { firstScheduledAt = nil }

    // MARK: Pure helpers (no engine)

    nonisolated static func buffer(fromInt16 bytes: Data) -> AVAudioPCMBuffer? {
        let frames = bytes.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        bytes.withUnsafeBytes { raw in
            for index in 0..<frames {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                out[index] = Float(sample) / 32_768
            }
        }
        return buffer
    }

    nonisolated static func read(_ url: URL) -> AVAudioPCMBuffer? {
        if url.pathExtension.lowercased() == "pcm" {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return buffer(fromInt16: data)
        }
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// To 24 kHz mono float, the one format the chain is connected with.
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format.sampleRate == format.sampleRate, buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1_024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) let source = buffer
        nonisolated(unsafe) var supplied = false
        var failure: NSError?
        let status = converter.convert(to: out, error: &failure) { _, inputStatus in
            if supplied { inputStatus.pointee = .endOfStream; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return source
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }
}

/// The same chain run offline (no speakers): used by the silent preview and by tests.
enum UltronOfflineRender {
    /// The processed audio, with room for the reverb tail. Nil when the engine cannot render.
    nonisolated static func render(_ input: AVAudioPCMBuffer, parameters: UltronEffectParameters) -> AVAudioPCMBuffer? {
        guard let source = UltronAudioChain.convert(input) else { return nil }
        let format = UltronAudioChain.format
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let graph = UltronEffectGraph()
        engine.attach(player)
        graph.attach(to: engine)
        let chunk: AVAudioFrameCount = 4_096
        // Manual mode first: the engine then renders on its own clock and never asks for hardware, so
        // this runs on a machine with no audio device. Connecting before it would bind the mixer to
        // the (absent) output device's format.
        do { try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk) } catch {
            NSLog("[ZEUS] voice: offline render unavailable (%@); passthrough", error.localizedDescription)
            return source
        }
        if let reason = graph.connect(from: player, format: format, engine: engine) {
            NSLog("[ZEUS] voice: offline effect graph not connected (%@); passthrough", reason)
            return source
        }
        graph.apply(parameters)
        do { try engine.start() } catch {
            NSLog("[ZEUS] voice: offline engine did not start (%@); passthrough", error.localizedDescription)
            return source
        }
        defer { engine.stop() }
        player.scheduleBuffer(source)
        player.play()
        let total = Int(source.frameLength) + Int(format.sampleRate * 0.6)
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              let target = result.floatChannelData?[0] else { return nil }
        var written = 0
        while written < total {
            let want = AVAudioFrameCount(min(Int(chunk), total - written))
            let status: AVAudioEngineManualRenderingStatus
            do { status = try engine.renderOffline(want, to: scratch) } catch { return nil }
            guard status == .success || status == .insufficientDataFromInputNode,
                  let rendered = scratch.floatChannelData?[0] else { break }
            let count = Int(scratch.frameLength)
            for index in 0..<count { target[written + index] = rendered[index] }
            written += count
            if count == 0 { break }
        }
        result.frameLength = AVAudioFrameCount(written)
        return result
    }

    nonisolated static func writeProcessedCopy(from source: URL, to destination: URL, parameters: UltronEffectParameters) throws {
        guard let input = UltronAudioChain.read(source),
              let processed = render(input, parameters: parameters) else { throw CocoaError(.fileReadUnknown) }
        let out = try AVAudioFile(forWriting: destination, settings: UltronAudioChain.format.settings)
        try out.write(from: processed)
    }
}
