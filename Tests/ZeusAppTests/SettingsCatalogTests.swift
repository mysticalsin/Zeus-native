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

    // MARK: Face presence

    @MainActor static func isolatedStore() throws -> (SettingsStore, UserDefaults, String) {
        let suiteName = "zeus.settings.face.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (SettingsStore(defaults: defaults), defaults, suiteName)
    }

    @MainActor @Test func faceSwitchIsNeverTurnedOnByImport() throws {
        let (store, defaults, suiteName) = try Self.isolatedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(SettingsStore.neverEnabledByImport.contains("face.presence"))
        #expect(!store.bool("face.presence"))

        func file(_ options: [String: String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["format": "zeus.settings", "version": 1, "options": options, "app": [String: String]()])
        }
        // A file that says on leaves the switch off; the same file's other value still applies.
        let applied = try store.importJSON(file(["face.presence": "true", "face.lockAfter": "5 minutes"]))
        #expect(!store.bool("face.presence"))
        #expect(defaults.string(forKey: SettingsStore.key("face.presence")) == nil)
        #expect(store.string("face.lockAfter") == "5 minutes")
        #expect(applied == 1)

        // A person who turned it on here can have an import turn it off, never on.
        store.set("face.presence", "true")
        try store.importJSON(file(["face.presence": "false"]))
        #expect(!store.bool("face.presence"))
        try store.importJSON(file(["face.presence": "true"]))
        #expect(!store.bool("face.presence"))
    }

    @MainActor @Test func exportHoldsNoFaceData() throws {
        let (store, defaults, suiteName) = try Self.isolatedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.set("face.presence", "true")
        store.set("face.lockAfter", "1 minute")

        // A vault with a face in it, so there is something that could leak.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("face-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = KeychainStore(backend: MemoryKeychain(), defaults: defaults)
        let vault = FaceVaultStore(directory: directory, keychain: keychain)
        let face = FaceRecord(id: "face-secret-id", name: "Face 1", isEnabled: true, revision: 2,
                              samples: [[0.123456, 0.654321, 0.111111], [0.222222, 0.333333, 0.444444]], threshold: 0.3)
        #expect(vault.save([face]) == .saved)

        let data = try store.exportJSON()
        let text = String(decoding: data, as: UTF8.self)
        for word in ["samples", "embedding", "threshold", "Face 1", "face-secret-id", "0.123456", "face-presence", "vaultKey", "isEnabled"] {
            #expect(!text.contains(word), "export holds \(word)")
        }
        // What it does hold about faces is the two stored settings.
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let options = try #require(root["options"] as? [String: String])
        #expect(options.keys.filter { $0.hasPrefix("face.") }.sorted() == ["face.lockAfter", "face.presence"])
        #expect(options["face.lockAfter"] == "1 minute")
        let app = try #require(root["app"] as? [String: Any])
        #expect(app.keys.allSatisfy { !$0.hasPrefix("face.") })
    }

    @MainActor @Test func unknownLockAfterFallsBackToTwoMinutes() throws {
        let option = try #require(SettingsCatalog.option("face.lockAfter"))
        #expect(option.choices == FaceLockAfter.choices.map(\.label))
        #expect(option.defaultValue == FaceLockAfter.defaultLabel)
        #expect(FaceLockAfter.seconds(forLabel: option.defaultValue) == 120)
        #expect(FaceLockAfter.seconds(forLabel: "45 minutes") == 120)
        // An import of a label that is not offered is refused, so the stored value is always one of the five.
        #expect(!SettingsStore.accepts("45 minutes", for: option))
        #expect(option.choices.allSatisfy { SettingsStore.accepts($0, for: option) })
        let (store, defaults, suiteName) = try Self.isolatedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let data = try JSONSerialization.data(withJSONObject: ["format": "zeus.settings", "version": 1,
                                                               "options": ["face.lockAfter": "45 minutes"], "app": [String: String]()])
        #expect(try store.importJSON(data) == 0)
        #expect(store.string("face.lockAfter") == "2 minutes")
    }
}
