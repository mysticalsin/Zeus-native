import Foundation
import ZeusCore

/// Finds, checks and fetches what the "Separate browser (browser-use)" option runs on: `uv`, the
/// pinned browser-use release in uv's cache, and a Chromium (or Chrome) for it to drive. Nothing is
/// downloaded except by `setUp`, which Tony starts from Settings.
enum BrowserUseSetup {
    struct Status: Equatable, Sendable {
        var uvPath: String?
        var packageCached: Bool
        var browserPath: String?

        var ready: Bool { uvPath != nil && packageCached && browserPath != nil }

        /// What the Settings rows say.
        var uvText: String { uvPath.map { "uv found (\(ProjectIndex.tilde($0)))" } ?? "uv not found (brew install uv)" }
        var packageText: String { packageCached ? "browser-use \(BrowserUseConfig.pinnedVersion) downloaded" : "browser-use not downloaded yet" }
        var browserText: String { browserPath != nil ? "Chromium ready" : "No Chromium yet" }
    }

    enum SetupError: Error, LocalizedError {
        case noUV
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noUV: "uv isn't installed. In Terminal: brew install uv"
            case .failed(let why): why
            }
        }
    }

    // MARK: Paths

    /// Its own browser profile: logins and cookies of the separate browser live here, apart from Chrome.
    static var profileDirectory: URL { ZeusPaths.supportDirectory.appendingPathComponent("browser-use-profile", isDirectory: true) }
    static var downloadsDirectory: URL { ZeusPaths.supportDirectory.appendingPathComponent("browser-use-downloads", isDirectory: true) }
    static var configDirectory: URL { ZeusPaths.supportDirectory.appendingPathComponent("browser-use", isDirectory: true) }
    static var configFile: URL { configDirectory.appendingPathComponent("config.json") }

    static func findUV() -> String? {
        CLILocator.searchDirectories.map { "\($0)/uv" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The Chromium browser-use will drive: Chrome stable first (as browser-use itself prefers),
    /// then a Playwright Chromium in its own cache.
    static func browserPath(home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String? {
        let manager = FileManager.default
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        if manager.isExecutableFile(atPath: chrome) { return chrome }
        let cache = "\(home)/Library/Caches/ms-playwright"
        for entry in ((try? manager.contentsOfDirectory(atPath: cache)) ?? []).sorted(by: >) where entry.hasPrefix("chromium") {
            let root = "\(cache)/\(entry)"
            for sub in (try? manager.contentsOfDirectory(atPath: root)) ?? [] where sub.hasPrefix("chrome-mac") {
                let binary = "\(root)/\(sub)/Chromium.app/Contents/MacOS/Chromium"
                if manager.isExecutableFile(atPath: binary) { return binary }
            }
        }
        return nil
    }

    // MARK: Status

    static func status() async -> Status {
        let uv = findUV()
        var cached = false
        if let uv {
            // --offline: succeeds only when the pinned release is already in uv's cache.
            cached = (try? await run(uv, ["tool", "run", "--offline"] + BrowserUseConfig.uvxArguments(["--version"]), timeout: 20, onLine: { _ in })) == 0
        }
        return Status(uvPath: uv, packageCached: cached, browserPath: browserPath())
    }

    // MARK: Set up

    /// Fetches browser-use into uv's cache and, if there is no Chromium, installs one with
    /// browser-use's own command. `progress` gets short lines.
    static func setUp(progress: @escaping @Sendable (String) -> Void) async throws {
        guard let uv = findUV() else { throw SetupError.noUV }
        progress("Downloading browser-use \(BrowserUseConfig.pinnedVersion)...")
        let fetched = try await run(uv, ["tool", "run"] + BrowserUseConfig.uvxArguments(["--version"]), timeout: 900, onLine: { progress(shorten($0)) })
        guard fetched == 0 else { throw SetupError.failed("uv couldn't download browser-use (exit \(fetched)). Check your connection and try again.") }
        if browserPath() == nil {
            progress("Installing Chromium...")
            let installed = try await run(uv, ["tool", "run"] + BrowserUseConfig.uvxArguments(["install"]), timeout: 1_800, onLine: { progress(shorten($0)) })
            guard installed == 0, browserPath() != nil else { throw SetupError.failed("Chromium didn't install (exit \(installed)).") }
        }
        progress("Ready.")
    }

    private static func shorten(_ line: String) -> String { String(line.trimmingCharacters(in: .whitespaces).prefix(90)) }

    // MARK: Launch

    /// Writes Zeus's own browser-use config and returns how to start `uvx browser-use --mcp`.
    static func launch(allowedDomains: [String], headless: Bool? = nil) throws -> MCPStdioClient.Launch {
        guard let uv = findUV() else { throw SetupError.noUV }
        let manager = FileManager.default
        for directory in [profileDirectory, downloadsDirectory, configDirectory] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try BrowserUseConfig.json(profileDirectory: profileDirectory.path, downloadsDirectory: downloadsDirectory.path, headless: headless ?? false)
            .write(to: configFile, options: .atomic)
        let environment = BrowserUseConfig.environment(base: ProcessInfo.processInfo.environment, searchPath: CLILocator.searchDirectories,
                                                       configPath: configFile.path, configDirectory: configDirectory.appendingPathComponent("home").path,
                                                       allowedDomains: allowedDomains, headless: headless)
        return MCPStdioClient.Launch(executable: uv, arguments: ["tool", "run"] + BrowserUseConfig.uvxArguments(["--mcp"]),
                                     environment: environment, currentDirectory: configDirectory)
    }

    // MARK: Running uv

    /// Runs a process, handing each output line to `onLine`; returns the exit status.
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = BrowserUseConfig.environment(base: ProcessInfo.processInfo.environment, searchPath: CLILocator.searchDirectories,
                                                           configPath: configFile.path, configDirectory: configDirectory.appendingPathComponent("home").path,
                                                           allowedDomains: [])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        let lines = LineTail()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            lines.append(data)
            // uv redraws progress with carriage returns; report each piece.
            for piece in String(decoding: data, as: UTF8.self).split(whereSeparator: { $0 == "\n" || $0 == "\r" }) where !piece.trimmingCharacters(in: .whitespaces).isEmpty {
                onLine(String(piece))
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { finished in
                    output.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: finished.terminationStatus)
                }
                do { try process.run() } catch {
                    output.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
