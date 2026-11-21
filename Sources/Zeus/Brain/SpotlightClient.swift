import Foundation
import ZeusCore

/// Runs Spotlight for a file ask. The query is built in `SpotlightQuery`; this only launches `mdfind`.
enum SpotlightClient {
    static func paths(matching query: String, limit: Int = 8) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [SpotlightQuery.expression(for: query)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").prefix(limit).map { String($0) }
    }
}

/// Reads a page as text when the ask names a URL. Short timeout, no screenshot.
enum PageFetch {
    /// Stop reading once a page is larger than this. The spoken extract is much shorter.
    static let maximumBytes = 1_048_576

    static func text(from url: URL) async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let policy = SafeRemoteFetch.Policy(
            allowsHTTP: false, maximumRedirects: 3, maximumBytes: maximumBytes,
            acceptedStatusCodes: 200..<300,
            allowedContentTypes: ["text/html", "application/xhtml+xml", "text/plain"])
        guard let data = await SafeRemoteFetch.data(
            from: url, policy: policy, configuration: configuration, requestTimeout: 3,
            headers: ["User-Agent": "Zeus"]
        ), let html = String(data: data, encoding: .utf8) else { return nil }
        let plain = PageText.plain(html)
        guard !plain.isEmpty else { return nil }
        return PageText.truncate(plain, to: PageText.defaultExtractLimit)
    }

    /// The spoken request stays outside the fence. The page is untrusted data.
    static func prompt(transcript: String, page: String) -> String {
        SafeRemoteFetch.untrustedPagePrompt(page: page, transcript: transcript)
    }
}
