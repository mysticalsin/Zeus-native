import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The tiling rows in the generated settings catalog, their agreement with the readers and the engine, and the
/// rule that a settings import never turns tiling on.
@Suite("Tiling settings catalog")
struct TilingSettingsCatalogTests {
    private static let ids = [
        "tiling.enabled", "tiling.keyBase", "tiling.innerGap", "tiling.outerGap",
        "tiling.splitRatio", "tiling.focusBorder", "tiling.excludedApps",
    ]

    private func isolated() throws -> (UserDefaults, cleanup: () -> Void) {
        let name = NSTemporaryDirectory() + "zeus.tiling.catalog.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func everyRowIsALiveRowOnTheTilingSection() {
        for id in Self.ids {
            let option = SettingsCatalog.option(id)
            #expect(option != nil, "\(id) is in the catalog")
            #expect(option?.section == .tiling, "\(id) section")
            #expect(option?.state == .live, "\(id) state")
            #expect(option?.isShown == true, "\(id) is shown")
        }
        #expect(SettingsCatalog.options(in: .tiling).map(\.id).sorted() == Self.ids.sorted())
    }

    @Test func theRowsHaveTheSpecifiedKindsTitlesAndRanges() throws {
        let enabled = try #require(SettingsCatalog.option("tiling.enabled"))
        #expect(enabled.kind == .toggle)
        #expect(enabled.title == "Arrange my windows from the keyboard")
        #expect(enabled.defaultValue == "false")

        let base = try #require(SettingsCatalog.option("tiling.keyBase"))
        #expect(base.kind == .choice)
        #expect(base.title == "Tiling keys")
        #expect(base.choices == ["Control-Option", "Option-Command", "Control-Option-Command"])
        #expect(base.defaultValue == "Control-Option-Command")

        for (id, title) in [("tiling.innerGap", "Gap between windows"), ("tiling.outerGap", "Gap to the screen edge")] {
            let gap = try #require(SettingsCatalog.option(id))
            #expect(gap.kind == .slider)
            #expect(gap.title == title)
            #expect(gap.range?.min == 0)
            #expect(gap.range?.max == 64)
            #expect(gap.defaultValue == "8")
        }

        let split = try #require(SettingsCatalog.option("tiling.splitRatio"))
        #expect(split.kind == .slider)
        #expect(split.title == "Default split")
        #expect(split.range?.min == 30)
        #expect(split.range?.max == 70)
        #expect(split.range?.step == 5)
        #expect(split.defaultValue == "50")

        let border = try #require(SettingsCatalog.option("tiling.focusBorder"))
        #expect(border.kind == .toggle)
        #expect(border.title == "Ring the focused window")
        #expect(border.defaultValue == "true")

        let excluded = try #require(SettingsCatalog.option("tiling.excludedApps"))
        #expect(excluded.kind == .text)
        #expect(excluded.title == "Apps Zeus never tiles")
        #expect(excluded.defaultValue == "")
    }

    @Test func everyNoteIsOurOwnWording() {
        for id in Self.ids {
            let note = SettingsCatalog.option(id)?.todo ?? ""
            #expect(note.hasPrefix("Zeus addition."), "\(id) note")
        }
    }

    @Test func tilingIsOffByDefault() throws {
        #expect(SettingsCatalog.option("tiling.enabled")?.defaultValue == "false")
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        #expect(FeatureSettings.tilingEnabled(defaults: defaults) == false)
        #expect(TileConfig.defaults.enabled == false)
    }

    // Every setting is checked against a reader. The values a TileConfig carries are checked against the engine;
    // the focus border and the split as the percentage the page shows have no TileConfig field of that shape.

