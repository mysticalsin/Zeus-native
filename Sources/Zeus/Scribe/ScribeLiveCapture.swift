import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import ZeusCore

/// A reason capture could not start or had to stop, worded for the person.
struct ScribeCaptureFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Things the capture run reports besides the lifecycle events. They share the controller's ordered input
/// stream with those events, so an issue always arrives before the `captureEnded` that follows it.
enum ScribeCaptureIssue: Sendable {
    /// Audio was lost before it reached the drain (the capture ring overflowed, or a write lost a lock race).
    case audioLost(seconds: Double, source: ScribeAudioSource)
    /// The microphone verdict changed: `.unmuted` (admitted), `.muted` or `.unknown` (dropped).
    case microphone(ScribeMuteState)
    /// Microphone audio withheld, in seconds, while the verdict was `state` (`.muted` or `.unknown`).
    case microphoneWithheld(ScribeMuteState, seconds: Double)
    /// Whether the microphone is currently dropped because a call was detected (reported on change only).
    case microphoneExcludedByCall(Bool)
}

/// A capture provider that also reports `ScribeCaptureIssue`s.
protocol ScribeIssueReportingCaptureProvider: ScribeCaptureProvider {
    func start(
        session: ScribeSessionID,
        frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
        events: @escaping @Sendable (ScribeCaptureEvent) -> Void,
        issues: @escaping @Sendable (ScribeCaptureIssue) -> Void
    )
}

/// Real meeting capture: the microphone (AVAudioEngine) and everything the Mac plays (a CoreAudio process
/// tap), both as 16 kHz mono Float frames. Nothing starts until `start(session:)`; that is also what makes
/// macOS show its Microphone and System Audio Recording prompts. Audio is never written to disk here.
///
/// Microphone audio is admitted per sample interval, against the shared `ScribeMuteMonitor`'s history of
/// readings, before it is handed on: an interval not fully covered by fresh unmuted evidence is dropped here.
final class ScribeLiveCaptureProvider: ScribeIssueReportingCaptureProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var current: ScribeCaptureRun?
    private let monitor: ScribeMuteMonitor

    /// `monitor` should be the one the router's `ScribeMuteDetector` reads. The default is a private one, so a
    /// provider built without it still fails closed on its own evidence.
    init(monitor: ScribeMuteMonitor = ScribeMuteMonitor()) {
        self.monitor = monitor
    }

    /// Why the microphone can't be used right now (denied in System Settings), or nil. Never prompts.
    static var microphoneIssue: String? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied:
            return "Microphone access is off for Zeus. Turn it on in System Settings → Privacy & Security → Microphone."
        case .restricted:
            return "Microphone access is restricted on this Mac."
        default:
            return nil
        }
    }

    func start(
        session: ScribeSessionID,
        frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
        events: @escaping @Sendable (ScribeCaptureEvent) -> Void
    ) {
        start(session: session, frames: frames, events: events, issues: { _ in })
    }

    func start(
        session: ScribeSessionID,
        frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
        events: @escaping @Sendable (ScribeCaptureEvent) -> Void,
        issues: @escaping @Sendable (ScribeCaptureIssue) -> Void
    ) {
        let run = ScribeCaptureRun(session: session, monitor: monitor, frames: frames, events: events, issues: issues)
        let previous = lock.withLock { () -> ScribeCaptureRun? in
            let old = current
            current = run
            return old
        }
        previous?.abandon()
        run.begin()
    }

    func stop(session: ScribeSessionID) {
        let run = lock.withLock { () -> ScribeCaptureRun? in
            guard let run = current, run.session == session else { return nil }
            return run
        }
        run?.end()
    }
}

/// What a system-audio producer offers the capture run. The only implementation needs macOS 14.2.
private protocol ScribeSystemSource: AnyObject {
    var ring: ScribeSampleRing? { get }
    var sampleRate: Double { get }
    func start() throws
    /// Waits for any callback still running, so nothing is written after it returns.
    func synchronize()
    func stop()
}

