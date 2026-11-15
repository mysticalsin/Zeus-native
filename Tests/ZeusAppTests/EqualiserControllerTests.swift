import Foundation
import Observation
import Testing
import ZeusCore
@testable import Zeus

// The controller carries out what the lifecycle reducer asks for. Everything below runs against fakes: a fake tap
// factory, a fake monitor, a fake claim and a fake clock. No test creates a tap, builds a device or opens a listener.

// MARK: - Fakes

@MainActor
private final class FakeMonitor: EqualiserMonitoring {
    var onEvent: (@MainActor (EqualiserMonitorEvent) -> Void)?
    var reading = EqualiserReading()
    var alive: Set<Int32> = []
    private(set) var started = false

    func start() { started = true }
    func stop() { started = false }
    func read() -> EqualiserReading { reading }
    func pidIsAlive(_ pid: Int32) -> Bool { alive.contains(pid) }

    /// What a Core Audio listener would do. Nothing happens while the monitor is stopped.
    func fire(_ event: EqualiserMonitorEvent) {
        guard started else { return }
        onEvent?(event)
    }
}

@MainActor
private final class FakeTap: ShapingTapHandle {
    let request: ShapingRequest
    var sampleRate = 48_000.0
    /// Each read of the meter counts one more callback of one second of sound.
    var autoBeat = true
    var allZeros = false
    var retargetResult = true
    private(set) var posts: [EqualiserParameters] = []
    private(set) var retargets: [[UInt32]] = []
    private(set) var stopped = false
    private var counts = ShapingMeterReading(callbacks: 0, frames: 0, zeroFrames: 0)
    private let onStop: (String) -> Void

    init(request: ShapingRequest, onStop: @escaping (String) -> Void) {
        self.request = request
        self.onStop = onStop
    }

    var meter: ShapingMeterReading {
        if autoBeat {
            counts.callbacks += 1
            counts.frames += 48_000
            if allZeros { counts.zeroFrames += 48_000 }
        }
        return counts
    }

    func post(_ parameters: EqualiserParameters) { posts.append(parameters) }

    func retarget(objectIDs: [UInt32]) -> Bool {
        retargets.append(objectIDs)
        return retargetResult
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        onStop("stop-tap:\(request.displayName)")
    }
}

@MainActor
private final class FakeProbe: ShapingProbeHandle {
    let request: ShapingRequest
    var meter = ShapingMeterReading(callbacks: 0, frames: 0, zeroFrames: 0)
    private(set) var stopped = false
    private let onStop: (String) -> Void

    init(request: ShapingRequest, onStop: @escaping (String) -> Void) {
        self.request = request
        self.onStop = onStop
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        onStop("stop-probe:\(request.displayName)")
    }
}

@MainActor
private final class FakeFactory: ShapingTapFactory {
    var log: [String] = []
    var taps: [FakeTap] = []
    var probes: [FakeProbe] = []
    var tapError: ShapingFailure?
    var probeError: ShapingFailure?
    private(set) var tapAttempts = 0
    private(set) var sweeps = 0

    func makeTap(_ request: ShapingRequest) throws -> any ShapingTapHandle {
        tapAttempts += 1
        if let tapError { throw tapError }
        let tap = FakeTap(request: request) { [unowned self] in self.log.append($0) }
        taps.append(tap)
        log.append("tap:\(request.displayName)")
        return tap
    }

    func makeProbe(_ request: ShapingRequest) throws -> any ShapingProbeHandle {
        if let probeError { throw probeError }
        let probe = FakeProbe(request: request) { [unowned self] in self.log.append($0) }
        probes.append(probe)
        log.append("probe:\(request.displayName)")
        return probe
    }

    func sweepLeftovers() -> Int {
        sweeps += 1
        return 0
    }

    var liveTaps: [FakeTap] { taps.filter { !$0.stopped } }
    var liveProbes: [FakeProbe] { probes.filter { !$0.stopped } }
}

