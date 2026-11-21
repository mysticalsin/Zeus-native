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
        let suiteName = NSTemporaryDirectory() + "zeus.dictation.language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("off", forKey: ShortcutStore.dictationKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = DictationSettings(defaults: defaults)
        #expect(settings.language == .automatic)
        settings.language = .portugueseBrazil
        #expect(defaults.string(forKey: "dictation.language") == "Portuguese (Brazil)")
        #expect(DictationSettings(defaults: defaults).language == .portugueseBrazil)
    }

    @MainActor @Test func shortcutBehaviorPersistsAndSharedKeyStaysHoldToSpeak() throws {
        let suiteName = NSTemporaryDirectory() + "zeus.dictation.behavior.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
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
        let suiteName = NSTemporaryDirectory() + "zeus.settings.catalog.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
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

    // MARK: Start automatically is the opt-in

    /// A store over a throwaway suite whose microphone answer is fixed and whose prompt only counts.
    @MainActor private final class AutoStartRig {
        let defaults: UserDefaults
        let store: SettingsStore
        private let suiteName = NSTemporaryDirectory() + "zeus.autostart.\(UUID().uuidString)"
        private(set) var prompts = 0

        init(access: ScribeMicrophoneAccess = .allowed, stored: String? = nil) {
            defaults = UserDefaults(suiteName: suiteName)!
            if let stored { defaults.set(stored, forKey: SettingsStore.key(ScribeAutoStartMode.settingID)) }
            store = SettingsStore(defaults: defaults)
            store.microphoneAccess = { access }
            store.askForMicrophone = { [unowned self] in self.prompts += 1 }
        }

        func cleanup() { defaults.removePersistentDomain(forName: suiteName) }

        var stamp: Date? { ScribeAutoStartOptIn.date(defaults: defaults) }
        var mode: String { store.string(ScribeAutoStartMode.settingID) }

        func importFile(_ choice: String) throws -> Int {
            let root: [String: Any] = ["format": "zeus.settings", "version": 1,
                                       "options": [ScribeAutoStartMode.settingID: choice], "app": [String: Any]()]
            return try store.importJSON(JSONSerialization.data(withJSONObject: root))
        }
    }

    @MainActor @Test func choosingStartAutomaticallyIsTheOptInAndAsksOnlyWhenMacOSHasNotAsked() throws {
        let fresh = AutoStartRig(access: .notAsked)
        defer { fresh.cleanup() }
        fresh.store.set("scribe.autoStart", "Start automatically")
        #expect(fresh.mode == "Start automatically")
        #expect(fresh.stamp != nil)
        #expect(fresh.prompts == 1)

        for access in [ScribeMicrophoneAccess.allowed, .denied] {
            let rig = AutoStartRig(access: access)
            defer { rig.cleanup() }
            rig.store.set("scribe.autoStart", "Start automatically")
            #expect(rig.stamp != nil, "\(access)")
            #expect(rig.prompts == 0, "\(access)")
        }
    }

    @MainActor @Test func theOtherChoicesNeverAskMacOSAndNeverStamp() throws {
        let rig = AutoStartRig(access: .notAsked)
        defer { rig.cleanup() }
        rig.store.set("scribe.autoStart", "Off")
        rig.store.set("scribe.autoStart", "Ask me")
        #expect(rig.prompts == 0)
        #expect(rig.stamp == nil)
    }

    @MainActor @Test func choosingAnotherModeWithdrawsTheOptIn() throws {
        for other in ["Ask me", "Off"] {
            let rig = AutoStartRig()
            defer { rig.cleanup() }
            rig.store.set("scribe.autoStart", "Start automatically")
            #expect(rig.stamp != nil)
            rig.store.set("scribe.autoStart", other)
            #expect(rig.mode == other)
            #expect(rig.stamp == nil, "\(other)")
        }
    }

    @MainActor @Test func clickingTheChoiceThatAlreadyShowsStillGivesTheOptIn() throws {
        // A raw defaults write can leave the choice automatic with no stamp; the click is what gives it.
        let rig = AutoStartRig(stored: "Start automatically")
        defer { rig.cleanup() }
        #expect(rig.stamp == nil)
        rig.store.set("scribe.autoStart", "Start automatically")
        #expect(rig.stamp != nil)
    }

    @MainActor @Test func anImportNeverChoosesStartAutomatically() throws {
        let rig = AutoStartRig(access: .notAsked)
        defer { rig.cleanup() }
        let changed = try rig.importFile("Start automatically")
        #expect(changed == 0)
        #expect(rig.mode == "Ask me")
        #expect(rig.stamp == nil)
        #expect(rig.prompts == 0)
        #expect(rig.defaults.string(forKey: SettingsStore.key("scribe.autoStart")) == nil)
    }

    @MainActor @Test func anImportAskingForStartAutomaticallyLeavesAnExistingOptInAlone() throws {
        let rig = AutoStartRig()
        defer { rig.cleanup() }
        rig.store.set("scribe.autoStart", "Start automatically")
        let stamp = rig.stamp
        #expect(try rig.importFile("Start automatically") == 0)
        #expect(rig.mode == "Start automatically")
        #expect(rig.stamp == stamp)
    }

    @MainActor @Test func anImportWithOffAppliesAndRemovesTheStamp() throws {
        let rig = AutoStartRig()
        defer { rig.cleanup() }
        rig.store.set("scribe.autoStart", "Start automatically")
        #expect(try rig.importFile("Off") == 1)
        #expect(rig.mode == "Off")
        #expect(rig.stamp == nil)
        let other = AutoStartRig()
        defer { other.cleanup() }
        other.store.set("scribe.autoStart", "Start automatically")
        #expect(try other.importFile("Ask me") == 1)
        #expect(other.stamp == nil)
    }

    @MainActor @Test func theSecondTalkKeyTravelsWithAnExport() {
        #expect(SettingsStore.appKeys.contains(ShortcutStore.secondTalkKey), "the key the recorder writes is exported and imported like the talk key")
    }

    @MainActor @Test func aChosenTalkMicrophoneDeviceIsNeverExported() throws {
        let suiteName = NSTemporaryDirectory() + "zeus.settings.catalog.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.set(TalkMicrophoneChoice.settingID, TalkMicrophoneChoice.device("AppleUSBAudioEngine:ACME:1234").stored)
        let text = String(decoding: try store.exportJSON(), as: UTF8.self)
        #expect(!text.contains("device:"), "a CoreAudio UID is from this Mac and stays here")
        #expect(!text.contains("AppleUSBAudioEngine"))

        store.set(TalkMicrophoneChoice.settingID, TalkMicrophoneChoice.builtIn.stored)
        let root = try #require(JSONSerialization.jsonObject(with: store.exportJSON()) as? [String: Any])
        let options = try #require(root["options"] as? [String: String])
        #expect(options[TalkMicrophoneChoice.settingID] == TalkMicrophoneChoice.builtInTitle, "a named choice still travels")
    }

    @MainActor @Test func theStampKeysAreNeverExportedOrImported() throws {
        let keys = Set(SettingsStore.appKeys)
        for key in [ScribeAutoStartOptIn.key, ScribeAutoStartOptIn.legacyKey, ScribeAutoStartOptIn.firstRecordingKey] {
            #expect(!keys.contains(key), "\(key)")
        }
        let rig = AutoStartRig()
        defer { rig.cleanup() }
        rig.store.set("scribe.autoStart", "Start automatically")
        let text = String(decoding: try rig.store.exportJSON(), as: UTF8.self)
        #expect(!text.contains("optInAt"))
        #expect(!text.contains("firstRecordingAt"))
    }

    @MainActor @Test func aSectionResetWithdrawsTheOptIn() throws {
        let rig = AutoStartRig()
        defer { rig.cleanup() }
        rig.store.set("scribe.autoStart", "Start automatically")
        #expect(rig.stamp != nil)
        rig.store.reset(.agents)
        #expect(rig.mode == "Ask me")
        #expect(rig.stamp == nil)
        #expect(rig.prompts == 0)
    }

    @MainActor @Test func aResetOfAChoiceThatAlreadyShowsAskMeStillClearsAStaleStamp() throws {
        let rig = AutoStartRig()
        defer { rig.cleanup() }
        rig.defaults.set(1_000.0, forKey: ScribeAutoStartOptIn.key)
        rig.store.reset(.agents)
        #expect(rig.stamp == nil)
    }

    // MARK: Face presence

    @MainActor static func isolatedStore() throws -> (SettingsStore, UserDefaults, String) {
        let suiteName = NSTemporaryDirectory() + "zeus.settings.face.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
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

    /// REG-684: Fling is an explicit opt-in. It starts off, and an import can leave it alone or turn it off, never on.
    @MainActor @Test func flingStartsOffAndAnImportNeverTurnsItOn() throws {
        let (store, defaults, suiteName) = try Self.isolatedStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(SettingsCatalog.option("fling.enabled")?.defaultValue == "false")
        #expect(SettingsCatalog.option("fling.papers")?.defaultValue == "false")
        #expect(SettingsStore.neverEnabledByImport.contains("fling.enabled"))
        #expect(!store.bool("fling.enabled"))
        func file(_ options: [String: String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["format": "zeus.settings", "version": 1, "options": options, "app": [String: String]()])
        }
        try store.importJSON(file(["fling.enabled": "true", "fling.flickSensitivity": "High"]))
        #expect(!store.bool("fling.enabled"))
        #expect(store.string("fling.flickSensitivity") == "High")
        store.set("fling.enabled", "true")
        try store.importJSON(file(["fling.enabled": "false"]))
        #expect(!store.bool("fling.enabled"))
    }

    @Test func theFlingRowsLiveOnTheShelfSectionAndTheLightIsEverydayLights() {
        let ids = SettingsCatalog.options(in: .shelf).map(\.id)
        #expect(ids == ["fling.enabled", "fling.receiveInBackground", "fling.deviceName", "fling.visibility", "fling.autoAcceptPaired",
                        "fling.saveMode", "fling.papers", "fling.flickSensitivity", "fling.openLinks", "fling.pairedMacs"])
        #expect(SettingsCatalog.option("lights.fling")?.group == "Everyday lights")
        #expect(SettingsCatalog.option("lights.fling")?.defaultValue == "true")
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

    @Test func drawOnScreenIsAnOffByDefaultLiveToggleOnTheVoicePage() throws {
        let option = try #require(SettingsCatalog.option("talk.drawOnScreen"))
        #expect(option.section == .voice)
        #expect(option.kind == .toggle)
        #expect(option.defaultValue == "false")
        #expect(option.state == .live)
        #expect(option.note.contains("screenshot"))
        let empty = UserDefaults(suiteName: NSTemporaryDirectory() + "talk.drawOnScreen.\(UUID().uuidString)")!
        #expect(!FeatureSettings.talkDrawOnScreen(defaults: empty))
        empty.set("true", forKey: FeatureSettings.key("talk.drawOnScreen"))
        #expect(FeatureSettings.talkDrawOnScreen(defaults: empty))
    }

    @Test func seeScreenIsAnOffByDefaultLiveToggleOnTheVoicePageSeparateFromDrawing() throws {
        let option = try #require(SettingsCatalog.option("talk.seeScreen"))
        #expect(option.section == .voice)
        #expect(option.kind == .toggle)
        #expect(option.defaultValue == "false")
        #expect(option.state == .live)
        #expect(option.note.lowercased().contains("screen"))
        let draw = try #require(SettingsCatalog.option("talk.drawOnScreen"))
        #expect(draw.defaultValue == "false")
        let suiteName = NSTemporaryDirectory() + "talk.seeScreen.\(UUID().uuidString)"
        let empty = UserDefaults(suiteName: suiteName)!
        defer { empty.removePersistentDomain(forName: suiteName) }
        #expect(!FeatureSettings.talkSeeScreen(defaults: empty))
        #expect(!FeatureSettings.talkDrawOnScreen(defaults: empty))
        empty.set("true", forKey: FeatureSettings.key("talk.seeScreen"))
        #expect(FeatureSettings.talkSeeScreen(defaults: empty))
    }
}