/// One session's capture. Device work runs on `queue` (serial), so start, failure and stop can never
/// interleave. The audio callbacks do nothing but copy samples into preallocated rings; `worker` (serial)
/// drains the rings, resamples, stamps and hands frames on, so routing and chunking never run on an audio
/// thread. Frames reach `frames` only between the acknowledgement and the stop.
private final class ScribeCaptureRun: @unchecked Sendable {
    /// One source's ring and resampler. The resampler is touched only on `worker`.
    private final class Pipe: @unchecked Sendable {
        let ring: ScribeSampleRing
        let inputRate: Double
        var resampler: ScribeResampler
        /// Where the next block should start if capture was contiguous; nil after a reset.
        var expectedStart: TimeInterval?

        init(ring: ScribeSampleRing, inputRate: Double) {
            self.ring = ring
            self.inputRate = inputRate
            self.resampler = ScribeResampler(inputRate: inputRate)
        }

        func resetResampler() {
            resampler = ScribeResampler(inputRate: inputRate)
            expectedStart = nil
        }
    }

    let session: ScribeSessionID
    private let monitor: ScribeMuteMonitor
    private let frames: @Sendable (ScribeAudioFrame) -> Void
    private let events: @Sendable (ScribeCaptureEvent) -> Void
    private let issues: @Sendable (ScribeCaptureIssue) -> Void
    private let queue = DispatchQueue(label: "zeus.scribe.capture", qos: .userInitiated)
    private let worker = DispatchQueue(label: "zeus.scribe.drain", qos: .userInitiated)

    /// Guards the flags below (never taken on an audio thread).
    private let lock = NSLock()
    private var stopRequested = false
    private var delivering = false
    private var finished = false

    // Touched only on `queue` (setup, teardown).
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var systemSource: (any ScribeSystemSource)?

    // Touched only on `worker`.
    /// Host-clock boundary after both sources have started. Earlier buffered samples are never delivered.
    private var captureStartedAt: TimeInterval?
    private var micPipe: Pipe?
    private var systemPipe: Pipe?
    private var micSequence: UInt64 = 0
    private var systemSequence: UInt64 = 0
    private var timer: DispatchSourceTimer?
    /// The microphone verdict last reported, and the audio withheld under it since.
    private var micVerdict: ScribeMuteState?
    private var micWithheldSeconds = 0.0
    /// Whether the last report said the microphone is dropped because of a call.
    private var micCallExcluded = false

    /// Ring size in seconds of audio, and how often the worker drains. A stall longer than the ring drops
    /// (and counts) audio rather than growing without bound.
    private static let ringSeconds = 10.0
    private static let drainInterval = 50

    init(
        session: ScribeSessionID,
        monitor: ScribeMuteMonitor,
        frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
        events: @escaping @Sendable (ScribeCaptureEvent) -> Void,
        issues: @escaping @Sendable (ScribeCaptureIssue) -> Void
    ) {
        self.session = session
        self.monitor = monitor
        self.frames = frames
        self.events = events
        self.issues = issues
    }

    // MARK: Lifecycle

