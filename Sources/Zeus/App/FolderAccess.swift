import AppKit
import Foundation
import ZeusCore

/// Manages on-demand access checks and requests for specific protected folders (Downloads and Desktop),
/// asking ONLY when the user enables the corresponding feature in Settings.
@MainActor
public enum FolderAccess {
    public enum Target: String, CaseIterable, Sendable {
        case downloads = "Downloads"
        case desktop = "Desktop"

        public var url: URL {
            switch self {
            case .downloads:
                return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            case .desktop:
                return ScreenshotDetector.location()
            }
        }

        public var askedKey: String {
            "permissions.folder.\(rawValue.lowercased()).asked"
        }
    }

    public enum Status: Equatable, Sendable {
        case granted
        case notDetermined
        case denied
    }

    /// Pure decision logic for `status(for:)`, factored out so it's unit-testable without ever
    /// touching a real TCC-protected folder -- doing that from a test binary risks popping a
    /// *brand new* one-time system consent dialog for that binary (the exact bug this guards
    /// against, just aimed at the test runner instead of Zeus.app).
    nonisolated static func status(asked: Bool, exists: Bool, listable: @autoclosure () -> Bool) -> Status {
        guard asked else { return .notDetermined }
        guard exists else { return .denied }
        return listable() ? .granted : .denied
    }

    public static func status(for target: Target) -> Status {
        // QA7 round 11 (report-11.md): this used to call `contentsOfDirectory` unconditionally,
        // including from passive SwiftUI `body` evaluation (`AirDropPermissionRow`/
        // `ScreenshotPermissionRow` read `status` just to pick which control to show). The
        // *first* read of a TCC-protected folder (Downloads/Desktop) blocks the calling thread
        // in the `open()` syscall itself until the user answers the one-time system consent
        // dialog -- so merely *viewing* a Settings page silently popped that dialog, and because
        // nothing here ever taps it (and must never: "never click permission prompts"), the main
        // thread hung forever. Confirmed from a `sample` capture: the thread sat unmoving inside
        // `open` (via `FolderAccess.status(for:)` -> `contentsOfDirectory`) for the entire hang.
        // This method's own doc comment already promised "asking ONLY when the user enables the
        // feature" -- only honor that: don't probe the real filesystem at all until `request(for:)`
        // (a direct, deliberate response to the user tapping "Allow") has set `askedKey`.
        let path = target.url.path
        return status(asked: UserDefaults.standard.bool(forKey: target.askedKey),
                      exists: FileManager.default.fileExists(atPath: path),
                      listable: (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil)
    }

    @discardableResult
    public static func request(for target: Target) -> Status {
        UserDefaults.standard.set(true, forKey: target.askedKey)
        let path = target.url.path
        if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
            return .granted
        }
        return .denied
    }

    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}
