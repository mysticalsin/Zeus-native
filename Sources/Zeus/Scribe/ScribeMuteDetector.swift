import CoreAudio
import Foundation
import ZeusCore

/// Reads whether the person's microphone is muted, and keeps the history of those readings.
///
/// Positive evidence only (see `ScribeMuteResolver`): the microphone is admitted only when the default input
/// device isn't muted AND a complete scan finds no external microphone owner. Idle call apps and idle browsers
/// do not count as calls. Unidentified active inputs fail closed. There is no Accessibility reading and no per-app mute check: any call
/// means `.unknown`. Anything unreadable, incomplete or stale is `.unknown` too, and the microphone is dropped
/// before storage and ASR (system audio is unaffected).
///
/// Two consumers share one monitor:
/// - the capture drain asks `coverage(start:seconds:)` for each microphone sample interval, against the history
///   (so audio captured while muted or unknown can't be admitted later by fresh evidence), and calls
///   `refreshIfNeeded()` every tick, because a dropped interval never reaches the router;
/// - the router reads `currentMuteState()` (cached, TTL 1.5 s) as a second, independent gate.
final class ScribeMuteMonitor: @unchecked Sendable {
    let ingress: ScribeMicrophoneIngress
    private let lock = NSLock()
    // Concurrent: a read stalled in CoreAudio or the window list must not queue the watchdog's replacement read behind it.
    private let queue = DispatchQueue(label: "zeus.scribe.mute", qos: .userInitiated, attributes: .concurrent)
    private let refreshInterval: TimeInterval
    private let timeToLive: TimeInterval
    private let refreshWatchdog: TimeInterval
    private var evidence: ScribeMuteEvidence?
    private var timeline: ScribeMuteTimeline
    private var refreshStartedAt: TimeInterval?

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
        if ingress.hasExternalInput { return .dropped(.unknown) }
        return lock.withLock { timeline.coverage(start: start, seconds: seconds) }
    }

    /// Whether call evidence (a known call app or browser using the microphone) was present for this interval,
    /// even if the microphone was dropped as muted or unknown for another reason.
    func callDetected(start: TimeInterval?, seconds: TimeInterval) -> Bool {
        ingress.hasExternalInput || lock.withLock { timeline.callDetected(start: start, seconds: seconds) }
    }

    func refreshIfNeeded() {
        refreshIfNeeded(now: ScribeHostClock.now())
    }

    private func refreshIfNeeded(now: TimeInterval) {
        let start = lock.withLock { () -> Bool in
            let begin = ScribeMuteRefreshPolicy.shouldStart(
                now: now,
                evidenceTakenAt: evidence?.takenAt,
                inFlightSince: refreshStartedAt,
                interval: refreshInterval,
                watchdog: refreshWatchdog
            )
            if begin { refreshStartedAt = now }
            return begin
        }
        guard start else { return }
        queue.async { [self] in
            let reading = Self.read()
            let finished = ScribeHostClock.now()
            ingress.record(state: reading.state, readStart: now, readEnd: finished,
                           externalInputDetected: reading.externalInputDetected || reading.callDetected)
            lock.withLock {
                // Every reading joins the history; a late one never replaces fresher cached evidence.
                timeline.record(state: reading.state, readStart: now, readEnd: finished, callDetected: reading.callDetected)
                if (evidence?.takenAt ?? -.infinity) <= now {
                    evidence = ScribeMuteEvidence(state: reading.state, takenAt: now)
                }
                if refreshStartedAt == now { refreshStartedAt = nil }
            }
        }
    }

    /// One full reading. Runs off the audio thread. The scan always runs, so `callDetected` (call evidence:
    /// a microphone-using call app, browser call window or doubt) is collected whatever the device mute state and
    /// whether or not every process was readable. Admission rules are unchanged and still fail closed.
    static func read() -> (state: ScribeMuteState, callDetected: Bool, externalInputDetected: Bool) {
        let device = ScribeInputDevice.state()
        let scan = ScribeCallProbe.scan()
        let sample = ScribeMuteResolver.sample(device: device, scan: scan.inputScan, callPresent: scan.callPresent)
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
