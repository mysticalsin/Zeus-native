import AudioToolbox
import CoreAudio
import Foundation
import ZeusCore

/// A CoreAudio process tap of everything the Mac is playing (macOS 14.2+), read as mono samples.
/// It listens only; the sound still plays normally (`muteBehavior = .unmuted`). Starting it is what
/// raises macOS's "System Audio Recording" prompt, so it is only started when a person asked.
final class SystemAudioTap: @unchecked Sendable {
    enum Failure: Error { case tap(OSStatus), format(OSStatus), device(OSStatus), start(OSStatus) }

    let ring = SampleRing()
    private(set) var sampleRate: Double = 48_000
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "zeus.audio.tap", qos: .userInteractive)

    var isRunning: Bool { procID != nil }

    func start() throws {
        guard procID == nil else { return }
        do { try build() } catch { stop(); throw error }
    }

    private func build() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Zeus spectrum"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Failure.tap(status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { throw Failure.format(status) }
        if format.mSampleRate > 0 { sampleRate = format.mSampleRate }

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Zeus spectrum",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw Failure.device(status) }

        let ring = self.ring
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            Self.mixDown(input, into: ring)
        }
        guard status == noErr else { throw Failure.start(status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw Failure.start(status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    /// Interleaved or planar float frames averaged to mono. Runs on the audio queue, so no allocation.
    private static func mixDown(_ input: UnsafePointer<AudioBufferList>, into ring: SampleRing) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let base = first.mData?.assumingMemoryBound(to: Float.self) else { return }
        let channels = Int(first.mNumberChannels)
        if buffers.count == 1 && channels <= 1 {
            ring.write(base, count: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        } else if buffers.count == 1 {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            withUnsafeTemporaryAllocation(of: Float.self, capacity: frames) { mono in
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += base[f * channels + c] }
                    mono[f] = sum / Float(channels)
                }
                ring.write(mono.baseAddress!, count: frames)
            }
        } else {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            withUnsafeTemporaryAllocation(of: Float.self, capacity: frames) { mono in
                for f in 0..<frames {
                    var sum: Float = 0
                    var count: Float = 0
                    for buffer in buffers {
                        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), f < Int(buffer.mDataByteSize) / 4 else { continue }
                        sum += data[f]; count += 1
                    }
                    mono[f] = count > 0 ? sum / count : 0
                }
                ring.write(mono.baseAddress!, count: frames)
            }
        }
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw Failure.device(status) }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw Failure.device(status) }
        return uid.takeRetainedValue() as String
    }
}

/// Tap, ring, FFT and smoothing on one timer. Everything here is off the main thread; it hands
/// finished frames to `onFrame`. `close()` tears the tap and the timer down completely.
final class SpectrumPipeline: @unchecked Sendable {
    private let tap = SystemAudioTap()
    private let queue = DispatchQueue(label: "zeus.audio.fft", qos: .userInteractive)
    private let lock = NSLock()
    private var analyzer: SpectrumAnalyzer?
    private var timer: DispatchSourceTimer?
    private var fps: Double = 0
    private var previous = [Float](repeating: 0, count: SpectrumMath.bandCount)
    private var last = Date()
    private var _gain: Float = 1
    private var _onFrame: (@Sendable ([Float], Float) -> Void)?

    var gain: Float {
        get { lock.withLock { _gain } }
        set { lock.withLock { _gain = newValue } }
    }
    var onFrame: (@Sendable ([Float], Float) -> Void)? {
        get { lock.withLock { _onFrame } }
        set { lock.withLock { _onFrame = newValue } }
    }

    func open() throws {
        try tap.start()
        analyzer = SpectrumAnalyzer(sampleRate: tap.sampleRate)
    }

    func run(fps wanted: Double) {
        queue.async { [self] in
            if timer != nil, abs(fps - wanted) < 0.5 { return }
            timer?.cancel()
            fps = wanted
            last = Date()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 1 / wanted, leeway: .milliseconds(2))
            source.setEventHandler { [weak self] in self?.frame() }
            timer = source
            source.resume()
        }
    }

    private func frame() {
        guard let analyzer else { return }
        let now = Date()
        let dt = max(0.001, now.timeIntervalSince(last))
        last = now
        let g = gain
        let raw = analyzer.levels(samples: tap.ring.latest(SpectrumMath.fftSize)).map { min(1, $0 * g) }
        previous = SpectrumMath.smooth(previous: previous, target: raw, dt: dt)
        let mean = previous.prefix(20).reduce(0, +) / 20
        onFrame?(previous, mean)
    }

    func close() {
        onFrame = nil
        queue.sync {
            timer?.cancel()
            timer = nil
        }
        tap.stop()
    }
}