@MainActor
private final class FakeClaim: EqualiserClaiming {
    var available = true
    private(set) var held = false

    func take() -> Bool {
        if available { held = true }
        return available
    }

    func release() { held = false }
}

@MainActor
private final class FakeScheduler: EqualiserScheduling {
    private struct Item {
        let id: Int
        var due: TimeInterval
        let interval: TimeInterval?
        let action: @MainActor () -> Void
    }

    private(set) var now: TimeInterval = 1_000
    private var items: [Item] = []
    private var nextID = 0

    var pendingCount: Int { items.count }

    func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer {
        add(seconds, nil, action)
    }

    func every(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer {
        add(seconds, seconds, action)
    }

    private func add(_ seconds: TimeInterval, _ interval: TimeInterval?, _ action: @escaping @MainActor () -> Void) -> EqualiserTimer {
        nextID += 1
        let id = nextID
        items.append(Item(id: id, due: now + seconds, interval: interval, action: action))
        return EqualiserTimer { [weak self] in self?.items.removeAll { $0.id == id } }
    }

    /// Runs every timer that falls due, in order, then leaves the clock at the end of the span.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = items.filter({ $0.due <= target }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            now = max(now, next.due)
            if let interval = next.interval, let index = items.firstIndex(where: { $0.id == next.id }) {
                items[index].due = next.due + interval
            } else {
                items.removeAll { $0.id == next.id }
            }
            next.action()
        }
        now = target
    }
}

// MARK: - Fixtures

private let ownPID: Int32 = 100
private let output = EqualiserOutputFacts(
    uid: "out", format: .float32(sampleRate: 48_000, channelCount: 2), isAggregate: false)

private let bassMusic = AppSoundSettings(
    bundleID: "com.apple.Music", displayName: "Music", gainsDB: [6, 4, 0, 0, 0, 0, 0, 0, 0, 0],
    volume: 1, shapes: true, lastUsed: Date(timeIntervalSince1970: 10))

private func process(
    _ id: UInt32, pid: Int32, bundle: String, output isOutput: Bool = true, input: Bool? = false
) -> AudioProcessFacts {
    AudioProcessFacts(
        objectID: id, pid: pid, bundleID: bundle, runningOutput: isOutput, runningInput: input, devices: ["out"])
}

private func musicReading(playing: Bool = true, extra: [AudioProcessFacts] = []) -> EqualiserReading {
    EqualiserReading(
        processes: [process(1, pid: 200, bundle: "com.apple.Music", output: playing)] + extra,
        runningAppBundleIDs: ["com.apple.Music"],
        names: ["com.apple.Music": "Music", "us.zoom.xos": "zoom.us"],
        output: output)
}

@MainActor
private final class Rig {
    let defaults: UserDefaults
    let factory = FakeFactory()
    let monitor = FakeMonitor()
    let claim = FakeClaim()
    let scheduler = FakeScheduler()
    var captures = false
    var permission: AudioCapturePermission = .allowed
    private(set) var allowedCount = 0
    var controller: EqualiserController!

    init(book: [AppSoundSettings] = [bassMusic], playing: Bool = true, preload: ((UserDefaults) -> Void)? = nil) {
        let suite = "zeus.equaliser.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var saved = AppSoundBook()
        for entry in book { saved.add(entry) }
        if !book.isEmpty { defaults.set(try! saved.encode(), forKey: AppSoundBook.storageKey) }
        preload?(defaults)
        monitor.reading = musicReading(playing: playing)
        controller = EqualiserController(
            defaults: defaults, factory: factory, monitor: monitor, claim: claim, scheduler: scheduler,
            ownBundleID: "app.zeus.test", ownPID: ownPID,
            zeusCaptures: { [unowned self] in self.captures },
            onProvenAllowed: { [unowned self] in self.allowedCount += 1 },
            capturePermission: { [unowned self] in self.permission })
    }