    func begin() {
        monitor.ingress.begin(session: session)
        monitor.refreshIfNeeded()
        queue.async { [self] in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                startDevices()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    self.queue.async {
                        if granted {
                            self.startDevices()
                        } else {
                            self.fail(ScribeCaptureFailure(message: ScribeLiveCaptureProvider.microphoneIssue
                                ?? "Microphone access was declined. Turn it on in System Settings → Privacy & Security → Microphone."))
                        }
                    }
                }
            default:
                fail(ScribeCaptureFailure(message: ScribeLiveCaptureProvider.microphoneIssue
                    ?? "Microphone access isn't available."))
            }
        }
    }

    /// Follows `ScribeShutdown.order`: stop the producers and wait for them, then drain what they still
    /// held, then close delivery, and only then report `captureEnded`. No frame follows it.
    func end() {
        // Revoke startup synchronously, even while setup is waiting on an OS permission dialog.
        // Producer teardown remains serialized on `queue`.
        lock.withLock { stopRequested = true }
        monitor.ingress.revoke(session: session)
        queue.async { [self] in
            let alreadyFinished = lock.withLock { () -> Bool in
                stopRequested = true
                let done = finished
                finished = true
                return done
            }
            guard !alreadyFinished else { return }
            for step in ScribeShutdown.order {
                switch step {
                case .stopProducers:
                    stopMic()
                    systemSource?.stop()
                case .synchronizeProducers:
                    systemSource?.synchronize()
                case .drainRemaining:
                    worker.sync {
                        timer?.cancel()
                        timer = nil
                        drainAll()
                        reportMicrophoneWithheld()
                    }
                case .closeDelivery:
                    // Behind the final drain on the same queue, so no frame is in flight past this point.
                    worker.sync { lock.withLock { delivering = false } }
                case .emitEnded:
                    systemSource = nil
                    worker.sync {
                        micPipe = nil
                        systemPipe = nil
                    }
                    events(.captureEnded(session))
                }
            }
        }
    }

    /// A replaced session: tear everything down and say nothing (the controller already moved on).
    func abandon() {
        monitor.ingress.revoke(session: session)
        lock.withLock {
            stopRequested = true
            delivering = false
        }
        queue.async { [self] in
            lock.withLock {
                stopRequested = true
                finished = true
                delivering = false
            }
            teardown()
        }
    }

    private func startDevices() {
        guard !lock.withLock({ stopRequested }) else { return }
        do {
            try startMic()
            try startSystem()
        } catch {
            fail(error)
            return
        }
        // Both taps are running: only now is it honest to say capture started. Establish the boundary and
        // report it before starting the drain; a microphone buffer collected while the system-audio prompt
        // was open must not become part of the meeting when the first drain runs.
        let acknowledged = worker.sync { () -> Bool in
            let mayDeliver = lock.withLock { () -> Bool in
                guard !stopRequested else { return false }
                delivering = true
                return true
            }
            guard mayDeliver else { return false }
            let startedAt = ScribeHostClock.now()
            guard monitor.ingress.acknowledge(session: session, at: startedAt) else { return false }
            captureStartedAt = startedAt
            // The worker is serial and its timer has not started, so no delivery can overtake this
            // callback. Invoke it outside the lock to avoid reentrant lifecycle callbacks deadlocking.
            events(.captureAcknowledged(session))
            return true
        }
        guard acknowledged else { teardown(); return }
        startDrainTimer()
    }

    /// A start or runtime failure: stop everything, deliver nothing more, report once.
    private func fail(_ error: any Error) {
        monitor.ingress.revoke(session: session)
        let first = lock.withLock { () -> Bool in
            stopRequested = true
            delivering = false
            let done = finished
            finished = true
            return !done
        }
        teardown()
        if first { events(.failed(session, error)) }
    }

    /// Stops the producers, then clears the worker's state after anything it was running. Delivery is already
    /// off when this runs from `fail` or `abandon`, so leftover samples are discarded, not delivered.
    private func teardown() {
        stopMic()
        systemSource?.stop()
        systemSource = nil
        worker.sync {
            timer?.cancel()
            timer = nil
            micPipe = nil
            systemPipe = nil
        }
    }

    // MARK: Microphone

    private func startMic() throws {
        stopMic()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw ScribeCaptureFailure(message: "No microphone input is available. Check the input device in System Settings → Sound.")
        }
        let ring = ScribeSampleRing(
            capacityFrames: Int(format.sampleRate * Self.ringSeconds),
            channels: Int(format.channelCount),
            sampleRate: format.sampleRate
        )
        let channels = ring.channels
        let interleaved = format.isInterleaved
        let ingress = monitor.ingress
        let captureSession = session
        let sampleRate = format.sampleRate
        // Realtime: obtain a nonblocking admission permit BEFORE reading sample memory or copying to the
        // app ring. Unknown/muted/stale/startup/stopped buffers are never copied. The permit spans the write
        // so revocation cannot race it. OS-owned buffers and unreported OS mute changes remain outside this gate.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
            let count = Int(buffer.frameLength)
            // The time the first frame was captured. An invalid host time stays unknown (nil): callback time is
            // not capture time, so the drain drops such a block rather than guess.
            let start = ScribeMicStamp.captureStart(hostTimeValid: when.isHostTimeValid, hostTime: when.hostTime)
            ingress.admit(session: captureSession, start: start, duration: Double(count) / sampleRate,
                          now: ScribeHostClock.now()) {
                guard let data = buffer.floatChannelData else { return false }
                if interleaved {
                    let base = UnsafePointer(data[0])
                    return ring.write(frames: count, at: start) { frame, channel in base[frame * channels + channel] }
                } else {
                    return ring.write(frames: count, at: start) { frame, channel in data[channel][frame] }
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw ScribeCaptureFailure(message: "Zeus couldn't start the microphone: \(error.localizedDescription)")
        }
        self.engine = engine
        // The previous engine (if any) was stopped above, so its ring is quiet: deliver what it held, then switch.
        let pipe = Pipe(ring: ring, inputRate: format.sampleRate)
        worker.sync {
            if let old = micPipe { drain(old, source: .microphone) }
            micPipe = pipe
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [self] _ in
            queue.async { [self] in micConfigurationChanged() }
        }
    }

    private func stopMic() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        self.engine = nil
    }

    /// The input device changed or the engine stopped (headphones, a sleep). Rebuild the microphone on the
    /// new format; if that fails, end the capture with a reason rather than keep listening to nothing.
    private func micConfigurationChanged() {
        guard !lock.withLock({ stopRequested }) else { return }
        do {
            try startMic()
        } catch {
            fail(error)
        }
    }

    // MARK: System audio

    /// Package.swift targets macOS 14.2, which has the process-tap APIs, so there is no older-system fallback.
    private func startSystem() throws {
        let source = ScribeSystemTap()
        try source.start()
        systemSource = source
        guard let ring = source.ring else { return }
        let pipe = Pipe(ring: ring, inputRate: source.sampleRate)
        worker.sync { systemPipe = pipe }
    }

    // MARK: Drain (worker queue)

    private func startDrainTimer() {
        let source = DispatchSource.makeTimerSource(queue: worker)
        source.schedule(
            deadline: .now() + .milliseconds(Self.drainInterval),
            repeating: .milliseconds(Self.drainInterval),
            leeway: .milliseconds(5)
        )
        source.setEventHandler { [self] in drainAll() }
        worker.sync { timer = source }
        source.resume()
    }

    /// Worker queue only.
    private func drainAll() {
        if let pipe = micPipe { drain(pipe, source: .microphone) }
        if let pipe = systemPipe { drain(pipe, source: .system) }
    }

    /// Worker queue only: ring -> blocks with capture times -> (microphone: admission) -> mono -> 16 kHz -> frame.
    private func drain(_ pipe: Pipe, source: ScribeAudioSource) {
        // The microphone's evidence is refreshed from here: an interval that is dropped never reaches the router,
        // which would otherwise be the only thing asking for a fresh reading.
        if source == .microphone {
            monitor.refreshIfNeeded()
            let report = monitor.ingress.takeReport(now: ScribeHostClock.now())
            if report.withheldSeconds > 0 { pipe.resetResampler() }
            let coverage: ScribeMicCoverage = report.state == .unmuted ? .admitted : .dropped(report.state)
            noteMicrophone(coverage, start: nil, seconds: report.withheldSeconds)
        }
        let width = pipe.ring.channels
        while true {
            let drained = pipe.ring.drainBlocks(maxFrames: 16_384)
            if drained.samples.isEmpty { break }
            var offset = 0
            for block in drained.blocks {
                let count = block.frames * width
                guard count > 0, offset + count <= drained.samples.count else { continue }
                process(block, interleaved: drained.samples[offset..<(offset + count)], pipe: pipe, source: source)
                offset += count
            }
        }
        let lost = pipe.ring.takeDroppedFrames()
        if lost > 0, lock.withLock({ delivering }) {
            issues(.audioLost(seconds: Double(lost) / pipe.ring.sampleRate, source: source))
        }
    }

    /// Worker queue only. One contiguous run of captured frames.
    private func process(_ block: ScribeSampleRing.Block, interleaved: ArraySlice<Float>, pipe: Pipe, source: ScribeAudioSource) {
        let seconds = Double(block.frames) / pipe.ring.sampleRate
        let start = block.start
        guard ScribeCaptureWindow.admits(start: start, duration: seconds, acknowledgedAt: captureStartedAt) else {
            pipe.resetResampler()
            // Samples from startup are deliberately excluded. Missing host timestamps are unexpected and
            // could hide further loss, so report those instead of inventing a capture time.
            if start == nil, lock.withLock({ delivering }) {
                issues(.audioLost(seconds: seconds, source: source))
            }
            return
        }
        if source == .microphone {
            // Admit this interval only if fresh unmuted evidence covers all of it; no capture time, no admission.
            let coverage = monitor.coverage(start: start, seconds: seconds)
            noteMicrophone(coverage, start: start, seconds: seconds)
            guard case .admitted = coverage else {
                pipe.resetResampler()
                return
            }
        }
        guard let start else { return }
        // A gap in capture (a dropped write) must not be bridged by the resampler's carried samples.
        if let expected = pipe.expectedStart, abs(start - expected) > 0.1 { pipe.resetResampler() }
        pipe.expectedStart = start + seconds
        let mono = interleaved.withUnsafeBufferPointer {
            ScribeAudioMath.monoMix(interleaved: $0, channels: pipe.ring.channels)
        }
        emit(source, pipe.resampler.process(mono), start: start)
    }

    /// Worker queue only. Reports a change of microphone verdict, and the audio withheld under the old one.
    private func noteMicrophone(_ coverage: ScribeMicCoverage, start: TimeInterval?, seconds: Double) {
        // Before the acknowledgement nothing is delivered, so nothing is withheld or reported either.
        guard lock.withLock({ delivering }) else { return }
        let verdict: ScribeMuteState
        switch coverage {
        case .admitted: verdict = .unmuted
        case .dropped(let state): verdict = state
        }
        if verdict != micVerdict {
            reportMicrophoneWithheld()
            micVerdict = verdict
            if lock.withLock({ delivering }) { issues(.microphone(verdict)) }
        }
        if verdict != .unmuted { micWithheldSeconds += seconds }
        let excluded = verdict != .unmuted && monitor.callDetected(start: start, seconds: seconds)
        if excluded != micCallExcluded {
            micCallExcluded = excluded
            issues(.microphoneExcludedByCall(excluded))
        }
    }

    private func reportMicrophoneWithheld() {
        defer { micWithheldSeconds = 0 }
        guard micWithheldSeconds > 0, let verdict = micVerdict, verdict != .unmuted,
              lock.withLock({ delivering }) else { return }
        issues(.microphoneWithheld(verdict, seconds: micWithheldSeconds))
    }

    // MARK: Delivery

    /// Worker queue only. `start` is the capture time (host clock) of the first sample.
    private func emit(_ source: ScribeAudioSource, _ samples: [Float], start: TimeInterval) {
        guard !samples.isEmpty, let captureStartedAt, lock.withLock({ delivering }) else { return }
        let sequence: UInt64
        switch source {
        case .microphone:
            sequence = micSequence
            micSequence += 1
        case .system:
            sequence = systemSequence
            systemSequence += 1
        }
        frames(ScribeAudioFrame(
            session: session,
            source: source,
            sequence: sequence,
            hostTime: max(0, start - captureStartedAt),
            sampleCount: samples.count,
            payload: ScribePCM.encode(samples)
        ))
    }
}

