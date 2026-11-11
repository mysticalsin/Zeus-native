import Foundation
import Testing
@testable import ZeusCore

@Suite struct FastIntentTests {
    private func parse(_ text: String) -> FastIntent? { FastIntent.parse(text) }

    /// The app an utterance opens, ignoring the website fallback.
    private func opens(_ text: String) -> String? {
        if case .openApp(let name, _) = parse(text) { return name }
        return nil
    }

    // MARK: Apps

    @Test func opensAppsInManyPhrasings() {
        for phrase in ["open Spotify", "Open Spotify.", "hey zeus open spotify", "Hey Zeus, open Spotify please",
                       "can you open spotify", "could you please open Spotify for me", "launch spotify", "start Spotify",
                       "go to Spotify", "switch to spotify", "bring up Spotify", "fire up spotify", "open the Spotify app",
                       "um, open Spotify now", "Okay Zeus open Spotify", "just open spotify thanks"] {
            #expect(opens(phrase)?.lowercased() == "spotify", "\(phrase)")
        }
        #expect(parse("launch VS Code") == .openApp("VS Code", website: nil))
        #expect(parse("open visual studio code") == .openApp("visual studio code", website: nil))
        #expect(opens("go to Slack") == "Slack")
        #expect(parse("open Spotify") == .openApp("Spotify", website: URL(string: "https://open.spotify.com")))
        #expect(parse("switch to Google Chrome") == .openApp("Google Chrome", website: nil))
    }

    @Test func quitsAndHidesApps() {
        #expect(parse("quit Slack") == .quitApp("Slack"))
        #expect(parse("close Spotify please") == .quitApp("Spotify"))
        #expect(parse("hey zeus exit Xcode") == .quitApp("Xcode"))
        #expect(parse("hide Slack") == .hideApp("Slack"))
        #expect(parse("hide the Music app") == .hideApp("Music"))
    }

    // MARK: Spotify and media

    @Test func playsOnSpotify() {
        #expect(parse("open Spotify and play Daft Punk") == .playOnSpotify("Daft Punk"))
        #expect(parse("play Daft Punk on Spotify") == .playOnSpotify("Daft Punk"))
        #expect(parse("Hey Zeus, play Bohemian Rhapsody on Spotify.") == .playOnSpotify("Bohemian Rhapsody"))
        #expect(parse("play some jazz on spotify") == .playOnSpotify("jazz"))
        #expect(parse("put on lofi beats on Spotify") == .playOnSpotify("lofi beats"))
        #expect(parse("launch spotify and play my discover weekly") == .playOnSpotify("my discover weekly"))
        #expect(parse("spotify play Radiohead") == .playOnSpotify("Radiohead"))
        #expect(parse("open spotify and play") == .playOnSpotify(""))
        #expect(parse("play music on spotify") == .playOnSpotify(""))
    }

    @Test func mediaControls() {
        #expect(parse("pause") == .media(.pause))
        #expect(parse("pause the music") == .media(.pause))
        #expect(parse("stop the music please") == .media(.pause))
        #expect(parse("play") == .media(.play))
        #expect(parse("play some music") == .media(.play))
        #expect(parse("put on some music") == .media(.play))
        #expect(parse("play a song") == .media(.play))
        #expect(parse("play something") == .media(.play))
        #expect(parse("play some tunes") == .media(.play))
        #expect(parse("start playing music") == .media(.play))
        #expect(parse("queue up some music") == .media(.play))
        #expect(parse("resume") == .media(.play))
        #expect(parse("next song") == .media(.next))
        #expect(parse("skip this track") == .media(.next))
        #expect(parse("Next.") == .media(.next))
        #expect(parse("previous track") == .media(.previous))
        #expect(parse("go back a song") == .media(.previous))
    }

    // MARK: Volume

