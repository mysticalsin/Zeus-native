import Foundation
import Testing
@testable import ZeusCore

/// Cold launch uses the existing settings store. The feed and the public key stay in the build.
@Suite("Update persistence")
struct UpdatePersistenceTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let checked = Date(timeIntervalSince1970: 1_763_683_200)
    private static let publicKey = Data(repeating: 4, count: 32).base64EncodedString()

    @Test func storedUpdateStateSurvivesRecreatingFromTheSameStore() {
        let defaults = Self.freshDefaults()
        let saved = UpdatePersistedState(
            automaticChecks: true,
            automaticInstall: true,
            lastChecked: Self.checked,
            status: "This copy is up to date.",
            notes: ["A fix"]
        )
        UpdateSettingsStore.save(saved, to: defaults)
        let loaded = UpdateSettingsStore.load(from: defaults)
        #expect(loaded.automaticChecks)
        #expect(loaded.automaticInstall == false)
        #expect(loaded.lastChecked == Self.checked)
        #expect(loaded.status == saved.status)
        #expect(loaded.notes == saved.notes)
        #expect(defaults.string(forKey: "opt.about.autoUpdate") == "true")
        #expect(defaults.string(forKey: "opt.about.autoInstall") == "false")
        #expect(defaults.string(forKey: "SUPublicEDKey") == nil)
        #expect(defaults.string(forKey: "opt.about.updateFeedURL") == nil)
    }

    @Test func updateDefaultsAreOff() {
        let loaded = UpdateSettingsStore.load(from: Self.freshDefaults())
        #expect(loaded.automaticChecks == false)
        #expect(loaded.automaticInstall == false)
        #expect(loaded.lastChecked == nil)
        #expect(loaded.notes.isEmpty)
    }

    @Test func aboutAutoUpdateStaysInTheSharedCatalog() throws {
        let catalog = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let line = catalog.split(separator: "\n").first { $0.contains("\"about.autoUpdate\"") }
        let row = try #require(line)
        #expect(row.contains("defaultValue: \"false\""))
        #expect(row.contains("kind: .toggle"))
    }

    @Test func anImportedSettingsFileCannotEnableInstallOrChangeTheFeedOrKey() throws {
        let defaults = Self.freshDefaults()
        let build = UpdateBuildConfiguration(
            feedURL: "https://updates.example.com/appcast.xml",
            publicKey: Self.publicKey
        )
        let file = Data("""
        {"format":"zeus.settings","version":1,"options":{
          "about.autoUpdate":"true",
          "about.autoInstall":"true",
          "updates.automaticInstall":"true",
          "about.updateFeedURL":"https://evil.example/appcast.xml",
          "SUFeedURL":"https://evil.example/appcast.xml",
          "SUPublicEDKey":"\(Self.publicKey)",
          "about.publicKey":"\(Self.publicKey)"
        }}
        """.utf8)
        let loaded = try #require(try UpdateImportPolicy.apply(file, to: defaults, build: build).get())
        #expect(loaded.automaticChecks == false)
        #expect(loaded.automaticInstall == false)
        #expect(build.feedURL == "https://updates.example.com/appcast.xml")
        #expect(build.publicKey == Self.publicKey)
        #expect(defaults.string(forKey: "opt.about.updateFeedURL") == nil)
        #expect(defaults.string(forKey: "opt.about.autoInstall") != "true")
        #expect(defaults.string(forKey: "SUPublicEDKey") == nil)
        let configuration = UpdateConfiguration.resolve(automaticChecks: loaded.automaticChecks, info: [
            "SUFeedURL": build.feedURL,
            "SUPublicEDKey": build.publicKey,
        ])
        #expect(configuration.secureFeedURL?.host == "updates.example.com")
        #expect(configuration.feedURL == build.feedURL)
    }

    @Test func theFeedMustBeHTTPSAndAHostChangeNeedsASignedAppcast() {
        let pinned = URL(string: "https://updates.example.com/appcast.xml")!
        let insecure = URL(string: "http://updates.example.com/appcast.xml")!
        let other = URL(string: "https://evil.example/appcast.xml")!
        #expect(UpdateFeedTrust.allows(proposed: insecure, pinned: pinned, appcastSignature: .valid) == false)
        #expect(UpdateFeedTrust.allows(proposed: URL(string: "https://user:pass@updates.example.com/appcast.xml")!, pinned: pinned, appcastSignature: .valid) == false)
        #expect(UpdateFeedTrust.allows(proposed: pinned, pinned: pinned, appcastSignature: .missing))
        #expect(UpdateFeedTrust.allows(proposed: other, pinned: pinned, appcastSignature: .missing) == false)
        #expect(UpdateFeedTrust.allows(proposed: other, pinned: pinned, appcastSignature: .invalid) == false)
        #expect(UpdateFeedTrust.allows(proposed: other, pinned: pinned, appcastSignature: .valid))
    }

    @Test func theSessionUsesTheStoreAndTheImporterRefusesUpdateSecrets() throws {
        let model = try String(contentsOf: Self.root.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/UpdatesSessionModel.swift"), encoding: .utf8)
        #expect(model.contains("UpdateSettingsStore.load"))
        #expect(model.contains("UpdateSettingsStore.save"))
        #expect(!model.contains("setFeed"))
    }

    @Test func settingsStoreMatchesTheShellHead() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = Self.gitRoot
        process.arguments = ["diff", "--exit-code", "origin/zeus-bot/glass-settings-shell", "--", "Sources/Zeus/App/SettingsStore.swift"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0)
        #expect(output.isEmpty)
    }

    @Test func autoUpdateContributionsUseTheShellPolicy() throws {
        let items = AutoUpdateSectionSlot.keyContributions
        func policy(_ id: String) -> SettingsKeyPolicy? { items.first { $0.id == id }?.policy }
        #expect(policy("about.autoUpdate") == nil)
        #expect(policy("about.autoInstall") == .importCannotEnable)
        #expect(policy("about.lastChecked") == .localOnly)
        #expect(policy("about.updateStatus") == .localOnly)
        #expect(policy("about.updateNotes") == .localOnly)
        #expect(items.allSatisfy { $0.id != "SUPublicEDKey" && $0.id != "about.updateFeedURL" && $0.id != "SUFeedURL" })
        #expect(SettingsKeyLedger.problems(catalogIDs: ["general.language"], contributions: items).isEmpty)
        let catalog = try String(contentsOf: Self.gitRoot.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let settingsView = try String(contentsOf: Self.gitRoot.appendingPathComponent("Sources/Zeus/App/SettingsView.swift"), encoding: .utf8)
        let failures = GlassSettingsAudit.keyAndSectionFailures(catalogSource: catalog, settingsViewSource: settingsView)
        #expect(failures.isEmpty)
    }

    private static var gitRoot: URL {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url }
            url.deleteLastPathComponent()
        }
        return root
    }

    private static func freshDefaults() -> UserDefaults {
        let suite = NSTemporaryDirectory() + "zeus.update.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
