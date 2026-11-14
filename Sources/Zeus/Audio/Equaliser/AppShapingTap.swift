import AudioToolbox
import CoreAudio
import Foundation
import ZeusCore

// One tap per shaped app, rendered to the current output in the same callback.
//
// Shape: a private tap of the app's processes (`mutedWhenTapped`), a private aggregate (UID `app.zeus.eq.<uuid>`) whose
// only sub-device is the default output, and one IOProc on a serial queue. The probe is the same build with an
// `unmuted` tap and an IOProc that only listens. Both turn every other input stream off, so a headset microphone is
// never opened.
//
// Teardown order: `AudioDeviceStop`, `AudioDeviceDestroyIOProcID`, `queue.sync {}`, destroy the aggregate, destroy the
// tap. The sync comes before the render state is released, so a callback still on the queue never meets freed memory.

/// Where each output channel gets its sound, in a form the render callback reads without allocating.
final class RenderChannelMap: @unchecked Sendable {
    static let silence: Int32 = -1
    static let average: Int32 = -2

    let count: Int
    let sources: UnsafeMutablePointer<Int32>

    init(_ map: [EqualiserChannelSource]) {
        count = max(1, map.count)
        sources = UnsafeMutablePointer<Int32>.allocate(capacity: count)
        sources.initialize(repeating: Self.silence, count: count)
        for (index, source) in map.enumerated() {
            switch source {
            case .silence: sources[index] = Self.silence
            case .average: sources[index] = Self.average
            case .tap(let channel): sources[index] = Int32(channel)
            }
        }
    }

    deinit { sources.deallocate() }
}

// MARK: - Render (realtime)

/// Callback and frame counters the render adds to and the main thread reads. Lock-free: one atomic add each.
/// `OSAtomicAdd64Barrier` is deprecated, but it is available on the macOS 14.2 target (Swift's `Atomic` needs macOS 15),
/// as in `ScribeSampleRing`; the warning is expected.
final class TapMeter: @unchecked Sendable {
    private let counters: UnsafeMutablePointer<Int64>

    init() {
        counters = UnsafeMutablePointer<Int64>.allocate(capacity: 3)
        counters.initialize(repeating: 0, count: 3)
    }

    deinit { counters.deallocate() }

    func countCallback() {
        _ = OSAtomicAdd64Barrier(1, counters)
    }

    func countFrames(_ frames: Int, zero: Int) {
        _ = OSAtomicAdd64Barrier(Int64(frames), counters + 1)
        _ = OSAtomicAdd64Barrier(Int64(zero), counters + 2)
    }

    var reading: ShapingMeterReading {
        ShapingMeterReading(
            callbacks: OSAtomicAdd64Barrier(0, counters),
            frames: OSAtomicAdd64Barrier(0, counters + 1),
            zeroFrames: OSAtomicAdd64Barrier(0, counters + 2))
    }
}