    @Test func readerDefaultsEqualCatalogDefaults() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        func catalog(_ id: String) -> String { SettingsCatalog.option(id)?.defaultValue ?? "missing" }
        #expect(FeatureSettings.tilingEnabled(defaults: defaults) == (catalog("tiling.enabled") == "true"))
        #expect(FeatureSettings.tilingFocusBorder(defaults: defaults) == (catalog("tiling.focusBorder") == "true"))
        #expect(FeatureSettings.tilingInnerGap(defaults: defaults) == Double(catalog("tiling.innerGap")))
        #expect(FeatureSettings.tilingOuterGap(defaults: defaults) == Double(catalog("tiling.outerGap")))
        #expect(FeatureSettings.tilingSplitRatio(defaults: defaults) == Double(catalog("tiling.splitRatio")))
        #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == TileModifierBase(label: catalog("tiling.keyBase")))
        #expect(FeatureSettings.tilingExcludedApps(defaults: defaults).isEmpty == catalog("tiling.excludedApps").isEmpty)
    }

    @Test func engineDefaultsEqualCatalogDefaults() {
        func catalog(_ id: String) -> Double { Double(SettingsCatalog.option(id)?.defaultValue ?? "") ?? -1 }
        let engine = TileConfig.defaults
        #expect(engine.innerGap == catalog("tiling.innerGap"))
        #expect(engine.outerGap == catalog("tiling.outerGap"))
        #expect(engine.defaultRatio == catalog("tiling.splitRatio") / 100)
        #expect(engine.base == TileModifierBase(label: SettingsCatalog.option("tiling.keyBase")?.defaultValue ?? ""))
        #expect(engine.enabled == (SettingsCatalog.option("tiling.enabled")?.defaultValue == "true"))
        // The depth and the smallest tile have no settings row: the engine's own numbers stand.
        #expect(engine.maxDepth == 3)
        #expect(engine.minTileSize == 200)
        #expect(SettingsCatalog.option("tiling.maxDepth") == nil)
        #expect(SettingsCatalog.option("tiling.minTileSize") == nil)
    }

    @Test func everyKeyBaseChoiceIsARealBase() {
        let choices = SettingsCatalog.option("tiling.keyBase")?.choices ?? []
        #expect(Set(choices.map { TileModifierBase(label: $0) }) == Set(TileModifierBase.allCases))
    }

    @Test func theSplitChoicesAreReachableOnTheSlider() throws {
        let split = try #require(SettingsCatalog.option("tiling.splitRatio")?.range)
        #expect(TileRatio.minimum * 100 <= split.min)
        #expect(split.max <= TileRatio.maximum * 100)
    }

    // MARK: Import

    @MainActor @Test func theCatalogListsTilingAmongTheSwitchesAnImportCannotTurnOn() {
        #expect(SettingsStore.neverEnabledByImport.contains("tiling.enabled"))
        // The focus border is passive: an import may carry it either way.
        #expect(!SettingsStore.neverEnabledByImport.contains("tiling.focusBorder"))
    }

    private func file(_ options: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["format": "zeus.settings", "version": 1, "options": options, "app": [String: String]()])
    }

    @MainActor @Test func anImportNeverTurnsTilingOn() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let store = SettingsStore(defaults: defaults)
        #expect(store.bool("tiling.enabled") == false)
        let changed = try store.importJSON(file(["tiling.enabled": "true"]))
        #expect(changed == 0)
        #expect(store.bool("tiling.enabled") == false)
        #expect(defaults.string(forKey: "opt.tiling.enabled") == nil)
    }

    @MainActor @Test func anImportMayTurnTilingOff() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let store = SettingsStore(defaults: defaults)
        store.set("tiling.enabled", "true", origin: .person)
        #expect(try store.importJSON(file(["tiling.enabled": "false"])) == 1)
        #expect(store.bool("tiling.enabled") == false)
    }

    @MainActor @Test func anExportFromAMacWithTilingOnDoesNotTurnItOnHere() throws {
        let (sourceDefaults, sourceCleanup) = try isolated()
        let (targetDefaults, targetCleanup) = try isolated()
        defer { sourceCleanup(); targetCleanup() }
        let source = SettingsStore(defaults: sourceDefaults)
        source.set("tiling.enabled", "true", origin: .person)
        source.set("tiling.innerGap", "20", origin: .person)
        let target = SettingsStore(defaults: targetDefaults)
        _ = try target.importJSON(source.exportJSON())
        #expect(target.bool("tiling.enabled") == false)
        // The other rows carry over.
        #expect(target.string("tiling.innerGap") == "20")
    }

    @MainActor @Test func anImportKeepsOnlyValuesTheRowsAccept() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let store = SettingsStore(defaults: defaults)
        let changed = try store.importJSON(file([
            "tiling.keyBase": "Hyper",          // not a choice
            "tiling.innerGap": "99",            // above 64
            "tiling.outerGap": "-1",            // below 0
            "tiling.splitRatio": "75",          // above 70
            "tiling.focusBorder": "maybe",      // not a switch value
        ]))
        #expect(changed == 0)
        #expect(store.string("tiling.keyBase") == "Control-Option-Command")
        #expect(store.string("tiling.innerGap") == "8")
        #expect(store.string("tiling.outerGap") == "8")
        #expect(store.string("tiling.splitRatio") == "50")
        #expect(store.bool("tiling.focusBorder"))

        let good = try store.importJSON(file([
            "tiling.keyBase": "Option-Command", "tiling.innerGap": "12", "tiling.outerGap": "0",
            "tiling.splitRatio": "60", "tiling.focusBorder": "false", "tiling.excludedApps": "com.example.One",
        ]))
        #expect(good == 6)
        #expect(store.string("tiling.keyBase") == "Option-Command")
        #expect(store.string("tiling.splitRatio") == "60")
        #expect(store.bool("tiling.focusBorder") == false)
    }

    @MainActor @Test func resettingTheSectionPutsEveryRowBackAndLeavesTilingOff() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let store = SettingsStore(defaults: defaults)
        store.set("tiling.enabled", "true", origin: .person)
        store.set("tiling.innerGap", "30", origin: .person)
        store.reset(.tiling)
        #expect(store.bool("tiling.enabled") == false)
        #expect(store.string("tiling.innerGap") == "8")
    }

    // MARK: The live page

    @Test func theTilingPageIsASectionInYourTools() {
        #expect(GSSection.tiling.title == "Tiling")
        #expect(GSSection.tiling.group == .tools)
        #expect(GSSection.tiling.isShown)
        #expect(GSSection.shown.contains(.tiling))
        #expect(GSSection.matching("tiling") == .tiling)
        #expect(!GSSection.tiling.symbol.isEmpty)
    }

    @MainActor @Test func theLegacySectionNamesTheSameWords() {
        #expect(SettingsNavigation.Section.tiling.title == "Tiling")
        #expect(SettingsNavigation.Section.shown.contains(.tiling))
    }
}
