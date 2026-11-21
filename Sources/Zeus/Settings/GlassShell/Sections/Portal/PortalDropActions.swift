import Foundation
import ZeusCore

/// The private inbox a converted file is written into. Created on demand, owner-only.
enum PortalDropActions {
    static func inboxPath() -> String? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("Zeus/PortalInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }

    static func convert(url: URL, current: PortalDropFlow) -> PortalDropFlow {
        switch current.phase {
        case .received, .converting:
            return current
        case .idle, .done, .failed:
            break
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let inbox = inboxPath() else {
            var flow = current
            _ = PortalDropCommand.drop(.failure(.insecureSandbox), on: &flow)
            return flow
        }
        let type = PortalFileTypes.fromExtension(url.pathExtension)
        return PortalLocalConversion.importDrop(path: url.path, declaredType: type, inbox: inbox)
    }
}
