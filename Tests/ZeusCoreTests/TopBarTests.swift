import Foundation
import Testing
@testable import ZeusCore

@Suite struct TopBarLayoutTests {
    @Test func homeAlwaysFirstAndNoDuplicates() {
        let layout = TopBarLayout(tabs: [.music, .home, .music, .shelf])
        #expect(layout.tabs == [.home, .music, .shelf])
    }

    @Test func roundTripsAndIgnoresUnknown() {
        let decoded = TopBarLayout.decode("[\"shelf\",\"bogus\",\"agents\"]")
        #expect(decoded.tabs == [.home, .shelf, .agents])
        #expect(TopBarLayout.decode(decoded.encoded()) == decoded)
        #expect(TopBarLayout.decode(nil) == .standard)
    }

    @Test func toggleRestoresCanonicalOrder() {
        var layout = TopBarLayout(tabs: [.agents, .shelf])
        layout.toggle(.music)
        #expect(layout.tabs == [.home, .agents, .music, .shelf])
        layout.toggle(.home)
        #expect(layout.tabs.first == .home)
        layout.toggle(.agents)
        #expect(!layout.contains(.agents))
        layout.move(.shelf, by: -5)
        #expect(layout.tabs == [.home, .shelf, .music])
    }
}

@Suite struct ClipboardHistoryTests {
    @Test func dedupesKeepsPinsAndTrims() {
        var history = ClipboardHistory(limit: 3)
        let r1 = history.add("   ")

        #expect(!r1)
        history.add("a"); history.add("b")
        history.togglePin(history.entries[1].id) // pin "a"
        history.add("c"); history.add("d"); history.add("e")
        #expect(history.entries.map(\.text) == ["e", "d", "a"])
        history.add("a")
        #expect(history.entries.first?.text == "a" && history.entries.first?.pinned == true)
        history.clear()
        #expect(history.entries.map(\.text) == ["a"])
        #expect(history.search("A").count == 1)
    }

    @Test func classifiesLinksAndImageHints() {
        #expect(ClipboardEntry(text: "https://example.com/a").isLink)
        #expect(ClipboardEntry(text: "mailto:a@b.com").isLink)
        #expect(!ClipboardEntry(text: "plain words").isLink)
        #expect(ClipboardEntry(text: "/tmp/shot.PNG").isImageHint)
        #expect(!ClipboardEntry(text: "png is a word").isImageHint)
    }
}

@Suite struct FocusTimerTests {
    @Test func runsPausesAndAdvances() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timer = FocusTimer(focusLength: 60, restLength: 10)
        timer.start(at: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(20)) == 40)
        timer.pause(at: t0.addingTimeInterval(20))
        #expect(timer.remaining(at: t0.addingTimeInterval(500)) == 40)
        timer.resume(at: t0.addingTimeInterval(100))
        #expect(timer.tick(at: t0.addingTimeInterval(139)) == nil)
        #expect(timer.tick(at: t0.addingTimeInterval(141)) == .focus)
        #expect(timer.phase == .rest && timer.completedRounds == 1)
        #expect(timer.tick(at: t0.addingTimeInterval(152)) == .rest)
        #expect(timer.phase == .idle)
        #expect(FocusTimer.format(65) == "1:05")
    }
}

@Suite struct DictationCoreTests {
    @Test func replacementsAreWholeWordAndCaseInsensitive() {
        let vocabulary = Vocabulary.parse("""
        Cahê
        ZEUS
        super whisper -> Superwhisper
        at sign -> @
        # comment
        """)
        #expect(vocabulary.words == ["Cahê", "ZEUS"])
        #expect(vocabulary.replacements.count == 2)
        let out = vocabulary.apply(to: "Super Whisper and zeus, mail tony at sign example, superwhispers stay")
        #expect(out == "Superwhisper and ZEUS, mail tony @ example, superwhispers stay")
        #expect(Vocabulary.parse(vocabulary.editableText) .words == vocabulary.words)
    }

