import Foundation
import ZeusCore

/// Settings and approvals call this. The camera is the presence camera. The prompt is `LocalOwnerPrompt`.
@MainActor
enum FaceApprovalBridge {
    private static var session = FaceApprovalSession()

    static func enabledChanged(_ on: Bool) {
        if !on {
            FacePresenceController.shared.setApprovalCapture(false)
            return
        }
        Task { _ = await FacePresenceController.shared.prepareApprovalCamera() }
    }

    static func checkNow() async -> String {
        guard SettingsStore.shared.bool(FaceApprovalPreference.key) else { return "Face verification is off." }
        let action = ApprovalAction(id: "settings-check", nonce: UUID().uuidString)
        guard let grant = await approve(action) else { return "Not approved." }
        return grant.method == .face ? "Matched." : "Approved with the fallback."
    }

    static func approve(_ action: ApprovalAction) async -> FaceApprovalGrant? {
        guard SettingsStore.shared.bool(FaceApprovalPreference.key) else { return nil }
        let controller = FacePresenceController.shared
        let access = map(await controller.prepareApprovalCamera())
        var camera = PresenceCameraPort(access: access)
        let enrolled = controller.enabledFaceCount > 0
        let now = ProcessInfo.processInfo.systemUptime
        if !session.machine.approvalEnabled {
            session.restore(enabled: true, enrolled: enrolled, camera: &camera, at: now)
        }
        let started = session.begin(action, camera: &camera, at: now)
        if started == .authenticateOwner {
            camera.setRunning(false)
            return await finish(action)
        }
        guard started == .watching else { return nil }
        let sample = await controller.oneApprovalSample()
        let next = session.observe(sample, camera: &camera, at: ProcessInfo.processInfo.systemUptime)
        if case .approved(let grant) = next { return grant }
        guard next == .authenticateOwner else { return nil }
        camera.setRunning(false)
        return await finish(action)
    }

    private static func finish(_ action: ApprovalAction) async -> FaceApprovalGrant? {
        let outcome = await LocalOwnerPrompt.evaluate()
        return session.finish(outcome, action: action, at: ProcessInfo.processInfo.systemUptime)
    }

    private static func map(_ access: FacePresenceMachine.CameraAccess) -> FaceCameraAccess {
        switch access {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        }
    }
}

private struct PresenceCameraPort: FaceApprovalCameraDriving {
    var access: FaceCameraAccess

    mutating func requestAccessIfNeeded() -> FaceCameraAccess { access }

    mutating func setRunning(_ running: Bool) {
        // The session calls this synchronously from the main-actor bridge.
        MainActor.assumeIsolated {
            FacePresenceController.shared.setApprovalCapture(running)
        }
    }
}
