import Foundation

/// Microphone and camera for Recordly. Capture is a separate path from screen recording.
/// The machine never asks for permission and never starts a device unless a command says the person tapped.
public struct RecordlyDeviceCaptureMachine: Equatable, Sendable {
    public private(set) var phase: RecordlyDeviceCapturePhase = .idle
    public private(set) var selection = RecordlyDeviceCaptureSelection()
    public private(set) var captureStartCount = 0
    public private(set) var permissionRequestCount = 0
    public private(set) var startedAt: TimeInterval?
    private var granted: Set<RecordlyDeviceCaptureDevice> = []
    private var captureAcknowledged = false
    private var discardOnFinish = false

    public init() {}

    /// The red dot is on only after a record tap and after the engine has actually started.
    public var showsRecordingIndicator: Bool {
        phase == .recording && captureAcknowledged
    }

    public var savedURL: URL? {
        if case .saved(let receipt) = phase { return receipt.url }
        return nil
    }

    public func permissionGranted(_ device: RecordlyDeviceCaptureDevice) -> Bool {
        granted.contains(device)
    }

    public var recordButtonTitle: String {
        switch (selection.microphone, selection.camera) {
        case (true, true): "Record microphone and camera"
        case (false, true): "Record camera"
        default: "Record microphone"
        }
    }

    public var statusText: String {
        switch phase {
        case .idle:
            ""
        case .requestingPermission:
            "Zeus is asking to use the \(selection.deviceName)."
        case .ready:
            "Ready. Press Record. Nothing is recorded until you do."
        case .recording:
            captureAcknowledged ? "Recording \(selection.deviceName)." : "Starting \(selection.deviceName)."
        case .finishing:
            discardOnFinish ? "Cancelling the recording." : "Saving the recording on this Mac."
        case .saved:
            "Saved on this Mac. Nothing was uploaded."
        case .failed(let failure):
            failure.message
        }
    }

    public mutating func send(_ command: RecordlyDeviceCaptureCommand) -> [RecordlyDeviceCaptureEffect] {
        switch command {
        case .launch, .appear:
            return []
        case .select(let next):
            return select(next)
        case .record:
            return record()
        case .captureDidStart(let now):
            guard phase == .recording, !captureAcknowledged else { return [] }
            captureAcknowledged = true
            startedAt = now
            return []
        case .permission(let report):
            return apply(report)
        case .stop:
            guard phase == .recording else { return [] }
            phase = .finishing
            discardOnFinish = false
            captureAcknowledged = false
            return [.stopCapture(discard: false)]
        case .cancel:
            guard phase == .recording else { return [] }
            phase = .finishing
            discardOnFinish = true
            captureAcknowledged = false
            return [.stopCapture(discard: true)]
        case .discarded:
            guard phase == .finishing, discardOnFinish else { return [] }
            discardOnFinish = false
            phase = readyIfGranted()
            return []
        case .writeSucceeded(let receipt):
            return accept(receipt)
        case .writeFailed(let error):
            return fail(error)
        case .dismiss:
            guard phase.isSaved || phase.isFailed else { return [] }
            selection = RecordlyDeviceCaptureSelection()
            captureAcknowledged = false
            startedAt = nil
            discardOnFinish = false
            phase = .idle
            return []
        }
    }

    private mutating func select(_ next: RecordlyDeviceCaptureSelection) -> [RecordlyDeviceCaptureEffect] {
        switch phase {
        case .recording, .finishing:
            return []
        case .idle, .requestingPermission, .ready, .saved, .failed:
            break
        }
        selection = next
        captureAcknowledged = false
        startedAt = nil
        if next.isEmpty {
            phase = .idle
            return []
        }
        if next.devices.allSatisfy({ granted.contains($0) }) {
            phase = .ready
            return []
        }
        phase = .requestingPermission
        permissionRequestCount += 1
        return [.requestPermission(next)]
    }

    private mutating func record() -> [RecordlyDeviceCaptureEffect] {
        guard phase == .ready, !selection.isEmpty else { return [] }
        guard selection.devices.allSatisfy({ granted.contains($0) }) else { return [] }
        phase = .recording
        captureAcknowledged = false
        startedAt = nil
        discardOnFinish = false
        captureStartCount += 1
        return [.startCapture(selection)]
    }

