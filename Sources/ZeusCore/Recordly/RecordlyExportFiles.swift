import Darwin
import Foundation

/// Publishes a finished export with one atomic, exclusive rename. A competing export cannot be overwritten
/// between a file-exists check and a rename. The caller owns/removes the temporary file on failure or cancel.
public enum RecordlyExportFiles {
    public static func publish(
        temp: URL, directory: URL, date: Date, fileExtension: String,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> URL {
        for index in 1...99 {
            try checkCancellation()
            let destination = directory.appendingPathComponent(
                RecordlyExportPlan.fileName(date: date, fileExtension: fileExtension, collisionIndex: index)
            )
            if renameatx_np(AT_FDCWD, temp.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL)) == 0 {
                return destination
            }
            let code = errno
            if code == EEXIST { continue }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
