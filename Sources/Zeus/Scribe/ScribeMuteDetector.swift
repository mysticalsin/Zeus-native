import CoreAudio
import Foundation
import ZeusCore

/// Reads whether the person's microphone is muted, and keeps the history of those readings.
///
/// The person's own mute decides (see `ScribeMuteResolver`): the microphone is admitted while the default input
/// device isn't muted. Another app using the microphone (a call, a browser, an app Zeus can't identify) never
/// withholds it, and nothing stays set after that app lets go. An unreadable device or stale evidence is
/// `.unknown`, and the microphone is dropped before storage and ASR (system audio is unaffected).
/// Whether another app is using the microphone is still recorded per reading, for the "shared" note only.
///
/// Two consumers share one monitor:
/// - the capture drain asks `coverage(start:seconds:)` for each microphone sample interval, against the history
///   (so audio captured while muted or unknown can't be admitted later by fresh evidence), and calls
///   `refreshIfNeeded()` every tick, because a dropped interval never reaches the router;
/// - the router reads `currentMuteState()` (cached, TTL 1.5 s) as a second, independent gate.
final class ScribeMuteMonitor: @unchecked Sendable {
    let ingress: ScribeMicrophoneIngress
    private let lock = NSLock()
    // One replacement can bypass a stalled scan. Further refreshes wait for an actual free slot.
    private let reads = ScribeMuteReadScheduler()
    private let refreshInterval: TimeInterval
    private let timeToLive: TimeInterval
    private let refreshWatchdog: TimeInterval
    private var evidence: ScribeMuteEvidence?
    private var timeline: ScribeMuteTimeline

    init(
        refreshInterval: TimeInterval = 0.5,
        timeToLive: TimeInterval = ScribeMuteEvidence.timeToLive,
        refreshWatchdog: TimeInterval = 3
    ) {
        self.refreshInterval = refreshInterval
        self.timeToLive = timeToLive
        self.refreshWatchdog = refreshWatchdog
        self.timeline = ScribeMuteTimeline(timeToLive: timeToLive)
        self.ingress = ScribeMicrophoneIngress(timeToLive: timeToLive)
    }

    /// The cached reading (`.unknown` once it is older than the time to live). Also starts a refresh when due.
    func currentMuteState() -> ScribeMuteState {
        let now = ScribeHostClock.now()
        refreshIfNeeded(now: now)
        return ingress.currentState(now: now)
    }

    /// Whether a microphone sample interval (`ScribeHostClock` seconds) lies fully inside fresh unmuted evidence.
    /// A nil `start` (capture time unknown) is never admitted.
    func coverage(start: TimeInterval?, seconds: TimeInterval) -> ScribeMicCoverage {
        lock.withLock { timeline.coverage(start: start, seconds: seconds) }
    }

    /// Whether another app (a call app, a browser or any other process) was using the microphone for this
    /// interval, by the newest reading taken by then. Follows the readings: false again once that app lets go.
    func otherAppUsingMicrophone(start: TimeInterval?, seconds: TimeInterval) -> Bool {
        lock.withLock { timeline.callDetected(start: start, seconds: seconds) }
    }

    func refreshIfNeeded() {
        refreshIfNeeded(now: ScribeHostClock.now())
    }

    private func refreshIfNeeded(now: TimeInterval) {
        let takenAt = lock.withLock { evidence?.takenAt }
        reads.schedule(now: now, evidenceTakenAt: takenAt, interval: refreshInterval,
                       watchdog: refreshWatchdog) { [self] in
            let reading = Self.read()
            let finished = ScribeHostClock.now()
            ingress.record(state: reading.state, readStart: now, readEnd: finished)
            let shared = reading.callDetected || reading.externalInputDetected
            lock.withLock {
                // Every reading joins the history; a late one never replaces fresher cached evidence.
                timeline.record(state: reading.state, readStart: now, readEnd: finished, callDetected: shared)
                if (evidence?.takenAt ?? -.infinity) <= now {
                    evidence = ScribeMuteEvidence(state: reading.state, takenAt: now)
                }
            }
        }
    }

    /// One full reading. Runs off the audio thread. Admission comes from the device's mute switch alone; the scan
    /// only says whether another app is using the microphone (`callDetected`: a call app, a browser call window or
    /// doubt; `externalInputDetected`: any other process capturing input).
    static func read() -> (state: ScribeMuteState, callDetected: Bool, externalInputDetected: Bool) {
        let device = ScribeInputDevice.state()
        let scan = ScribeCallProbe.scan()
        let sample = ScribeMuteResolver.sample(device: device, callPresent: scan.callPresent)
        return (sample.admission, sample.callPresent, scan.externalInputDetected)
    }
}

/// The router's view of a monitor: the cached reading, per microphone frame.
final class ScribeMuteDetector: ScribeMicMuteSource, @unchecked Sendable {
    let monitor: ScribeMuteMonitor

    init(monitor: ScribeMuteMonitor = ScribeMuteMonitor()) {
        self.monitor = monitor
    }

    func currentMuteState() -> ScribeMuteState {
        monitor.currentMuteState()
    }
}

/// The default input device's own mute switch (kAudioDevicePropertyMute). Most devices don't have one.
enum ScribeInputDevice {
    /// `.muted` when every channel that has a mute switch is muted; `.noSwitch` when asking shows the device
    /// has none; `.unreadable` when the device can't be found or a mute switch it has can't be read.
    static func state() -> ScribeDeviceMute {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let device = ScribeCoreAudio.readObjectID(system, ScribeCoreAudio.address(kAudioHardwarePropertyDefaultInputDevice)) else {
            return .unreadable
        }
        var values: [UInt32] = []
        for element in AudioObjectPropertyElement(0)...2 {
            var address = ScribeCoreAudio.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput, element: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            guard let value = ScribeCoreAudio.readUInt32(device, address) else { return .unreadable }
            values.append(value)
        }
        guard !values.isEmpty else { return .noSwitch }
        return values.allSatisfy { $0 != 0 } ? .muted : .notMuted
    }
}
