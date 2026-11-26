import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// How large a chosen chime may be, and how big a decode buffer may be.
public enum ChimeAudioLimits {
    public static let maxFileBytes = 2_000_000
    public static let maxChannels = 2
    public static let minimumSampleRate = 8_000.0
    public static let maximumSampleRate = 96_000.0
    public static let maxSeconds = 2.0

    /// Frames that may be allocated for this header. Nil when the header asks for an unbounded buffer.
    public static func frameCount(headerFrames: Int64, sampleRate: Double, channels: Int) -> Int? {
        guard (1...maxChannels).contains(channels) else { return nil }
        guard sampleRate.isFinite, (minimumSampleRate...maximumSampleRate).contains(sampleRate) else { return nil }
        guard headerFrames > 0 else { return nil }
        let secondsCap = Int64((sampleRate * maxSeconds).rounded(.down))
        guard secondsCap > 0, secondsCap <= 192_000 else { return nil }
        let frames = min(headerFrames, secondsCap)
        let channels64 = Int64(channels)
        guard frames <= Int64(Int.max) / 4 / channels64 else { return nil }
        guard frames * channels64 * 4 <= Int64(maxFileBytes) else { return nil }
        return Int(frames)
    }
}

/// Bytes of a regular file, read from the descriptor that was opened with `O_NOFOLLOW`.
/// A symlink is refused. The size comes from `fstat` on that descriptor, then the read uses the same descriptor.
public enum ChimeFileAccess {
    public enum Problem: Equatable, Error, Sendable {
        case unreadable
        case notRegular
        case tooLarge
    }

    public static func measureRegularFile(at path: String, maxBytes: Int = ChimeAudioLimits.maxFileBytes) -> Result<Int, Problem> {
        switch opened(path, maxBytes: maxBytes) {
        case .success(let file):
            close(file.descriptor)
            return .success(file.bytes)
        case .failure(let problem):
            return .failure(problem)
        }
    }

    public static func readRegularFile(at path: String, maxBytes: Int = ChimeAudioLimits.maxFileBytes) -> Result<Data, Problem> {
        switch opened(path, maxBytes: maxBytes) {
        case .failure(let problem):
            return .failure(problem)
        case .success(let file):
            defer { close(file.descriptor) }
            var data = Data(count: file.bytes)
            var filled = 0
            let complete = data.withUnsafeMutableBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                while filled < file.bytes {
                    let count = read(file.descriptor, base.advanced(by: filled), file.bytes - filled)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { return false }
                    filled += count
                }
                return true
            }
            guard complete, filled == file.bytes else { return .failure(.unreadable) }
            return .success(data)
        }
    }

    private struct OpenFile {
        var descriptor: Int32
        var bytes: Int
    }

    /// Opens first, then `fstat`s that descriptor. The size is never taken from a path lookup.
    private static func opened(_ path: String, maxBytes: Int) -> Result<OpenFile, Problem> {
        guard maxBytes > 0, maxBytes <= ChimeAudioLimits.maxFileBytes else { return .failure(.tooLarge) }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return .failure(.unreadable) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            close(descriptor)
            return .failure(.unreadable)
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            close(descriptor)
            return .failure(.notRegular)
        }
        guard info.st_size > 0 else {
            close(descriptor)
            return .failure(.unreadable)
        }
        guard info.st_size <= Int64(maxBytes) else {
            close(descriptor)
            return .failure(.tooLarge)
        }
        return .success(OpenFile(descriptor: descriptor, bytes: Int(info.st_size)))
    }
}