extension AppShapingTap {
    /// The IOProc block for a shaped tap. Built here, in a nonisolated function that never captures `self`, so it carries
    /// no main-actor isolation and cannot trap on the HAL thread.
    nonisolated static func makeRenderBlock(
        kernel: EqualiserKernel,
        scratch: RenderScratch,
        map: RenderChannelMap,
        tapIndex: Int,
        meter: TapMeter,
        sampleRate: Double
    ) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            AppShapingTap.render(
                input, output, kernel: kernel, scratch: scratch, map: map, tapIndex: tapIndex, meter: meter,
                sampleRate: sampleRate)
        }
    }

    /// The IOProc block for a listen-only probe: counts what the tap hears and writes nothing.
    nonisolated static func makeProbeBlock(meter: TapMeter, tapIndex: Int) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in
            AppShapingTap.listen(input, tapIndex: tapIndex, meter: meter)
        }
    }

    /// One callback: the tap's buffer in, the kernel, the output buffers out. Longer than the scratch runs in chunks.
    nonisolated private static func render(
        _ input: UnsafePointer<AudioBufferList>,
        _ output: UnsafeMutablePointer<AudioBufferList>,
        kernel: EqualiserKernel,
        scratch: RenderScratch,
        map: RenderChannelMap,
        tapIndex: Int,
        meter: TapMeter,
        sampleRate: Double
    ) {
        meter.countCallback()
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard tapIndex < inputs.count else { return }
        let tapBuffer = inputs[tapIndex]
        guard let source = tapBuffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let width = max(1, Int(tapBuffer.mNumberChannels))
        let frames = Int(tapBuffer.mDataByteSize) / (MemoryLayout<Float>.size * width)
        let live = min(width, scratch.maxChannels)
        let samples = scratch.samples

        var offset = 0
        while offset < frames {
            let chunk = min(scratch.maxFrames, frames - offset)
            var zeroFrames = 0
            for frame in 0..<chunk {
                var silent = true
                for channel in 0..<width {
                    let value = source[(offset + frame) * width + channel]
                    if value != 0 { silent = false }
                    if channel < live { samples[channel * chunk + frame] = value }
                }
                if silent { zeroFrames += 1 }
            }
            meter.countFrames(chunk, zero: zeroFrames)
            kernel.process(samples, frames: chunk, channels: live, interleaved: false, sampleRate: sampleRate)
            write(samples, chunk: chunk, live: live, offset: offset, into: outputs, map: map)
            offset += chunk
        }
    }

    /// Copies the processed chunk to the output channels the map names. Channels the map leaves silent stay zero.
    nonisolated private static func write(
        _ samples: UnsafeMutablePointer<Float>,
        chunk: Int,
        live: Int,
        offset: Int,
        into outputs: UnsafeMutableAudioBufferListPointer,
        map: RenderChannelMap
    ) {
        var global = 0
        for buffer in outputs {
            let width = max(1, Int(buffer.mNumberChannels))
            defer { global += width }
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let available = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * width) - offset
            let count = min(chunk, available)
            guard count > 0 else { continue }
            for channel in 0..<width {
                let slot = global + channel
                let route = slot < map.count ? map.sources[slot] : RenderChannelMap.silence
                if route == RenderChannelMap.silence { continue }
                for frame in 0..<count {
                    var value: Float = 0
                    if route == RenderChannelMap.average {
                        for tapChannel in 0..<live { value += samples[tapChannel * chunk + frame] }
                        value /= Float(live)
                    } else {
                        value = samples[min(Int(route), live - 1) * chunk + frame]
                    }
                    data[(offset + frame) * width + channel] = value
                }
            }
        }
    }

    nonisolated private static func listen(_ input: UnsafePointer<AudioBufferList>, tapIndex: Int, meter: TapMeter) {
        meter.countCallback()
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard tapIndex < inputs.count else { return }
        let tapBuffer = inputs[tapIndex]
        guard let source = tapBuffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let width = max(1, Int(tapBuffer.mNumberChannels))
        let frames = Int(tapBuffer.mDataByteSize) / (MemoryLayout<Float>.size * width)
        var zeroFrames = 0
        for frame in 0..<frames {
            var silent = true
            for channel in 0..<width where source[frame * width + channel] != 0 { silent = false }
            if silent { zeroFrames += 1 }
        }
        meter.countFrames(frames, zero: zeroFrames)
    }
}

// MARK: - End of render

/// A tap that is built, running and owned by the controller. Both the shaped tap and the listen-only probe are this
/// class; `mode` picks the mute behaviour and the IOProc.
@MainActor
final class AppShapingTap: ShapingTapHandle, ShapingProbeHandle {
    enum Mode { case shaped, probe }

    private let request: ShapingRequest
    private let mode: Mode
    private let meterCounters = TapMeter()
    private let queue = DispatchQueue(label: "zeus.equaliser.tap", qos: .userInteractive)

    private var kernel: EqualiserKernel?
    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private(set) var sampleRate = 48_000.0

    var meter: ShapingMeterReading { meterCounters.reading }

    private init(request: ShapingRequest, mode: Mode) {
        self.request = request
        self.mode = mode
    }

