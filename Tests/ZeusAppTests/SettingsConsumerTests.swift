import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Every row the live Settings window shows must reach something that acts on it.
@Suite("Settings consumers")
struct SettingsConsumerTests {
    private static let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func swiftFiles(under path: String) -> [URL] {
        let base = root.appendingPathComponent(path)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Catalog ids the Glance window's pages mention.
    private static func idsOnPages() -> Set<String> {
        let ids = Set(SettingsCatalog.all.map(\.id))
        let regex = try! NSRegularExpression(pattern: "\"([a-z][A-Za-z]*\\.[A-Za-z.]+)\"")
        var found = Set<String>()
        for file in swiftFiles(under: "Sources/Zeus/Settings") {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text), ids.contains(String(text[range])) { found.insert(String(text[range])) }
            }
        }
        return found
    }

    /// Source outside the Settings pages and the catalog: where an id can be acted on.
    private static func consumerText() -> String {
        (swiftFiles(under: "Sources/Zeus") + swiftFiles(under: "Sources/ZeusCore"))
            .filter { !$0.path.contains("/Sources/Zeus/Settings/") && !$0.lastPathComponent.hasPrefix("SettingsCatalog") && $0.lastPathComponent != "SettingsView.swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    /// Rows that are still inert. Each belongs to someone else's round; the test fails if one gains
    /// a consumer, so the entry gets removed.
    static let knownInert: Set<String> = []

    @Test func everyRowOnAPageHasAConsumer() {
        let consumers = Self.consumerText()
        var dead: [String] = []
        for id in Self.idsOnPages().sorted() where !Self.knownInert.contains(id) {
            if !consumers.contains("\"\(id)\"") { dead.append(id) }
        }
        #expect(dead.isEmpty, "Rows with nothing behind them: \(dead)")
        for id in Self.knownInert { #expect(!consumers.contains("\"\(id)\""), "\(id) now has a consumer: drop it from knownInert") }
    }

    @Test func inertRowsAreHidden() {
        let onPages = Self.idsOnPages()
        // notify.errors went live with failed/stalled agents (merge 02205a7).
        for id in ["general.windowTheme", "general.language"] { // halo.wallpaper, lights.liveSpectrum and lights.eventGlow went live
            #expect(SettingsCatalog.option(id)?.isShown == false, "\(id) is a stub")
            #expect(!onPages.contains(id), "\(id) must not have a row")
        }
    }

    /// The features Tony asked to switch off, with the text that proves something reads each one.
    static let featureConsumers: [(id: String, needle: String)] = [
        ("fastPath.enabled", "FeatureSettings.fastPathEnabled()"),
        ("browserAgent.enabled", "FeatureSettings.browserAgentEnabled()"),
        ("browserAgent.maxSteps", "FeatureSettings.browserAgentMaxSteps()"),
        ("browserAgent.alwaysAsk", "FeatureSettings.browserAgentAlwaysAsk()"),
        ("research.depth", "FeatureSettings.researchDepth()"),
        ("research.folder", "FeatureSettings.researchFolder()"),
        ("beamer.autoStart", "SettingsStore.shared.bool(\"beamer.autoStart\")"),
        ("beamer.cue", "SettingsStore.shared.bool(\"beamer.cue\")"),
        ("code.tool", "CodingTool.preferenceKey"),
        ("code.terminal", "TerminalApp.preferenceKey"),
        ("prompter.followPresentation", "PrompterHub.followKey"),
        ("prompter.followAdvances", "\"prompter.followAdvances\""),
        ("prompterWindow.private", "\"prompterWindow.private\""),
        ("voice.heyZeus", "WakeWordController"),
        ("voice.talkKey", "pushToTalk"),
        ("voice.personality", "ZeusPersonality.defaultsKey"),
        ("dictation.engine", "\"dictation.engine\""),
        ("insomnia.lidClosed", "\"insomnia.lidClosed\""),
        ("privacy.driveAutonomy", "DriveAutonomy.settingsKey"),
        ("models.caps", "ModelCap"),
    ]

    @Test func recentFeaturesHaveACatalogRowAndAConsumer() {
        let consumers = Self.consumerText()
        for (id, needle) in Self.featureConsumers {
            #expect(SettingsCatalog.option(id)?.isShown == true, "\(id) needs a catalog row")
            #expect(consumers.contains(needle), "\(id): nothing contains \(needle)")
        }
    }

    @Test func coreDefaultsMatchTheCatalog() throws {
        let empty = try #require(UserDefaults(suiteName: "zeus.features.\(UUID().uuidString)"))
        #expect(SettingsCatalog.option("fastPath.enabled")?.defaultValue == String(FeatureSettings.fastPathEnabled(defaults: empty)))
        #expect(SettingsCatalog.option("browserAgent.enabled")?.defaultValue == String(FeatureSettings.browserAgentEnabled(defaults: empty)))
        #expect(SettingsCatalog.option("browserAgent.maxSteps")?.defaultValue == String(FeatureSettings.browserAgentMaxSteps(defaults: empty)))
        #expect(SettingsCatalog.option("research.depth")?.defaultValue == "Quick")
        #expect(FeatureSettings.researchDepth(defaults: empty) == .quick)
        #expect(FeatureSettings.researchFolder(defaults: empty) == nil)
    }

    @Test func settingsReachTheirConsumers() throws {
        let defaults = try #require(UserDefaults(suiteName: "zeus.features.\(UUID().uuidString)"))
        defaults.set("false", forKey: "opt.fastPath.enabled")
        defaults.set("40", forKey: "opt.browserAgent.maxSteps")
        defaults.set("Apply, Invite ,", forKey: "opt.browserAgent.alwaysAsk")
        defaults.set("Deep", forKey: "opt.research.depth")
        defaults.set("~/Reports", forKey: "opt.research.folder")
        #expect(!FeatureSettings.fastPathEnabled(defaults: defaults))
        #expect(FeatureSettings.browserAgentMaxSteps(defaults: defaults) == 40)
        #expect(FeatureSettings.browserAgentAlwaysAsk(defaults: defaults) == ["apply", "invite"])
        #expect(FeatureSettings.researchDepth(defaults: defaults) == .deep)
        #expect(FeatureSettings.researchFolder(defaults: defaults)?.path.hasSuffix("/Reports") == true)
        defaults.set("1000", forKey: "opt.browserAgent.maxSteps")
        #expect(FeatureSettings.browserAgentMaxSteps(defaults: defaults) == 100)
    }

    @Test func alwaysAskWordsStopAClick() {
        let button = PageElement(index: 1, role: "button", text: "Learn more")
        #expect(BrowserAgentSafety.approvalReason(for: .click(index: 1), element: button, alwaysAsk: []) == nil)
        #expect(BrowserAgentSafety.approvalReason(for: .click(index: 1), element: button, alwaysAsk: ["learn more"]) == "it matches your always-ask list")
    }

    @Test func researchReportsGoWhereTheyAreSent() {
        let folder = URL(fileURLWithPath: "/Users/tony/Reports")
        let url = ResearchReport.destination(fileName: "a.md", connection: nil, chosenFolder: folder, exists: { _ in false })
        #expect(url.path == "/Users/tony/Reports/a.md")
    }

    @Test func modelCapsAreDescribedAndNeverAboveSonnet() {
        let claude = ModelCap.describe(.claude)
        #expect(claude.fast == "haiku" && claude.deep == "sonnet")
        #expect(ModelCap.describe(.codex).fast.hasSuffix("low effort"))
        for engine in RouterEngine.allCases {
            let text = ModelCap.describe(engine)
            #expect(ModelCap.isAllowed(text.fast) && ModelCap.isAllowed(text.deep))
        }
    }
}

@Suite("Parity wiring")
struct ParityWiringTests {
    private static func sourceText() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Zeus")
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (walker?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    @Test func cardStylesMapToFinishes() {
        #expect(CardFinish.allCases.map(\.rawValue) == ["Liquid Glass", "Glass", "Classic", "Physical", "Dashboard", "Dashboard B"])
        for name in ["Glass", "Physical", "Liquid Glass", "Classic", "Dashboard", "Dashboard B"] { #expect(CardFinish.resolve(name).rawValue == name) }
        #expect(CardFinish.resolve("nonsense") == .liquidGlass)
        #expect(SettingsCatalog.option("appearance.cardStyle")?.choices == ["Liquid Glass", "Glass", "Classic", "Physical", "Dashboard", "Dashboard B"])
        #expect(SettingsCatalog.option("privacy.lyrics")?.isShown == true)
    }

    @Test func everySoundSlotIsPlayedSomewhere() {
        let text = Self.sourceText()
        for event in ["approval", "done", "todo", "start", "answer", "timer", "listenStart", "listenStop", "voiceDone", "voiceError", "failure", "dictationBegin", "dictationEnd"] {
            #expect(text.contains("play(.\(event)") || text.contains("cue(.\(event)"), "\(event) is never played")
        }
        #expect(text.contains("startRunningLoop()"))
    }
}