    @Test func volume() {
        #expect(parse("volume up") == .volume(.up))
        #expect(parse("turn it up") == .volume(.up))
        #expect(parse("louder please") == .volume(.up))
        #expect(parse("turn the volume down") == .volume(.down))
        #expect(parse("quieter") == .volume(.down))
        #expect(parse("mute") == .volume(.mute))
        #expect(parse("unmute") == .volume(.unmute))
        #expect(parse("set the volume to 30%") == .volume(.set(30)))
        #expect(parse("set volume to 45 percent") == .volume(.set(45)))
        #expect(parse("volume 70") == .volume(.set(70)))
        #expect(parse("set the volume to fifty") == .volume(.set(50)))
        #expect(parse("set the volume to twenty five percent") == .volume(.set(25)))
        #expect(parse("set the volume to 150") == nil)
    }

    // MARK: To-dos

    @Test func todos() {
        #expect(parse("add buy milk tomorrow to my to-do") == .addTodos(["buy milk tomorrow"]))
        #expect(parse("add a to-do: buy milk") == .addTodos(["buy milk"]))
        #expect(parse("Hey Zeus, add buy milk tomorrow to my to-do list.") == .addTodos(["buy milk tomorrow"]))
        #expect(parse("add call Ana to my to do list") == .addTodos(["call Ana"]))
        #expect(parse("add book the dentist to my todos") == .addTodos(["book the dentist"]))
        #expect(parse("remind me to call Mom on Friday") == .addTodos(["call Mom on Friday"]))
        #expect(parse("to-do: renew passport") == .addTodos(["renew passport"]))
        #expect(parse("todo send the invoice") == .addTodos(["send the invoice"]))
        #expect(parse("new task water the plants") == .addTodos(["water the plants"]))
        #expect(parse("add rock and roll lessons to my list") == .addTodos(["rock and roll lessons"]))
        #expect(parse("add call Ana, book the dentist to my to-do list") == .addTodos(["call Ana", "book the dentist"]))
    }

    // MARK: Links, lock, timer

    @Test func websites() {
        #expect(parse("open github.com") == .openURL(URL(string: "https://github.com")!))
        #expect(parse("go to news.ycombinator.com") == .openURL(URL(string: "https://news.ycombinator.com")!))
        #expect(parse("open https://example.org/docs") == .openURL(URL(string: "https://example.org/docs")!))
        #expect(parse("open github dot com") == .openURL(URL(string: "https://github.com")!))
        #expect(parse("open Gmail") == .openURL(URL(string: "https://mail.google.com")!))
        #expect(parse("open YouTube") == .openApp("YouTube", website: URL(string: "https://www.youtube.com")!))
    }

    @Test func lockScreen() {
        for phrase in ["lock the screen", "lock my Mac", "Hey Zeus lock screen", "lock my computer please"] {
            #expect(parse(phrase) == .lockScreen, "\(phrase)")
        }
    }

    @Test func polyglotCommands() {
        for phrase in ["translate", "Hey Zeus, translate", "start Polyglot", "start live translation", "traduz ao vivo"] {
            #expect(parse(phrase) == .polyglot(start: true), "\(phrase)")
        }
        for phrase in ["stop polyglot", "stop translating", "Hey Zeus stop live translation"] {
            #expect(parse(phrase) == .polyglot(start: false), "\(phrase)")
        }
        #expect(FastIntent.polyglot(start: true).intentLabel == "polyglot.toggle")
    }

    @Test func timers() {
        #expect(parse("set a timer for 5 minutes") == .timer(seconds: 300))
        #expect(parse("start a timer for ten minutes") == .timer(seconds: 600))
        #expect(parse("timer for 90 seconds") == .timer(seconds: 90))
        #expect(parse("set a 25 minute timer") == .timer(seconds: 1500))
        #expect(parse("a five minute timer") == .timer(seconds: 300))
        #expect(parse("set a timer for an hour") == .timer(seconds: 3600))
        #expect(parse("set a timer for half an hour") == .timer(seconds: 1800))
        #expect(parse("set a timer for 1 hour 30 minutes") == .timer(seconds: 5400))
        #expect(parse("timer 10 min") == .timer(seconds: 600))
        #expect(parse("set a timer for twenty five minutes") == .timer(seconds: 1500))
        #expect(parse("set a timer for 3 days") == nil)
        #expect(parse("cancel the timer") == .cancelTimer)
        #expect(parse("stop timer") == .cancelTimer)
        #expect(FastIntent.fromEngine(label: "timer.cancel", utterance: "cancel the timer") == .cancelTimer)
    }

