import Foundation
import Testing
@testable import ZeusCore

@Suite struct LyricsTests {
    static let fixture = """
    {"id":1,"trackName":"Midnight City","artistName":"M83","albumName":"Hurry Up","duration":243,"instrumental":false,
     "plainLyrics":"Waiting\\nWaiting 2","syncedLyrics":"[ti:Midnight City]\\n[offset:+500]\\n[00:12.50] Waiting in a car\\n[00:20.00][01:00.25] Chorus\\n[00:30.1]\\n[01:05] Last"}
    """

    @Test func parsesSyncedLyricsFromLRCLIB() {
        guard case .synced(let lines) = LRCLIBResponse.parse(Data(Self.fixture.utf8)) else { Issue.record("not synced"); return }
        #expect(lines.map(\.text) == ["Waiting in a car", "Chorus", "", "Chorus", "Last"])
        #expect(lines[0].time == 12.0) // offset +500 ms pulls it earlier
        #expect(lines[3].time == 59.75)
    }

    @Test func lineTimingFindsTheCurrentLine() {
        let lines = LRC.parse("[00:10.00]a\n[00:20.00]b\n[00:30.00]c")
        #expect(lines.currentIndex(at: 5) == nil)
        #expect(lines.currentIndex(at: 10) == 0)
        #expect(lines.currentIndex(at: 29.9) == 1)
        #expect(lines.currentIndex(at: 500) == 2)
        #expect(abs(lines.lineProgress(at: 15) - 0.5) < 0.001)
    }

    @Test func instrumentalMissAndPlain() {
        #expect(LRCLIBResponse.parse(Data(#"{"instrumental":true}"#.utf8)) == .instrumental)
        #expect(LRCLIBResponse.parse(Data(#"{"code":404,"name":"NotFound"}"#.utf8)) == .none)
        #expect(LRCLIBResponse.parse(Data(#"{"plainLyrics":"la la"}"#.utf8)) == .plain("la la"))
    }

    @Test func queryAndCache() throws {
        let query = LRCLIBQuery(artist: "M83", title: "Midnight City", album: "Hurry Up", duration: 243.4)
        let url = try #require(query.url).absoluteString
        #expect(url.contains("artist_name=M83") && url.contains("track_name=Midnight%20City") && url.contains("album_name=Hurry%20Up") && url.contains("duration=243"))
        #expect(query.looseURL?.absoluteString.contains("duration") == false)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lyr-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = LyricsCache(directory: dir)
        #expect(cache.load(query) == nil)
        cache.save(.synced([LyricLine(time: 1, text: "x")]), for: query)
        #expect(cache.load(query) == .synced([LyricLine(time: 1, text: "x")]))
        let miss = LRCLIBQuery(artist: "A", title: "B")
        let now = Date()
        cache.save(.none, for: miss, now: now)
        #expect(cache.load(miss, now: now.addingTimeInterval(3600)) == LyricsResult.none)
        #expect(cache.load(miss, now: now.addingTimeInterval(5 * 86400)) == nil) // a miss expires
    }
}

@Suite struct FlightRecorderTests {
    @Test func ringKeepsTheLastEvents() {
        let recorder = FlightRecorder(capacity: 3)
        for i in 1...5 { recorder.record("voice", "s\(i)") }
        #expect(recorder.events.map(\.stage) == ["s3", "s4", "s5"])
        #expect(recorder.totalRecorded == 5)
        #expect(FlightRecorder.defaultCapacity == 2000)
    }

    @Test func redactsSecrets() {
        let text = DiagnosticsRedactor.redact("key sk-abcdefghijklmnop1234 and token=abc123def Authorization: Bearer abcdefghijkl1234 at /Users/x", home: "/Users/x")
        #expect(!text.contains("sk-abc") && !text.contains("abc123def") && !text.contains("abcdefghijkl1234"))
        #expect(text.contains("~"))
        let recorder = FlightRecorder(capacity: 2)
        recorder.record("error", "x", "password=hunter2")
        #expect(!recorder.text().contains("hunter2"))
        let settings = DiagnosticsRedactor.redactSettings(["ai.openai.key": "sk-zzzzzzzzzzzzzzzz", "notch.openDelay": "Fast"]) as? [String: Any]
        #expect(settings?["ai.openai.key"] as? String == DiagnosticsRedactor.mask)
        #expect(settings?["notch.openDelay"] as? String == "Fast")
    }