    /// The listen-only probe hears sound, and the next poll ends it.
    func heardProbe() {
        factory.liveProbes.last!.meter = ShapingMeterReading(callbacks: 4, frames: 4_800, zeroFrames: 0)
        scheduler.advance(by: 0.25)
    }

    func startRunning() {
        controller.setSwitch(true)
        heardProbe()
    }

    func play(_ playing: Bool, extra: [AudioProcessFacts] = []) {
        monitor.reading = musicReading(playing: playing, extra: extra)
    }
}

@Observable
private final class CaptureFlag {
    var on = false
}

private let zoomOnTheMicrophone = process(5, pid: 300, bundle: "us.zoom.xos", output: false, input: true)

// MARK: - Suite

@MainActor
@Suite("Equaliser controller", .serialized)
struct EqualiserControllerTests {
    // MARK: Probe, then tap

    @Test func aPlayingAppIsProbedThenTapped() {
        let rig = Rig()
        rig.controller.setSwitch(true)
        #expect(rig.factory.log == ["probe:Music"])
        #expect(rig.factory.taps.isEmpty)
        rig.heardProbe()
        #expect(rig.factory.log == ["probe:Music", "stop-probe:Music", "tap:Music"])
        #expect(rig.factory.taps[0].request.parameters == bassMusic.parameters)
        #expect(rig.factory.taps[0].request.group.objectIDs == [1])
        #expect(rig.allowedCount == 1)
        #expect(rig.controller.status.line == "Shaping 1 app.")
        #expect(rig.monitor.started)
    }

    @Test func aNeutralOrUnsavedAppIsNeverProbedOrTapped() {
        var flat = bassMusic
        flat.gainsDB = [Double](repeating: 0, count: 10)
        let rig = Rig(book: [flat])
        rig.controller.setSwitch(true)
        #expect(rig.factory.log.isEmpty)
        #expect(rig.controller.state == .waitingForSound)
        rig.scheduler.advance(by: 60)
        #expect(rig.factory.log.isEmpty)
    }

    @Test func aSilentProbeNeverMutesAndTwoStopTheEngine() {
        let rig = Rig()
        rig.controller.setSwitch(true)
        rig.factory.liveProbes.last!.meter = ShapingMeterReading(callbacks: 100, frames: 240_000, zeroFrames: 240_000)
        rig.scheduler.advance(by: 5)
        #expect(rig.factory.probes.count == 2)
        rig.factory.liveProbes.last!.meter = ShapingMeterReading(callbacks: 100, frames: 240_000, zeroFrames: 240_000)
        rig.scheduler.advance(by: 5)
        #expect(rig.controller.state == .stopped(.silentWhilePlaying(app: "Music")))
        #expect(rig.factory.taps.isEmpty)
        #expect(rig.factory.liveProbes.isEmpty)
        #expect(rig.allowedCount == 0)
    }

    @Test func noMutedTapIsBuiltBeforeAHeardProbeEvenWithAllowedStored() {
        let rig = Rig()
        rig.permission = .allowed
        rig.controller.setSwitch(true)
        #expect(rig.factory.tapAttempts == 0)
        #expect(rig.factory.log == ["probe:Music"])
        // Zeros keep every app unmuted: the first silent probe ends and the next one starts.
        rig.factory.liveProbes.last!.meter = ShapingMeterReading(callbacks: 100, frames: 240_000, zeroFrames: 240_000)
        rig.scheduler.advance(by: 5)
        #expect(rig.factory.tapAttempts == 0)
        #expect(rig.allowedCount == 0)
        rig.heardProbe()
        #expect(rig.factory.tapAttempts == 1)
        #expect(rig.factory.log.suffix(2) == ["stop-probe:Music", "tap:Music"])
        #expect(rig.allowedCount == 1)
    }

    @Test func theFirstProbeAfterNotAskedListensThirtySeconds() {
        let rig = Rig()
        rig.permission = .notAsked
        rig.controller.setSwitch(true)
        rig.scheduler.advance(by: 29.75)
        #expect(rig.factory.liveProbes.count == 1)
        rig.scheduler.advance(by: 0.5)
        #expect(rig.factory.liveProbes.isEmpty)
        #expect(rig.factory.tapAttempts == 0)
    }