    // MARK: French and Portuguese

    @Test func french() {
        #expect(opens("ouvre Spotify") == "Spotify")
        #expect(opens("lance Slack s'il te plaît") == "Slack")
        #expect(parse("ferme Slack") == .quitApp("Slack"))
        #expect(parse("joue Daft Punk sur Spotify") == .playOnSpotify("Daft Punk"))
        #expect(parse("ouvre Spotify et mets Stromae") == .playOnSpotify("Stromae"))
        #expect(parse("chanson suivante") == .media(.next))
        #expect(parse("mets en pause") == .media(.pause))
        #expect(parse("monte le son") == .volume(.up))
        #expect(parse("coupe le son") == .volume(.mute))
        #expect(parse("mets le volume à 40") == .volume(.set(40)))
        #expect(parse("verrouille l'écran") == .lockScreen)
        #expect(parse("mets un minuteur de 5 minutes") == .timer(seconds: 300))
        #expect(parse("ajoute acheter du pain demain à ma liste") == .addTodos(["acheter du pain tomorrow"]))
        #expect(parse("rappelle-moi d'appeler Ana") == .addTodos(["appeler Ana"]))
    }

    @Test func portuguese() {
        #expect(opens("abre o Spotify") == "Spotify")
        #expect(opens("abra o WhatsApp por favor") == "WhatsApp")
        #expect(opens("abre o Finder") == "Finder")
        #expect(parse("fecha o Slack") == .quitApp("Slack"))
        #expect(parse("toca Anitta no Spotify") == .playOnSpotify("Anitta"))
        #expect(parse("abre o Spotify e toca Jorge Ben") == .playOnSpotify("Jorge Ben"))
        #expect(parse("próxima música") == .media(.next))
        #expect(parse("pausa") == .media(.pause))
        #expect(parse("aumenta o volume") == .volume(.up))
        #expect(parse("coloca o volume em 20") == .volume(.set(20)))
        #expect(parse("bloqueia a tela") == .lockScreen)
        #expect(parse("coloca um timer de 10 minutos") == .timer(seconds: 600))
        #expect(parse("adiciona comprar leite amanhã na minha lista") == .addTodos(["comprar leite tomorrow"]))
        #expect(parse("me lembra de ligar para a Ana") == .addTodos(["ligar para a Ana"]))
    }

    // MARK: Fall through to the LLM

    @Test func ambiguousOrCompoundFallsThrough() {
        for phrase in [
            "what's the weather tomorrow", "close this tab", "close the window",
            "open the file I downloaded yesterday", "open Spotify and then tell me the weather", "open Slack and Mail",
            "play something relaxing and dim the lights", "quit everything", "write an email to Ana", "how do I open Spotify",
            "tell me a joke", "stop", "open it", "what's playing", "remind me in 10 minutes to stretch",
            "play jazz", "summarize this page", "go to sleep", "add it to my list", "", "hey zeus",
            "can you explain how timers work", "open spotify, then slack",
        ] {
            #expect(parse(phrase) == nil, "\(phrase) should go to the LLM, got \(String(describing: parse(phrase)))")
        }
    }

    // MARK: Engine answers (Laya / Jev labels → actions)

    @Test func engineLabelsBecomeActions() {
        #expect(FastIntent.fromEngine(label: "app.open", utterance: "I need Figma up") == .openApp("Figma", website: URL(string: "https://www.figma.com")))
        #expect(FastIntent.fromEngine(label: "app.open", utterance: "get me Xcode") == .openApp("Xcode", website: nil))
        #expect(FastIntent.fromEngine(label: "media.play", utterance: "put on some Miles Davis") == .playOnSpotify("Miles Davis"))
        #expect(FastIntent.fromEngine(label: "media.play", utterance: "skip that one") == .media(.next))
        #expect(FastIntent.fromEngine(label: "system.volume", utterance: "it's way too loud, bring it down") == .volume(.down))
        #expect(FastIntent.fromEngine(label: "timer.start", utterance: "wake me in 20 minutes") == .timer(seconds: 1200))
        #expect(FastIntent.fromEngine(label: "todo.add", utterance: "add pay rent") == .addTodos(["pay rent"]))
        #expect(FastIntent.fromEngine(label: "browser.open", utterance: "pull up reddit") == .openURL(URL(string: "https://www.reddit.com")!))
        #expect(FastIntent.fromEngine(label: "chat.answer", utterance: "open Spotify") == nil)
        #expect(FastIntent.fromEngine(label: "clarify", utterance: "do the thing") == nil)
        #expect(FastIntent.fromEngine(label: "system.volume", utterance: "the volume") == nil)
    }