    @Test func exportManifestListsTheFiles() throws {
        let recorder = FlightRecorder(capacity: 10)
        recorder.record("voice", "listen", "started")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("voice.log")
        try "2026 listen token=SECRETVALUE1".write(to: log, atomically: true, encoding: .utf8)
        let settings = Data(#"{"options":{"x.apiKey":"abc","a":"b"}}"#.utf8)
        let zip = try DiagnosticsExporter.export(.init(version: "1.2", build: "9", settingsJSON: settings, logFiles: [log], recorder: recorder), to: dir)
        #expect(zip.lastPathComponent.hasPrefix("Zeus-diagnostics-") && zip.pathExtension == "zip")
        let staged = dir.appendingPathComponent("staged")
        let manifest = try DiagnosticsExporter.stage(.init(version: "1.2", build: "9", settingsJSON: settings, logFiles: [log], recorder: recorder), in: staged)
        #expect(manifest.files.map(\.path) == ["logs/flight-recorder.log", "logs/voice.log", "settings.json", "version.txt"])
        #expect(manifest.version == "1.2" && manifest.secretsRedacted && manifest.eventCount == 1)
        let settingsText = try String(contentsOf: staged.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(!settingsText.contains("\"abc\""))
        #expect(!(try String(contentsOf: staged.appendingPathComponent("logs/voice.log"), encoding: .utf8)).contains("SECRETVALUE1"))
    }
}

@Suite struct TaskPolishTests {
    let cal = Calendar(identifier: .gregorian)
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 14, minute: 7))! } // a Wednesday

    @Test func reminderFilters() {
        let yesterday = now.addingTimeInterval(-86400), later = now.addingTimeInterval(3600), nextWeek = now.addingTimeInterval(7 * 86400)
        #expect(ReminderFilter.today.includes(due: yesterday, flagged: false, now: now))
        #expect(ReminderFilter.today.includes(due: later, flagged: false, now: now))
        #expect(!ReminderFilter.today.includes(due: nextWeek, flagged: false, now: now))
        #expect(!ReminderFilter.today.includes(due: nil, flagged: false, now: now))
        #expect(ReminderFilter.scheduled.includes(due: nextWeek, flagged: false, now: now))
        #expect(!ReminderFilter.scheduled.includes(due: nil, flagged: true, now: now))
        #expect(ReminderFilter.all.includes(due: nil, flagged: false, now: now))
        #expect(ReminderFilter.flagged.includes(due: nil, flagged: true, now: now))
        #expect(!ReminderFilter.flagged.includes(due: later, flagged: false, now: now))
    }

    @Test func quickDueTimes() {
        func parts(_ d: Date) -> (Int, Int, Int, Int) {
            let c = cal.dateComponents([.day, .hour, .minute, .weekday], from: d); return (c.day!, c.hour!, c.minute!, c.weekday!)
        }
        #expect(parts(ReminderQuickDue.thisEvening.date(now: now, calendar: cal)) == (4, 18, 0, 4))
        #expect(parts(ReminderQuickDue.tomorrowMorning.date(now: now, calendar: cal)) == (5, 9, 0, 5))
        #expect(parts(ReminderQuickDue.nextWeek.date(now: now, calendar: cal)) == (9, 9, 0, 2)) // Monday
        let hour = ReminderQuickDue.inAnHour.date(now: now, calendar: cal)
        #expect(parts(hour).1 == 15 && parts(hour).2 == 15)
    }

    @Test func draftTimes() {
        let a = ReminderDraft.parse("pay rent friday at 5pm", now: now, calendar: cal)
        #expect(a.title == "pay rent" && a.hasTime)
        #expect(cal.component(.hour, from: a.due!) == 17 && cal.component(.weekday, from: a.due!) == 6)
        let b = ReminderDraft.parse("call Ana at 9:30", now: now, calendar: cal) // already past today, so tomorrow
        #expect(b.title == "call Ana" && cal.component(.day, from: b.due!) == 5 && cal.component(.minute, from: b.due!) == 30)
        #expect(ReminderDraft.parse("buy 2", now: now, calendar: cal).due == nil)
        #expect(!ReminderDraft.parse("water plants tomorrow", now: now, calendar: cal).hasTime)
    }

    @Test func timerDragMathAndExtend() {
        #expect(FocusDial.fraction(dx: 0, dy: -10) == 0)
        #expect(abs(FocusDial.fraction(dx: 10, dy: 0) - 0.25) < 1e-9)
        #expect(abs(FocusDial.fraction(dx: 0, dy: 10) - 0.5) < 1e-9)
        #expect(abs(FocusDial.fraction(dx: -10, dy: 0) - 0.75) < 1e-9)
        #expect(FocusDial.minutes(fraction: 0.5) == 30)
        #expect(FocusDial.minutes(fraction: 0.26) == 15)
        #expect(FocusDial.minutes(fraction: 0.001, previous: 10) == 5)
        #expect(FocusDial.minutes(fraction: 0.999, previous: 55) == 60)
        #expect(FocusDial.minutes(fraction: 0.0, previous: 55) == 60)
        var timer = FocusTimer(focusLength: 25 * 60)
        timer.setTime(minutes: 40); #expect(timer.focusLength == 2400)
        timer.extend(); #expect(timer.focusLength == 2700)
        let t0 = Date(timeIntervalSince1970: 0)
        timer.start(at: t0)
        timer.extend(at: t0)
        #expect(timer.remaining(at: t0) == 3000 && timer.phaseLength == 3000)
        timer.setTime(minutes: 10, at: t0)
        #expect(timer.remaining(at: t0) == 600)
        let data = try! JSONEncoder().encode(timer)
        #expect(try! JSONDecoder().decode(FocusTimer.self, from: data).phase == .focus)
    }

    @Test func clipboardKinds() {
        var history = ClipboardHistory()
        history.add("hello"); history.add("https://a.com")
        history.addImage(file: "abc.png", width: 10, height: 20)
        history.addFiles(["/tmp/a.pdf", "/tmp/b.png"])
        let kinds = history.entries.map(\.kind)
        #expect(kinds == [.file, .image, .link, .text])
        #expect(history.entries[1].text == "Image 10 \u{00D7} 20")
        #expect(history.entries[0].text == "a.pdf, b.png")
        history.addImage(file: "abc.png", width: 10, height: 20)
        #expect(history.entries.count == 4 && history.entries[0].kind == .image)
        #expect(history.imageFilesInUse == ["abc.png"])
        #expect(ClipboardFilter.images.includes(history.entries[0]) && !ClipboardFilter.text.includes(history.entries[0]))
        #expect(ClipboardFilter.files.includes(history.entries[1]) && ClipboardFilter.links.includes(history.entries[2]))
    }

    @Test func quitPeek() {
        let peek = ShortcutPeek.lookup("q", shift: false)
        #expect(peek?.title == "Quit" && peek?.key == "⌘Q" && peek?.motion == .quit)
        let seg = NotchLightMath.segments(.shortcut(.quit), progress: 0.5, shoulder: 0.3)
        #expect(seg.count == 1 && seg[0].to < 1)
    }
}

