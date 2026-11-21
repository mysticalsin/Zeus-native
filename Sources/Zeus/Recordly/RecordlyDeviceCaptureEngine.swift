import AVFoundation
import Foundation
import ZeusCore

/// AVFoundation microphone and camera capture for Recordly.
/// `init` does not open a device. Permission is requested only from `requestPermission`.
/// A session is created only from `start`, which the controller calls after the record tap.
@MainActor
final class RecordlyDeviceCaptureEngine: NSObject {
    private var session: AVCaptureSession?
    private var output: AVCaptureFileOutput?
    private var fileURL: URL?
    private var usesCamera = false
    private var cancelled = false
    private var waiter: CheckedContinuation<Result<URL, Error>, Never>?
    private var finished: Result<URL, Error>?
    private let queue = DispatchQueue(label: "app.zeus.recordly.device-capture")

    func requestPermission(_ selection: RecordlyDeviceCaptureSelection) async -> RecordlyDevicePermissionReport {
        let microphone: RecordlyDevicePermission = selection.microphone ? await Self.access(.audio) : .notRequested
        let camera: RecordlyDevicePermission = selection.camera ? await Self.access(.video) : .notRequested
        return RecordlyDevicePermissionReport(microphone: microphone, camera: camera)
    }

    /// Starts writing into Zeus's support directory. Throws before opening a device when the volume is short.
    func start(selection: RecordlyDeviceCaptureSelection, supportDirectory: URL, now: Date) async throws {
        if session != nil { throw RecordlyDeviceCaptureWriteError.failed("A recording is already open.") }
        cancelled = false
        if selection.microphone, AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            throw RecordlyDeviceCaptureWriteError.permissionDenied(.microphone)
        }
        if selection.camera, AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            throw RecordlyDeviceCaptureWriteError.permissionDenied(.camera)
        }
        let directory = try RecordlyDeviceCaptureStore.prepareDirectory(
            supportDirectory: supportDirectory,
            reserveBytes: RecordlyDeviceCaptureStore.reserveBytes
        )
        let url = directory.appendingPathComponent(RecordlyDeviceCaptureStore.fileName(for: selection, at: now))
        if FileManager.default.fileExists(atPath: url.path) {
            throw RecordlyDeviceCaptureWriteError.failed("A recording with that name is already there.")
        }

        let capture = AVCaptureSession()
        capture.beginConfiguration()
        do {
            if selection.camera {
                capture.sessionPreset = .high
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    throw RecordlyDeviceCaptureWriteError.failed("No camera is available.")
                }
                try add(camera, to: capture, busy: "The camera is busy in another app.")
                if selection.microphone {
                    try addMicrophone(to: capture)
                }
                let movie = AVCaptureMovieFileOutput()
                guard capture.canAddOutput(movie) else {
                    throw RecordlyDeviceCaptureWriteError.failed("The recording could not be started.")
                }
                capture.addOutput(movie)
                output = movie
            } else {
                try addMicrophone(to: capture)
                let audio = AVCaptureAudioFileOutput()
                guard capture.canAddOutput(audio) else {
                    throw RecordlyDeviceCaptureWriteError.failed("The recording could not be started.")
                }
                capture.addOutput(audio)
                output = audio
            }
            capture.commitConfiguration()
        } catch {
            capture.commitConfiguration()
            output = nil
            throw error
        }

        if selection.camera {
            usesCamera = true
            FacePresenceController.shared.teleprompterCapture(active: true)
        }
        let box = RecordlyCaptureSessionBox(capture)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                box.session.startRunning()
                continuation.resume()
            }
        }
        if cancelled || !capture.isRunning {
            tearDown(capture)
            if cancelled {
                throw RecordlyDeviceCaptureWriteError.failed("The recording was cancelled before it started.")
            }
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be started.")
        }
        session = capture
        fileURL = url
        if let movie = output as? AVCaptureMovieFileOutput {
            movie.startRecording(to: url, recordingDelegate: self)
        } else if let audio = output as? AVCaptureAudioFileOutput {
            audio.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
        } else {
            tearDown(capture)
            throw RecordlyDeviceCaptureWriteError.failed("The recording could not be started.")
        }
    }

    /// Stops the devices. `discard` deletes the file and returns nil. A kept file is mode 0600.
    func stop(discard: Bool) async throws -> RecordlyDeviceCaptureReceipt? {
        cancelled = true
        let result: Result<URL, Error>
        if output?.isRecording == true {
            result = await withCheckedContinuation { continuation in
                output?.stopRecording()
                if let finished {
                    self.finished = nil
                    continuation.resume(returning: finished)
                } else {
                    waiter = continuation
                }
            }
        } else if let finished {
            result = finished
            self.finished = nil
        } else {
            let url = fileURL
            tearDown(session)
            if discard, let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        let url = fileURL
        tearDown(session)
        switch result {
        case .success(let recorded):
            if discard {
                try? FileManager.default.removeItem(at: recorded)
                return nil
            }
            return try RecordlyDeviceCaptureStore.protect(recorded)
        case .failure(let error):
            if let url { try? FileManager.default.removeItem(at: url) }
            throw map(error)
        }
    }

    private func addMicrophone(to capture: AVCaptureSession) throws {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw RecordlyDeviceCaptureWriteError.failed("No microphone is available.")
        }
        try add(microphone, to: capture, busy: "The microphone is busy in another app.")
    }

    private func add(_ device: AVCaptureDevice, to capture: AVCaptureSession, busy: String) throws {
        let input = try AVCaptureDeviceInput(device: device)
        guard capture.canAddInput(input) else {
            throw RecordlyDeviceCaptureWriteError.failed(busy)
        }
        capture.addInput(input)
    }

    private func tearDown(_ capture: AVCaptureSession?) {
        let running = capture ?? session
        session = nil
        output = nil
        fileURL = nil
        if let running {
            let box = RecordlyCaptureSessionBox(running)
            queue.async { box.session.stopRunning() }
        }
        if usesCamera {
            usesCamera = false
            FacePresenceController.shared.teleprompterCapture(active: false)
        }
    }

    private func finish(url: URL, error: Error?) {
        let nsError = error as NSError?
        let succeeded = error == nil || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        let result: Result<URL, Error>
        if succeeded {
            result = .success(url)
        } else if let error {
            result = .failure(error)
        } else {
            result = .failure(RecordlyDeviceCaptureWriteError.failed("The recording was not saved."))
        }
        if let waiting = waiter {
            waiter = nil
            waiting.resume(returning: result)
        } else {
            finished = result
        }
    }

    private func map(_ error: Error) -> Error {
        if let write = error as? RecordlyDeviceCaptureWriteError { return write }
        let nsError = error as NSError
        if let classified = RecordlyDeviceCaptureWriteError.classify(domain: nsError.domain, code: nsError.code) {
            return classified
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           let classified = RecordlyDeviceCaptureWriteError.classify(domain: underlying.domain, code: underlying.code) {
            return classified
        }
        return RecordlyDeviceCaptureWriteError.failed("The recording stopped before it was saved.")
    }

    private static func access(_ media: AVMediaType) async -> RecordlyDevicePermission {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized:
            return .granted
        case .notDetermined:
            let allowed = await AVCaptureDevice.requestAccess(for: media)
            return allowed ? .granted : .denied
        default:
            return .denied
        }
    }
}

extension RecordlyDeviceCaptureEngine: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let recorded = outputFileURL
        let failure = error
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.finish(url: recorded, error: failure)
            }
        }
    }
}

/// `AVCaptureSession` can start and stop off the main thread, and it is not `Sendable`.
private final class RecordlyCaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}
