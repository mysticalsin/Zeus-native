import AppKit
import ZeusCore

/// `Zeus --ask "question"`: one brain turn from the command line (with screenshots if Screen
/// Recording is granted), printing tags and text. Exercises the same path as a voice turn.
@MainActor
enum DebugCommands {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        // `ZEUS_CLAUDE_SETTINGS=copy.json Zeus --install-hooks` (or --uninstall-hooks)
        if arguments.contains("--install-hooks") || arguments.contains("--uninstall-hooks") {
            do {
                if arguments.contains("--install-hooks") {
                    let backup = try ClaudeHookInstaller.install()
                    print("installed into \(ClaudeHookInstaller.settingsURL.path); backup \(backup?.lastPathComponent ?? "none")")
                } else {
                    try ClaudeHookInstaller.uninstall()
                    print("uninstalled from \(ClaudeHookInstaller.settingsURL.path)")
                }
                exit(0)
            } catch {
                print("ERROR \(error.localizedDescription)")
                exit(1)
            }
        }
        // `Zeus --browseruse-smoke [url]`: starts the separate browser (browser-use over MCP), opens the
        // page, reads its state and prints the title and numbered elements. No AI is involved; set
        // ZEUS_BROWSERUSE_HEADLESS=1 to keep the window hidden.
        if let flag = arguments.firstIndex(of: "--browseruse-smoke") {
            let address = flag + 1 < arguments.count && !arguments[flag + 1].hasPrefix("--") ? arguments[flag + 1] : "https://example.com"
            Task { @MainActor in
                exit(await BrowserUseSmoke.run(url: address))
            }
            RunLoop.main.run()
        }
        // `Zeus --codex-replay rollout.jsonl`: what the Codex watcher would show for a log.
        if let flag = arguments.firstIndex(of: "--codex-replay"), flag + 1 < arguments.count,
           let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[flag + 1])) {
            var watch = CodexRolloutWatch()
            JSONLines.forEach(data, markers: ["\"session_meta\"", "\"user_message\"", "\"UserMessage\"", "\"task_complete\"",
                                              "\"function_call\"", "\"custom_tool_call\""], prefixLimit: 320) { line in
                if let change = watch.apply(line: line) { print(String(describing: change).prefix(140)) }
            }
            exit(0)
        }
        // `Zeus --tty`: the terminal device the agent hook would report from here.
        if arguments.contains("--tty") {
            print(ControllingTTY.find(startingAt: getpid()) ?? "no terminal")
            exit(0)
        }
        // `Zeus --microphones`: the inputs Settings › Dictation lists.
        if arguments.contains("--microphones") {
            for device in Microphones.all() { print("\(device.isDefault ? "*" : " ") \(device.name)  [\(device.uid)]") }
            exit(0)
        }
        // `Zeus --transcribe file.wav [engine]`: one file through the local dictation engines (never
        // a cloud one: this is for benchmarks and checks, and must not send audio anywhere).
        if let flag = arguments.firstIndex(of: "--transcribe"), flag + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[flag + 1])
            let preferred = (flag + 2 < arguments.count ? TranscriptionEngineKind(rawValue: arguments[flag + 2]) : nil) ?? .parakeet
            Task {
                do {
                    let samples = try AudioSamples.load(url)
                    let router = TranscriptionRouter(engines: [ParakeetEngine(), ParakeetEngine(.parakeetUltra), WhisperKitEngine(),
                                                               WhisperCppEngine(), AppleAnalyzerEngine(), AppleSpeechEngine(), FasterWhisperEngine()])
                    for (kind, state) in await router.availability().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                        print("\(kind.rawValue): \(state)")
                    }
                    let hints = DictationVocabularyPrompt.terms(Vocabulary())
                    let result = try await router.transcribe(samples: samples, preferred: preferred, hints: hints)
                    print("\(result.engine.rawValue) \(result.latencyMs) ms: \(result.text)")
                    exit(0)
                } catch {
                    print("ERROR \(error.localizedDescription)")
                    exit(1)
                }
            }
            return true
        }
        // `Zeus --voice-selftest file.wav [--transcript "..."] [--speak]`: the wake word and turn stages, offline.
        if VoiceSelfTest.runIfRequested(arguments) { return true }
        if let flag = arguments.firstIndex(of: "--chrome"), flag + 1 < arguments.count {
            #if DEBUG
            runChrome(type: arguments[flag + 1], json: flag + 2 < arguments.count ? arguments[flag + 2] : "{}")
            return true
            #else
            // The raw browser bridge bypasses CommandCenter authorization; debug builds only.
            print("--chrome is not available in this build")
            exit(1)
            #endif
        }
        guard let flag = arguments.firstIndex(of: "--ask"), flag + 1 < arguments.count else { return false }
        #if DEBUG
        let question = arguments[flag + 1]
        Task { @MainActor in
            let started = Date()
            let shots = await ScreenCapture.captureAll()
            print("screens: \(shots.count) \(shots.map(\.label))")
            let request = BrainRequest(transcript: question, screenshots: shots,
                                       axSummary: NSWorkspace.shared.frontmostApplication?.localizedName,
                                       systemPrompt: ZeusPrompt.system)
            var parser = ZeusTagStreamParser()
            var splitter = SentenceSplitter()
            var first: TimeInterval?
            do {
                for try await event in ClaudeCLIProvider().send(request) {
                    guard case .textDelta(let delta) = event else { continue }
                    for output in parser.feed(delta) {
                        if first == nil { first = Date().timeIntervalSince(started) }
                        switch output {
                        case .tag(let tag): print("TAG \(tag)")
                        case .text(let text): splitter.feed(text).forEach { print("SAY \($0)") }
                        }
                    }
                }
                for output in parser.finish() {
                    if case .tag(let tag) = output { print("TAG \(tag)") }
                    if case .text(let text) = output { splitter.feed(text).forEach { print("SAY \($0)") } }
                }
                if let rest = splitter.flush() { print("SAY \(rest)") }
                print(String(format: "first output %.2f s, total %.2f s", first ?? -1, Date().timeIntervalSince(started)))
                exit(0)
            } catch {
                print("ERROR \(error.localizedDescription)")
                print("SPOKEN \(VoiceTurnController.spokenError(error))")
                exit(1)
            }
        }
        return true
        #else
        // Screen capture plus assistant submission is a debug-only diagnostic; release builds refuse it.
        print("--ask is not available in this build")
        exit(1)
        #endif
    }

    /// `Zeus --chrome page.context '{"limit":500}'`: one raw request through the Chrome bridge.
    #if DEBUG
    static func runChrome(type: String, json: String) {
        Task { @MainActor in
            let params: [String: JSONValue]
            if let data = json.data(using: .utf8),
               case .object(let object)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
                params = object
            } else {
                params = [:]
            }
            do {
                let result = try await ChromeBridge.call(type, params, timeout: 40)
                let data = try JSONEncoder().encode(result ?? .null)
                print(String(decoding: data, as: UTF8.self))
                exit(0)
            } catch {
                print("ERROR \(error.localizedDescription)")
                exit(1)
            }
        }
    }
    #endif
}