    @Test func rulesDecisionCarriesTheLabel() {
        let decision = FastIntent.openApp("Slack", website: nil).decision
        #expect(decision.source == .rules)
        #expect(decision.answers["intent"]?.choice == "app.open")
        #expect(decision.confidence == 1)
    }

    @Test func engineGateSkipsQuestionsAndLongRequests() {
        #expect(FastIntent.mayBeCommand("I need Figma up"))
        #expect(FastIntent.mayBeCommand("hey zeus put on some Miles Davis"))
        #expect(!FastIntent.mayBeCommand("what's the weather"))
        #expect(!FastIntent.mayBeCommand("is it going to rain?"))
        #expect(!FastIntent.mayBeCommand("explain quantum computing"))
        #expect(!FastIntent.mayBeCommand("please write a long email to the whole team about the launch plan and the budget and the dates"))
        #expect(FastIntent.key("Hey Zeus, open Spotify please") == FastIntent.key("open spotify"))
    }

    // MARK: Speed

    @Test func parserStaysUnderTwoMillisecondsPerUtterance() {
        let phrases = [
            "Hey Zeus, open Spotify and play Daft Punk please", "add buy milk tomorrow to my to-do list", "set a timer for 25 minutes",
            "what's the weather like in Rio tomorrow afternoon", "open my zeus repo in Finder and show me the README",
            "abre o Spotify e toca Jorge Ben", "mets le volume à 40", "lock my Mac", "go to github.com",
            "could you please summarize the last three emails from Ana about the launch and draft a reply",
        ]
        _ = phrases.map(FastIntent.parse)   // warm the static tables
        let rounds = 50
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<rounds { for phrase in phrases { _ = FastIntent.parse(phrase) } }
        }
        let perUtterance = Double(elapsed.components.attoseconds) / 1e15 / Double(rounds * phrases.count)
            + Double(elapsed.components.seconds) * 1000 / Double(rounds * phrases.count)
        print("[fast] parse: \(String(format: "%.3f", perUtterance)) ms per utterance (debug build)")
        #expect(perUtterance < 2.0)
    }
}

@Suite struct WakePhraseTests {
    @Test func spotsTheWakePhraseAndKeepsTheRequest() {
        #expect(WakePhrase.spot("Hey Zeus open Spotify")?.request == "open Spotify")
        #expect(WakePhrase.spot("Hey, Zeus. Add buy milk tomorrow to my to-do.")?.request == "Add buy milk tomorrow to my to-do")
        #expect(WakePhrase.spot("hey zeus")?.request == "")
        #expect(WakePhrase.spot("Okay Zeus, lock the screen")?.request == "lock the screen")
    }

    @Test func toleratesMishearings() {
        for heard in ["Hey zoos open Slack", "Hey Seuss open Slack", "hey Zeus's open Slack", "Heyzeus open Slack",
                      "hey zues open Slack", "Hi Zeus open Slack", "A Zeus open Slack", "Ei Zeus open Slack",
                      "Hey juice open Slack", "Hi zest open Slack", "hey deus open Slack"] {
            #expect(WakePhrase.spot(heard)?.request == "open Slack", "\(heard)")
        }
    }

    @Test func takesTheLastWakePhraseAndIgnoresChatter() {
        let match = WakePhrase.spot("so I was telling him hey zeus never mind hey Zeus pause")
        #expect(match?.request == "pause")
        #expect((match?.skippedWords ?? 0) > 0)
    }