@Suite struct WelcomeBackTests {
    let t0 = Date(timeIntervalSince1970: 10_000)
    func ev(_ kind: RecapEvent.Kind, _ id: String, at offset: Double) -> RecapEvent {
        RecapEvent(kind: kind, id: id, agent: "Claude Code", project: id, date: t0.addingTimeInterval(offset))
    }

    @Test func awayTrackerNeedsTenMinutes() {
        var tracker = AwayTracker()
        #expect(tracker.update(idle: 0, now: t0) == nil)
        #expect(tracker.update(idle: 300, now: t0.addingTimeInterval(300)) == nil)
        // input at +400: 6.7 minutes away, too short
        #expect(tracker.update(idle: 1, now: t0.addingTimeInterval(400)) == nil)
        var other = AwayTracker()
        _ = other.update(idle: 0, now: t0)
        _ = other.update(idle: 650, now: t0.addingTimeInterval(650))
        let back = other.update(idle: 2, now: t0.addingTimeInterval(700))
        #expect(back != nil && back!.awaySeconds >= 600 && back!.awayStart == t0)
        // a sleep: idle restarts small after a long gap
        var sleeper = AwayTracker()
        _ = sleeper.update(idle: 5, now: t0)
        #expect(sleeper.update(idle: 1, now: t0.addingTimeInterval(3600)) != nil)
    }

