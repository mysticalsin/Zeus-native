import CoreGraphics
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The controller with a fake camera, lock, clock, session, permissions and vault. No camera opens, no prompt is
/// raised, the real Keychain and the real support folder are never touched, and nothing locks the Mac.
@MainActor
@Suite("Face presence controller")
struct FacePresenceControllerTests {
    typealias Machine = FacePresenceMachine

    final class FakeSource: FaceFrameSource, @unchecked Sendable {
        private(set) var starts = 0
        private(set) var stops = 0
        private(set) var finishes = 0
        private(set) var running = false
        func start(deliver: @escaping @Sendable (FaceFrame) -> Void, report: @escaping @Sendable (FaceCameraEvent) -> Void) {
            starts += 1
            running = true
        }
        func stop() {
            stops += 1
            running = false
        }
        func analysisFinished() { finishes += 1 }
    }

    /// What the fake analyzer answers next. Read from the detached analysis task, so it takes a lock.
    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<FaceVision.FrameAnalysis, Error> = .success(Rig.noFace)
        func set(_ value: Result<FaceVision.FrameAnalysis, Error>) { lock.lock(); result = value; lock.unlock() }
        func value() throws -> FaceVision.FrameAnalysis { lock.lock(); defer { lock.unlock() }; return try result.get() }
    }

    struct Failure: Error {}

    @MainActor
    final class Rig {
        static let revision = 7
        static let sample: [Float] = [1, 0.2, 0.5, 0.1, 0.3, 0.7, 0.2, 0.4]
        nonisolated static let noFace = FaceVision.FrameAnalysis(faceCount: 0, faceBox: nil, observation: nil, quality: nil, alignment: nil,
                                                     spoofFrame: SpoofFrame(glare: nil, deviceOverlapFraction: nil))

        let source = FakeSource()
        let script = Script()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("face-controller-\(UUID().uuidString)", isDirectory: true)
        let keychain = KeychainStore(backend: MemoryKeychain(), defaults: UserDefaults(suiteName: "zeus.facecontroller.\(UUID().uuidString)")!)
        var vault: FaceVaultStore { FaceVaultStore(directory: directory, keychain: keychain) }
        var clock: Double = 1000
        var lockCalls = 0
        var lockResult = true
        var canLock = true
        var session: Machine.SessionLockState = .unlocked
        var camera: Machine.CameraAccess = .authorized
        var cameraAfterAsk: Machine.CameraAccess = .authorized
        var asks = 0
        var settingsOpens = 0
        var storedSwitch = false
        var storedLockAfter = "2 minutes"
        private(set) var controller: FacePresenceController!

        init() {
            let script = script
            let environment = FacePresenceController.Environment(
                source: source, vault: vault,
                analyze: { _, _ in try script.value() },
                featurePrintRevision: Self.revision,
                lock: { [unowned self] in lockCalls += 1; return lockResult },
                canLock: { [unowned self] in canLock },
                sessionState: { [unowned self] in session },
                uptime: { [unowned self] in clock },
                settings: FacePresenceController.Settings(switchIsOn: { [unowned self] in storedSwitch },
                                                          lockAfterLabel: { [unowned self] in storedLockAfter }),
                permissions: FacePresenceController.Permissions(
                    cameraAccess: { [unowned self] in camera },
                    askCamera: { [unowned self] in asks += 1; camera = cameraAfterAsk },
                    openCameraSettings: { [unowned self] in settingsOpens += 1 }),
                usesTimers: false)
            controller = FacePresenceController(environment: environment)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }

        func record(_ id: String, name: String? = nil, enabled: Bool = true) -> FaceRecord {
            FaceRecord(id: id, name: name ?? "Face \(id)", isEnabled: enabled, revision: Self.revision,
                       samples: [Self.sample, Self.sample.map { $0 + 0.01 }, Self.sample.map { $0 - 0.01 }], threshold: 0.3)
        }

        func enroll(_ ids: String...) {
            #expect(vault.save(ids.map { record($0) }) == .saved)
        }

        /// The owner's switch turned on through the setting, as the card does.
        func turnOn() {
            storedSwitch = true
            controller.settingChanged("face.presence")
        }

        func turnOff() {
            storedSwitch = false
            controller.settingChanged("face.presence")
        }

        func frame() -> FaceFrame {
            let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return FaceFrame(image: context.makeImage()!, uptime: clock)
        }

        /// One analyzed frame at the current clock, with `result` as what the analyzer saw.
        func feed(_ result: Result<FaceVision.FrameAnalysis, Error>, run: Int? = nil) async {
            script.set(result)
            await controller.process(frame(), run: run ?? controller.cameraRun)
        }

        func seeOwner(embedding: [Float] = Rig.sample, deviceOverlap: Float? = nil) -> FaceVision.FrameAnalysis {
            FaceVision.FrameAnalysis(faceCount: 1, faceBox: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
                                     observation: FaceObservation(embedding: embedding, revision: Self.revision),
                                     quality: 0.9, alignment: .fivePoint,
                                     spoofFrame: SpoofFrame(glare: nil, deviceOverlapFraction: deviceOverlap))
        }

        /// Ten frames, half a second apart, each different enough from the one before to count for enrollment.
        func enrollTenSamples() async {
            for index in 0..<10 {
                clock += 0.5
                var vector = Self.sample
                vector[1] += Float(index) * 0.25
                await feed(.success(seeOwner(embedding: vector)))
            }
        }

        /// Switched on with one enrolled face and a camera that is allowed: watching.
        func startWatching() {
            enroll("1")
            turnOn()
        }
    }

    // MARK: Launch and switching on

    @Test func launchNeverStartsTheCamera() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.storedSwitch = true
        rig.controller.begin()
        #expect(rig.controller.machine.state == .paused(.launch))
        #expect(rig.source.starts == 0)
        #expect(!rig.source.running)
        #expect(rig.controller.status().word == "Paused")
        #expect(rig.controller.presence == .unknown)
        #expect(rig.controller.faces.count == 1)

        let off = Rig()
        defer { off.cleanUp() }
        off.controller.begin()
        #expect(off.controller.machine.state == .off)
        #expect(off.source.starts == 0)
    }

    @Test func launchReadsTheStoredLockAfterChoice() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.storedLockAfter = "10 minutes"
        rig.controller.begin()
        #expect(rig.controller.machine.lockAfter == 600)
        rig.storedLockAfter = "a week"
        rig.controller.settingChanged("face.lockAfter")
        #expect(rig.controller.machine.lockAfter == 120)
        rig.storedLockAfter = "30 seconds"
        rig.controller.settingChanged("face.lockAfter")
        #expect(rig.controller.machine.lockAfter == 30)
    }

    @Test func switchOnAsksForConsentThroughPermissions() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.camera = .notDetermined
        rig.turnOn()
        #expect(rig.controller.machine.state == .needsCameraConsent)
        #expect(rig.source.starts == 0)
        await rig.controller.consentTask?.value
        #expect(rig.asks == 1)
        #expect(rig.settingsOpens == 0)
        // The answer arrived through the permissions model, so the machine moved on and the camera started.
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        #expect(rig.source.starts == 1)
        #expect(rig.source.running)
    }

    @Test func aRefusedConsentKeepsTheCameraOff() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.camera = .notDetermined
        rig.cameraAfterAsk = .denied
        rig.turnOn()
        await rig.controller.consentTask?.value
        #expect(rig.controller.machine.state == .needsCameraConsent)
        #expect(rig.source.starts == 0)
        #expect(rig.controller.status().word == "Needs camera")
    }

    @Test func aDeniedCameraOpensSystemSettingsAndAsksNothing() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.camera = .denied
        rig.turnOn()
        #expect(rig.settingsOpens == 1)
        #expect(rig.asks == 0)
        #expect(rig.controller.machine.state == .needsCameraConsent)
        #expect(rig.source.starts == 0)
    }

    @Test func switchOnWithNoFacesStartsEnrolling() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.turnOn()
        #expect(rig.controller.machine.state == .enrolling(token: 1))
        #expect(rig.source.starts == 1)
        #expect(rig.controller.status().word == "Enrolling")
    }

    @Test func switchOnWithoutTheEventFreeLockIsUnavailableAndStartsNothing() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.canLock = false
        rig.turnOn()
        #expect(rig.controller.machine.state == .unavailable(.lock))
        #expect(rig.source.starts == 0)
        #expect(rig.controller.status().word == "Unavailable")
    }

    @Test func anUnreadableVaultMakesTheFeatureUnavailable() throws {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        var bytes = try Data(contentsOf: rig.vault.url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: rig.vault.url)
        rig.turnOn()
        #expect(rig.controller.machine.state == .unavailable(.vault))
        #expect(!rig.controller.vaultReadable)
        #expect(rig.source.starts == 0)
    }

    @Test func aSettingChangeThatMatchesTheMachineDoesNothingTwice() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        let before = rig.controller.machine
        rig.controller.settingChanged("face.presence")
        rig.controller.settingChanged("something.else")
        #expect(rig.controller.machine == before)
        #expect(rig.source.starts == 1)
    }

    @Test func switchingOffStopsTheCameraAtOnce() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        #expect(rig.source.running)
        rig.turnOff()
        #expect(rig.controller.machine.state == .off)
        #expect(!rig.source.running)
        #expect(rig.source.stops == 1)
    }

    // MARK: Lock and unlock notices

    @Test func anUnlockNoticeWhileTheSessionIsLockedStartsNothing() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.storedSwitch = true
        rig.controller.begin()
        // A forged or early "unlocked" notice: the session dictionary still says locked, or cannot be read.
        for state in [Machine.SessionLockState.locked, .unknown] {
            rig.session = state
            rig.controller.screenUnlockedNotice()
            rig.controller.didWakeNotice()
            #expect(rig.controller.machine.state == .paused(.launch), "\(state)")
            #expect(rig.source.starts == 0, "\(state)")
        }
        // Only a plainly unlocked session starts the camera.
        rig.session = .unlocked
        rig.clock += 10
        rig.controller.screenUnlockedNotice()
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        #expect(rig.source.starts == 1)
    }

    @Test func lockingTheScreenOrSleepingStopsTheCameraAndWakingLockedKeepsItOff() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        rig.controller.screenLockedNotice()
        #expect(rig.controller.machine.state == .paused(.screenLocked))
        #expect(!rig.source.running)
        rig.session = .locked
        rig.controller.didWakeNotice()
        #expect(rig.controller.machine.state == .paused(.screenLocked))
        rig.session = .unlocked
        rig.clock += 5
        rig.controller.screenUnlockedNotice()
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        #expect(rig.source.running)
        rig.controller.willSleepNotice()
        #expect(rig.controller.machine.state == .paused(.asleep))
        #expect(!rig.source.running)
        #expect(rig.source.starts == 2)
        #expect(rig.source.stops == 2)
    }

    // MARK: The lock

    @Test func theLockerIsCalledOnceAndOnlyTheEventFreeCall() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        await rig.feed(.success(Rig.noFace))
        #expect(rig.controller.machine.state == .away(since: 1000))
        #expect(rig.controller.presence == .absent)
        // Not yet: 119 seconds of two minutes.
        rig.clock += 119
        rig.controller.tick()
        #expect(rig.lockCalls == 0)
        rig.clock += 1
        rig.controller.tick()
        #expect(rig.lockCalls == 1)
        #expect(rig.controller.machine.state == .paused(.lockedByZeus))
        #expect(rig.controller.status().word == "Locked")
        #expect(!rig.source.running)
        // Nothing asks again, however long it runs.
        for _ in 0..<30 {
            rig.clock += 1
            rig.controller.tick()
        }
        rig.controller.screenLockedNotice()
        #expect(rig.lockCalls == 1)
        #expect(rig.controller.machine.state == .paused(.lockedByZeus))
    }

    @Test func aLockThatFailsIsNeverRetried() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        rig.lockResult = false
        await rig.feed(.success(Rig.noFace))
        rig.clock += 120
        rig.controller.tick()
        #expect(rig.lockCalls == 1)
        #expect(rig.controller.machine.state == .unavailable(.lock))
        for _ in 0..<30 {
            rig.clock += 1
            rig.controller.tick()
        }
        #expect(rig.lockCalls == 1)
    }

    // MARK: Teleprompter

    @Test func teleprompterRecordingPausesAndResumes() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        rig.controller.teleprompterCapture(active: true)
        #expect(rig.controller.machine.state == .paused(.zeusCapture))
        #expect(!rig.source.running)
        #expect(rig.controller.status().word == "Paused")
        rig.clock += 60
        rig.controller.teleprompterCapture(active: false)
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        #expect(rig.source.running)
        #expect(rig.source.starts == 2)
    }

    // MARK: Frames

    @Test func aFrameAfterStopIsDropped() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        let oldRun = rig.controller.cameraRun
        rig.turnOff()
        let finishes = rig.source.finishes
        // The frame was in flight when the camera stopped: it must not move the machine or count as seen.
        await rig.feed(.success(rig.seeOwner()), run: oldRun)
        #expect(rig.controller.machine.state == .off)
        #expect(rig.controller.presence == .unknown)
        #expect(rig.source.finishes == finishes + 1)

        // The same after a stop and a restart: a frame from the earlier run is not this run's.
        rig.turnOn()
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        await rig.feed(.success(rig.seeOwner()), run: oldRun)
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        await rig.feed(.success(rig.seeOwner()))
        #expect(rig.controller.machine.state == .present(lastSeen: rig.clock))
    }

    @Test func theEnrolledOwnerIsPresentAndAStrangerIsNot() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        rig.clock += 1
        await rig.feed(.success(rig.seeOwner()))
        #expect(rig.controller.machine.state == .present(lastSeen: rig.clock))
        #expect(rig.controller.presence == .present)
        // A very different feature print is not the owner. After the grace the machine reads absent.
        rig.clock += 1
        await rig.feed(.success(rig.seeOwner(embedding: [-1, 0.9, -0.5, 0.8, -0.3, -0.7, 0.9, -0.4])))
        rig.clock += 3
        await rig.feed(.success(rig.seeOwner(embedding: [-1, 0.9, -0.5, 0.8, -0.3, -0.7, 0.9, -0.4])))
        #expect(rig.controller.presence == .absent)
    }

    @Test func aSwitchedOffFaceIsNeverTheOwner() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        let id = rig.controller.faces[0].id
        rig.controller.setFace(id, enabled: false)
        // With the only face off there is nobody to match: the camera stops and nothing reads present.
        #expect(rig.controller.machine.state == .paused(.noFace))
        #expect(!rig.source.running)
        #expect(rig.controller.presence == .unknown)
    }

    @Test func aLatchedSpoofCueMakesTheOwnerAbsent() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        // The owner's own print, but a device shaped rectangle around the face in three frames.
        for _ in 0..<3 {
            rig.clock += 0.5
            await rig.feed(.success(rig.seeOwner(deviceOverlap: 0.6)))
        }
        // The first two frames counted as the owner; once the cue latched the verdict turned, and the grace runs out.
        rig.clock += 4
        await rig.feed(.success(rig.seeOwner(deviceOverlap: 0.6)))
        #expect(rig.controller.presence == .absent)
    }

    @Test func presenceIsReadOnlyForOtherFeatures() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        let starts = rig.source.starts
        let state = rig.controller.machine.state
        for _ in 0..<50 { _ = rig.controller.presence }
        #expect(rig.source.starts == starts)
        #expect(rig.controller.machine.state == state)
        // The value comes from the machine and nothing else.
        #expect(rig.controller.presence == rig.controller.machine.presence)
        let labels = Mirror(reflecting: rig.controller.presence).children.compactMap(\.label)
        #expect(labels.isEmpty)
    }

    @Test func framesThatVisionCannotReadStopTheCameraAfterAFewInARow() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        for _ in 0..<(FacePresenceController.visionFailureLimit - 1) {
            await rig.feed(.failure(Failure()))
        }
        #expect(rig.controller.machine.state == .watching(since: 1000))
        await rig.feed(.success(rig.seeOwner()))
        for _ in 0..<(FacePresenceController.visionFailureLimit - 1) {
            await rig.feed(.failure(Failure()))
        }
        // A good frame in between reset the count.
        #expect(rig.controller.machine.state == .present(lastSeen: 1000))
        await rig.feed(.failure(Failure()))
        #expect(rig.controller.machine.state == .unavailable(.camera))
        #expect(!rig.source.running)
    }

    @Test func cameraReportsMoveTheMachineOnlyForTheCurrentRun() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        let run = rig.controller.cameraRun
        rig.controller.cameraEvent(.deviceLost, run: run - 1)
        #expect(rig.controller.machine.state == .watching(since: 1000))
        rig.controller.cameraEvent(.interrupted, run: run)
        #expect(rig.controller.machine.state == .unavailable(.camera))
        #expect(!rig.source.running)
        // The stopped camera's later reports belong to no run.
        rig.controller.cameraEvent(.interruptionEnded, run: run)
        #expect(rig.controller.machine.state == .unavailable(.camera))
    }

    // MARK: Enrollment

    @Test func tenDifferentSamplesSaveAFaceAndStartWatching() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.turnOn()
        #expect(rig.controller.machine.state == .enrolling(token: 1))
        await rig.enrollTenSamples()
        #expect(rig.controller.faces.count == 1)
        let face = rig.controller.faces[0]
        #expect(face.name == "Face 1")
        #expect(face.isEnabled)
        #expect(face.revision == Rig.revision)
        #expect(face.samples.count == 10)
        #expect(rig.vault.load() == .faces([face]))
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        #expect(rig.source.running)
    }

    @Test func nineSamplesAndAClosedWindowSaveNothing() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.turnOn()
        for index in 0..<9 {
            rig.clock += 0.5
            var vector = Rig.sample
            vector[1] += Float(index) * 0.25
            await rig.feed(.success(rig.seeOwner(embedding: vector)))
        }
        #expect(rig.controller.machine.state == .enrolling(token: 1))
        rig.clock += 30
        rig.controller.checkEnrollmentWindow()
        #expect(rig.controller.machine.state == .paused(.noFace))
        #expect(rig.controller.faces.isEmpty)
        #expect(rig.vault.load() == .empty)
        #expect(!rig.source.running)
    }

    @Test func aSilentCameraCannotKeepAnEnrollmentOpenPastItsWindow() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.turnOn()
        rig.clock += 10
        rig.controller.checkEnrollmentWindow()
        #expect(rig.controller.machine.state == .enrolling(token: 1))
        rig.clock += 25
        rig.controller.checkEnrollmentWindow()
        #expect(rig.controller.machine.state == .paused(.noFace))
        #expect(!rig.source.running)
    }

    @Test func lockingDuringEnrollmentSavesNothing() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.turnOn()
        let run = rig.controller.cameraRun
        for index in 0..<6 {
            rig.clock += 0.5
            var vector = Rig.sample
            vector[1] += Float(index) * 0.25
            await rig.feed(.success(rig.seeOwner(embedding: vector)))
        }
        rig.controller.screenLockedNotice()
        #expect(rig.controller.machine.state == .paused(.screenLocked))
        #expect(!rig.source.running)
        // Frames still in flight for the cancelled enrollment, enough to have finished it, are dropped.
        for index in 6..<12 {
            rig.clock += 0.5
            var vector = Rig.sample
            vector[1] += Float(index) * 0.25
            await rig.feed(.success(rig.seeOwner(embedding: vector)), run: run)
        }
        #expect(rig.controller.faces.isEmpty)
        #expect(rig.vault.load() == .empty)
        #expect(rig.controller.machine.state == .paused(.screenLocked))
    }

    @Test func aSampleWithASpoofCueIsRefusedSoNothingSavesFromAPhone() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.turnOn()
        for index in 0..<14 {
            rig.clock += 0.5
            var vector = Rig.sample
            vector[1] += Float(index) * 0.25
            await rig.feed(.success(rig.seeOwner(embedding: vector, deviceOverlap: 0.6)))
        }
        // The cue latches after three frames, so at most two samples were taken before it and never ten.
        #expect(rig.controller.faces.isEmpty)
    }

    @Test func enrollFromWatchingAddsASecondFaceWithTheNextName() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.startWatching()
        rig.controller.enroll()
        #expect(rig.controller.machine.state == .enrolling(token: 1))
        await rig.enrollTenSamples()
        #expect(rig.controller.faces.map(\.name) == ["Face 1", "Face 2"])
        #expect(rig.controller.enabledFaceCount == 2)
    }

    @Test func aDeletedNumberIsUsedAgain() async {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1", "2")
        rig.turnOn()
        rig.controller.deleteFace(rig.controller.faces[0].id)
        #expect(rig.controller.faces.map(\.name) == ["Face 2"])
        rig.controller.enroll()
        await rig.enrollTenSamples()
        #expect(Set(rig.controller.faces.map(\.name)) == ["Face 1", "Face 2"])
    }

    // MARK: The faces list

    @Test func switchingFacesOffAndOnAndDeletingThemIsImmediateAndStored() {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1", "2")
        rig.turnOn()
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        rig.controller.setFace("1", enabled: false)
        #expect(rig.controller.enabledFaceCount == 1)
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        if case .faces(let stored) = rig.vault.load() {
            #expect(stored.first { $0.id == "1" }?.isEnabled == false)
        } else { Issue.record("vault should hold the faces") }

        rig.controller.setFace("2", enabled: false)
        #expect(rig.controller.machine.state == .paused(.noFace))
        #expect(!rig.source.running)
        rig.clock += 5
        rig.controller.setFace("2", enabled: true)
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
        #expect(rig.source.running)

        rig.controller.deleteFace("1")
        #expect(rig.controller.faces.map(\.id) == ["2"])
        rig.controller.deleteFace("2")
        #expect(rig.controller.faces.isEmpty)
        #expect(rig.controller.machine.state == .paused(.noFace))
        // The last face gone: file and key are gone with it.
        #expect(rig.vault.load() == .empty)
        #expect(!FileManager.default.fileExists(atPath: rig.vault.url.path))
        #expect(rig.keychain.get(FaceVaultStore.keyAccount) == nil)
    }

    @Test func aFaceChangeThatCannotBeSavedIsNotShown() throws {
        let rig = Rig(); defer { rig.cleanUp() }
        rig.enroll("1")
        rig.turnOn()
        try Data("damaged".utf8).write(to: rig.vault.url)
        rig.controller.setFace("1", enabled: false)
        #expect(rig.controller.faces[0].isEnabled)
        rig.controller.deleteFace("1")
        #expect(rig.controller.faces.count == 1)
        #expect(rig.controller.machine.state == .watching(since: rig.clock))
    }

    @Test func theEnrollButtonFollowsTheMachine() {
        let rig = Rig(); defer { rig.cleanUp() }
        #expect(!rig.controller.machine.canEnroll)
        rig.startWatching()
        #expect(rig.controller.machine.canEnroll)
        rig.controller.teleprompterCapture(active: true)
        #expect(!rig.controller.machine.canEnroll)
    }

    // MARK: Camera usage string

    @Test func theCameraUsageStringNamesBothFeaturesAndSaysNoImageIsSaved() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let text = try #require(plist["NSCameraUsageDescription"] as? String)
        #expect(text == "ZEUS uses the camera while you read from the teleprompter, only when you press Record, and for Face presence, only after you turn it on, to lock your Mac when you step away. No image is saved.")
    }
}
