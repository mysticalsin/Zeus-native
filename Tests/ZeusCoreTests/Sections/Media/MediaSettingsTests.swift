import Foundation
import Testing
@testable import ZeusCore

@Suite("Media settings") struct MediaSettingsTests {
    @Test func mediaShowsTheNamedContractRowsAndHeldRowsSayNotAvailableYet() throws {
        let controls = MediaSectionCatalog.controls(for: .defaults)
        let ids = controls.map(\.id)
        let required = [
            "music.follow",
            "home.variant.music",
            "media.playerLook",
            "media.tintFromSong",
            "media.likeFollowsSong",
            "media.explicitBadge",
            "media.explicitMatchColour",
            "topBar.musicWings",
            "privacy.lyrics",
            "lyrics.wordByWord",
            "media.shuffleRepeat",
            "media.leftButton",
            "media.hideOnPause",
            "notch.openTrigger",
            "keepAwake.whileMusic",
            "audio.equaliser",
            "music.browserMedia",
            "media.animatedArtwork",
            "media.systemNowPlaying",
        ]
        #expect(ids == required)
        #expect(Set(ids).count == ids.count)
        for control in controls {
            #expect(!control.title.isEmpty)
            #expect(!control.helper.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(control.accessibilityLabel.contains(control.title))
        }
        let held = controls.filter { $0.interaction == .held }
        #expect(held.map(\.id) == ["media.animatedArtwork", "media.systemNowPlaying"])
        for control in held {
            guard case .held(let note) = control.kind else {
                Issue.record("\(control.id) is not a held row")
                continue
            }
            #expect(note == MediaHeldFeature.heldNote)
            #expect(note == "Coming later")
        }
        #expect(MediaHeldFeature.animatedArtworkImplemented == false)
        #expect(MediaHeldFeature.systemNowPlayingImplemented == false)
        #expect(MediaSectionPlacement.topbarTab == 0)
        let root = repoRoot()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        #expect(catalog.contains("choices: [\"Art\", \"Disc\", \"Cassette\", \"Wave\", \"Lyrics\"]"))
        let store = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsStore.swift"), encoding: .utf8)
        #expect(store.contains("static func key(_ id: String) -> String { \"opt.\" + id }"))
        #expect(MediaDefaultsKey.prefix == "opt.")
        #expect(MediaDefaultsKey.stored("music.follow") == "opt.music.follow")
    }

