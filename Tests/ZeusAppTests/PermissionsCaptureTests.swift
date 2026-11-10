import Testing
import ZeusCore
@testable import Zeus

@Suite("Camera and screen permissions", .serialized)
@MainActor
struct PermissionsCaptureTests {
    @Test func captureReportUsesInjectedStatesWithoutRequestingAccess() {
        var requests = 0
        let model = PermissionsModel(captureAccess: .init(
            camera: { .denied }, screen: { .authorized }, requestCamera: { requests += 1 }
        ))
        let report = model.capturePermissionsReport
        #expect(report == CapturePermissions.debugReport(camera: .denied, screen: .authorized))
        #expect(requests == 0)
    }

    @Test func cameraRequestReadsTheResultWithoutStartingCapture() async {
        var state = PermissionState.notDetermined
        var requests = 0
        let model = PermissionsModel(captureAccess: .init(
            camera: { state }, screen: { .denied },
            requestCamera: { requests += 1; state = .authorized }
        ))
        await model.requestCamera()
        #expect(requests == 1)
        #expect(model.cameraPermissionState == .authorized)
        #expect(model.granted[.camera] == true)
        await model.requestCamera()
        #expect(requests == 1)
    }

    @Test func deniedCameraIsNotPromptedAgain() async {
        var requests = 0
        let model = PermissionsModel(captureAccess: .init(
            camera: { .denied }, screen: { .notDetermined }, requestCamera: { requests += 1 }
        ))
        await model.requestCamera()
        #expect(requests == 0)
        #expect(model.granted[.camera] == false)
    }
}
