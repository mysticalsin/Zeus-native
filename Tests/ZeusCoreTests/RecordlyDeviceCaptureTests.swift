import Foundation
import Testing
@testable import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Pure Recordly microphone and camera capture. No AVFoundation, no prompt, no upload.
@Suite("Recordly device capture", .serialized)
struct RecordlyDeviceCaptureTests {
    @Test func launchAndAppearanceNeverAskOrRecord() {
        var machine = RecordlyDeviceCaptureMachine()
        #expect(machine.phase == .idle)
        #expect(machine.send(.launch) == [])
        #expect(machine.send(.appear) == [])
        #expect(machine.send(.permission(.microphoneGranted)) == [])
        #expect(machine.send(.captureDidStart(now: 1)) == [])
        #expect(machine.send(.record(now: 2)) == [])
        #expect(machine.phase == .idle)
        #expect(machine.captureStartCount == 0)
        #expect(machine.permissionRequestCount == 0)
        #expect(machine.showsRecordingIndicator == false)
        #expect(machine.savedURL == nil)
    }

    @Test func selectingADeviceAsksAndStopsAtReady() {
        var machine = RecordlyDeviceCaptureMachine()
        let effects = machine.send(.select(.microphone))
        #expect(effects == [.requestPermission(.microphone)])
        #expect(machine.phase == .requestingPermission)
        #expect(machine.permissionRequestCount == 1)
        #expect(machine.captureStartCount == 0)
        #expect(machine.send(.permission(.microphoneGranted)) == [])
        #expect(machine.phase == .ready)
        #expect(machine.captureStartCount == 0)
        #expect(machine.showsRecordingIndicator == false)
        #expect(machine.statusText == "Ready. Press Record. Nothing is recorded until you do.")
    }

    @Test func recordTapIsTheOnlyStart() {
        var machine = RecordlyDeviceCaptureMachine()
        _ = machine.send(.select(.microphone))
        #expect(machine.send(.record(now: 4)) == [])
        #expect(machine.captureStartCount == 0)
        #expect(machine.phase == .requestingPermission)
        _ = machine.send(.permission(.microphoneGranted))
        let start = machine.send(.record(now: 5))
        #expect(start == [.startCapture(.microphone)])
        #expect(machine.phase == .recording)
        #expect(machine.captureStartCount == 1)
        #expect(machine.showsRecordingIndicator == false)
        #expect(machine.statusText == "Starting microphone.")
        #expect(machine.send(.captureDidStart(now: 6)) == [])
        #expect(machine.showsRecordingIndicator == true)
        #expect(machine.startedAt == 6)
        #expect(machine.statusText == "Recording microphone.")
        #expect(machine.send(.record(now: 7)) == [])
        #expect(machine.captureStartCount == 1)
    }

    @Test func acknowledgementWithoutATapDoesNothing() {
        var machine = RecordlyDeviceCaptureMachine()
        _ = machine.send(.select(.both))
        _ = machine.send(.permission(.bothGranted))
        #expect(machine.phase == .ready)
        #expect(machine.send(.captureDidStart(now: 9)) == [])
        #expect(machine.phase == .ready)
        #expect(machine.showsRecordingIndicator == false)
        #expect(machine.captureStartCount == 0)
    }

    @Test func permissionDeniedOffersSystemSettings() {
        var microphone = RecordlyDeviceCaptureMachine()
        _ = microphone.send(.select(.microphone))
        #expect(microphone.send(.permission(.microphoneDenied)) == [])
        guard case .failed(let mic) = microphone.phase else {
            Issue.record("microphone denial should fail")
            return
        }
        #expect(mic.kind == .permissionDenied)
        #expect(mic.message == "Microphone access is off for Zeus. Open System Settings, then Privacy & Security, then Microphone, and allow Zeus.")
        #expect(mic.settingsLinks.map(\.device) == [.microphone])
        #expect(mic.settingsLinks[0].url.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #expect(microphone.captureStartCount == 0)
        #expect(microphone.showsRecordingIndicator == false)

        var camera = RecordlyDeviceCaptureMachine()
        _ = camera.send(.select(.camera))
        _ = camera.send(.permission(.cameraDenied))
        guard case .failed(let cam) = camera.phase else {
            Issue.record("camera denial should fail")
            return
        }
        #expect(cam.message == "Camera access is off for Zeus. Open System Settings, then Privacy & Security, then Camera, and allow Zeus.")
        #expect(cam.settingsLinks.map(\.url.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"])

        var both = RecordlyDeviceCaptureMachine()
        _ = both.send(.select(.both))
        _ = both.send(.permission(.bothDenied))
        guard case .failed(let denied) = both.phase else {
            Issue.record("both denials should fail")
            return
        }
        #expect(denied.settingsLinks.map(\.device) == [.microphone, .camera])
        #expect(denied.message.contains("Microphone"))
        #expect(denied.message.contains("Camera"))
        #expect(both.captureStartCount == 0)
    }