    /// Builds everything, or destroys what it built and throws.
    static func build(_ request: ShapingRequest, mode: Mode) throws -> AppShapingTap {
        let tap = AppShapingTap(request: request, mode: mode)
        do {
            try tap.assemble()
        } catch {
            tap.stop()
            throw error
        }
        return tap
    }

    private func assemble() throws {
        let objectIDs = request.group.objectIDs.map { AudioObjectID($0) }
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        tapDescription.name = "Zeus EQ \(request.displayName)"
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = mode == .shaped ? .mutedWhenTapped : .unmuted
        self.tapDescription = tapDescription
        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr else { throw ShapingFailure.system(stage: "tap", status: status) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = ScribeCoreAudio.address(kAudioTapPropertyFormat)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { throw ShapingFailure.system(stage: "format", status: status) }
        let tapChannels = Int(asbd.mChannelsPerFrame)
        let tapFormat = EqualiserStreamFormat(
            isLinearPCM: asbd.mFormatID == kAudioFormatLinearPCM,
            isFloat: asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            bitsPerChannel: Int(asbd.mBitsPerChannel),
            sampleRate: asbd.mSampleRate,
            channelCount: tapChannels)
        if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
        if mode == .shaped {
            if case .unsupported(let reason) = EqualiserFormat.verdict(
                tap: tapFormat, output: request.output.format, outputIsAggregate: request.output.isAggregate) {
                throw ShapingFailure.unsupported(reason: reason)
            }
            if tapChannels > 1, asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
                throw ShapingFailure.unsupported(reason: "the tap is not interleaved")
            }
        }

        guard let device = Self.deviceID(forUID: request.output.uid) else { throw ShapingFailure.noOutput }
        let deviceInputStreams = Self.streamCount(device, scope: kAudioDevicePropertyScopeInput)
        let uid = ZeusAudioDevices.equaliserUIDPrefix + UUID().uuidString
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Zeus EQ \(request.displayName)",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceMainSubDeviceKey: request.output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: request.output.uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: false,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw ShapingFailure.system(stage: "aggregate", status: status) }

        let aggregateInputStreams = Self.streamCount(aggregateID, scope: kAudioDevicePropertyScopeInput)
        guard let tapIndex = EqualiserRouting.tapStreamIndex(
            deviceInputStreams: deviceInputStreams, aggregateInputStreams: aggregateInputStreams, tapStreams: 1)
        else { throw ShapingFailure.system(stage: "stream index", status: -1) }

        let block: AudioDeviceIOBlock
        switch mode {
        case .shaped:
            let maxFrames = Self.largestBuffer(device)
            let kernel = EqualiserKernel(maxChannels: 2, maxFrames: maxFrames, bandCount: EqualiserParameters.bandCount)
            kernel.reset()
            kernel.mailbox.post(request.parameters)
            self.kernel = kernel
            let map = RenderChannelMap(EqualiserRouting.channelMap(
                tapChannels: tapChannels, outputChannels: request.output.format.channelCount,
                stereoPair: (left: request.output.stereoLeft, right: request.output.stereoRight)))
            block = Self.makeRenderBlock(
                kernel: kernel, scratch: RenderScratch(maxChannels: 2, maxFrames: maxFrames), map: map,
                tapIndex: tapIndex, meter: meterCounters, sampleRate: sampleRate)
        case .probe:
            block = Self.makeProbeBlock(meter: meterCounters, tapIndex: tapIndex)
        }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, block)
        guard status == noErr, let procID else { throw ShapingFailure.system(stage: "io", status: status) }

        status = Self.keepOnlyTapStream(aggregateID, procID: procID, streams: aggregateInputStreams, keep: tapIndex)
        guard status == noErr else { throw ShapingFailure.system(stage: "stream usage", status: status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw ShapingFailure.system(stage: "start", status: status) }

        let frameSize = ScribeCoreAudio.readUInt32(aggregateID, ScribeCoreAudio.address(kAudioDevicePropertyBufferFrameSize)) ?? 0
        NSLog("[ZEUS] equaliser: %@ built, buffer %u frames at %.0f Hz",
              mode == .shaped ? "tap" : "probe", frameSize, sampleRate)
    }

