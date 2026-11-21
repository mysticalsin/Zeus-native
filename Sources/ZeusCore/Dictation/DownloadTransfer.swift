import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Byte counts of the pinned model files, from their published Content-Length.
/// The cap is that size plus 25 percent, using integer division.
public enum PinnedModelBytes {
    public static let whisperBaseEn: Int64 = 147_964_211
    public static let whisperSmall: Int64 = 487_601_967
    public static let whisperLargeTurboQ5: Int64 = 574_041_195
    public static let kokoroOnnx: Int64 = 325_532_387
    public static let kokoroVoices: Int64 = 28_214_398

    public static func cap(_ known: Int64) -> Int64 { known + known / 4 }

    public static func whisperKnownBytes(id: String) -> Int64? {
        switch id {
        case "base.en": whisperBaseEn
        case "small": whisperSmall
        case "large-v3-turbo-q5_0": whisperLargeTurboQ5
        default: nil
        }
    }
}

/// Hosts a redirect may use. A different host, or a scheme other than https, is refused.
public enum PinnedDownloadHosts {
    public static let whisper: Set<String> = ["huggingface.co", "us.aws.cdn.hf.co"]
    public static let kokoro: Set<String> = ["github.com", "release-assets.githubusercontent.com"]
}

/// Bytes `pip install faster-whisper` may leave on disk.
/// The known total is the unpacked size of the six large macOS wheels measured from PyPI
/// (ctranslate2 62318280, onnxruntime 83215359, av 68390463, numpy 50124502, tokenizers 10106273,
/// hf-xet 8426554) plus 11986242 bytes for the small pure-Python wheels in that install.
/// The cap adds 25 percent.
public enum FasterWhisperUnpack {
    public static let knownBytes: Int64 = 294_567_673
    public static var maximumBytes: Int64 { PinnedModelBytes.cap(knownBytes) }
}

/// An extracted archive must stay within the byte cap. The pinned Whisper and Kokoro files are not archives.
public enum ArchiveUnpackCap {
    public static func exceeds(producedBytes: Int64, maximumBytes: Int64) -> Bool {
        producedBytes > maximumBytes
    }

    public static func isArchive(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["zip", "tar", "gz", "tgz", "bz2", "xz"].contains(ext)
    }
}

public protocol DownloadTransferTask: AnyObject {
    func cancel()
}

public final class FakeDownloadTask: DownloadTransferTask, @unchecked Sendable {
    public private(set) var cancelCount = 0
    public init() {}
    public func cancel() { cancelCount += 1 }
}

/// URLSession delegate for one model file. At most five redirects, https, allowlisted hosts.
/// expectedContentLength and bytes written both cancel the task past the cap.
public final class DownloadTransferGuard: NSObject, @unchecked Sendable {
    public static let redirectLimit = 5
    public let maximumBytes: Int64
    public let allowedHosts: Set<String>
    public let report: (@Sendable (Double) -> Void)?
    public private(set) var redirectCount = 0
    public private(set) var stopped = false
    /// Where `didFinishDownloadingTo` moves the file before macOS deletes the temp.
    public var destination: URL?
    public private(set) var keptURL: URL?
    public private(set) var statusCode: Int?

    public init(maximumBytes: Int64, allowedHosts: Set<String>, report: (@Sendable (Double) -> Void)? = nil) {
        self.maximumBytes = maximumBytes
        self.allowedHosts = allowedHosts
        self.report = report
    }

    public func evaluateRedirect(_ url: URL, task: DownloadTransferTask, completion: (URLRequest?) -> Void) {
        redirectCount += 1
        let host = url.host?.lowercased()
        let portOK = url.port == nil || url.port == 443
        let userOK = url.user == nil && url.password == nil
        let allowed = redirectCount <= Self.redirectLimit
            && url.scheme == "https"
            && portOK
            && userOK
            && host.map { allowedHosts.contains($0) } == true
        if allowed {
            completion(URLRequest(url: url))
        } else {
            stopped = true
            task.cancel()
            completion(nil)
        }
    }

    public func evaluateWrite(written: Int64, expected: Int64, task: DownloadTransferTask) {
        let expectedOver = expected >= 0 && expected > maximumBytes
        if written > maximumBytes || expectedOver {
            stopped = true
            task.cancel()
            return
        }
        if expected > 0 {
            report?(min(Double(written) / Double(expected), 1))
        }
    }

    /// Moves the finished download to `destination` before the caller returns.
    /// macOS deletes the temp file when `didFinishDownloadingTo` returns, so the move happens here.
    public func acceptFinishedDownload(at location: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path))?[.size] as? NSNumber
        let bytes = size?.int64Value ?? 0
        guard let destination, bytes <= maximumBytes else {
            stopped = true
            try? FileManager.default.removeItem(at: location)
            return
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            keptURL = destination
        } catch {
            stopped = true
            try? FileManager.default.removeItem(at: location)
        }
    }

}

#if os(macOS)
extension URLSessionTask: DownloadTransferTask {}

extension DownloadTransferGuard: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            stopped = true
            task.cancel()
            completionHandler(nil)
            return
        }
        evaluateRedirect(url, task: task) { decision in
            completionHandler(decision == nil ? nil : request)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        evaluateWrite(written: totalBytesWritten, expected: totalBytesExpectedToWrite, task: downloadTask)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse {
            statusCode = http.statusCode
        }
        acceptFinishedDownload(at: location)
    }
}
#endif
