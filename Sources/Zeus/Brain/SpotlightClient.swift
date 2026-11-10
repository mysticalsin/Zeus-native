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
    static func text(from url: URL) async -> String? {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("Zeus", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let plain = PageText.plain(html)
        guard !plain.isEmpty else { return nil }
        return PageText.truncate(plain, to: PageText.defaultExtractLimit)
    }
}