    @Test func aRefusalOnRecordWaitsForTryAgainAtLaunch() {
        let rig = Rig()
        rig.permission = .refused
        rig.controller.launch(switchOn: true)
        #expect(rig.controller.state == .stopped(.silentWhilePlaying(app: "Music")))
        #expect(rig.controller.status.stop == .silentWhilePlaying(app: "Music"))
        #expect(rig.factory.log == [])
        rig.monitor.fire(.processes)
        rig.scheduler.advance(by: 30)
        #expect(rig.factory.log == [])
        #expect(rig.allowedCount == 0)
        rig.controller.tryAgain()
        #expect(rig.factory.log == ["probe:Music"])
        rig.heardProbe()
        #expect(rig.factory.tapAttempts == 1)
        #expect(rig.allowedCount == 1)
    }

    @Test func theOwnersSwitchProbesEvenWithARefusalOnRecord() {
        let rig = Rig()
        rig.permission = .refused
        rig.controller.setSwitch(true)
        #expect(rig.factory.log == ["probe:Music"])
        #expect(rig.factory.tapAttempts == 0)
    }

    @Test func aProbeThatSawNoFramesIsInconclusiveAndDoesNotStop() {
        let rig = Rig()
        rig.controller.setSwitch(true)
        rig.scheduler.advance(by: 5)
        #expect(rig.factory.taps.isEmpty)
        #expect(rig.factory.liveProbes.isEmpty)
        if case .stopped = rig.controller.state { Issue.record("one probe with no frames must not stop") }
    }

