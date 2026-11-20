import Foundation

@main
struct GlassSettingsShellCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        func text(_ relative: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        }

        let settings = root.appendingPathComponent("Sources/Zeus/Settings")
        let windowFiles = try FileManager.default.contentsOfDirectory(at: settings, includingPropertiesForKeys: nil)
        let windows = try windowFiles.filter { $0.pathExtension == "swift" }.compactMap { url -> String? in
            let source = try String(contentsOf: url, encoding: .utf8)
            return source.contains("title = \"Zeus Settings\"") ? source : nil
        }
        guard windows.count == 1 else {
            fputs("settings window sources \(windows.count)\n", stderr)
            exit(1)
        }

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

        if failures.isEmpty {
            let count = SettingsKeyReachability.reachableKeys(
                catalogIDs: SettingsKeyReachability.catalogIDs(in: try text("Sources/Zeus/App/SettingsCatalog.swift"))
            ).count
            print("passed \(count) keys, \(GlassSectionManifest.slots.count) placeholders, \(SettingsWindowCensus.productWindowCount) window")
            return
        }
        for failure in failures {
            print(failure)
        }
        exit(1)
    }
}
