import Foundation

/// Puts a staged helper in place of the installed one. A rejected stage must not remove the
/// previous helper or its registration.
public enum BundledHelperPublish {
    public enum Failure: Error, Equatable, Sendable {
        case rejected
        case unreadableStage
        case swapFailed
    }

    public static func replaceIfAccepted(
        staged: URL,
        destination: URL,
        registration: URL,
        accept: (URL) -> Bool,
        writeRegistration: () throws -> Void
    ) -> Result<Void, Failure> {
        let files = FileManager.default
        guard staged.isFileURL, destination.isFileURL, registration.isFileURL else { return .failure(.unreadableStage) }
        guard files.fileExists(atPath: staged.path) else { return .failure(.unreadableStage) }
        guard accept(staged) else {
            try? files.removeItem(at: staged)
            return .failure(.rejected)
        }
        let backup = destination.appendingPathExtension("bak")
        try? files.removeItem(at: backup)
        let hadDestination = files.fileExists(atPath: destination.path)
        do {
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if hadDestination { try files.moveItem(at: destination, to: backup) }
            try files.moveItem(at: staged, to: destination)
            do {
                try writeRegistration()
            } catch {
                try? files.removeItem(at: destination)
                if hadDestination { try? files.moveItem(at: backup, to: destination) }
                return .failure(.swapFailed)
            }
            if hadDestination { try? files.removeItem(at: backup) }
            return .success(())
        } catch {
            if hadDestination, !files.fileExists(atPath: destination.path) {
                try? files.moveItem(at: backup, to: destination)
            }
            return .failure(.swapFailed)
        }
    }
}