    @Test func recapGatingOnlyEventsSinceAway() {
        let away = t0.addingTimeInterval(100)
        let events = [ev(.finished, "old", at: 50), ev(.finished, "a", at: 200), ev(.failed, "b", at: 300),
                      ev(.waiting, "c", at: 400), ev(.waiting, "d", at: 500)]
        let recap = WelcomeRecap.make(events: events, awayStart: away, awaySeconds: 900, stillWaiting: ["c"])
        #expect(recap?.finished.map(\.id) == ["a"])
        #expect(recap?.failed.map(\.id) == ["b"])
        #expect(recap?.waiting.map(\.id) == ["c"]) // d was answered
        #expect(recap?.summary == "1 finished, 1 failed, 1 waiting for you")
        #expect(WelcomeRecap.make(events: events, awayStart: away, awaySeconds: 599, stillWaiting: ["c"]) == nil)
        #expect(WelcomeRecap.make(events: [ev(.finished, "old", at: 50)], awayStart: away, awaySeconds: 900, stillWaiting: []) == nil)
        // the latest event for a session wins
        let retried = WelcomeRecap.make(events: [ev(.failed, "x", at: 200), ev(.finished, "x", at: 300)], awayStart: away, awaySeconds: 900, stillWaiting: [])
        #expect(retried?.failed.isEmpty == true && retried?.finished.count == 1)
    }

    @Test func logTurnsTransitionsIntoEvents() {
        var log = RecapLog()
        func s(_ status: AgentRunState) -> [RecapSession] { [RecapSession(id: "s", agent: "Codex", project: "p", status: status)] }
        log.observe(sessions: s(.working), approval: nil, now: t0)
        log.observe(sessions: s(.working), approval: nil, now: t0.addingTimeInterval(1))
        log.observe(sessions: s(.done), approval: nil, now: t0.addingTimeInterval(2))
        log.observe(sessions: s(.done), approval: nil, now: t0.addingTimeInterval(3))
        log.observe(sessions: s(.done), approval: (id: "ap", session: nil, agent: "Claude", project: "q", tool: "Bash"), now: t0.addingTimeInterval(4))
        #expect(log.events.map(\.kind) == [.finished, .waiting])
        #expect(RecapLog.waitingNow(sessions: s(.needsYou), approvalID: "ap") == ["s", "ap"])
    }
}

@Suite struct SoundParityTests {
    @Test func everyReferenceEventHasAZeusSound() {
        #expect(SoundParity.entries.count == 15)
        for entry in SoundParity.entries {
            let spec = SoundCatalog.spec(entry.slot, style: entry.style)
            #expect(spec?.style == entry.style, "\(entry.reference)")
            #expect(spec.map { abs($0.seconds - entry.seconds) < 0.01 } == true, "\(entry.reference) length")
        }
        for slot in SoundParity.zeusExtras { #expect(!SoundCatalog.styles(for: slot).isEmpty) }
    }
}
