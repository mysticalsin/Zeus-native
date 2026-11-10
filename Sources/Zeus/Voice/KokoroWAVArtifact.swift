import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Publishes a private PCM WAV by descriptor. Path replacement cannot substitute another
/// artifact after validation, and the final copy must contain complete bounded fmt/data chunks.
enum KokoroWAVArtifact {
    static func publish(_ source: URL, to target: URL, maximumBytes: Int, shouldStop: @Sendable () -> Bool = { false }) -> Bool {
        let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard input >= 0 else { return false }
        defer { closeDescriptor(input) }
        return publish(descriptor: input, to: target, maximumBytes: maximumBytes, shouldStop: shouldStop)
    }

    /// Borrows an already opened input descriptor; its owner retains responsibility for closing it.
    static func publish(descriptor input: Int32, to target: URL, maximumBytes: Int, shouldStop: @Sendable () -> Bool = { false }) -> Bool {
        guard !shouldStop() else { return false }
        var info = stat()
        guard fstat(input, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size >= 44, info.st_size <= maximumBytes else { return false }
        let output = open(target.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { return false }
        var published = false
        defer {
            closeDescriptor(output)
            if !published { try? FileManager.default.removeItem(at: target) }
        }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        var remaining = Int(info.st_size)
        while remaining > 0 {
            guard !shouldStop() else { return false }
            let count = read(input, &bytes, min(bytes.count, remaining))
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return false }
            var offset = 0
            while offset < count {
                let written = bytes.withUnsafeBytes { buffer in
                    write(output, buffer.baseAddress!.advanced(by: offset), count - offset)
                }
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            remaining -= count
        }
        // Validate the bytes actually copied, not a pathname or an earlier header observation.
        guard !shouldStop(), validPCM(descriptor: output, bytes: Int(info.st_size)), !shouldStop() else { return false }
        published = true
        return true
    }

    private static func validPCM(descriptor: Int32, bytes: Int) -> Bool {
        func chunk(_ offset: Int, _ count: Int) -> [UInt8]? {
            guard offset >= 0, count <= bytes - offset else { return nil }
            var result = [UInt8](repeating: 0, count: count)
            var copied = 0
            while copied < count {
                let amount = result.withUnsafeMutableBytes { buffer in
                    pread(descriptor, buffer.baseAddress!.advanced(by: copied), count - copied, off_t(offset + copied))
                }
                if amount < 0, errno == EINTR { continue }
                guard amount > 0 else { return nil }
                copied += amount
            }
            return result
        }
        func u16(_ value: [UInt8], _ start: Int) -> Int {
            Int(value[start]) | Int(value[start + 1]) << 8
        }
        func u32(_ value: [UInt8], _ start: Int) -> Int {
            Int(value[start]) | Int(value[start + 1]) << 8 | Int(value[start + 2]) << 16 | Int(value[start + 3]) << 24
        }
        guard let header = chunk(0, 12), Array(header[0..<4]) == Array("RIFF".utf8),
              Array(header[8..<12]) == Array("WAVE".utf8), u32(header, 4) + 8 == bytes else { return false }
        var position = 12, chunks = 0
        var alignment: Int?, dataBytes: Int?
        while position < bytes {
            guard chunks < 4096, let header = chunk(position, 8) else { return false }
            chunks += 1
            let length = u32(header, 4), body = position + 8
            guard length <= bytes - body else { return false }
            switch String(decoding: header[0..<4], as: UTF8.self) {
            case "fmt ":
                guard alignment == nil, length >= 16, let format = chunk(body, 16) else { return false }
                let channels = u16(format, 2), rate = u32(format, 4), align = u16(format, 12)
                guard u16(format, 0) == 1, (1...2).contains(channels), (8_000...192_000).contains(rate),
                      u16(format, 14) == 16, align == channels * 2, u32(format, 8) == rate * align else { return false }
                alignment = align
            case "data":
                guard dataBytes == nil, length > 0 else { return false }
                dataBytes = length
            default: break
            }
            position = body + length + (length & 1)
            guard position <= bytes else { return false }
        }
        guard let alignment, let dataBytes else { return false }
        return position == bytes && dataBytes % alignment == 0
    }

    private static func closeDescriptor(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #else
        _ = Glibc.close(descriptor)
        #endif
    }
}