/// A CoreAudio process tap of everything the Mac plays (macOS 14.2+), copied as interleaved Float samples at
/// the device rate into a `ScribeSampleRing`. It listens only; the sound still plays normally. Modelled on
/// `SystemAudioTap.build()`, but with a draining ring instead of a "latest samples" one, because transcription
/// needs every sample once. The IO callback only copies into the ring.
private final class ScribeSystemTap: ScribeSystemSource, @unchecked Sendable {
    struct Failure: LocalizedError {
        let stage: String
        let status: OSStatus

        var errorDescription: String? {
            "Zeus couldn't record the Mac's audio (\(stage), error \(status)). "
                + "Allow Zeus under System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        }
    }

    private(set) var sampleRate: Double = 48_000
    private(set) var ring: ScribeSampleRing?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "zeus.scribe.tap", qos: .userInteractive)

    private static let ringSeconds = 10.0

    func start() throws {
        guard procID == nil else { return }
        do { try build() } catch { stop(); throw error }
    }

    /// Runs after the IO proc was destroyed: waits for a callback block still on `queue`.
    func synchronize() {
        queue.sync {}
    }

    private func build() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Zeus Scribe"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Failure(stage: "tap", status: status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else { throw Failure(stage: "format", status: status) }
        if format.mSampleRate > 0 { sampleRate = format.mSampleRate }
        let tapRing = ScribeSampleRing(
            capacityFrames: Int(sampleRate * Self.ringSeconds),
            channels: max(1, min(8, Int(format.mChannelsPerFrame))),
            sampleRate: sampleRate
        )
        ring = tapRing

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Zeus Scribe",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw Failure(stage: "device", status: status) }