    // MARK: ShapingTapHandle

    func post(_ parameters: EqualiserParameters) {
        kernel?.mailbox.post(parameters)
    }

    func retarget(objectIDs: [UInt32]) -> Bool {
        guard let tapDescription, tapID != kAudioObjectUnknown else { return false }
        tapDescription.processes = objectIDs.map { AudioObjectID($0) }
        var address = ScribeCoreAudio.address(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(tapDescription)
        return AudioObjectSetPropertyData(
            tapID, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &reference) == noErr
    }

    /// Stop the device, destroy the IOProc, wait for a callback still on the queue, then destroy the aggregate and
    /// the tap. Never call this from the tap's own queue.
    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            queue.sync {}
            AudioHardwareDestroyAggregateDevice(aggregateID)
        } else {
            queue.sync {}
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        kernel = nil
        tapDescription = nil
    }

    // MARK: Core Audio helpers

    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = ScribeCoreAudio.address(kAudioHardwarePropertyTranslateUIDToDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var qualifier = uid as CFString
        let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func streamCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = ScribeCoreAudio.address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioObjectID>.size
    }

    /// The largest buffer the output may use, so the scratch fits any callback. Longer ones run in chunks.
    private static func largestBuffer(_ device: AudioObjectID) -> Int {
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var address = ScribeCoreAudio.address(kAudioDevicePropertyBufferFrameSizeRange)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &range) == noErr, range.mMaximum > 0 else {
            return 4_096
        }
        return min(max(Int(range.mMaximum), 1_024), 16_384)
    }

    /// Reads the IOProc's stream usage, then turns off every input stream but the tap's. A device microphone is never
    /// opened. Any failed read or write is an error, and the caller destroys what it built.
    private static func keepOnlyTapStream(
        _ device: AudioObjectID, procID: AudioDeviceIOProcID, streams: Int, keep: Int
    ) -> OSStatus {
        var address = ScribeCoreAudio.address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioDevicePropertyScopeInput)
        let header = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
        let bytes = max(header + MemoryLayout<UInt32>.size * streams, MemoryLayout<AudioHardwareIOProcStreamUsage>.size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeRawPointer?.self), as: UnsafeRawPointer?.self)

        var size = UInt32(bytes)
        var status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw)
        guard status == noErr else { return status }
        let numberOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mNumberStreams) ?? 8
        guard Int(raw.load(fromByteOffset: numberOffset, as: UInt32.self)) == streams else { return -1 }
        for index in 0..<streams {
            raw.storeBytes(of: index == keep ? 1 : 0, toByteOffset: header + MemoryLayout<UInt32>.size * index, as: UInt32.self)
        }
        status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(bytes), raw)
        return status
    }
}

// MARK: - Factory

/// The live factory. Only `AppDelegate` builds it; tests give the controller a fake.
@MainActor
final class LiveShapingTapFactory: ShapingTapFactory {
    func makeTap(_ request: ShapingRequest) throws -> any ShapingTapHandle {
        try AppShapingTap.build(request, mode: .shaped)
    }

    func makeProbe(_ request: ShapingRequest) throws -> any ShapingProbeHandle {
        try AppShapingTap.build(request, mode: .probe)
    }

    /// Destroys any aggregate whose UID carries the equaliser prefix. After a crash the private ones should already be
    /// gone with the process; this is the check.
    func sweepLeftovers() -> Int {
        var destroyed = 0
        for device in AudioProcessMonitor.readObjectIDs(
            AudioObjectID(kAudioObjectSystemObject), ScribeCoreAudio.address(kAudioHardwarePropertyDevices)) {
            guard let uid = ScribeCoreAudio.readString(device, ScribeCoreAudio.address(kAudioDevicePropertyDeviceUID)),
                  uid.hasPrefix(ZeusAudioDevices.equaliserUIDPrefix) else { continue }
            if AudioHardwareDestroyAggregateDevice(device) == noErr { destroyed += 1 }
        }
        return destroyed
    }
}
