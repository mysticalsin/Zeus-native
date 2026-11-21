// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): CameraManager.swift, CameraDeviceCatalog.swift.
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import ZeusCore

/// One camera frame on its way to one analysis: pixels in memory, and the monotonic time it arrived.
/// The analysis reads it and lets it go; nothing keeps it.
struct FaceFrame: @unchecked Sendable {
    let image: CGImage
    let uptime: Double
}

/// What the camera reports besides frames.
enum FaceCameraEvent: Equatable, Sendable {
    case deviceLost
    case interrupted
    case interruptionEnded
    case runtimeError
}

/// Where frames come from. The real one is `FaceCamera`; tests use a fake that never opens a camera.
protocol FaceFrameSource: AnyObject, Sendable {
    /// Opens the camera and starts delivering the frames the sampler admits. Both closures are called on the
    /// source's own queue, never on the main actor.
    func start(deliver: @escaping @Sendable (FaceFrame) -> Void, report: @escaping @Sendable (FaceCameraEvent) -> Void)
    /// Stops the camera and closes the gate at once: a frame still in flight is dropped, never delivered.
    func stop()
    /// The analysis of the last delivered frame ended, so the next admitted frame may be delivered.
    func analysisFinished()
}

/// The gate between the capture queue and the analyzer. The sampler is asked before a frame is converted, so a
/// frame that will not be analyzed costs a comparison. Once closed, nothing more is delivered.
final class FaceFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var sampler = PresenceSampler()
    private var handler: (@Sendable (FaceFrame) -> Void)?
    private var generation = 0

    /// Opens the gate for one run and returns its generation. A newer open or a close makes it stale.
    func open(deliver: @escaping @Sendable (FaceFrame) -> Void) -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        sampler = PresenceSampler()
        handler = deliver
        return generation
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        handler = nil
        sampler = PresenceSampler()
    }

    func isCurrent(_ run: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return handler != nil && generation == run
    }

    /// True when this frame should be converted and analyzed. False while closed.
    func admit(at uptime: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard handler != nil else { return false }
        return sampler.shouldAnalyze(at: uptime)
    }

    /// Hands an admitted frame on, or drops it when the gate closed since. Either way the sampler is never left
    /// waiting on an analysis that will not run.
    func deliver(_ frame: FaceFrame) {
        lock.lock()
        let target = handler
        if target == nil { sampler.analysisFinished() }
        lock.unlock()
        target?(frame)
    }

    func analysisFinished() {
        lock.lock(); defer { lock.unlock() }
        sampler.analysisFinished()
    }
}

/// The AVFoundation camera for face presence: one capture session on its own queue, BGRA frames at 640 by 480, late
/// frames dropped, the built-in front camera first. It only runs between `start` and `stop`, and `start` is called
/// only while the machine wants the camera.
final class FaceCamera: NSObject, FaceFrameSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "zeus.face-presence.camera")
    private let gate = FaceFrameGate()
    // Touched only on `queue`.
    private var session: AVCaptureSession?
    /// The output does not keep its delegate alive, so this does.
    private var delegate: FrameDelegate?
    private var observers: [NSObjectProtocol] = []
    private var boundDevice: AVCaptureDevice?
    private var runs = CameraRun()

    func start(deliver: @escaping @Sendable (FaceFrame) -> Void, report: @escaping @Sendable (FaceCameraEvent) -> Void) {
        let run = gate.open(deliver: deliver)
        _ = runs.start()
        queue.async { [self] in
            guard gate.isCurrent(run) else { return }
            if session != nil {
                rebind(run: run, report: report)
                return
            }
            open(run: run, report: report)
        }
    }

    func stop() {
        gate.close()
        queue.async { [self] in tearDown() }
    }

    func analysisFinished() { gate.analysisFinished() }

    // MARK: Queue work

    private func open(run: Int, report: @escaping @Sendable (FaceCameraEvent) -> Void) {
        guard let device = Self.preferredDevice(), let input = try? AVCaptureDeviceInput(device: device) else {
            report(.runtimeError)
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        let delegate = FrameDelegate(gate: gate)
        output.setSampleBufferDelegate(delegate, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            report(.runtimeError)
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        self.session = session
        self.delegate = delegate
        self.boundDevice = device
        installObservers(run: run, session: session, device: device, report: report)
        session.startRunning()
    }

    /// A second start keeps the session and points interruption events at the new run.
    private func rebind(run: Int, report: @escaping @Sendable (FaceCameraEvent) -> Void) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard let session, let device = boundDevice else { return }
        installObservers(run: run, session: session, device: device, report: report)
    }

    private func installObservers(run: Int, session: AVCaptureSession, device: AVCaptureDevice,
                                  report: @escaping @Sendable (FaceCameraEvent) -> Void) {
        let center = NotificationCenter.default
        let pairs: [(Notification.Name, AnyObject?, FaceCameraEvent)] = [
            (AVCaptureSession.runtimeErrorNotification, session, .runtimeError),
            (AVCaptureSession.wasInterruptedNotification, session, .interrupted),
            (AVCaptureSession.interruptionEndedNotification, session, .interruptionEnded),
            (AVCaptureDevice.wasDisconnectedNotification, device, .deviceLost),
        ]
        observers = pairs.map { name, object, event in
            center.addObserver(forName: name, object: object, queue: nil) { [gate] _ in
                // A notice that arrives after the run ended says nothing about the next one.
                if gate.isCurrent(run) { report(event) }
            }
        }
    }

    private func tearDown() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard let session else { return }
        self.session = nil
        boundDevice = nil
        delegate = nil
        session.stopRunning()
        session.beginConfiguration()
        for output in session.outputs {
            (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
        }
        for input in session.inputs { session.removeInput(input) }
        session.commitConfiguration()
    }

    /// The built-in camera first, then whatever the system calls its default. No picker.
    private static func preferredDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// Sample buffers arrive on the capture queue, off the main actor. The sampler is asked first, so a frame that
    /// will not be analyzed is dropped before any conversion.
    private final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        private let gate: FaceFrameGate
        private let context = CIContext()
        /// Detection needs a modest size; the capture preset is already 640 by 480.
        private let longEdge: CGFloat = 640

        init(gate: FaceFrameGate) { self.gate = gate }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            let now = ProcessInfo.processInfo.systemUptime
            guard gate.admit(at: now) else { return }
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { gate.analysisFinished(); return }
            var image = CIImage(cvPixelBuffer: buffer)
            let edge = max(image.extent.width, image.extent.height)
            if edge > longEdge {
                let scale = longEdge / edge
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            guard let converted = context.createCGImage(image, from: image.extent) else { gate.analysisFinished(); return }
            gate.deliver(FaceFrame(image: converted, uptime: now))
        }
    }
}
