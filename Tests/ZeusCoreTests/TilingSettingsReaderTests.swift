import Foundation
import Testing
@testable import ZeusCore

/// The tiling readers in `FeatureSettings`: what each returns on a fresh install, what it reads back, and how a
/// stored value that is wrong falls back. The catalog side (ids, kinds, defaults) is `TilingSettingsCatalogTests`.
struct TilingSettingsReaderTests {
    private func isolated() throws -> (UserDefaults, cleanup: () -> Void) {
        let name = NSTemporaryDirectory() + "zeus.tiling.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func freshInstallIsOffWithTheShippedValues() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        #expect(FeatureSettings.tilingEnabled(defaults: defaults) == false)
        #expect(FeatureSettings.tilingInnerGap(defaults: defaults) == 8)
        #expect(FeatureSettings.tilingOuterGap(defaults: defaults) == 8)
        #expect(FeatureSettings.tilingSplitRatio(defaults: defaults) == 50)
        #expect(FeatureSettings.tilingFocusBorder(defaults: defaults) == true)
        #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == .controlOptionCommand)
        #expect(FeatureSettings.tilingExcludedApps(defaults: defaults).isEmpty)
    }

    @Test func freshInstallMatchesTheEngineDefaults() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let engine = TileConfig.defaults
        #expect(FeatureSettings.tilingEnabled(defaults: defaults) == engine.enabled)
        #expect(FeatureSettings.tilingInnerGap(defaults: defaults) == engine.innerGap)
        #expect(FeatureSettings.tilingOuterGap(defaults: defaults) == engine.outerGap)
        #expect(FeatureSettings.tilingDefaultRatio(defaults: defaults) == engine.defaultRatio)
        #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == engine.base)
        #expect(Set(FeatureSettings.tilingExcludedApps(defaults: defaults)) == engine.excludedBundleIDs)
    }

    @Test func storedValuesAreReadFromTheOptKeys() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        defaults.set("true", forKey: "opt.tiling.enabled")
        defaults.set("16", forKey: "opt.tiling.innerGap")
        defaults.set("4", forKey: "opt.tiling.outerGap")
        defaults.set("60", forKey: "opt.tiling.splitRatio")
        defaults.set("false", forKey: "opt.tiling.focusBorder")
        defaults.set("Option-Command", forKey: "opt.tiling.keyBase")
        defaults.set("com.example.One, com.example.Two", forKey: "opt.tiling.excludedApps")
        #expect(FeatureSettings.tilingEnabled(defaults: defaults))
        #expect(FeatureSettings.tilingInnerGap(defaults: defaults) == 16)
        #expect(FeatureSettings.tilingOuterGap(defaults: defaults) == 4)
        #expect(FeatureSettings.tilingSplitRatio(defaults: defaults) == 60)
        #expect(FeatureSettings.tilingFocusBorder(defaults: defaults) == false)
        #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == .optionCommand)
        #expect(FeatureSettings.tilingExcludedApps(defaults: defaults) == ["com.example.One", "com.example.Two"])
        #expect(abs(FeatureSettings.tilingDefaultRatio(defaults: defaults) - 0.6) < 1e-9)
    }

    @Test func theEngineRatioIsTheSplitPercentOverOneHundred() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        #expect(FeatureSettings.tilingDefaultRatio(defaults: defaults) == 0.5)
        defaults.set("30", forKey: "opt.tiling.splitRatio")
        #expect(abs(FeatureSettings.tilingDefaultRatio(defaults: defaults) - 0.3) < 1e-9)
        defaults.set("wide", forKey: "opt.tiling.splitRatio")
        #expect(FeatureSettings.tilingDefaultRatio(defaults: defaults) == 0.5)
        // The percentage handed to the engine as a ratio would clamp to the maximum, the mistake the ratio reader prevents.
        defaults.set("50", forKey: "opt.tiling.splitRatio")
        #expect(TileConfig(defaultRatio: FeatureSettings.tilingSplitRatio(defaults: defaults)).defaultRatio == TileRatio.maximum)
        #expect(TileConfig(defaultRatio: FeatureSettings.tilingDefaultRatio(defaults: defaults)).defaultRatio == 0.5)
    }

    @Test func everyKeyBaseChoiceMapsToItsOwnCase() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        let expected: [(String, TileModifierBase)] = [
            ("Control-Option", .controlOption), ("Option-Command", .optionCommand),
            ("Control-Option-Command", .controlOptionCommand),
        ]
        for (label, base) in expected {
            defaults.set(label, forKey: "opt.tiling.keyBase")
            #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == base)
        }
        #expect(Set(expected.map(\.1)).count == TileModifierBase.allCases.count)
    }

    @Test func aStoredValueThatIsNotANumberFallsBackToTheDefault() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        for text in ["", "wide", "nan", "inf", "-inf"] {
            defaults.set(text, forKey: "opt.tiling.innerGap")
            defaults.set(text, forKey: "opt.tiling.outerGap")
            defaults.set(text, forKey: "opt.tiling.splitRatio")
            #expect(FeatureSettings.tilingInnerGap(defaults: defaults) == 8, "inner gap for \(text)")
            #expect(FeatureSettings.tilingOuterGap(defaults: defaults) == 8, "outer gap for \(text)")
            #expect(FeatureSettings.tilingSplitRatio(defaults: defaults) == 50, "split for \(text)")
        }
    }

    @Test func anUnknownKeyBaseFallsBackToTheDefault() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        defaults.set("Hyper", forKey: "opt.tiling.keyBase")
        #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == .controlOptionCommand)
        defaults.set("", forKey: "opt.tiling.keyBase")
        #expect(FeatureSettings.tilingKeyBase(defaults: defaults) == .controlOptionCommand)
    }

    @Test func anOutOfRangeNumberIsLeftForTheEngineToClamp() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        defaults.set("500", forKey: "opt.tiling.innerGap")
        defaults.set("-9", forKey: "opt.tiling.outerGap")
        defaults.set("5", forKey: "opt.tiling.splitRatio")
        let config = TileConfig(innerGap: FeatureSettings.tilingInnerGap(defaults: defaults),
                                outerGap: FeatureSettings.tilingOuterGap(defaults: defaults),
                                defaultRatio: FeatureSettings.tilingDefaultRatio(defaults: defaults))
        #expect(config.innerGap == 64)
        #expect(config.outerGap == 0)
        #expect(config.defaultRatio == TileRatio.minimum)
    }

    @Test func excludedAppsKeepTheirCaseAndDropBlanks() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        defaults.set(" com.example.One ,, com.example.App\n com.example.One ,   ", forKey: "opt.tiling.excludedApps")
        #expect(FeatureSettings.tilingExcludedApps(defaults: defaults) == ["com.example.One", "com.example.App"])
        defaults.set("com.example.One\r\ncom.example.Two\rcom.example.Three\u{2028}com.example.Four,\t com.example.Five \r\n",
                     forKey: "opt.tiling.excludedApps")
        #expect(FeatureSettings.tilingExcludedApps(defaults: defaults) ==
                ["com.example.One", "com.example.Two", "com.example.Three", "com.example.Four", "com.example.Five"])
        defaults.set("  ,\n ", forKey: "opt.tiling.excludedApps")
        #expect(FeatureSettings.tilingExcludedApps(defaults: defaults).isEmpty)
    }

    @Test func onlyTheWordTrueTurnsTilingOn() throws {
        let (defaults, cleanup) = try isolated()
        defer { cleanup() }
        for text in ["", "yes", "1", "TRUE", "on"] {
            defaults.set(text, forKey: "opt.tiling.enabled")
            #expect(FeatureSettings.tilingEnabled(defaults: defaults) == false, "enabled for \(text)")
        }
        defaults.set("true", forKey: "opt.tiling.enabled")
        #expect(FeatureSettings.tilingEnabled(defaults: defaults))
    }
}
