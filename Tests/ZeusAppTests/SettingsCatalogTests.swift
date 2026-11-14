import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Settings catalog")
struct SettingsCatalogTests {
    @Test func implementedAppearanceControlsAreListed() {
        let options = Set(SettingsCatalog.options(in: .appearance).map(\.id))
        #expect(options.contains("appearance.runningCard"))
        #expect(options.contains("halo.intensity"))
        #expect(SettingsCatalog.option("halo.speed")?.isShown == true)
        #expect(options.contains("lights.micGlow"))
        #expect(options.contains("lights.rain"))
        #expect(options.contains("halo.armWidth"))
        #expect(options.contains("halo.thickness"))
        #expect(options.contains("halo.edgeWave"))
        #expect(options.contains("lights.musicProgress"))
        #expect(options.contains("lights.reminderGlow"))
        #expect(options.contains("lights.shortcutPeeks"))
        #expect(options.contains("halo.style"))
        #expect(SettingsCatalog.option("assistant.model") != nil)
    }

    @Test func wordByWordLyricsIsALiveToggleThatDefaultsOn() {
        let option = SettingsCatalog.option("lyrics.wordByWord")
        #expect(option?.section == .appearance)
        #expect(option?.group == "Everyday lights")
        #expect(option?.kind == .toggle)
        #expect(option?.defaultValue == "true")
        #expect(option?.state == .live)
        #expect(option?.title == "Light lyrics word by word")
    }

    @Test func theOpenTriggerChoicesParseToTheirTriggersAndDefaultToHover() throws {
        let option = try #require(SettingsCatalog.option("notch.openTrigger"))
        #expect(option.section == .appearance)
        #expect(option.group == "Notch behavior")
        #expect(option.kind == .choice)
        #expect(option.state == .live)
        #expect(option.title == "Open the notch on")
        #expect(option.choices == ["Hover", "Click"])
        #expect(option.choices.map { NotchOpenTrigger(label: $0) } == [.hover, .click])
        #expect(NotchOpenTrigger(label: option.defaultValue) == .hover)
        #expect(option.choices.contains(option.defaultValue))
    }

    @Test func theCornerSizeChoicesAreTheCoreSizesAndDefaultToMedium() throws {
        let option = try #require(SettingsCatalog.option("screen.cornerRadius"))
        #expect(option.section == .appearance)
        #expect(option.group == "Screen")
        #expect(option.kind == .choice)
        #expect(option.state == .live)
        #expect(option.title == "Corner size")
        #expect(option.choices == ScreenCornerSize.allCases.map(\.label))
        #expect(option.choices.map { ScreenCornerSize(label: $0) } == ScreenCornerSize.allCases)
        #expect(Set(option.choices.map { ScreenCornerSize(label: $0).radius }).count == option.choices.count)
        #expect(ScreenCornerSize(label: option.defaultValue) == .medium)
    }

    @MainActor @Test func theCornerAndMusicAwakeTogglesAreLiveAndDefaultOff() throws {
        let corners = try #require(SettingsCatalog.option("screen.roundBottomCorners"))
        #expect(corners.section == .appearance)
        #expect(corners.group == "Screen")
        #expect(corners.kind == .toggle)
        #expect(corners.state == .live)
        #expect(corners.defaultValue == "false")
        #expect(corners.title == "Round the bottom screen corners")

        let music = try #require(SettingsCatalog.option("keepAwake.whileMusic"))
        #expect(music.section == .general)
        #expect(music.group == "Day to day")
        #expect(music.kind == .toggle)
        #expect(music.state == .live)
        #expect(music.defaultValue == "false")
        #expect(music.title == "Keep the display awake while music plays")
        #expect(music.id == MusicAwakeHold.settingID)
    }

    @Test func dictationLanguageIsCatalogued() {
        #expect(SettingsCatalog.option("dictation.language")?.title == "Dictation language")
        #expect(SettingsCatalog.option("dictation.behavior")?.isShown == true)
        #expect(SettingsCatalog.option("notify.system")?.isShown == true)
    }

    @MainActor @Test func codexConnectionStatusDistinguishesHookFromLogFallback() {
        let connected = SettingStatus.codexConnectionStatus(cliFound: true, hookInstalled: true)
        #expect(connected.0)
        #expect(connected.1 == "Hook installed · approvals")

        let logsOnly = SettingStatus.codexConnectionStatus(cliFound: true, hookInstalled: false)
        #expect(logsOnly.0)
        #expect(logsOnly.1 == "Logs only · hook adds approvals")

        let missing = SettingStatus.codexConnectionStatus(cliFound: false, hookInstalled: false)
        #expect(!missing.0)
        #expect(missing.1 == "Not installed")
    }

    @MainActor @Test func dictationLanguagePersistsInIsolatedDefaults() throws {
        let suiteName = "zeus.dictation.language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("off", forKey: ShortcutStore.dictationKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = DictationSettings(defaults: defaults)
        #expect(settings.language == .automatic)
        settings.language = .portugueseBrazil
        #expect(defaults.string(forKey: "dictation.language") == "Portuguese (Brazil)")
        #expect(DictationSettings(defaults: defaults).language == .portugueseBrazil)
    }

    @MainActor @Test func shortcutBehaviorPersistsAndSharedKeyStaysHoldToSpeak() throws {
        let suiteName = "zeus.dictation.behavior.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let talkKey = Preferences.shared.pushToTalk
        defaults.set(Shortcut.stored(talkKey), forKey: ShortcutStore.dictationKey)
        defaults.set(DictationBehavior.pressToToggle.rawValue, forKey: "dictation.behavior")
        let settings = DictationSettings(defaults: defaults)

        #expect(settings.selectedBehavior == .holdToSpeak)
        #expect(settings.availableBehaviors == [.holdToSpeak])
        let dedicatedKey = talkKey == .rightOption ? Shortcut.function : Shortcut.rightOption
        settings.key = dedicatedKey
        settings.behavior = .pressToToggle
        #expect(settings.selectedBehavior == .pressToToggle)
        #expect(defaults.string(forKey: "dictation.behavior") == DictationBehavior.pressToToggle.rawValue)

        settings.key = talkKey
        #expect(settings.selectedBehavior == .holdToSpeak)
        #expect(defaults.string(forKey: "dictation.behavior") == DictationBehavior.holdToSpeak.rawValue)
    }

    @MainActor @Test func exportIncludesHandBuiltSettings() throws {
        let suiteName = "zeus.settings.catalog.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.set("assistant.provider", "Anthropic")
        store.set("assistant.model", "claude-sonnet-4")
        store.set("halo.style", "Crystal prism")

        let root = try #require(JSONSerialization.jsonObject(with: store.exportJSON()) as? [String: Any])
        let options = try #require(root["options"] as? [String: String])
        #expect(options["assistant.provider"] == "Anthropic")
        #expect(options["assistant.model"] == "claude-sonnet-4")
        #expect(options["halo.style"] == "Crystal prism")
    }
}
