import Foundation

public enum FaceVerificationScreen: Equatable, Sendable {
    case loading
    case empty
    case ready
    case error(String)
}

public struct FaceVerificationControl: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var helper: String
    public var accessibilityLabel: String
    public var keyboardReachable: Bool

    public init(id: String, title: String, helper: String, accessibilityLabel: String, keyboardReachable: Bool) {
        self.id = id
        self.title = title
        self.helper = helper
        self.accessibilityLabel = accessibilityLabel
        self.keyboardReachable = keyboardReachable
    }
}

public struct FaceVerificationPreview: Equatable, Sendable {
    public var title: String
    public var status: String
    public var showsCameraImage: Bool
    public var accessibilityLabel: String

    public init(title: String, status: String, showsCameraImage: Bool, accessibilityLabel: String) {
        self.title = title
        self.status = status
        self.showsCameraImage = showsCameraImage
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct FaceVerificationSectionModel: Equatable, Sendable {
    public var title: String
    public var onboarding: String
    public var placement: FaceVerificationPlacement
    public var controls: [FaceVerificationControl]
    public var preview: FaceVerificationPreview
    public var screen: FaceVerificationScreen
    public var animationDuration: Double
    public var layout: FaceVerificationLayout

    public init(title: String, onboarding: String, placement: FaceVerificationPlacement, controls: [FaceVerificationControl], preview: FaceVerificationPreview, screen: FaceVerificationScreen, animationDuration: Double, layout: FaceVerificationLayout) {
        self.title = title
        self.onboarding = onboarding
        self.placement = placement
        self.controls = controls
        self.preview = preview
        self.screen = screen
        self.animationDuration = animationDuration
        self.layout = layout
    }

    /// Settings that already have a home. `face.approval` is the opt-in and is stored with them.
    public static let persistedKeys = ["face.approval", "face.presence", "face.lockAfter", "face.status"]
    public static let persistsApprovalSwitch = true

    public static func make(machine: FaceVerificationMachine, presenceEnabled: Bool, reduceMotion: Bool, vaultReadable: Bool?) -> FaceVerificationSectionModel {
        let screen = screen(machine: machine, vaultReadable: vaultReadable)
        let status = previewStatus(machine: machine, screen: screen)
        return FaceVerificationSectionModel(
            title: FaceVerificationCopy.title,
            onboarding: FaceVerificationCopy.onboarding,
            placement: .standard,
            controls: controls(machine: machine, presenceEnabled: presenceEnabled),
            preview: FaceVerificationPreview(
                title: "Check",
                status: status,
                showsCameraImage: false,
                accessibilityLabel: "Face verification status: \(status)"
            ),
            screen: screen,
            animationDuration: reduceMotion ? 0 : 0.22,
            layout: .standard
        )
    }

    private static func screen(machine: FaceVerificationMachine, vaultReadable: Bool?) -> FaceVerificationScreen {
        guard let vaultReadable else { return .loading }
        if !vaultReadable { return .error("The saved face could not be read. Face verification stays off.") }
        if machine.approvalEnabled && !machine.enrolled { return .empty }
        return .ready
    }

    private static func previewStatus(machine: FaceVerificationMachine, screen: FaceVerificationScreen) -> String {
        switch screen {
        case .loading: return "Loading"
        case .empty: return "No face saved"
        case .error: return "Unavailable"
        case .ready:
            switch machine.phase {
            case .disabled: return "Off"
            case .notEnrolled: return "No face saved"
            case .enrolling: return "Saving a face"
            case .idle: return "Ready"
            case .capturing: return "Looking"
            case .livenessCheck: return "Checking a blink or a turn"
            case .matched: return "Matched"
            case .rejected: return "Not approved"
            case .lockedOut: return "Locked"
            case .fallback: return "Use the fallback"
            }
        }
    }

    private static func controls(machine: FaceVerificationMachine, presenceEnabled: Bool) -> [FaceVerificationControl] {
        let approval = machine.approvalEnabled ? "On for this session" : "Off"
        let presence = presenceEnabled ? "On" : "Off"
        return [
            row("face.approval", "Face verification", "Off until you turn it on. The camera is asked for only then, and a relaunch starts off.", "Face verification, \(approval)"),
            row("face.enroll", "Save a face", "Several poses are kept as a protected template. A photo of the face is not kept.", "Save a face"),
            row("face.delete", "Delete saved face", "One action removes the template from this Mac.", "Delete saved face"),
            row("face.fallback", "Fallback", "Touch ID, Apple Watch, or your password. During a lock, none of these can approve.", "Fallback for face verification"),
            row(FacePresenceLink.enabledKey, "Lock when away", "Uses the existing face.presence switch. Off until you turn it on. The Mac locks when you leave and wakes when you come back.", "Lock when away, \(presence)"),
            row(FacePresenceLink.lockAfterKey, "Lock after", "How long you can be away before the Mac locks. This is the existing face.lockAfter choice.", "Lock after absent for"),
        ]
    }

    private static func row(_ id: String, _ title: String, _ helper: String, _ label: String) -> FaceVerificationControl {
        FaceVerificationControl(id: id, title: title, helper: helper, accessibilityLabel: label, keyboardReachable: true)
    }
}
