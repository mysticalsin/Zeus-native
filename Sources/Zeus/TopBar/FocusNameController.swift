import Foundation
import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Reads the local Focus store only while the setting is on. A permission failure is reported;
/// the files are never written.
@MainActor
final class FocusNameController {
    private let model: TopBarModel
    private let files: () -> FocusNameStore.Files

    init(model: TopBarModel, files: @escaping () -> FocusNameStore.Files = { FocusNameFiles.load() }) {
        self.model = model
        self.files = files
    }

    func setEnabled(_ on: Bool) {
        guard on else {
            model.systemFocus = .off
            return
        }
        model.systemFocus = FocusNameStore.status(enabled: true, files: files())
    }

    func stop() { setEnabled(false) }
}

enum FocusNameStatusText {
    static func line(_ status: FocusNameStatus) -> String {
        switch status {
        case .off: ""
        case .needsFullDiskAccess: "Needs Full Disk Access"
        case .unavailable: "Focus name unavailable"
        case .named(let name): name
        }
    }
}

enum FocusNameFiles {
    static func load() -> FocusNameStore.Files {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
        let configurations = readFile(base.appendingPathComponent("ModeConfigurations.json"))
        let assertions = readFile(base.appendingPathComponent("Assertions.json"))
        if configurations.denied || assertions.denied {
            return FocusNameStore.Files(configurations: nil, assertions: nil, permissionDenied: true)
        }
        return FocusNameStore.Files(configurations: configurations.data, assertions: assertions.data, permissionDenied: false)
    }

    /// Read-only, no-follow, and capped. A missing file is not a permission failure.
    private static func readFile(_ url: URL) -> (data: Data?, denied: Bool) {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 { return (nil, errno == EACCES || errno == EPERM) }
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < FocusNameStore.maxBytes {
            #if canImport(Darwin)
            let count = Darwin.read(fd, &buffer, min(buffer.count, FocusNameStore.maxBytes - data.count))
            #else
            let count = Glibc.read(fd, &buffer, min(buffer.count, FocusNameStore.maxBytes - data.count))
            #endif
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return (data, false)
    }
}
