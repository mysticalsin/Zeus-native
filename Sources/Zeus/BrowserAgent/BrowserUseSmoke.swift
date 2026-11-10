import Foundation
import ZeusCore

/// The no-AI check behind `Zeus --browseruse-smoke`: the real backend against a real page.
enum BrowserUseSmoke {
    static func run(url: String) async -> Int32 {
        func say(_ line: String) { print(line); fflush(stdout) }
        let status = await BrowserUseSetup.status()
        say("uv: \(status.uvText)")
        say("package: \(status.packageText)")
        say("browser: \(status.browserText)\(status.browserPath.map { " (\($0))" } ?? "")")
        guard status.ready else { say("not set up: press Set up in Settings > Features > Browser agent"); return 2 }
        let headless = ProcessInfo.processInfo.environment["ZEUS_BROWSERUSE_HEADLESS"] == "1" ? true : nil
        let backend: BrowserUseBackend
        do { backend = try await BrowserUseBackend.launch(allowedDomains: [], headless: headless) } catch {
            say("launch failed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            return 1
        }
        say("started: browser-use \(BrowserUseConfig.pinnedVersion) over MCP")
        var code: Int32 = 0
        do {
            _ = try await backend.execute(.open(url: url))
            let first = try await backend.observe()
            say("url: \(first.url)")
            say("title: \(first.title)")
            say("state id: \(first.state ?? "none")")
            say("elements (\(first.elements.count)):")
            for element in first.elements { say("  \(element.promptLine)") }
            let again = try await backend.observe()
            say("state id stable on a second look: \(again.state == first.state)")
            let text = try await backend.execute(.command(.extract(limit: 300)))
            say("page text: \((text ?? "").replacingOccurrences(of: "\n", with: " | "))")
        } catch {
            say("failed: \((error as? BridgeError)?.spokenMessage ?? "\(error)")")
            code = 1
        }
        await backend.close()
        say("closed")
        return code
    }
}
