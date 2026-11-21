import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Puts a staged helper in place of the installed one. The new file is renamed over the old
/// one, so the destination name is never absent. A rejected stage removes only the staged file.
/// A registration write that throws puts the previous bridge and the previous registration back.
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
        let hadDestination = files.fileExists(atPath: destination.path)
        let previousBridge = hadDestination ? try? Data(contentsOf: destination) : nil
        let hadRegistration = files.fileExists(atPath: registration.path)
        let previousRegistration = hadRegistration ? try? Data(contentsOf: registration) : nil
        do {
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try replaceFile(destination, with: staged)
            do {
                try writeRegistration()
            } catch {
                if let previousBridge {
                    try? restore(previousBridge, to: destination)
                } else {
                    try? files.removeItem(at: destination)
                }
                if let previousRegistration {
                    try? restore(previousRegistration, to: registration)
                } else if files.fileExists(atPath: registration.path) {
                    try? files.removeItem(at: registration)
                }
                try? files.removeItem(at: staged)
                return .failure(.swapFailed)
            }
            return .success(())
        } catch {
            try? files.removeItem(at: staged)
            return .failure(.swapFailed)
        }
    }

    /// `rename` replaces an existing file in one step. The destination name stays occupied.
    private static func replaceFile(_ destination: URL, with staged: URL) throws {
        var result: Int32 = -1
        staged.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                if let source, let target { result = rename(source, target) }
            }
        }
        if result != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    private static func restore(_ data: Data, to url: URL) throws {
        let temporary = url.appendingPathExtension("restore")
        try data.write(to: temporary, options: .atomic)
        try replaceFile(url, with: temporary)
    }
}