    @Test func cancelMidRecordingDiscardsAndDoesNotSave() {
        var machine = RecordlyDeviceCaptureMachine()
        _ = machine.send(.select(.camera))
        _ = machine.send(.permission(.cameraGranted))
        _ = machine.send(.record(now: 3))
        _ = machine.send(.captureDidStart(now: 4))
        #expect(machine.showsRecordingIndicator == true)
        #expect(machine.send(.select(.microphone)) == [])
        #expect(machine.phase == .recording)
        #expect(machine.selection == .camera)
        let cancel = machine.send(.cancel)
        #expect(cancel == [.stopCapture(discard: true)])
        #expect(machine.phase == .finishing)
        #expect(machine.showsRecordingIndicator == false)
        #expect(machine.send(.discarded) == [])
        #expect(machine.phase == .ready)
        #expect(machine.savedURL == nil)
        #expect(machine.captureStartCount == 1)
        #expect(machine.selection == .camera)
    }

    @Test func diskFullFailsAndDoesNotSave() {
        var machine = RecordlyDeviceCaptureMachine()
        _ = machine.send(.select(.both))
        _ = machine.send(.permission(.bothGranted))
        _ = machine.send(.record(now: 8))
        _ = machine.send(.captureDidStart(now: 9))
        let effects = machine.send(.writeFailed(.diskFull))
        #expect(effects == [.stopCapture(discard: true)])
        guard case .failed(let failure) = machine.phase else {
            Issue.record("disk full should fail")
            return
        }
        #expect(failure.kind == .diskFull)
        #expect(failure.message == "This Mac is out of space, so the recording was not saved.")
        #expect(failure.settingsLinks.isEmpty)
        #expect(machine.savedURL == nil)
        #expect(machine.showsRecordingIndicator == false)

        var finishing = RecordlyDeviceCaptureMachine()
        _ = finishing.send(.select(.microphone))
        _ = finishing.send(.permission(.microphoneGranted))
        _ = finishing.send(.record(now: 1))
        _ = finishing.send(.captureDidStart(now: 2))
        #expect(finishing.send(.stop) == [.stopCapture(discard: false)])
        #expect(finishing.phase == .finishing)
        #expect(finishing.send(.writeFailed(.diskFull)) == [])
        guard case .failed(let stopped) = finishing.phase else {
            Issue.record("disk full while saving should fail")
            return
        }
        #expect(stopped.kind == .diskFull)
        #expect(finishing.savedURL == nil)
    }

    @Test func happyPathStatesStayLocal() {
        var machine = RecordlyDeviceCaptureMachine()
        #expect(machine.phase == .idle)
        _ = machine.send(.select(.microphone))
        #expect(machine.phase == .requestingPermission)
        _ = machine.send(.permission(.microphoneGranted))
        #expect(machine.phase == .ready)
        _ = machine.send(.record(now: 10))
        #expect(machine.phase == .recording)
        _ = machine.send(.captureDidStart(now: 11))
        _ = machine.send(.stop)
        #expect(machine.phase == .finishing)
        let receipt = RecordlyDeviceCaptureReceipt(
            url: URL(fileURLWithPath: "/tmp/recordly-microphone.m4a"),
            byteCount: 12,
            mode: 0o600,
            uploaded: false
        )
        #expect(machine.send(.writeSucceeded(receipt)) == [])
        #expect(machine.phase == .saved(receipt))
        #expect(machine.savedURL == receipt.url)
        #expect(machine.statusText == "Saved on this Mac. Nothing was uploaded.")
        #expect(machine.send(.dismiss) == [])
        #expect(machine.phase == .idle)
        #expect(machine.selection.isEmpty)
        #expect(machine.captureStartCount == 1)
    }

    @Test func anUploadedOrWorldReadableReceiptIsRefused() {
        var uploaded = finishingMicrophone()
        let remote = RecordlyDeviceCaptureReceipt(
            url: URL(fileURLWithPath: "/tmp/clip.m4a"), byteCount: 4, mode: 0o600, uploaded: true)
        #expect(uploaded.send(.writeSucceeded(remote)) == [])
        guard case .failed(let refused) = uploaded.phase else {
            Issue.record("upload should be refused")
            return
        }
        #expect(refused.kind == .engine)
        #expect(refused.message == "Zeus does not upload recordings. This one was not saved.")
        #expect(uploaded.savedURL == nil)

        var loose = finishingMicrophone()
        let open = RecordlyDeviceCaptureReceipt(
            url: URL(fileURLWithPath: "/tmp/clip.m4a"), byteCount: 4, mode: 0o644, uploaded: false)
        _ = loose.send(.writeSucceeded(open))
        guard case .failed(let privacy) = loose.phase else {
            Issue.record("a loose file should be refused")
            return
        }
        #expect(privacy.message == "The recording could not be kept private, so it was not saved.")
    }

