import Testing
@testable import ZeusCore

@Suite struct CapturePermissionsTests {
    @Test func cameraMapsAuthorizationRawValues() {
        #expect(CapturePermissions.cameraState(authorizationRaw: 3) == .authorized)
        #expect(CapturePermissions.cameraState(authorizationRaw: 0) == .notDetermined)
        #expect(CapturePermissions.cameraState(authorizationRaw: 2) == .denied)
        #expect(CapturePermissions.cameraState(authorizationRaw: 1) == .denied)
    }

    @Test func screenRecordingUsesPreflightAndRequestAttempt() {
        #expect(CapturePermissions.screenRecordingState(preflightGranted: true, requestAttempted: false) == .authorized)
        #expect(CapturePermissions.screenRecordingState(preflightGranted: false, requestAttempted: false) == .notDetermined)
        #expect(CapturePermissions.screenRecordingState(preflightGranted: false, requestAttempted: true) == .denied)
    }

    @Test func debugReportFormat() {
        let line = CapturePermissions.debugReport(camera: .notDetermined, screen: .authorized)
        #expect(line == "ok=true camera=notDetermined screen=granted")
    }
}