    @Test func ignoresOrdinaryTalk() {
        for text in ["Zeus is a Greek god", "hey there", "I saw a zoo", "a zoo is open", "the house of Zeus", "Hey, can you hear me?",
                     "the juice is cold", "a zest of lemon", "the zeus pantheon",
                     "She said hey Jesus was her neighbor and they carpool on Tuesdays.",
                     "So I mentioned hey Zeus was only a myth"] {
            #expect(WakePhrase.spot(text) == nil, "\(text)")
        }
    }

    // Item 6, QA7: a second Zeus, or a headless recorder with no bundle ID, must never count as
    // "another app is using the microphone" -- only real calls should pause "Hey Zeus".
    @Test func micConflictIgnoresZeusAndUnidentifiedRecorders() {
        #expect(!MicConflict.counts(bundleID: "us.zoom.xos", pid: 100, ownPID: 100)) // own pid, regardless of bundle id
        #expect(!MicConflict.counts(bundleID: "app.zeus.dev", pid: 200, ownPID: 100)) // a second Zeus
        #expect(!MicConflict.counts(bundleID: "", pid: 300, ownPID: 100)) // ffmpeg/sox/QA tooling: no bundle id
        #expect(!MicConflict.counts(bundleID: "com.apple.universalaccessd", pid: 400, ownPID: 100)) // ordinary Apple daemon
    }

    @Test func micConflictCountsRealCalls() {
        #expect(MicConflict.counts(bundleID: "us.zoom.xos", pid: 500, ownPID: 100))
        #expect(MicConflict.counts(bundleID: "com.apple.FaceTime", pid: 600, ownPID: 100))
    }

    @Test func gateRules() {
        var gate = WakeGate()
        #expect(gate.pauseReason == "needs microphone and speech recognition")
        gate.micAllowed = true
        gate.speechAllowed = true
        #expect(gate.mayListen)
        gate.dictating = true
        #expect(gate.pauseReason == "dictation")
        gate.dictating = false
        gate.otherAppRecording = true
        #expect(!gate.mayListen)
        gate.otherAppRecording = false
        gate.screenLocked = true
        #expect(gate.pauseReason == "Mac locked")
        gate.enabled = false
        #expect(gate.pauseReason == "off")
    }

    @Test func voiceActivityOpensOnSpeechAndClosesAfterQuiet() {
        var vad = VoiceActivity()
        #expect(vad.attack == 2)
        for _ in 0..<40 { vad.feed(rms: 0.003, seconds: 0.085) }
        #expect(!vad.active)
        vad.feed(rms: 0.08, seconds: 0.085)
        #expect(!vad.active)            // one loud buffer is a click
        vad.feed(rms: 0.08, seconds: 0.085)
        #expect(vad.active)
        for _ in 0..<10 { vad.feed(rms: 0.003, seconds: 0.085) }
        #expect(vad.active)             // 0.85 s of quiet: still inside the hangover
        for _ in 0..<5 { vad.feed(rms: 0.003, seconds: 0.085) }
        #expect(!vad.active)
    }

    /// The per-buffer work the always-on tap does when nobody talks: RMS and the gate. A minute of
    /// 48 kHz audio in 4096-frame buffers should cost well under a millisecond per buffer.
    @Test func voiceActivityIsCheapPerBuffer() {
        var vad = VoiceActivity()
        let samples = (0..<4096).map { Float(sin(Double($0) * 0.01)) * 0.002 }
        let clock = ContinuousClock()
        let buffers = 60 * 48_000 / 4096
        let elapsed = clock.measure {
            for _ in 0..<buffers {
                var sum: Float = 0
                for s in samples { sum += s * s }
                vad.feed(rms: (sum / Float(samples.count)).squareRoot(), seconds: 4096 / 48_000)
            }
        }
        let perBuffer = (Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15) / Double(buffers)
        print("[fast] wake gate: \(String(format: "%.4f", perBuffer)) ms per 85 ms buffer (debug build, scalar RMS)")
        #expect(perBuffer < 1.0)
    }
}

