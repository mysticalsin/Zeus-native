import AppKit
import Foundation
import Observation
import ZeusCore

/// Recordly microphone and camera. The top bar can create this at launch.
/// Creating it does not open a device, ask for permission, or start a recording.
@MainActor
@Observable
final class RecordlyDeviceCaptureController {
    static let shared = RecordlyDeviceCaptureController()

    private var machine = RecordlyDeviceCaptureMachine()
    private var engineBox: RecordlyDeviceCaptureEngine?
    private var generation = 0

    var phase: RecordlyDeviceCapturePhase { machine.phase }
    var selection: RecordlyDeviceCaptureSelection { machine.selection }
    var showsRecordingIndicator: Bool { machine.showsRecordingIndicator }
    /// Closed-notch wings use this. It is false until capture has actually started.
    var isRecording: Bool { showsRecordingIndicator }
    var statusText: String { machine.statusText }
    var recordButtonTitle: String { machine.recordButtonTitle }
    var failure: RecordlyDeviceCaptureFailure? {
        if case .failed(let failure) = machine.phase { return failure }
        return nil
    }

    var startedAt: Date? {
        guard let startedAt = machine.startedAt else { return nil }
        return Date(timeIntervalSinceReferenceDate: startedAt)
    }

    func denied(_ device: RecordlyDeviceCaptureDevice) -> Bool {
        guard failure?.kind == .permissionDenied else { return false }
        return failure?.settingsLinks.contains { $0.device == device } == true
    }

    /// Chip tap. Turns a device on or off. The first time a device is turned on, Zeus asks permission.
    /// This does not start capture.
    func press(_ device: RecordlyDeviceCaptureDevice) {
        if denied(device), let link = failure?.settingsLinks.first(where: { $0.device == device }) {
            openSettings(link)
            return
        }
        guard machine.phase != .recording, machine.phase != .finishing else { return }
        var next = machine.selection
        switch device {
        case .microphone: next.microphone.toggle()
        case .camera: next.camera.toggle()
        }
        generation += 1
        apply(machine.send(.select(next)), token: generation)
    }

    /// The only call that can start capture, and only once permission is already granted.
    func record() {
        generation += 1
        apply(machine.send(.record(now: Date().timeIntervalSinceReferenceDate)), token: generation)
    }

    func stop() {
        generation += 1
        apply(machine.send(.stop), token: generation)
    }

    func cancel() {
        generation += 1
        apply(machine.send(.cancel), token: generation)
    }

    func dismiss() {
        generation += 1
        _ = machine.send(.dismiss)
    }

    /// Opens the System Settings pane stored on the failure. Does not start capture.
    func openSettings(_ link: RecordlyDeviceCaptureSettingsLink) {
        NSWorkspace.shared.open(link.url)
    }

    private func engine() -> RecordlyDeviceCaptureEngine {
        if let engineBox { return engineBox }
        let created = RecordlyDeviceCaptureEngine()
        engineBox = created
        return created
    }

    private func apply(_ effects: [RecordlyDeviceCaptureEffect], token: Int) {
        for effect in effects {
            switch effect {
            case .requestPermission(let selection):
                Task { @MainActor in
                    let report = await self.engine().requestPermission(selection)
                    guard token == self.generation, self.machine.phase == .requestingPermission else { return }
                    self.apply(self.machine.send(.permission(report)), token: token)
                }
            case .startCapture(let selection):
                Task { @MainActor in
                    do {
                        try await self.engine().start(
                            selection: selection,
                            supportDirectory: ZeusPaths.supportDirectory,
                            now: Date()
                        )
                        guard token == self.generation, self.machine.phase == .recording else {
                            _ = try? await self.engine().stop(discard: true)
                            if self.machine.phase == .finishing {
                                self.apply(self.machine.send(.discarded), token: token)
                            }
                            return
                        }
                        self.apply(
                            self.machine.send(.captureDidStart(now: Date().timeIntervalSinceReferenceDate)),
                            token: token
                        )
                    } catch let error as RecordlyDeviceCaptureWriteError {
                        self.apply(self.machine.send(.writeFailed(error)), token: token)
                    } catch {
                        self.apply(self.machine.send(.writeFailed(.failed("The recording could not be started."))), token: token)
                    }
                }
            case .stopCapture(let discard):
                Task { @MainActor in
                    do {
                        let receipt = try await self.engine().stop(discard: discard)
                        if discard {
                            self.apply(self.machine.send(.discarded), token: token)
                        } else if let receipt {
                            self.apply(self.machine.send(.writeSucceeded(receipt)), token: token)
                        } else {
                            self.apply(self.machine.send(.writeFailed(.failed("The recording was not saved."))), token: token)
                        }
                    } catch let error as RecordlyDeviceCaptureWriteError {
                        self.apply(self.machine.send(.writeFailed(error)), token: token)
                    } catch {
                        self.apply(self.machine.send(.writeFailed(.failed("The recording was not saved."))), token: token)
                    }
                }
            }
        }
    }
}
