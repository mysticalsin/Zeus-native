import Foundation

/// Camera and Screen Recording rows in Settings (PERM-CAM). Pure logic for tests; the app
/// supplies live TCC answers from AVFoundation and CoreGraphics.
public enum CapturePermissions {
    /// Matches `AVAuthorizationStatus` raw values used by the app layer.
    public static func cameraState(authorizationRaw: Int) -> PermissionState {
        switch authorizationRaw {
        case 3: .authorized
        case 0: .notDetermined
        default: .denied
        }
    }

    /// macOS exposes only `CGPreflightScreenCaptureAccess`; after an explicit request attempt,
    /// a still-false preflight is treated as denied.
    public static func screenRecordingState(preflightGranted: Bool, requestAttempted: Bool) -> PermissionState {
        if preflightGranted { return .authorized }
        if !requestAttempted { return .notDetermined }
        return .denied
    }

    public static func statusLabel(_ state: PermissionState) -> String {
        switch state {
        case .authorized: "granted"
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        }
    }

    /// One line for `zeus debug permissions` (silent E2E).
    public static func debugReport(camera: PermissionState, screen: PermissionState) -> String {
        "ok=true camera=\(statusLabel(camera)) screen=\(statusLabel(screen))"
    }
}