        // Realtime: the block captures only the ring and the rate, never `self`.
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, inputTime, _, _ in
            let hostTime: UInt64? = inputTime.pointee.mFlags.contains(.hostTimeValid) ? inputTime.pointee.mHostTime : nil
            Self.copy(input, hostTime: hostTime, into: tapRing)
        }
        guard status == noErr else { throw Failure(stage: "io", status: status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw Failure(stage: "start", status: status) }
    }

    /// Stops the IO proc and tears everything down, then waits for a callback block still queued.
    /// Never call this from the tap's own queue (it waits on it).
    func stop() {
        teardownHandles()
        queue.sync {}
    }

    private func teardownHandles() {
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

    deinit { teardownHandles() }

    /// Realtime: interleaved or planar float frames copied into the ring as they are. No allocation, no
    /// blocking; mono mixing happens on the worker.
    private static func copy(_ input: UnsafePointer<AudioBufferList>, hostTime: UInt64?, into ring: ScribeSampleRing) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first else { return }
        if buffers.count == 1 {
            guard let base = first.mData?.assumingMemoryBound(to: Float.self) else { return }
            let width = max(1, Int(first.mNumberChannels))
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * width)
            let start = hostTime.map { ScribeHostClock.seconds(hostTime: $0) }
            ring.write(frames: frames, at: start) { frame, channel in base[frame * width + (channel < width ? channel : 0)] }
        } else {
            var frames = Int.max
            for buffer in buffers { frames = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) }
            guard frames > 0, frames != Int.max else { return }
            let planes = buffers.count
            let start = hostTime.map { ScribeHostClock.seconds(hostTime: $0) }
            ring.write(frames: frames, at: start) { frame, channel in
                guard let data = buffers[channel < planes ? channel : 0].mData else { return 0 }
                return data.assumingMemoryBound(to: Float.self)[frame]
            }
        }
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw Failure(stage: "output device", status: status) }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw Failure(stage: "output uid", status: status) }
        return uid.takeRetainedValue() as String
    }
}
