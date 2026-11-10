import AVFoundation
import Foundation
import ZeusCore

/// Records camera and microphone to ~/Movies while you read. Permission is asked the first
/// time you press Record, never before.
@MainActor
final class PrompterRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case cameraDenied, micDenied, noCamera, cannotAdd

        var errorDescription: String? {
            switch self {
            case .cameraDenied: "Allow the camera for ZEUS in System Settings › Privacy & Security › Camera."
            case .micDenied: "Allow the microphone for ZEUS in System Settings › Privacy & Security › Microphone."
            case .noCamera: "No camera found."
            case .cannotAdd: "The camera or microphone is busy in another app."
            }
        }
    }

    private var session: AVCaptureSession?
    private var output: AVCaptureMovieFileOutput?
    private(set) var fileURL: URL?
    private(set) var startedAt: Date?
    /// Called with the finished file, or an error.
    var onFinish: (Result<URL, Error>) -> Void = { _ in }

    var isRecording: Bool { output?.isRecording == true }

    func start() async throws {
        guard await Self.access(.video) else { throw RecorderError.cameraDenied }
        guard await Self.access(.audio) else { throw RecorderError.micDenied }
        guard let camera = AVCaptureDevice.default(for: .video) else { throw RecorderError.noCamera }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high
        let output = AVCaptureMovieFileOutput()
        guard let video = try? AVCaptureDeviceInput(device: camera), session.canAddInput(video) else { throw RecorderError.cannotAdd }
        session.addInput(video)
        if let mic = AVCaptureDevice.default(for: .audio), let audio = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audio) {
            session.addInput(audio)
        }
        guard session.canAddOutput(output) else { throw RecorderError.cannotAdd }
        session.addOutput(output)
        session.commitConfiguration()

        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        let url = PrompterRecordingName.url(in: movies, at: Date())

        // startRunning blocks; keep it off the main thread.
        let box = SessionBox(session)
        await withCheckedContinuation { continuation in
            Self.queue.async {
                box.session.startRunning()
                continuation.resume()
            }
        }
        output.startRecording(to: url, recordingDelegate: self)
        self.session = session
        self.output = output
        fileURL = url
        startedAt = Date()
    }

    func stop() {
        output?.stopRecording()
    }

    private func tearDown() {
        let box = session.map(SessionBox.init)
        session = nil
        output = nil
        startedAt = nil
        Self.queue.async { box?.session.stopRunning() }
    }

    private static let queue = DispatchQueue(label: "zeus.prompter.capture")

    static func access(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }
}

extension PrompterRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // A stop reports an error with "finished successfully" set; that is still a good file.
        let success = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.tearDown()
                self.onFinish(success ? .success(outputFileURL) : .failure(error!))
            }
        }
    }
}

/// AVCaptureSession is thread-safe for start/stop but not marked Sendable.
private final class SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}