    @Test func modeResolvesByFrontmostApp() {
        let modes = DictationMode.builtIns
        #expect(DictationMode.resolve(modes, selectedKey: "voice", frontmostBundleID: "com.apple.mail", autoSwitch: true).key == "email")
        #expect(DictationMode.resolve(modes, selectedKey: "voice", frontmostBundleID: "com.apple.mail", autoSwitch: false).key == "voice")
        #expect(DictationMode.resolve(modes, selectedKey: "nope", frontmostBundleID: nil, autoSwitch: true).key == "voice")
        #expect(!modes[0].usesAI && modes[1].usesAI)
        let prompt = modes[4].buildPrompt(transcript: "fix the build", selectedText: "error: x", clipboard: "secret", appName: "Terminal")
        #expect(prompt.contains("# Selected text\nerror: x") && !prompt.contains("secret") && prompt.hasSuffix("fix the build"))
    }

    @Test func storeRoundTripsHistoryModesAndVocabulary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-dict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationStore(root: root)
        let old = DictationRecord(datetime: Date().addingTimeInterval(-40 * 86_400), duration: 1000, processingTime: 80,
                                  modeKey: "voice", modeName: "Voice", rawResult: "hi", result: "Hi.")
        let new = DictationRecord(duration: 2000, processingTime: 90, modeKey: "note", modeName: "Note", rawResult: "x", result: "two words")
        try store.save(old); try store.save(new)
        #expect(store.history().map(\.id) == [new.id, old.id])
        #expect(store.prune(olderThanDays: 30) == 1)
        #expect(store.history().map(\.id) == [new.id])
        #expect(new.wordCount == 2)
        var custom = DictationMode(key: "voice", name: "Plain")
        custom.activationApps = ["x"]
        try store.save(custom)
        try store.save(DictationMode(key: "standup", name: "Standup", prompt: "Summarise"))
        let modes = store.modes()
        #expect(modes.first?.name == "Plain" && modes.last?.key == "standup")
        try store.save(Vocabulary(words: ["Métis"]))
        #expect(store.vocabulary().words == ["Métis"])
    }
}

@Suite struct WeatherTests {
    @Test func decodesOpenMeteo() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let json = """
        {"current":{"temperature_2m":21.4,"apparent_temperature":20.1,"weather_code":61,"is_day":1,"relative_humidity_2m":70,"wind_speed_10m":12.5},
         "hourly":{"time":[1800000000,1800003600,1800007200],"temperature_2m":[21,22,23],"weather_code":[61,3,0],"precipitation_probability":[80,60,null]},
         "daily":{"temperature_2m_max":[25.0],"temperature_2m_min":[15.0]}}
        """
        let weather = try WeatherSnapshot.decode(Data(json.utf8), now: now)
        #expect(weather.sky == .rain && weather.high == 25 && weather.hours.count == 3)
        #expect(weather.rainSoon(after: now)?.rainChance == 60)
        #expect(WeatherSnapshot.sky(forCode: 95) == .storm)
        #expect(WeatherSnapshot.url(latitude: -23.55, longitude: -46.63).absoluteString.contains("latitude=-23.550"))
    }
}

@Suite struct NowPlayingTests {
    @Test func parsesMusicAndSpotify() {
        let now = Date(timeIntervalSince1970: 100)
        let music = NowPlaying.parse(["Name": "Song", "Artist": "A", "Album": "B", "Player State": "Playing", "Total Time": 200_000],
                                     player: .music, now: now)
        #expect(music?.duration == 200 && music?.isPlaying == true)
        #expect(music?.elapsed(at: now.addingTimeInterval(10)) == 10)
        let spotify = NowPlaying.parse(["Name": "S", "Player State": "Paused", "Duration": 90_000, "Playback Position": 30.5],
                                       player: .spotify, now: now)
        #expect(spotify?.duration == 90 && spotify?.elapsed(at: now.addingTimeInterval(50)) == 30.5)
        #expect(NowPlaying.parse(["Name": "x", "Player State": "Stopped"], player: .music) == nil)
        #expect((0..<1).contains(music!.hue))
    }

    @Test func findsMeetingLinks() {
        #expect(MeetingLink.find(in: [nil, "Room 4", "join https://us02web.zoom.us/j/123 now"])?.host == "us02web.zoom.us")
        #expect(MeetingLink.find(in: ["https://example.com/x"]) == nil)
    }
}