    @Test func aProbeAppThatStopsPlayingIsDestroyed() {
        let rig = Rig()
        rig.controller.setSwitch(true)
        rig.play(false)
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveProbes.isEmpty)
        #expect(rig.factory.taps.isEmpty)
    }

    @Test func aProbeCreationRefusalAtTheStartStopsEverything() {
        let rig = Rig()
        rig.factory.probeError = .system(stage: "tap", status: -50)
        rig.controller.setSwitch(true)
        #expect(rig.controller.state == .stopped(.startFailed(status: -50)))
        #expect(rig.factory.taps.isEmpty)
    }

    // MARK: Pauses

    @Test func aCallStartingDestroysTheTapFirst() {
        let rig = Rig()
        rig.startRunning()
        #expect(rig.factory.liveTaps.count == 1)
        rig.monitor.reading = musicReading(extra: [zoomOnTheMicrophone])
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(rig.factory.log.last == "stop-tap:Music")
        #expect(rig.controller.status.line == "Paused while a call app uses the microphone.")
        rig.monitor.reading = musicReading()
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveProbes.count == 1)
    }

    @Test func oneUnreadableReadDoesNotPauseButTwoDo() {
        let rig = Rig()
        rig.startRunning()
        let unreadable = process(5, pid: 300, bundle: "us.zoom.xos", output: false, input: nil)
        rig.monitor.alive = [300]
        rig.monitor.reading = musicReading(extra: [unreadable])
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveTaps.count == 1)
        rig.monitor.reading = musicReading(extra: [process(5, pid: 300, bundle: "us.zoom.xos", output: false, input: false)])
        rig.scheduler.advance(by: 0.25)
        #expect(rig.factory.liveTaps.count == 1)

        rig.monitor.reading = musicReading(extra: [unreadable])
        rig.monitor.fire(.processes)
        rig.scheduler.advance(by: 0.25)
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(rig.controller.state == .paused(.callRecording))
    }

    @Test func zeusCapturingPausesAndEndingResumes() {
        let rig = Rig()
        rig.startRunning()
        rig.captures = true
        rig.controller.zeusCaptureMayHaveChanged()
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(rig.controller.status.line == "Paused while Zeus records or captions this Mac's sound.")
        rig.captures = false
        rig.controller.zeusCaptureMayHaveChanged()
        #expect(rig.factory.liveProbes.count == 1)
    }

    @Test func theCaptureObservationReachesTheController() async throws {
        let flag = CaptureFlag()
        let rig = Rig()
        let controller = EqualiserController(
            defaults: rig.defaults, factory: rig.factory, monitor: rig.monitor, claim: rig.claim,
            scheduler: rig.scheduler, ownBundleID: "app.zeus.test", ownPID: ownPID,
            zeusCaptures: { flag.on })
        controller.setSwitch(true)
        flag.on = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.state == .paused(.zeusCaptures))
        controller.setSwitch(false)
    }

    @Test func sleepTearsDownAndWakeRebuildsTwoSecondsLater() {
        let rig = Rig()
        rig.startRunning()
        rig.controller.systemWillSleep()
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(rig.controller.status.line == "Paused while this Mac sleeps.")
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveProbes.isEmpty)

        rig.controller.systemDidWake()
        rig.scheduler.advance(by: 1.9)
        #expect(rig.factory.liveProbes.isEmpty)
        rig.scheduler.advance(by: 0.2)
        #expect(rig.factory.liveProbes.count == 1)
    }

    @Test func aHeldClaimBuildsNothingAndResumesWhenItFrees() {
        let rig = Rig()
        rig.claim.available = false
        rig.controller.setSwitch(true)
        #expect(rig.factory.log.isEmpty)
        #expect(rig.controller.status.line == "Paused: another copy of Zeus is shaping sound.")
        rig.claim.available = true
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveProbes.count == 1)
        #expect(rig.claim.held)
    }

    @Test func anUnsupportedFormatAtBuildPausesInsteadOfMuting() {
        let rig = Rig()
        rig.factory.tapError = .unsupported(reason: "the sample rates differ")
        rig.startRunning()
        #expect(rig.controller.state == .paused(.unsupportedOutput(reason: "the sample rates differ")))
        #expect(rig.controller.status.line == "Paused: this output is not supported.")
        rig.monitor.fire(.processes)
        #expect(rig.factory.tapAttempts == 1)

        rig.factory.tapError = nil
        rig.monitor.fire(.format)
        #expect(rig.factory.liveProbes.count == 1)
    }

    @Test func anAggregateOutputIsUnsupportedWithoutAnyBuild() {
        let rig = Rig()
        var reading = musicReading()
        reading.output?.isAggregate = true
        rig.monitor.reading = reading
        rig.controller.setSwitch(true)
        #expect(rig.factory.log.isEmpty)
        #expect(rig.controller.status.line == "Paused: this output is not supported.")
    }

    // MARK: Output changes

    @Test func deviceRemovalDestroysTheTapThenRebuildsWithoutAProbe() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.log.removeAll()
        rig.monitor.fire(.deviceGone)
        #expect(rig.factory.log == ["stop-tap:Music", "tap:Music"])
        #expect(rig.factory.probes.count == 1)
    }

    @Test func outputAndFormatChangesRebuildTheSameWay() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.log.removeAll()
        rig.monitor.fire(.output)
        rig.monitor.fire(.format)
        #expect(rig.factory.log == ["stop-tap:Music", "tap:Music", "stop-tap:Music", "tap:Music"])
    }

    // MARK: Failures and the watchdog

    @Test func theFifthBuildFailureStopsThatApp() {
        let rig = Rig()
        rig.factory.tapError = .system(stage: "start", status: -1)
        rig.startRunning()
        #expect(rig.factory.tapAttempts == 1)
        rig.scheduler.advance(by: 0.5)
        #expect(rig.factory.tapAttempts == 2)
        rig.scheduler.advance(by: 1)
        #expect(rig.factory.tapAttempts == 3)
        rig.scheduler.advance(by: 2)
        #expect(rig.factory.tapAttempts == 4)
        rig.scheduler.advance(by: 4)
        #expect(rig.factory.tapAttempts == 5)
        #expect(rig.controller.state == .stopped(.repeatedFailures(app: "Music")))
        #expect(rig.controller.status.line == "Stopped shaping Music after repeated errors. It plays normally.")
        rig.scheduler.advance(by: 60)
        #expect(rig.factory.tapAttempts == 5)
    }

    @Test func aStalledCallbackDestroysTheTapThenRebuilds() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.taps[0].autoBeat = false
        rig.factory.log.removeAll()
        rig.scheduler.advance(by: 2)
        #expect(rig.factory.log == ["stop-tap:Music"])
        rig.scheduler.advance(by: 0.5)
        #expect(rig.factory.log == ["stop-tap:Music", "tap:Music"])
    }

    @Test func aTapThatBeatsIsLeftAlone() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.log.removeAll()
        rig.scheduler.advance(by: 20)
        #expect(rig.factory.log.isEmpty)
    }

    @Test func zerosUnderAMutedTapDestroyTheTapBeforeAnythingElseThenProbe() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.taps[0].allZeros = true
        rig.factory.log.removeAll()
        rig.scheduler.advance(by: 2)
        #expect(rig.factory.log == ["stop-tap:Music", "probe:Music"])
    }

    @Test func exactZerosFromAnAppThatIsNotPlayingAreFine() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.taps[0].allZeros = true
        rig.play(false)
        rig.monitor.fire(.processes)
        rig.factory.log.removeAll()
        rig.scheduler.advance(by: 10)
        #expect(rig.factory.log.isEmpty)
    }

    // MARK: Helpers joining

    @Test func aHelperJoiningRetargetsTheLiveTap() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.log.removeAll()
        rig.play(true, extra: [process(2, pid: 201, bundle: "com.apple.Music.helper")])
        rig.monitor.fire(.processes)
        #expect(rig.factory.taps[0].retargets == [[1, 2]])
        rig.scheduler.advance(by: 2.5)
        #expect(rig.factory.log.isEmpty)
    }

    @Test func aFailedRetargetRebuildsTheTap() {
        let rig = Rig()
        rig.startRunning()
        rig.factory.taps[0].retargetResult = false
        rig.factory.log.removeAll()
        rig.play(true, extra: [process(2, pid: 201, bundle: "com.apple.Music.helper")])
        rig.monitor.fire(.processes)
        #expect(rig.factory.log == ["stop-tap:Music", "tap:Music"])
        #expect(rig.factory.taps[1].request.group.objectIDs == [1, 2])
    }

    @Test func noCallbackWithinTwoSecondsOfARetargetRebuildsTheTap() {
        let rig = Rig()
        rig.startRunning()
        rig.play(true, extra: [process(2, pid: 201, bundle: "com.apple.Music.helper")])
        rig.monitor.fire(.processes)
        rig.factory.taps[0].autoBeat = false
        rig.scheduler.advance(by: 3)
        #expect(rig.factory.taps.count >= 2)
        #expect(rig.factory.taps[0].stopped)
    }

    // MARK: Idle, settings, quit

    @Test func anIdleTapIsRemovedThirtySecondsAfterOutputStops() {
        let rig = Rig()
        rig.startRunning()
        rig.play(false)
        rig.monitor.fire(.processes)
        rig.scheduler.advance(by: 29)
        #expect(rig.factory.liveTaps.count == 1)
        rig.scheduler.advance(by: 1)
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(rig.controller.status.line == "On. Nothing to shape right now.")
    }

    @Test func playingAgainBeforeTheIdleTimeKeepsTheTap() {
        let rig = Rig()
        rig.startRunning()
        rig.play(false)
        rig.monitor.fire(.processes)
        rig.scheduler.advance(by: 20)
        rig.play(true)
        rig.monitor.fire(.processes)
        rig.scheduler.advance(by: 30)
        #expect(rig.factory.liveTaps.count == 1)
    }

    @Test func aQuitAppLosesItsTapAtOnce() {
        let rig = Rig()
        rig.startRunning()
        rig.monitor.reading = EqualiserReading(output: output)
        rig.monitor.fire(.processes)
        #expect(rig.factory.liveTaps.isEmpty)
    }

    @Test func settingsPostToTheLiveTapAndANeutralAppLosesIt() {
        let rig = Rig()
        rig.startRunning()
        var quieter = bassMusic
        quieter.volume = 0.5
        rig.controller.update(quieter)
        #expect(rig.factory.taps[0].posts.last?.volume == 0.5)
        #expect(rig.factory.liveTaps.count == 1)

        var off = bassMusic
        off.shapes = false
        rig.controller.update(off)
        #expect(rig.factory.liveTaps.isEmpty)

        let saved = AppSoundBook.decode(rig.defaults.data(forKey: AppSoundBook.storageKey)).book
        #expect(saved.settings(for: "com.apple.Music")?.shapes == false)
    }

    @Test func forgettingAnAppRemovesItsTapAndItsSettings() {
        let rig = Rig()
        rig.startRunning()
        rig.controller.forget(bundleID: "com.apple.Music")
        #expect(rig.factory.liveTaps.isEmpty)
        let saved = AppSoundBook.decode(rig.defaults.data(forKey: AppSoundBook.storageKey)).book
        #expect(saved.settings(for: "com.apple.Music") == nil)
    }

    @Test func switchingOffLeavesNoTapProbeListenerOrTimer() {
        let rig = Rig()
        rig.startRunning()
        rig.controller.setSwitch(false)
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(rig.factory.liveProbes.isEmpty)
        #expect(!rig.monitor.started)
        #expect(rig.scheduler.pendingCount == 0)
        #expect(!rig.claim.held)
        #expect(rig.controller.state == .off)
        #expect(rig.controller.status.line == "Off. No app is tapped.")
    }

    @Test func switchingOffDuringAProbeDestroysTheProbe() {
        let rig = Rig()
        rig.controller.setSwitch(true)
        #expect(rig.factory.liveProbes.count == 1)
        rig.controller.setSwitch(false)
        #expect(rig.factory.liveProbes.isEmpty)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func quittingDestroysEverythingAndReleasesTheClaim() {
        let rig = Rig()
        rig.startRunning()
        rig.controller.shutdown()
        #expect(rig.factory.liveTaps.isEmpty)
        #expect(!rig.claim.held)
        #expect(!rig.monitor.started)
        #expect(rig.defaults.object(forKey: EqualiserController.shapingSinceKey) == nil)
    }

    @Test func tryAgainAfterAStopStartsOver() {
        let rig = Rig()
        rig.factory.probeError = .system(stage: "tap", status: -50)
        rig.controller.setSwitch(true)
        #expect(rig.controller.state == .stopped(.startFailed(status: -50)))
        rig.factory.probeError = nil
        rig.controller.tryAgain()
        #expect(rig.factory.liveProbes.count == 1)
    }

    // MARK: Markers and the store

    @Test func theMarkerIsWrittenAtTheFirstMutedBuildAndRemovedOnTeardown() {
        let rig = Rig()
        rig.controller.setSwitch(true)
        #expect(rig.defaults.object(forKey: EqualiserController.shapingSinceKey) == nil)
        rig.heardProbe()
        #expect(rig.defaults.object(forKey: EqualiserController.shapingSinceKey) != nil)
        rig.controller.setSwitch(false)
        #expect(rig.defaults.object(forKey: EqualiserController.shapingSinceKey) == nil)
    }

    @Test func launchSweepsLeftoversAndReportsAPreviousUnexpectedStopOnce() {
        let rig = Rig { $0.set(Date().timeIntervalSince1970, forKey: EqualiserController.shapingSinceKey) }
        rig.controller.launch()
        #expect(rig.factory.sweeps == 1)
        #expect(rig.controller.launchNotice == "Zeus stopped while shaping sound. If an app is silent, quit and reopen it.")
        #expect(rig.defaults.object(forKey: EqualiserController.shapingSinceKey) == nil)
        rig.controller.acknowledgeLaunchNotice()
        #expect(rig.controller.launchNotice == nil)
    }

    @Test func aCleanLaunchHasNoNoticeButStillSweeps() {
        let rig = Rig()
        rig.controller.launch()
        #expect(rig.factory.sweeps == 1)
        #expect(rig.controller.launchNotice == nil)
    }

    @Test func aLaunchThatFindsTheSwitchOnStartsListeningAndProbesAPlayingApp() {
        let rig = Rig()
        rig.controller.launch(switchOn: true)
        #expect(rig.monitor.started)
        #expect(rig.factory.log == ["probe:Music"])
    }

    @Test func aLaunchThatFindsTheSwitchOffListensToNothing() {
        let rig = Rig()
        rig.controller.launch(switchOn: false)
        rig.controller.launch()
        #expect(!rig.monitor.started)
        #expect(rig.factory.log.isEmpty)
    }

    @Test func aLaunchWithTheSwitchOnStillSweepsAndReportsAPreviousStop() {
        let rig = Rig { $0.set(Date().timeIntervalSince1970, forKey: EqualiserController.shapingSinceKey) }
        rig.controller.launch(switchOn: true)
        #expect(rig.factory.sweeps == 1)
        #expect(rig.controller.launchNotice != nil)
        #expect(rig.monitor.started)
    }

    @Test func aFailedDecodeKeepsTheRawCopyAndShapesNothing() {
        let junk = Data("not a book".utf8)
        let rig = Rig(book: []) { $0.set(junk, forKey: AppSoundBook.storageKey) }
        #expect(rig.defaults.data(forKey: AppSoundBook.unreadableKey) == junk)
        #expect(rig.controller.savedSettingsUnreadable)
        rig.controller.setSwitch(true)
        #expect(rig.factory.log.isEmpty)

        rig.controller.update(bassMusic)
        #expect(rig.defaults.data(forKey: AppSoundBook.unreadableKey) == junk)
        #expect(AppSoundBook.decode(rig.defaults.data(forKey: AppSoundBook.storageKey)).failed == false)
    }

    @Test func aRefusedAdditionToAFullBookSaysSoAndChangesNothing() {
        var apps: [AppSoundSettings] = []
        for index in 0..<AppSoundBook.maxApps {
            apps.append(AppSoundSettings(
                bundleID: "app.test.\(index)", displayName: "App \(index)", gainsDB: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                volume: 1, shapes: true, lastUsed: Date(timeIntervalSince1970: Double(index))))
        }
        let rig = Rig(book: apps)
        rig.controller.update(bassMusic)
        #expect(rig.controller.message == AppSoundBook.fullMessage)
        let saved = AppSoundBook.decode(rig.defaults.data(forKey: AppSoundBook.storageKey)).book
        #expect(saved.settings(for: "com.apple.Music") == nil)
    }

    // MARK: Status

    @Test func theStatusListsPlayingAppsWithTheirExclusions() {
        let rig = Rig()
        let zoomPlaying = process(5, pid: 300, bundle: "us.zoom.xos", output: true, input: false)
        rig.play(true, extra: [zoomPlaying])
        rig.controller.setSwitch(true)
        let rows = rig.controller.status.rows
        #expect(rows.map(\.bundleID).contains("us.zoom.xos"))
        #expect(rows.first { $0.bundleID == "us.zoom.xos" }?.exclusion == .callApp)
        #expect(rows.first { $0.bundleID == "com.apple.Music" }?.isPlaying == true)
        #expect(rig.factory.log == ["probe:Music"])
    }

    @Test func provenSoundIsRecordedOncePerHeardProbe() {
        let rig = Rig()
        rig.startRunning()
        #expect(rig.allowedCount == 1)
        rig.monitor.fire(.processes)
        rig.scheduler.advance(by: 10)
        #expect(rig.allowedCount == 1)
    }
}