    private mutating func apply(_ report: RecordlyDevicePermissionReport) -> [RecordlyDeviceCaptureEffect] {
        guard phase == .requestingPermission else { return [] }
        var denied: [RecordlyDeviceCaptureDevice] = []
        var unanswered = false
        for device in selection.devices {
            switch report.status(for: device) {
            case .granted:
                granted.insert(device)
            case .denied:
                granted.remove(device)
                denied.append(device)
            case .notRequested:
                unanswered = true
            }
        }
        if !denied.isEmpty {
            phase = .failed(.permissionDenied(denied))
            return []
        }
        if unanswered {
            phase = .failed(RecordlyDeviceCaptureFailure(
                kind: .engine,
                message: "Zeus did not receive a permission answer.",
                settingsLinks: []
            ))
            return []
        }
        phase = .ready
        return []
    }

    private mutating func accept(_ receipt: RecordlyDeviceCaptureReceipt) -> [RecordlyDeviceCaptureEffect] {
        guard phase == .finishing, !discardOnFinish else { return [] }
        if receipt.uploaded {
            phase = .failed(RecordlyDeviceCaptureFailure(
                kind: .engine,
                message: "Zeus does not upload recordings. This one was not saved.",
                settingsLinks: []
            ))
            return []
        }
        if receipt.mode != 0o600 || !receipt.url.isFileURL {
            phase = .failed(RecordlyDeviceCaptureFailure(
                kind: .engine,
                message: "The recording could not be kept private, so it was not saved.",
                settingsLinks: []
            ))
            return []
        }
        phase = .saved(receipt)
        return []
    }

    private mutating func fail(_ error: RecordlyDeviceCaptureWriteError) -> [RecordlyDeviceCaptureEffect] {
        guard phase == .recording || phase == .finishing else { return [] }
        let stopDevices = phase == .recording
        captureAcknowledged = false
        switch error {
        case .diskFull:
            phase = .failed(RecordlyDeviceCaptureFailure(
                kind: .diskFull,
                message: "This Mac is out of space, so the recording was not saved.",
                settingsLinks: []
            ))
        case .permissionDenied(let device):
            phase = .failed(.permissionDenied([device]))
        case .failed(let message):
            phase = .failed(RecordlyDeviceCaptureFailure(kind: .engine, message: message, settingsLinks: []))
        }
        return stopDevices ? [.stopCapture(discard: true)] : []
    }

    private func readyIfGranted() -> RecordlyDeviceCapturePhase {
        if !selection.isEmpty, selection.devices.allSatisfy({ granted.contains($0) }) {
            return .ready
        }
        return .idle
    }
}

public enum RecordlyDeviceCapturePhase: Equatable, Sendable {
    case idle
    case requestingPermission
    case ready
    case recording
    case finishing
    case saved(RecordlyDeviceCaptureReceipt)
    case failed(RecordlyDeviceCaptureFailure)

    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

public enum RecordlyDeviceCaptureCommand: Equatable, Sendable {
    case launch
    case appear
    case select(RecordlyDeviceCaptureSelection)
    case record(now: TimeInterval)
    case captureDidStart(now: TimeInterval)
    case permission(RecordlyDevicePermissionReport)
    case stop
    case cancel
    case discarded
    case writeSucceeded(RecordlyDeviceCaptureReceipt)
    case writeFailed(RecordlyDeviceCaptureWriteError)
    case dismiss
}

public enum RecordlyDeviceCaptureEffect: Equatable, Sendable {
    case requestPermission(RecordlyDeviceCaptureSelection)
    case startCapture(RecordlyDeviceCaptureSelection)
    case stopCapture(discard: Bool)
}

public enum RecordlyDeviceCaptureDevice: String, Equatable, Hashable, Sendable {
    case microphone
    case camera

    public var settingsURL: URL {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .camera:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        }
    }

    public var recoveryMessage: String {
        switch self {
        case .microphone:
            "Microphone access is off for Zeus. Open System Settings, then Privacy & Security, then Microphone, and allow Zeus."
        case .camera:
            "Camera access is off for Zeus. Open System Settings, then Privacy & Security, then Camera, and allow Zeus."
        }
    }

    public var settingsButtonTitle: String {
        switch self {
        case .microphone: "Open Microphone settings"
        case .camera: "Open Camera settings"
        }
    }
}

public struct RecordlyDeviceCaptureSelection: Equatable, Sendable {
    public var microphone: Bool
    public var camera: Bool

    public init(microphone: Bool = false, camera: Bool = false) {
        self.microphone = microphone
        self.camera = camera
    }

    public static let microphone = Self(microphone: true, camera: false)
    public static let camera = Self(microphone: false, camera: true)
    public static let both = Self(microphone: true, camera: true)