    @Test func savedFileIsPrivateAndLocal() throws {
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let receipt = try RecordlyDeviceCaptureStore.save(
            data: Data("zeus-local".utf8),
            fileName: "recordly-microphone-19700101-000000.m4a",
            supportDirectory: support,
            freeBytes: { _ in 8_000_000 }
        )
        #expect(receipt.uploaded == false)
        #expect(receipt.mode == 0o600)
        #expect(receipt.byteCount == 10)
        let folder = support.appendingPathComponent("Recordly", isDirectory: true)
        #expect(receipt.url.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path))
        #expect(try mode(of: receipt.url) == 0o600)
        #expect(try mode(of: folder) == 0o700)
        let text = try String(contentsOf: receipt.url, encoding: .utf8)
        #expect(text == "zeus-local")
    }

    @Test func fullDiskWritesNothing() throws {
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        let name = "recordly-camera-19700101-000000.mov"
        #expect(throws: RecordlyDeviceCaptureWriteError.diskFull) {
            try RecordlyDeviceCaptureStore.save(
                data: Data([1, 2, 3, 4]),
                fileName: name,
                supportDirectory: support,
                freeBytes: { _ in 0 }
            )
        }
        let file = support.appendingPathComponent("Recordly").appendingPathComponent(name)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)

        #expect(throws: RecordlyDeviceCaptureWriteError.diskFull) {
            try RecordlyDeviceCaptureStore.save(
                data: Data([9]),
                fileName: name,
                supportDirectory: support,
                freeBytes: { _ in 8_000_000 },
                simulatedPOSIXError: ENOSPC
            )
        }
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
        #expect(RecordlyDeviceCaptureWriteError.classify(domain: "NSPOSIXErrorDomain", code: Int(ENOSPC)) == .diskFull)
        #expect(RecordlyDeviceCaptureWriteError.classify(domain: "NSPOSIXErrorDomain", code: Int(EDQUOT)) == .diskFull)
        #expect(RecordlyDeviceCaptureWriteError.classify(domain: "NSCocoaErrorDomain", code: 640) == .diskFull)
        #expect(RecordlyDeviceCaptureWriteError.classify(domain: "AVFoundationErrorDomain", code: -11813) == .diskFull)
        #expect(RecordlyDeviceCaptureWriteError.classify(domain: "NSPOSIXErrorDomain", code: Int(EIO)) == nil)
    }

    @Test func namesStayInsideTheContainer() throws {
        #expect(RecordlyDeviceCaptureStore.fileName(for: .microphone, at: Date(timeIntervalSince1970: 0))
            == "recordly-microphone-19700101-000000.m4a")
        #expect(RecordlyDeviceCaptureStore.fileName(for: .camera, at: Date(timeIntervalSince1970: 0))
            == "recordly-camera-19700101-000000.mov")
        #expect(RecordlyDeviceCaptureStore.fileName(for: .both, at: Date(timeIntervalSince1970: 0))
            == "recordly-microphone-camera-19700101-000000.mov")
        let support = try temporarySupport()
        defer { try? FileManager.default.removeItem(at: support) }
        for name in ["../escape.m4a", "nested/clip.m4a", "", ".", ".."] {
            #expect(throws: RecordlyDeviceCaptureWriteError.failed("The recording name is not safe.")) {
                try RecordlyDeviceCaptureStore.save(
                    data: Data([1]),
                    fileName: name,
                    supportDirectory: support,
                    freeBytes: { _ in 8_000_000 }
                )
            }
        }
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("escape.m4a").path) == false)
    }

    @Test func theMicrophoneFlagHonorsTheChip() {
        #expect(RecordlyPrimaryRecord.includeMicrophone(chipOn: true, permissionGranted: true))
        #expect(!RecordlyPrimaryRecord.includeMicrophone(chipOn: false, permissionGranted: true))
        #expect(!RecordlyPrimaryRecord.includeMicrophone(chipOn: true, permissionGranted: false))
        #expect(!RecordlyPrimaryRecord.includeMicrophone(chipOn: false, permissionGranted: false))
        var machine = RecordlyDeviceCaptureMachine()
        #expect(!machine.permissionGranted(.microphone))
        _ = machine.send(.select(.microphone))
        #expect(!machine.permissionGranted(.microphone))
        _ = machine.send(.permission(.microphoneGranted))
        #expect(machine.permissionGranted(.microphone))
        #expect(RecordlyPrimaryRecord.includeMicrophone(
            chipOn: machine.selection.microphone,
            permissionGranted: machine.permissionGranted(.microphone)
        ))
        #expect(RecordlyPrimaryRecord.startsDeviceCapture(phase: machine.phase))
        _ = machine.send(.record(now: 1))
        #expect(!RecordlyPrimaryRecord.startsDeviceCapture(phase: machine.phase))
    }

    /// A screen session that has started is the recorder. A ready chip must not open a second one.
    @Test func anActiveScreenSessionDoesNotStartAnotherRecorder() throws {
        #expect(RecordlyPrimaryRecord.blocksAnotherRecorder(screenSessionActive: true))
        #expect(!RecordlyPrimaryRecord.blocksAnotherRecorder(screenSessionActive: false))
        var machine = RecordlyDeviceCaptureMachine()
        _ = machine.send(.select(.microphone))
        _ = machine.send(.permission(.microphoneGranted))
        #expect(machine.phase == .ready)
        #expect(RecordlyPrimaryRecord.startsDeviceCapture(phase: machine.phase))
        #expect(!RecordlyPrimaryRecord.mayStartDeviceRecorder(
            phase: machine.phase,
            screenSessionActive: true
        ))
        #expect(RecordlyPrimaryRecord.mayStartDeviceRecorder(
            phase: machine.phase,
            screenSessionActive: false
        ))
        let controller = try repoSource("Sources/Zeus/Recordly/RecordlyController.swift")
        let started = controller.components(separatedBy: "case .started").dropFirst().first ?? ""
        let branch = started.components(separatedBy: "case .failed").first ?? started
        #expect(!branch.contains(".record()"))
    }

    /// The screen file drops microphone samples and has no camera. Copy must not say otherwise.
    /// A literal `chipOn: false` is not a substitute for the chip.
    @Test func theScreenCopyDoesNotOverClaimAndTheChipIsLive() throws {
        let route = try repoSource("Sources/ZeusCore/Recordly/RecordlyCaptureSource.swift")
        #expect(route.contains("case .microphone: .drop"))
        let controller = try repoSource("Sources/Zeus/Recordly/RecordlyController.swift")
        let page = try repoSource("Sources/Zeus/Recordly/RecordlyPage.swift")
        #expect(controller.contains("audio.microphone = RecordlyPrimaryRecord.screenFileIncludesMicrophone"))
        #expect(!controller.contains("chipOn: false"))
        #expect(!controller.contains("chipOn: true"))
        if controller.contains("includeMicrophone") {
            #expect(controller.contains("chipOn: devices.selection.microphone"))
        }
        #expect(!page.contains("and the \\(capture.selection.deviceName)"))
    }

    /// `phase != .idle` just after `guard phase == .idle` is always false, so a device
    /// that is already recording does not block the screen session.
    @Test func aLiveDeviceRecordingBlocksTheScreenSession() throws {
        let controller = try repoSource("Sources/Zeus/Recordly/RecordlyController.swift")
        let press = controller.components(separatedBy: "func pressRecord").dropFirst().first ?? ""
        let body = press.components(separatedBy: "func cancelCountdown").first ?? press
        #expect(!body.contains("screenSessionActive: phase != .idle"))
        #expect(body.contains("blocksScreenStart"))
    }

    /// One Record control. The status view does not grow a second Record button, and the primary
    /// start reads the chip instead of forcing the microphone off.
    @Test func oneRecordControlHonorsTheChip() throws {
        let controller = try repoSource("Sources/Zeus/Recordly/RecordlyController.swift")
        let status = try repoSource("Sources/Zeus/Recordly/RecordlyDeviceCaptureStatus.swift")
        let page = try repoSource("Sources/Zeus/Recordly/RecordlyPage.swift")
        #expect(controller.contains("RecordlyPrimaryRecord.includeMicrophone"))
        #expect(!controller.contains("audio.microphone = false"))
        #expect(controller.contains("RecordlyDeviceCaptureController.shared.record()"))
        #expect(!status.contains("capture.record()"))
        #expect(!status.contains("recordButtonTitle"))
        #expect(page.contains("Press Record"))
        #expect(!page.contains("accessibilityIdentifier(\"recordly.device.record\")"))
    }

    private func repoSource(_ relative: String) throws -> String {
        if let root = ProcessInfo.processInfo.environment["ZEUS_REPO"], !root.isEmpty {
            let url = URL(fileURLWithPath: root).appendingPathComponent(relative)
            return try String(contentsOf: url, encoding: .utf8)
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        Issue.record("Missing \(relative)")
        return ""
    }

    private func finishingMicrophone() -> RecordlyDeviceCaptureMachine {
        var machine = RecordlyDeviceCaptureMachine()
        _ = machine.send(.select(.microphone))
        _ = machine.send(.permission(.microphoneGranted))
        _ = machine.send(.record(now: 1))
        _ = machine.send(.captureDidStart(now: 2))
        _ = machine.send(.stop)
        return machine
    }

    private func temporarySupport() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-recordly-device-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o777
    }
}