@Suite struct AppMatcherTests {
    static let apps = [
        AppEntry(name: "Spotify", bundleID: "com.spotify.client"),
        AppEntry(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        AppEntry(name: "Google Chrome", bundleID: "com.google.Chrome"),
        AppEntry(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
        AppEntry(name: "System Settings", bundleID: "com.apple.systempreferences"),
        AppEntry(name: "FaceTime", bundleID: "com.apple.FaceTime"),
        AppEntry(name: "Photos", bundleID: "com.apple.Photos"),
        AppEntry(name: "Photo Booth", bundleID: "com.apple.PhotoBooth"),
        AppEntry(name: "Adobe Photoshop 2025", bundleID: "com.adobe.Photoshop"),
        AppEntry(name: "Motion", bundleID: "com.apple.motionapp"),
        AppEntry(name: "Xcode", bundleID: "com.apple.dt.Xcode"),
        AppEntry(name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp"),
    ]
    let matcher = AppMatcher(AppMatcherTests.apps)

    private func id(_ query: String) -> String? { matcher.confident(query)?.entry.bundleID }

    @Test func exactNamesAndAliases() {
        #expect(id("Spotify") == "com.spotify.client")
        #expect(id("vs code") == "com.microsoft.VSCode")
        #expect(id("VSCode") == "com.microsoft.VSCode")
        #expect(id("chrome") == "com.google.Chrome")
        #expect(id("settings") == "com.apple.systempreferences")
        #expect(id("system preferences") == "com.apple.systempreferences")
        #expect(id("face time") == "com.apple.FaceTime")
        #expect(id("photoshop") == "com.adobe.Photoshop")
        #expect(id("whats app") == "net.whatsapp.WhatsApp")
        #expect(id("xcode") == "com.apple.dt.Xcode")
    }

    @Test func prefixesInitialsAndMishearings() {
        #expect(id("visual studio") == "com.microsoft.VSCode")
        #expect(id("vsc") == "com.microsoft.VSCode")
        #expect(id("spotifi") == "com.spotify.client")
        #expect(id("slak") == nil || id("slak") == "com.tinyspeck.slackmacgap")
    }

    @Test func rejectsWhatIsNotThere() {
        #expect(id("notion") == nil)       // Motion is one letter off but short names must be near exact
        #expect(id("pod bay doors") == nil)
        #expect(id("sleep") == nil)
        #expect(id("the weather") == nil)
    }

    @Test func closeCallsAreAmbiguous() {
        let ranked = matcher.ranked("photo")
        #expect(ranked.count >= 2)
        #expect(AppMatcher.isAmbiguous(ranked))
        #expect(matcher.confident("photo") == nil)
        #expect(id("photos") == "com.apple.Photos")
    }

    @Test func editDistance() {
        #expect(AppMatcher.editDistance("kitten", "sitting") == 3)
        #expect(AppMatcher.editDistance("", "abc") == 3)
        #expect(AppMatcher.editDistance("same", "same") == 0)
    }
}

@Suite struct FastAckTests {
    @Test func neutralLines() {
        #expect(AckLines.neutral.line(.opening("Spotify")) == "Opening Spotify.")
        #expect(AckLines.neutral.line(.media(.play)) == "Playing.")
        #expect(AckLines.neutral.line(.media(.next)) == "Next track.")
        #expect(AckLines.neutral.line(.timer(seconds: 5400)) == "Timer set for 1 hour 30 minutes.")
        #expect(AckLines.spoken(45) == "45 seconds")
    }

    @Test func personaLinesNameTheThing() {
        let line = AckLines.persona(personality: .ultron).line(.opening("Spotify")) ?? ""
        #expect(!line.isEmpty)
        #expect(AckLines.persona(personality: .ultron).line(.volume(.up)) == nil)
        #expect(AckLines.persona(personality: .ultron).line(.timer(seconds: 300)) == "Timer set for 5 minutes.")
    }

    @Test func plainTimerEndsWithoutABreakAndRestoresFocusLength() {
        var timer = FocusTimer(focusLength: 1500, restLength: 300)
        let start = Date(timeIntervalSince1970: 1000)
        timer.startTimer(seconds: 60, at: start)
        #expect(timer.isPlainTimer)
        #expect(timer.remaining(at: start) == 60)
        #expect(timer.tick(at: start.addingTimeInterval(61)) == .focus)
        #expect(timer.phase == .idle)
        #expect(timer.focusLength == 1500)
        #expect(!timer.isPlainTimer)
    }
}
