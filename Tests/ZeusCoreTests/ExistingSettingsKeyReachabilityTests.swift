import Foundation
import Testing

/// Pins the settings that already ship. A dropped catalog row, outside-catalog key, section, or window fails these checks.
@Suite struct ExistingSettingsKeyReachabilityTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func everyExistingSettingsKeyStaysPresentAndReachable() throws {
        let catalog = try text("Sources/Zeus/App/SettingsCatalog.swift")
        let settingsView = try text("Sources/Zeus/App/SettingsView.swift")
        let failures = GlassSettingsAudit.keyAndSectionFailures(catalogSource: catalog, settingsViewSource: settingsView)
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func manifestOrderAndIdentityStayFixed() {
        let failures = GlassSettingsAudit.manifestFailures()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        let declared = GlassSectionManifest.slots.reduce(0) { $0 + $1.keys.count }
        #expect(GlassSectionManifest.newSettingKeyCount == declared)
    }

    @Test func keySetDifferenceIsOrderIndependent() {
        let failures = GlassSettingsAudit.propertyFailures()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func materialFocusAndEmptySetsStayInsideBounds() {
        let failures = GlassSettingsAudit.boundaryFailures()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func aTimeoutIsInfrastructureOnlyAfterOneRetry() {
        let failures = GlassSettingsAudit.timeoutFailures()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func theSettingsWindowCountStaysOne() throws {
        let window = try productWindowSource()
        let chrome = try text("Sources/Zeus/Settings/GlassSettingsChrome.swift")
        let failures = GlassSettingsAudit.windowFailures(windowSource: window, chromeSource: chrome)
            + GlassSettingsAudit.collisionFailures(windowSource: window)
            + GlassSettingsAudit.sidebarFailures()
            + GlassSettingsAudit.accessibilityFailures()
            + GlassSettingsAudit.hungCheckFailures()
            + GlassSettingsAudit.registryFailures()
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(window.contains("GlassSettingsChrome("))
        #expect(chrome.contains("Motion.reduced"))
        #expect(chrome.contains("accessibilityReduceTransparency"))
        #expect(chrome.contains("colorSchemeContrast"))
        #expect(chrome.contains("accessibilityHidden(true)"))
    }

    @Test func newSettingsSourcesDoNotSkipOrWriteAccessibility() throws {
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
            let directory = Self.root.appendingPathComponent(relative)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files.filter({ $0.pathExtension == "swift" }).sorted(by: { $0.path < $1.path }) {
                sources.append(try String(contentsOf: file, encoding: .utf8))
            }
        }
        let failures = GlassSettingsAudit.sourceRuleFailures(sources)
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    private func text(_ relative: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The product settings window is the source that titles itself "Zeus Settings". The file name is not part of the contract.
    private func productWindowSource() throws -> String {
        let directory = Self.root.appendingPathComponent("Sources/Zeus/Settings")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let matches = try files.filter { $0.pathExtension == "swift" }.compactMap { url -> String? in
            let source = try String(contentsOf: url, encoding: .utf8)
            return source.contains("title = \"Zeus Settings\"") ? source : nil
        }
        #expect(matches.count == 1)
        return matches[0]
    }
}