    public var isEmpty: Bool { !microphone && !camera }

    public var devices: [RecordlyDeviceCaptureDevice] {
        var list: [RecordlyDeviceCaptureDevice] = []
        if microphone { list.append(.microphone) }
        if camera { list.append(.camera) }
        return list
    }

    public var deviceName: String {
        switch (microphone, camera) {
        case (true, true): "microphone and camera"
        case (false, true): "camera"
        default: "microphone"
        }
    }
}

public enum RecordlyDevicePermission: Equatable, Sendable {
    case notRequested
    case granted
    case denied
}

public struct RecordlyDevicePermissionReport: Equatable, Sendable {
    public var microphone: RecordlyDevicePermission
    public var camera: RecordlyDevicePermission

    public init(microphone: RecordlyDevicePermission, camera: RecordlyDevicePermission) {
        self.microphone = microphone
        self.camera = camera
    }

    public static let microphoneGranted = Self(microphone: .granted, camera: .notRequested)
    public static let microphoneDenied = Self(microphone: .denied, camera: .notRequested)
    public static let cameraGranted = Self(microphone: .notRequested, camera: .granted)
    public static let cameraDenied = Self(microphone: .notRequested, camera: .denied)
    public static let bothGranted = Self(microphone: .granted, camera: .granted)
    public static let bothDenied = Self(microphone: .denied, camera: .denied)

    public func status(for device: RecordlyDeviceCaptureDevice) -> RecordlyDevicePermission {
        switch device {
        case .microphone: microphone
        case .camera: camera
        }
    }
}

public struct RecordlyDeviceCaptureSettingsLink: Equatable, Sendable {
    public var device: RecordlyDeviceCaptureDevice
    public var url: URL

    public init(device: RecordlyDeviceCaptureDevice, url: URL) {
        self.device = device
        self.url = url
    }
}

public struct RecordlyDeviceCaptureFailure: Equatable, Sendable {
    public var kind: Kind
    public var message: String
    public var settingsLinks: [RecordlyDeviceCaptureSettingsLink]

    public enum Kind: Equatable, Sendable {
        case permissionDenied
        case diskFull
        case engine
    }

    public init(kind: Kind, message: String, settingsLinks: [RecordlyDeviceCaptureSettingsLink]) {
        self.kind = kind
        self.message = message
        self.settingsLinks = settingsLinks
    }

    static func permissionDenied(_ devices: [RecordlyDeviceCaptureDevice]) -> RecordlyDeviceCaptureFailure {
        let unique = devices.reduce(into: [RecordlyDeviceCaptureDevice]()) { list, device in
            if !list.contains(device) { list.append(device) }
        }
        return RecordlyDeviceCaptureFailure(
            kind: .permissionDenied,
            message: unique.map(\.recoveryMessage).joined(separator: "\n"),
            settingsLinks: unique.map { RecordlyDeviceCaptureSettingsLink(device: $0, url: $0.settingsURL) }
        )
    }
}

/// The existing Record control is the only start. The microphone flag follows the chip.
public enum RecordlyPrimaryRecord {
    /// True only when the microphone chip is on and permission was already granted.
    /// A chip that is off, or still waiting, stays off. Nothing here starts a device.
    public static func includeMicrophone(chipOn: Bool, permissionGranted: Bool) -> Bool {
        chipOn && permissionGranted
    }

    /// Device capture starts from the primary Record, and only once the machine is ready.
    public static func startsDeviceCapture(phase: RecordlyDeviceCapturePhase) -> Bool {
        phase == .ready
    }

    /// A screen session that is already recording is the recorder. A chip must not open another.
    public static func blocksAnotherRecorder(screenSessionActive: Bool) -> Bool {
        screenSessionActive
    }

    /// Ready, and no screen session is already writing a file.
    public static func mayStartDeviceRecorder(phase: RecordlyDeviceCapturePhase, screenSessionActive: Bool) -> Bool {
        startsDeviceCapture(phase: phase) && !blocksAnotherRecorder(screenSessionActive: screenSessionActive)
    }
}

public struct RecordlyDeviceCaptureReceipt: Equatable, Sendable {
    public var url: URL
    public var byteCount: Int
    public var mode: Int
    /// Always false. A true value is refused and nothing is presented as saved.
    public var uploaded: Bool

    public init(url: URL, byteCount: Int, mode: Int, uploaded: Bool) {
        self.url = url
        self.byteCount = byteCount
        self.mode = mode
        self.uploaded = uploaded
    }
}
