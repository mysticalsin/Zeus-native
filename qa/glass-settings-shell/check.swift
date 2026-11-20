import Foundation

@main
struct GlassSettingsShellCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let budget: TimeInterval = 30
        let first = try run(root, budget: budget)
        var attempts = [first.run]
        var failures = first.failures
        if case .timedOut = first.run {
            let second = try run(root, budget: budget)
            attempts.append(second.run)
            failures = second.failures
        }
        switch GlassSettingsVerification.verdict(attempts: attempts) {
        case .infrastructure:
            fputs("infrastructure: the check timed out after one retry\n", stderr)
            exit(2)
        case .productFailure:
            for failure in failures {
                print(failure)
            }
            exit(1)
        case .passed:
            let count = SettingsKeyReachability.reachableKeys(
                catalogIDs: SettingsKeyReachability.catalogIDs(in: try text(root, "Sources/Zeus/App/SettingsCatalog.swift"))
            ).count
            print("passed \(count) keys, \(GlassSectionManifest.slots.count) placeholders, \(SettingsWindowCensus.productWindowCount) window")
        }
    }

    private static func run(_ root: URL, budget: TimeInterval) throws -> (run: GlassSettingsVerification.Run, failures: [String]) {
        let box = ResultBox()
        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                box.set(try collect(root))
            } catch {
                box.set(["check threw \(error)"])
            }
        }
        while box.get() == nil {
            if Date().timeIntervalSince(started) > budget {
                return (.timedOut, ["timed out"])
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let failures = box.get() ?? ["timed out"]
        let elapsed = Date().timeIntervalSince(started)
        return (GlassSettingsCheckRunner.attempt(elapsed: elapsed, succeeded: failures.isEmpty, budget: budget), failures)
    }

    private static func collect(_ root: URL) throws -> [String] {
        func text(_ relative: String) throws -> String { try Self.text(root, relative) }
        let settings = root.appendingPathComponent("Sources/Zeus/Settings")
        let windowFiles = try FileManager.default.contentsOfDirectory(at: settings, includingPropertiesForKeys: nil)
        let windows = try windowFiles.filter { $0.pathExtension == "swift" }.compactMap { url -> String? in
            let source = try String(contentsOf: url, encoding: .utf8)
            return source.contains("title = \"Zeus Settings\"") ? source : nil
        }
        guard windows.count == 1 else { return ["settings window sources \(windows.count)"] }

        var failures: [String] = []
        failures += GlassSettingsAudit.keyAndSectionFailures(
            catalogSource: try text("Sources/Zeus/App/SettingsCatalog.swift"),
            settingsViewSource: try text("Sources/Zeus/App/SettingsView.swift")
        )
        failures += GlassSettingsAudit.manifestFailures()
        failures += GlassSettingsAudit.propertyFailures()
        failures += GlassSettingsAudit.boundaryFailures()
        failures += GlassSettingsAudit.timeoutFailures()
        failures += GlassSettingsAudit.windowFailures(
            windowSource: windows[0],
            chromeSource: try text("Sources/Zeus/Settings/GlassSettingsChrome.swift")
        )
        failures += GlassSettingsAudit.collisionFailures(windowSource: windows[0])
        failures += GlassSettingsAudit.sidebarFailures()
        failures += GlassSettingsAudit.accessibilityFailures()
        failures += GlassSettingsAudit.hungCheckFailures()
        failures += GlassSettingsAudit.registryFailures()
        failures += GlassSettingsAudit.inspectorDeltaFailures(root: root)
        var sources = [
            try text("Sources/ZeusCore/Settings/GlassSettingsShell.swift"),
            try text("Sources/Zeus/Settings/GlassSettingsChrome.swift"),
            try text("Sources/Zeus/Settings/GlassShell/GlassSettingsSectionHost.swift"),
            try text("Tests/ZeusCoreTests/ExistingSettingsKeyReachabilityTests.swift"),
            try text("qa/glass-settings-shell/check.swift"),
        ]
        for relative in [
            "Sources/ZeusCore/Settings/Sections",
            "Tests/ZeusCoreTests/Sections",
            "Sources/Zeus/Settings/GlassShell/Sections",
        ] {
            let directory = root.appendingPathComponent(relative)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files.filter({ $0.pathExtension == "swift" }).sorted(by: { $0.path < $1.path }) {
                sources.append(try String(contentsOf: file, encoding: .utf8))
            }
        }
        failures += GlassSettingsAudit.sourceRuleFailures(sources)
        let fingerprint = SettingsKeyReachability.fingerprint(
            SettingsKeyReachability.reachableKeys(
                catalogIDs: SettingsKeyReachability.catalogIDs(in: try text("Sources/Zeus/App/SettingsCatalog.swift"))
            )
        )
        if fingerprint != "42a6fb1152bb4c71" {
            failures.append("checker fingerprint \(fingerprint)")
        }
        return failures
    }

    private static func text(_ root: URL, _ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String]?

    func set(_ value: [String]) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    func get() -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
