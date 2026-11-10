import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Runs a local helper without a shell. The caller supplies a worker thread: this API is synchronous.
/// All three pipes share one monotonic deadline and an output budget. A stalled helper cannot retain
/// unbounded output or leave a caller waiting for stdin, SIGTERM, or an inherited output descriptor.
public enum BoundedSubprocess {
    private static let launchLock = NSLock()
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
        public let error: String
    }

    public static func run(_ executable: String, _ arguments: [String], input: Data? = nil,
                           timeout: TimeInterval = 600, maxOutputBytes: Int = 8 * 1024 * 1024) -> Result {
        guard timeout.isFinite, timeout > 0, maxOutputBytes > 0 else {
            return Result(status: 125, output: "", error: "Invalid helper limits.")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        launchLock.lock()
        var launching = true
        defer { if launching { launchLock.unlock() } }
        let out = Pipe(), err = Pipe(), incoming = Pipe()
        let handles = [out.fileHandleForReading, out.fileHandleForWriting,
                       err.fileHandleForReading, err.fileHandleForWriting,
                       incoming.fileHandleForReading, incoming.fileHandleForWriting]
        defer { for handle in handles { try? handle.close() } }
        // Serialize this runner's pipe creation through spawn; CLOEXEC prevents its existing
        // parent ends from surviving later execs. This is not a process-tree sandbox.
        for handle in handles {
            guard fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC) >= 0 else {
                return Result(status: 125, output: "", error: "Could not configure helper pipes.")
            }
        }
        process.standardOutput = out
        process.standardError = err
        process.standardInput = incoming
        do { try process.run() } catch {
            return Result(status: 126, output: "", error: error.localizedDescription)
        }
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        try? incoming.fileHandleForReading.close()
        launching = false
        launchLock.unlock()

        let inputFD = incoming.fileHandleForWriting.fileDescriptor
        var outputFD = out.fileHandleForReading.fileDescriptor
        var errorFD = err.fileHandleForReading.fileDescriptor
        var inputOpen = true
        var stdout = Data(), stderr = Data()
        var offset = 0
        let payload = input ?? Data()
        var failure: String?
        var failureStatus: Int32 = 125
        for descriptor in [inputFD, outputFD, errorFD] {
            if fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) < 0 {
                failure = "Could not configure nonblocking helper pipes."
            }
        }
        #if canImport(Darwin)
        if fcntl(inputFD, F_SETNOSIGPIPE, 1) < 0 { failure = "Could not configure helper input." }
        #else
        // Suppress only this worker's SIGPIPE; do not change the application's signal policy.
        var mask = sigset_t(), oldMask = sigset_t(), pending = sigset_t()
        sigemptyset(&mask); sigaddset(&mask, SIGPIPE)
        let maskInstalled = pthread_sigmask(SIG_BLOCK, &mask, &oldMask) == 0
        sigpending(&pending)
        let alreadyPending = sigismember(&pending, SIGPIPE) == 1
        if !maskInstalled { failure = "Could not configure helper input." }
        defer {
            if maskInstalled {
                if !alreadyPending {
                    sigpending(&pending)
                    if sigismember(&pending, SIGPIPE) == 1 {
                        var zero = timespec(tv_sec: 0, tv_nsec: 0)
                        _ = sigtimedwait(&mask, nil, &zero)
                    }
                }
                pthread_sigmask(SIG_SETMASK, &oldMask, nil)
            }
        }
        #endif

        func closeInput() {
            if inputOpen { inputOpen = false; try? incoming.fileHandleForWriting.close() }
        }
        // One bounded read per stream per turn preserves the deadline even for an endlessly noisy child.
        func readChunk(_ descriptor: inout Int32, remaining: Int) -> Data {
            guard descriptor >= 0 else { return Data() }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            #if canImport(Darwin)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            #else
            let count = Glibc.read(descriptor, &bytes, bytes.count)
            #endif
            if count == 0 { descriptor = -1; return Data() }
            if count < 0 {
                if errno != EINTR && errno != EAGAIN { failure = "Could not read helper output." }
                return Data()
            }
            guard count <= remaining else {
                failure = "Helper output exceeded its byte limit."
                return Data()
            }
            return Data(bytes.prefix(count))
        }

        while failure == nil {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                failure = "Helper timed out."
                failureStatus = 124
                break
            }
            if offset == payload.count { closeInput() }
            var descriptors = [pollfd(fd: outputFD, events: Int16(POLLIN), revents: 0),
                               pollfd(fd: errorFD, events: Int16(POLLIN), revents: 0),
                               pollfd(fd: inputOpen ? inputFD : -1, events: Int16(POLLOUT), revents: 0)]
            let remainingMS = Int(max(0.001, min(0.025, deadline - ProcessInfo.processInfo.systemUptime)) * 1000)
            let ready = poll(&descriptors, nfds_t(descriptors.count), Int32(remainingMS))
            if ready < 0 {
                if errno == EINTR { continue }
                failure = "Could not wait for helper pipes."
                break
            }
            if descriptors[0].revents != 0 {
                stdout.append(readChunk(&outputFD, remaining: maxOutputBytes - stdout.count - stderr.count))
            }
            if descriptors[1].revents != 0 {
                stderr.append(readChunk(&errorFD, remaining: maxOutputBytes - stdout.count - stderr.count))
            }
            if inputOpen, descriptors[2].revents != 0 {
                if descriptors[2].revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                    failure = "Helper closed its input before accepting the request."
                } else {
                    let count = payload.withUnsafeBytes { bytes -> Int in
                        guard let base = bytes.baseAddress else { return 0 }
                        #if canImport(Darwin)
                        return Darwin.write(inputFD, base.advanced(by: offset), min(16_384, bytes.count - offset))
                        #else
                        return Glibc.write(inputFD, base.advanced(by: offset), min(16_384, bytes.count - offset))
                        #endif
                    }
                    if count > 0 { offset += count }
                    else if count < 0, errno != EINTR && errno != EAGAIN { failure = "Could not write helper input." }
                }
            }
            if failure == nil, !process.isRunning, outputFD < 0, errorFD < 0 {
                return Result(status: process.terminationStatus,
                              output: String(decoding: stdout, as: UTF8.self),
                              error: String(decoding: stderr, as: UTF8.self))
            }
        }
        closeInput()
        stop(process)
        // No waitUntilExit/read-to-EOF after a failure: a descendant may still own a pipe end.
        return Result(status: failureStatus, output: String(decoding: stdout, as: UTF8.self),
                      error: failure ?? "Helper failed.")
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let gracefulEnd = ProcessInfo.processInfo.systemUptime + 0.25
        while process.isRunning, ProcessInfo.processInfo.systemUptime < gracefulEnd {
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        let reapEnd = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning, ProcessInfo.processInfo.systemUptime < reapEnd {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