    @Test func defaultsKeepExistingKeysAndLeaveNetworkOff() {
        let settings = MediaSettings.defaults
        #expect(settings == MediaSettings(reading: { _ in nil }))
        #expect(settings == MediaSettings(reading: { _ in "  " }))
        #expect(settings.follow == .any)
        #expect(settings.homeMusic == "Art")
        #expect(settings.look == .art)
        #expect(settings.tintFromSong == false)
        #expect(settings.likeFollowsSong == false)
        #expect(settings.explicitBadge == false)
        #expect(settings.explicitMatchesColour == false)
        #expect(settings.waveform == true)
        #expect(settings.lyrics == false)
        #expect(settings.wordByWord == true)
        #expect(settings.leftButton == .previous)
        #expect(settings.hideOnPause == .never)
        #expect(settings.openTrigger == .hover)
        #expect(settings.keepAwake == false)
        #expect(settings.equaliser == false)
        #expect(settings.browserMedia == false)
        #expect(MediaLyricsPolicy.mayUseNetwork(enabled: settings.lyrics) == false)
        #expect(MediaLyricsPolicy.defaultEnabled == false)
        #expect(MediaSettingID.existing == [
            "music.follow", "home.variant.music", "topBar.musicWings", "privacy.lyrics", "lyrics.wordByWord",
            "notch.openTrigger", "keepAwake.whileMusic", "audio.equaliser", "music.browserMedia",
        ])
        #expect(MediaSettingID.added == [
            "media.playerLook", "media.tintFromSong", "media.likeFollowsSong", "media.explicitBadge",
            "media.explicitMatchColour", "media.leftButton", "media.hideOnPause",
        ])
        let controls = MediaSectionCatalog.controls(for: settings)
        #expect(toggle("privacy.lyrics", in: controls) == false)
        #expect(toggle("music.browserMedia", in: controls) == false)
        #expect(toggle("audio.equaliser", in: controls) == false)
        #expect(toggle("keepAwake.whileMusic", in: controls) == false)
        #expect(toggle("lyrics.wordByWord", in: controls) == true)
        #expect(toggle("topBar.musicWings", in: controls) == true)
    }

    @Test func unknownValuesFallBackAndRoundTrip() {
        let garbage = MediaSettings(reading: { _ in "nope" })
        #expect(garbage == .defaults)
        var custom = MediaSettings.defaults
        custom.follow = .pinned(NowPlaying.Player.allCases[0])
        custom.homeMusic = "Wave"
        custom.look = .glassCard
        custom.tintFromSong = true
        custom.likeFollowsSong = false
        custom.explicitBadge = false
        custom.explicitMatchesColour = true
        custom.waveform = false
        custom.lyrics = true
        custom.wordByWord = false
        custom.leftButton = .lyrics
        custom.hideOnPause = .afterDelay
        custom.openTrigger = .click
        custom.keepAwake = true
        custom.equaliser = true
        custom.browserMedia = true
        let stored = custom.persisted()
        #expect(MediaSettings(reading: { stored[$0] }) == custom)
        #expect(stored["privacy.lyrics"] == "true")
        #expect(stored["media.playerLook"] == "glassCard")
        #expect(stored["media.hideOnPause"] == "afterDelay")
        #expect(stored["home.variant.music"] == "Wave")
        #expect(MediaHomeMusicStyle.choices == ["Art", "Disc", "Cassette", "Wave", "Lyrics"])
    }

    @Test func anImportCannotTurnNetworkOrShapingOn() {
        for id in MediaImportGuard.protected {
            #expect(MediaImportGuard.value(id: id, imported: "true", current: nil) == nil)
            #expect(MediaImportGuard.value(id: id, imported: "true", current: "false") == "false")
            #expect(MediaImportGuard.value(id: id, imported: "false", current: "true") == "false")
        }
        #expect(MediaImportGuard.protected == ["privacy.lyrics", "music.browserMedia", "audio.equaliser"])
        #expect(MediaImportGuard.value(id: "media.tintFromSong", imported: "true", current: nil) == "true")
        let imported = MediaSettings(reading: { id in
            MediaImportGuard.value(id: id, imported: "true", current: nil)
        })
        #expect(imported.lyrics == false)
        #expect(imported.browserMedia == false)
        #expect(imported.equaliser == false)
        #expect(imported.tintFromSong == true)
    }

    @Test func onePlayerHidesRepeatOneAndAScriptTimesOutAtThreeSeconds() {
        let players = NowPlaying.Player.allCases
        #expect(players.count == 2)
        let availability = MediaRepeatAvailability.all
        #expect(availability.count == 2)
        #expect(availability.filter(\.offersOne).count == 1)
        #expect(availability.filter { !$0.offersOne }.count == 1)
        let withOne = players.filter { MusicModeRules.supportedRepeatModes($0).contains(.one) }
        let without = players.filter { !MusicModeRules.supportedRepeatModes($0).contains(.one) }
        #expect(withOne.count == 1)
        #expect(without.count == 1)
        for player in players {
            #expect(MediaTransport.script(consent: false, player: player, age: 0, shuffleOn: true) == nil)
            #expect(MediaTransport.repeatScript(consent: false, player: player, age: 0, mode: .all) == nil)
            #expect(MediaTransport.script(consent: true, player: player, age: 3, shuffleOn: false) != nil)
            #expect(MediaTransport.script(consent: true, player: player, age: 3.001, shuffleOn: true) == nil)
            #expect(MediaTransport.repeatScript(consent: true, player: player, age: -1, mode: .off) != nil)
        }
        let kept = MediaTransport.repeatScript(consent: true, player: withOne[0], age: 3, mode: .one)
        #expect(kept?.contains("one") == true)
        let hidden = MediaTransport.repeatScript(consent: true, player: without[0], age: 0, mode: .one)
        #expect(hidden != nil)
        #expect(hidden?.contains("one") == false)
        for step in 0...40 {
            let age = Double(step) / 10
            #expect(MediaTransport.abandoned(age: age) == (age > 3))
        }
        #expect(MediaTransport.timeout == 3)
        #expect(MediaTransport.abandoned(age: -0.1) == false)
    }

    @Test func awakeFollowsTheExistingBatteryAndHeatRule() {
        let rules = KeepAwakeRules()
        let power = KeepAwakeRules.Power(batteryPercent: 80, isCharging: false, onBattery: true, thermal: .nominal)
        let now = Date(timeIntervalSince1970: 5_000)
        #expect(MediaAwakePlan.verdict(enabled: false, isPlaying: true, lastPlayedAt: now, now: now, power: power, rules: rules) == .release(.off))
        #expect(MediaAwakePlan.verdict(enabled: true, isPlaying: true, lastPlayedAt: now, now: now, power: power, rules: rules) == .hold)
        let paused = now.addingTimeInterval(19)
        #expect(MediaAwakePlan.verdict(enabled: true, isPlaying: false, lastPlayedAt: now, now: paused, power: power, rules: rules) == .hold)
        let dropped = now.addingTimeInterval(20)
        #expect(MediaAwakePlan.verdict(enabled: true, isPlaying: false, lastPlayedAt: now, now: dropped, power: power, rules: rules) == .release(.notPlaying))
        let hot = KeepAwakeRules.Power(batteryPercent: 80, isCharging: false, onBattery: false, thermal: .critical)
        #expect(MediaAwakePlan.verdict(enabled: true, isPlaying: true, lastPlayedAt: now, now: now, power: hot, rules: rules) == .release(.tooHot))
    }

    @Test func addedKeysSurviveTheExistingSettingsStore() throws {
        let name = "zeus.media.persist.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let fresh = MediaSettings(reading: { defaults.string(forKey: MediaDefaultsKey.stored($0)) })
        #expect(fresh.tintFromSong == false)
        #expect(fresh.likeFollowsSong == false)
        #expect(fresh.explicitBadge == false)
        #expect(fresh.explicitMatchesColour == false)
        #expect(fresh.lyrics == false)
        #expect(fresh.browserMedia == false)
        #expect(fresh.equaliser == false)

        var edited = MediaSettings.defaults
        edited.look = .detailed
        edited.tintFromSong = true
        edited.likeFollowsSong = true
        edited.explicitBadge = true
        edited.explicitMatchesColour = true
        edited.leftButton = .like
        edited.hideOnPause = .instantly
        edited.homeMusic = "Wave"
        edited.lyrics = true
        for (id, value) in edited.persisted() {
            defaults.set(value, forKey: MediaDefaultsKey.stored(id))
        }
        let restored = MediaSettings(reading: { defaults.string(forKey: MediaDefaultsKey.stored($0)) })
        #expect(restored == edited)

        let root = repoRoot()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsCatalog.swift"), encoding: .utf8)
        let lines = catalog.split(separator: "\n").map(String.init)
        for id in MediaSettingID.added {
            #expect(lines.contains { $0.contains("id: \"\(id)\"") }, "\(id) is missing from the settings catalog")
        }
        for id in ["media.tintFromSong", "media.likeFollowsSong", "media.explicitBadge", "media.explicitMatchColour"] {
            let line = lines.first { $0.contains("id: \"\(id)\"") }
            #expect(line?.contains("defaultValue: \"false\"") == true)
            #expect(line?.contains("state: .live") == true)
        }
        let store = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/App/SettingsStore.swift"), encoding: .utf8)
        #expect(store.contains("neverEnabledByImport"))
        for id in ["privacy.lyrics", "music.browserMedia", "audio.equaliser"] {
            #expect(store.contains("\"\(id)\""))
        }
    }

    @Test func everyControlIsAKeyboardControl() {
        let interactions = Set(MediaSectionCatalog.controls(for: .defaults).map(\.interaction))
        #expect(interactions == [.toggle, .choice, .status, .held])
        for control in MediaSectionCatalog.controls(for: .defaults) where control.interaction == .choice {
            guard case .choice(let selected, let options) = control.kind else {
                Issue.record("\(control.id) lost its choices")
                continue
            }
            #expect(options.contains(selected))
            #expect(Set(options).count == options.count)
        }
    }

    private func toggle(_ id: String, in controls: [MediaControl]) -> Bool? {
        guard let control = controls.first(where: { $0.id == id }), case .toggle(let on) = control.kind else { return nil }
        return on
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
