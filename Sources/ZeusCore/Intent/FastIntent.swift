import Foundation

/// A command Zeus can carry out on the Mac at once, with no model call: the "local rules" stage
/// of the decision chain (rules → Jev, see `DecisionRouter`). `parse` is strict and pure
/// (no network, no model, well under 2 ms); anything ambiguous or compound returns nil so the
/// next stage (Jev, then the LLM brain) handles it. English first, with French and
/// Portuguese where it is cheap.
public enum FastIntent: Equatable, Sendable {
    public enum Media: String, Equatable, Sendable { case play, pause, toggle, next, previous }
    public enum Volume: Equatable, Sendable { case up, down, mute, unmute, set(Int) }

    /// Open or switch to an app. `website` is used when no such app is installed ("open YouTube").
    case openApp(String, website: URL?)
    case quitApp(String)
    case hideApp(String)
    /// Search Spotify and start the top result. Empty means just start Spotify playing.
    case playOnSpotify(String)
    case media(Media)
    case volume(Volume)
    /// One or more to-dos, as said, with any due words ("buy milk tomorrow").
    case addTodos([String])
    /// A calendar event, as said without the command: "lunch with Ana tomorrow at 1 pm" (`CalendarQuickAdd` reads the rest).
    case addEvent(String)
    case openURL(URL)
    case lockScreen
    case timer(seconds: Int)
    /// Stop a running focus/plain countdown ("cancel the timer").
    case cancelTimer
    /// A terminal window, in a project when one is named ("open a terminal in zeus").
    case openTerminal(project: String?)
    /// A project in an editor, Finder or a terminal ("open zeus in VS Code").
    case openProject(String, in: ProjectApp)
    /// A coding agent in a terminal, in a project, started on `task` ("fix the login bug in zeus").
    case codeAgent(tool: CodingTool?, project: String?, task: String)
    /// A web research turn ("research quantum batteries", "deep research ...").
    case research(topic: String, deep: Bool)
    /// Beamer: pause, resume, start, open its window, or send the keyboard to a machine.
    case beamer(BeamerCommand)
    /// Start or stop live translated captions ("Hey Zeus, translate", "start Polyglot").
    case polyglot(start: Bool)

    /// Where "open <project> in ..." opens it.
    public enum ProjectApp: String, Equatable, Sendable { case vscode, cursor, xcode, finder, terminal }

    /// The System One intent label this maps to (the `intent` question in `IntelligenceCenter`).
    public var intentLabel: String {
        switch self {
        case .openApp: "app.open"
        case .quitApp, .hideApp: "app.quit"
        case .playOnSpotify, .media: "media.play"
        case .volume: "system.volume"
        case .addTodos: "todo.add"
        case .addEvent: "calendar.add"
        case .openURL: "browser.open"
        case .lockScreen: "system.lock"
        case .timer: "timer.start"
        case .cancelTimer: "timer.cancel"
        case .openTerminal: "terminal.open"
        case .openProject: "project.open"
        case .codeAgent: "terminal.agent"
        case .research: "research"
        case .beamer: "beamer"
        case .polyglot: "polyglot.toggle"
        }
    }

    /// The labels a Jev decision may carry that Zeus can act on directly.
    public static let actionableLabels: Set<String> = ["app.open", "app.quit", "media.play", "system.volume", "timer.start", "timer.cancel", "todo.add", "browser.open"]

    /// Spoken English to-do adds that use a colon after the lead ("add a to-do: buy milk").
    private static func spokenTodoAdd(_ text: String) -> FastIntent? {
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        guard lower.hasPrefix("add a to-do") || lower.hasPrefix("add a todo") || lower.hasPrefix("add to-do") else { return nil }
        guard case .add(let items)? = TodoVoice.parse(text), !items.isEmpty else { return nil }
        return .addTodos(items)
    }

    /// Strict local rules. nil means "not sure": let the next stage decide.
    public static func parse(_ text: String) -> FastIntent? {
        if let intent = spokenTodoAdd(text) { return intent }
        var utterance = Utterance(text)
        utterance.stripFiller()
        // A coding task or a research topic can run long; everything else is a short command.
        guard !utterance.isEmpty, utterance.count <= (longFormLeads.contains(utterance.words[0]) ? 80 : 30) else { return nil }
        if let command = beamerCommand(utterance) { return .beamer(command) }
        if let (rule, slots) = codeRules.first(utterance.words) { return buildCode(rule: rule, slots: slots, in: utterance) }
        if let exact = exactPhrases[utterance.words.joined(separator: " ")] { return exact }
        guard let (rule, slots) = rules.first(utterance.words) else { return eventIntent(utterance) }
        return build(rule: rule, slots: slots, in: utterance)
    }

    /// The rules decision for the shared decision history and the notch badge ("Rules").
    public var decision: Decision {
        Decision(source: .rules, answers: ["intent": SystemOneAnswer(type: "choice", choice: intentLabel, confidence: 1)])
    }

    // MARK: Engine gate

    private static let questionWords: Set<String> = [
        "what", "who", "why", "how", "when", "where", "which", "whose", "is", "are", "was", "were", "do", "does", "did", "should",
        "explain", "tell", "describe", "summarize", "write", "draft", "translate", "compare",
        "quoi", "pourquoi", "comment", "quand", "ou", "qui", "quel", "quelle", "est-ce", "explique", "ecris",
        "que", "porque", "por", "como", "quando", "onde", "quem", "qual", "explica", "escreve",
    ]

    /// Whether an utterance the rules missed is worth a quick Jev look before the LLM: short,
    /// and not a question or a writing job (those are the LLM's anyway, so asking first only adds delay).
    public static func mayBeCommand(_ text: String) -> Bool {
        var utterance = Utterance(text)
        utterance.stripFiller()
        guard let first = utterance.words.first, (1...14).contains(utterance.count) else { return false }
        if text.trimmingCharacters(in: .whitespaces).hasSuffix("?") { return false }
        return !questionWords.contains(first)
    }

    /// The utterance with filler removed, for matching a speculative partial against the final transcript.
    public static func key(_ text: String) -> String {
        var utterance = Utterance(text)
        utterance.stripFiller()
        return utterance.words.joined(separator: " ")
    }

    // MARK: Engine answers (Jev, Ollama)

    /// Turns an engine's intent label into an action, reading the details (which app, how long,
    /// what to search) from the words. More forgiving than `parse` because the engine already
    /// said what kind of request this is; still nil when the details aren't there.
    public static func fromEngine(label: String, utterance text: String) -> FastIntent? {
        guard actionableLabels.contains(label) else { return nil }
        if let strict = parse(text), strict.intentLabel == label || (label == "app.quit" && strict.intentLabel == "app.quit") { return strict }
        var utterance = Utterance(text)
        utterance.stripFiller()
        let words = utterance.words
        guard !words.isEmpty, words.count <= 20 else { return nil }
        switch label {
        case "app.open":
            let rest = trimmedRange(words, dropping: openVerbs)
            guard let name = appName(rest, in: utterance) else { return nil }
            if let url = website(name) { return url.isPlainSite ? .openURL(url.url) : .openApp(name, website: url.url) }
            return .openApp(name, website: nil)
        case "app.quit":
            let hide = words.contains { ["hide", "masque", "cache", "esconde", "oculta", "minimiza"].contains($0) }
            let rest = trimmedRange(words, dropping: quitVerbs)
            guard let name = appName(rest, in: utterance) else { return nil }
            return hide ? .hideApp(name) : .quitApp(name)
        case "media.play":
            if let spotify = words.firstIndex(of: "spotify"), var play = words.firstIndex(where: { playVerbs.contains($0) }), play < words.count - 1 {
                if words[play + 1] == "on", play + 2 < words.count { play += 1 }
                var range = (play + 1)..<words.count
                if spotify > play { range = (play + 1)..<max(play + 1, spotify - (["on", "in", "sur", "no", "em", "with"].contains(words[spotify - 1]) ? 1 : 0)) }
                let query = cleanQuery(utterance.said(range))
                return .playOnSpotify(query)
            }
            if words.contains(where: { ["next", "skip", "suivant", "suivante", "proxima", "pula", "pular"].contains($0) }) { return .media(.next) }
            if words.contains(where: { ["previous", "back", "precedent", "precedente", "anterior", "volta"].contains($0) }) { return .media(.previous) }
            if words.contains(where: { ["pause", "stop", "pausa", "pausar", "para", "arrete"].contains($0) }) { return .media(.pause) }
            if var play = words.firstIndex(where: { playVerbs.contains($0) }), play < words.count - 1 {
                if words[play + 1] == "on", play + 2 < words.count { play += 1 }
                let query = cleanQuery(utterance.said((play + 1)..<words.count))
                if !genericMusic.contains(query.lowercased()) { return .playOnSpotify(query) }
            }
            return .media(.play)
        case "system.volume":
            if let value = number(in: words) { return .volume(.set(min(max(value, 0), 100))) }
            if words.contains(where: { ["unmute", "desmuta", "remets"].contains($0) }) { return .volume(.unmute) }
            if words.contains(where: { ["mute", "muta", "silencia", "coupe", "silence"].contains($0) }) { return .volume(.mute) }
            if words.contains(where: { ["up", "louder", "raise", "increase", "monte", "augmente", "aumenta", "sobe", "mais"].contains($0) }) { return .volume(.up) }
            if words.contains(where: { ["down", "quieter", "lower", "decrease", "baisse", "diminue", "abaixa", "diminui", "baixa", "menos"].contains($0) }) { return .volume(.down) }
            return nil
        case "timer.start":
            for start in words.indices {
                if let seconds = duration(Array(words[start...])) ?? duration(Array(words[start..<min(words.count, start + 2)])) {
                    return .timer(seconds: seconds)
                }
            }
            return nil
        case "timer.cancel":
            return .cancelTimer
        case "todo.add":
            var range = trimmedRange(words, dropping: todoLeads)
            for suffix in todoSuffixes where range.count > suffix.count && Array(words[range].suffix(suffix.count)) == suffix {
                range = range.lowerBound..<(range.upperBound - suffix.count)
            }
            guard !range.isEmpty else { return nil }
            return .addTodos(todoItems(utterance.source(range)))
        case "browser.open":
            for (index, word) in words.enumerated() {
                if let url = url(from: utterance, range: index..<(index + 1)) { return .openURL(url) }
                if let site = sites[word] { return .openURL(site) }
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: Rules

    private static let exactPhrases: [String: FastIntent] = {
        var map: [String: FastIntent] = [:]
        func add(_ phrases: [String], _ intent: FastIntent) {
            for phrase in phrases { map[Utterance(phrase).words.joined(separator: " ")] = intent }
        }
        add(["play", "resume", "unpause", "play music", "play some music", "resume music", "resume the music", "play the music", "continue the music",
             "resume playback", "start the music", "reprends la musique", "relance la musique", "remets la musique", "lecture",
             "continua a musica", "continue a musica", "retoma a musica", "toca a musica", "volta a tocar"], .media(.play))
        add(["pause", "pause it", "pause music", "pause the music", "pause the song", "pause playback", "stop the music", "stop music",
             "stop the song", "stop playing", "mets en pause", "mets la musique en pause", "arrete la musique", "pause la musique",
             "pausa", "pausar", "pausa a musica", "para a musica", "pare a musica", "pausa isso"], .media(.pause))
        add(["next", "next song", "next track", "skip", "skip it", "skip this", "skip song", "skip track", "skip this song", "skip this track",
             "skip the song", "play the next song", "go to the next song", "next one", "suivant", "chanson suivante", "morceau suivant",
             "piste suivante", "passe a la suivante", "proxima", "proxima musica", "proxima faixa", "pula", "pula a musica", "pular musica"], .media(.next))
        add(["previous", "previous song", "previous track", "last song", "go back a song", "go back one song", "play the previous song",
             "back one song", "precedent", "chanson precedente", "morceau precedent", "musica anterior", "faixa anterior", "volta a musica",
             "anterior"], .media(.previous))
        add(["volume up", "louder", "turn it up", "turn the volume up", "turn up the volume", "turn the sound up", "turn up the sound",
             "increase the volume", "increase volume", "raise the volume", "raise volume", "make it louder", "monte le son", "monte le volume",
             "augmente le son", "augmente le volume", "aumenta o volume", "aumente o volume", "aumenta o som", "sobe o volume", "sobe o som"], .volume(.up))
        add(["volume down", "quieter", "turn it down", "turn the volume down", "turn down the volume", "turn the sound down",
             "turn down the sound", "lower the volume", "lower volume", "decrease the volume", "decrease volume", "make it quieter",
             "baisse le son", "baisse le volume", "diminue le son", "diminue le volume", "abaixa o volume", "abaixe o volume",
             "diminui o volume", "abaixa o som", "baixa o volume"], .volume(.down))
        add(["mute", "mute it", "mute the sound", "mute the volume", "mute the audio", "mute sound", "mute volume", "mute the mac",
             "mute my mac", "coupe le son", "mets en sourdine", "muta", "silencia", "tira o som", "muta o som"], .volume(.mute))
        add(["unmute", "unmute it", "unmute the sound", "unmute sound", "unmute the mac", "remets le son", "desmuta", "volta o som"], .volume(.unmute))
        add(["lock", "lock screen", "lock the screen", "lock my screen", "lock the mac", "lock my mac", "lock the computer",
             "lock my computer", "lock my laptop", "lock the laptop", "lock it", "verrouille l'ecran", "verrouiller l'ecran", "verrouille le mac",
             "verrouille mon mac", "verrouille l'ordinateur", "bloqueia a tela", "bloquear a tela", "bloqueie a tela", "trava a tela",
             "travar a tela", "trave a tela", "bloqueia o mac", "trava o mac"], .lockScreen)
        add(["cancel the timer", "cancel timer", "stop the timer", "stop timer", "clear the timer", "clear timer", "delete the timer",
             "annule le minuteur", "annule le timer", "arrete le minuteur", "cancela o timer", "para o timer", "cancela o temporizador"],
            .cancelTimer)
        add(["translate", "translate this", "translate live", "translate for me", "live translate", "live translation", "live translate this",
             "start polyglot", "open polyglot", "polyglot", "start translating", "start the translation", "start live translation",
             "start live captions", "start captions", "traduis", "traduis en direct", "traduction en direct", "traduz", "traduz isso",
             "traduz ao vivo", "traduza ao vivo", "traduce", "traduce en vivo"], .polyglot(start: true))
        add(["stop polyglot", "stop translating", "stop the translation", "stop translation", "stop live translation", "stop translate",
             "stop live captions", "stop captions", "arrete la traduction", "para de traduzir", "pare de traduzir", "deja de traducir"],
            .polyglot(start: false))
        add(["open spotify and play", "open spotify and play music", "open spotify and play something", "launch spotify and play",
             "play spotify", "play some music on spotify", "play music on spotify", "play something on spotify", "resume spotify",
             "spotify play"], .playOnSpotify(""))
        return map
    }()

    private static let rules = TemplateSet([
        ("timer", [
            "(set|start|create|make|put|run) [a|an|the] (timer|countdown) (for|of|at) {dur}",
            "(set|start|create|make) [a|an] {dur} (timer|countdown)",
            "[a|an] (timer|countdown) (for|of) {dur}", "(timer|countdown) {dur}", "[a|an] {dur} (timer|countdown)",
            "(mets|lance|demarre|regle|programme) [un] (minuteur|timer|chrono) (de|pour|sur) {dur}",
            "(minuteur|timer) (de|pour) {dur}",
            "(coloca|poe|liga|inicia|cria|ativa|bota) [um|o] (timer|temporizador|cronometro|alarme) (de|para|por|em) {dur}",
            "(timer|temporizador|cronometro) (de|para) {dur}",
        ]),
        ("todo", [
            "(add|put) {todo} (to|on|onto|in) [my|the] (todo|todos|todo list|todos list|task list|tasks|list|to-do list|reminders)",
            "(add|put) {todo} (to|on) (my|the) (todo|task) list for (today|tomorrow)",
            "remind me to {todo}", "(todo|new todo|add [a] todo|add [a] task|new task|create [a] todo|make [a] todo) {todo}",
            "ajoute {todo} (a|dans|sur) (ma liste|la liste|mes taches|ma liste de taches|mes todos|ma todo|ma todo list)",
            "(rappelle-moi|rappelle moi) (de|d') {todo}",
            "(nouvelle tache) {todo}",
            "(adiciona|adicione|coloca|coloque|poe|bota) {todo} (na|a|nas|em) (minha lista|lista|minhas tarefas|lista de tarefas|meus todos|minha lista de tarefas)",
            "(me lembra|me lembre|lembre-me|lembra-me|me lembra de|me lembre de) (de) {todo}",
            "(nova tarefa) {todo}",
        ]),
        ("spotify", [
            "(play|put on|start|queue up|queue) {q} (on|in|with|from|using|via) spotify",
            "(open|launch|start) spotify (and|then|and then) (play|put on|start playing) {q}",
            "spotify (play|put on) {q}", "on spotify (play|put on) {q}",
            "(joue|mets|lance|passe) {q} sur spotify",
            "(ouvre|lance) spotify (et|puis|et puis) (joue|mets|lance) {q}",
            "(toca|toque|coloca|coloque|bota|poe|tocar) {q} (no|pelo) spotify",
            "(abre|abra|abrir) [o] spotify (e|e depois|depois) (toca|toque|coloca|bota|tocar) {q}",
        ]),
        // Generic music, after the Spotify rule so "play some jazz on spotify" still names Spotify.
        ("media", [
            "(play|put on|start|start playing|queue up) [me] [some|a|any] (music|song|songs|tunes|something|anything)",
        ]),
        ("volume", [
            "(set|change|put|turn|make) [the] (volume|sound) (to|at) {n}", "volume (to|at) {n}", "volume {n}",
            "(mets|regle) le (volume|son) (a|sur) {n}", "volume (a|sur) {n}",
            "(coloca|poe|bota|deixa|muda) [o] volume (em|para|no|a) {n}", "volume (em|para|no) {n}",
        ]),
        ("quit", [
            "(quit|close|exit) {app}", "(quitte|ferme|quitter|fermer) {app}",
            "(fecha|feche|fechar|encerra|encerre|sai do|sair do|sai da|sair da) {app}",
        ]),
        ("hide", ["hide {app}", "(masque|cache) {app}", "(esconde|esconda|oculta|oculte) {app}"]),
        ("open", [
            "(open|launch|start|run|fire up|bring up|pull up|switch to|go to|jump to|take me to|open up|load up) {app}",
            "(ouvre|ouvrir|lance|lancer|demarre|passe sur|va sur|bascule sur|affiche) {app}",
            "(abre|abra|abrir|inicia|inicie|vai para|vai pro|vai pra|muda para|muda pro|troca para|mude para|entra no|entra na) {app}",
        ]),
    ])

    private static func build(rule: String, slots: [String: Range<Int>], in utterance: Utterance) -> FastIntent? {
        let words = utterance.words
        switch rule {
        case "timer":
            guard let range = slots["dur"], let seconds = duration(Array(words[range])) else { return nil }
            return .timer(seconds: seconds)
        case "todo":
            guard let range = slots["todo"] else { return nil }
            let head = words[range]
            // "add these to-dos: ..." and "add it to my list" belong elsewhere.
            if let first = head.first, ["it", "this", "that", "these", "those", "them"].contains(first), head.count <= 2 { return nil }
            let items = todoItems(utterance.source(range))
            return items.isEmpty ? nil : .addTodos(items)
        case "spotify":
            guard let range = slots["q"] else { return nil }
            let query = cleanQuery(utterance.said(range))
            if genericMusic.contains(query.lowercased()) { return .playOnSpotify("") }
            return query.isEmpty ? nil : .playOnSpotify(query)
        case "media":
            return .media(.play)
        case "volume":
            guard let range = slots["n"], let value = number(in: Array(words[range])), (0...100).contains(value) else { return nil }
            return .volume(.set(value))
        case "quit", "hide":
            guard let range = slots["app"], let name = appName(range, in: utterance) else { return nil }
            return rule == "quit" ? .quitApp(name) : .hideApp(name)
        case "open":
            guard let range = slots["app"] else { return nil }
            if let url = url(from: utterance, range: range) { return .openURL(url) }
            guard let name = appName(range, in: utterance) else { return nil }
            if let site = website(name) { return site.isPlainSite ? .openURL(site.url) : .openApp(name, website: site.url) }
            return .openApp(name, website: nil)
        default:
            return nil
        }
    }

    // MARK: Slots

    static let openVerbs: Set<String> = ["open", "launch", "start", "run", "fire", "bring", "pull", "up", "switch", "go", "to", "jump", "take", "me",
                                         "load", "i", "want", "need", "get", "the", "app", "application", "ouvre", "lance", "va", "sur", "passe",
                                         "abre", "abra", "abrir", "vai", "para", "pro", "pra", "muda", "o", "a", "please", "can", "you", "could"]
    static let quitVerbs: Set<String> = ["quit", "close", "exit", "hide", "the", "app", "application", "quitte", "ferme", "masque", "cache",
                                         "fecha", "feche", "sai", "do", "da", "esconde", "oculta", "minimiza", "o", "a", "please", "can", "you"]
    static let playVerbs: Set<String> = ["play", "joue", "mets", "toca", "toque", "coloca", "bota", "tocar", "reproduz", "put"]
    static let todoLeads: Set<String> = ["add", "put", "remind", "me", "to", "todo", "new", "task", "a", "create", "make", "ajoute", "rappelle-moi",
                                         "de", "d'", "adiciona", "adicione", "coloca", "lembra", "lembre", "lembre-me", "please", "can", "you", "i", "need"]
    static let todoSuffixes: [[String]] = [
        "to my todo list", "to my todo", "to my todos", "to the todo list", "to my list", "to my tasks", "on my list", "to the list",
        "to my task list", "on my todo list", "a ma liste", "dans ma liste", "a mes taches", "na minha lista", "na lista", "nas minhas tarefas",
    ].map { $0.split(separator: " ").map(String.init) }

    /// Words that never name an app, so "open my zeus repo in Finder" or "close this tab" fall through.
    static let notAppWords: Set<String> = [
        "my", "your", "this", "that", "these", "those", "it", "them", "in", "on", "with", "for", "from", "into", "and", "then", "or", "but",
        "file", "files", "folder", "document", "doc", "tab", "tabs", "window", "windows", "page", "email", "message", "link", "repo",
        "project", "latest", "last", "recent", "new", "which", "where", "what", "when", "how", "why", "who", "i", "me", "you", "we",
        "everything", "all", "every", "some", "any", "sleep", "bed", "home", "work", "dinner", "lunch",
        "et", "puis", "ou", "mon", "ma", "mes", "ce", "cette", "e", "depois", "meu", "minha", "esse", "essa", "isso", "este", "esta",
    ]
    static let articles: Set<String> = ["the", "a", "an", "le", "la", "les", "l'", "o", "os", "as", "um", "uma", "app", "l"]
    static let genericMusic: Set<String> = ["", "music", "some music", "something", "a song", "anything", "it", "la musique", "de la musique",
                                            "musique", "musica", "uma musica", "alguma coisa", "algo"]

    /// The app name in `range`, or nil when it doesn't look like one (pronouns, compounds, too long).
    static func appName(_ range: Range<Int>, in utterance: Utterance) -> String? {
        var lower = range.lowerBound, upper = range.upperBound
        let words = utterance.words
        while lower < upper, articles.contains(words[lower]) { lower += 1 }
        while upper > lower, ["app", "application", "please", "up"].contains(words[upper - 1]) { upper -= 1 }
        guard upper > lower, upper - lower <= 4 else { return nil }
        if words[lower..<upper].contains(where: { notAppWords.contains($0) }) { return nil }
        let name = utterance.said(lower..<upper).trimmingCharacters(in: .whitespaces)
        return name.count >= 2 ? name : nil
    }

    /// The span left after dropping filler/verb words from both ends.
    private static func trimmedRange(_ words: [String], dropping: Set<String>) -> Range<Int> {
        var lower = 0, upper = words.count
        while lower < upper, dropping.contains(words[lower]) { lower += 1 }
        while upper > lower, ["please", "now", "app", "application", "for", "me"].contains(words[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    static func cleanQuery(_ text: String) -> String {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for lead in ["some ", "the song ", "the album ", "the artist ", "song ", "a bit of ", "un peu de ", "de la ", "du ", "um pouco de "]
        where query.lowercased().hasPrefix(lead) && query.count > lead.count {
            query = String(query.dropFirst(lead.count))
            break
        }
        return query
    }

    /// One or more to-dos: commas and semicolons split ("call Ana, book the dentist"); "and" doesn't,
    /// so "rock and roll lessons" stays whole. French and Portuguese day words become English for
    /// `TodoQuickAdd` ("demain" → "tomorrow").
    static func todoItems(_ text: String) -> [String] {
        let parts = text.contains(",") || text.contains(";")
            ? text.components(separatedBy: CharacterSet(charactersIn: ",;"))
            : [text]
        return parts.map { part in
            var item = part.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ":.-")))
            for (word, english) in [("demain", "tomorrow"), ("aujourd'hui", "today"), ("amanha", "tomorrow"), ("amanhã", "tomorrow"),
                                    ("hoje", "today"), ("ce soir", "tonight"), ("hoje a noite", "tonight"), ("hoje à noite", "tonight")]
            where item.lowercased().hasSuffix(" " + word) {
                item = String(item.dropLast(word.count)) + english
                break
            }
            return item
        }
        .map { $0.hasPrefix("and ") ? String($0.dropFirst(4)) : $0 }
        .filter { $0.count > 1 }
    }

    // MARK: Numbers and durations

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "a": 1, "an": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
        "ninety": 90, "hundred": 100, "a hundred": 100, "half": 50, "max": 100, "maximum": 100, "full": 100,
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "dix": 10, "quinze": 15, "vingt": 20, "trente": 30,
        "quarante": 40, "cinquante": 50, "soixante": 60, "cent": 100,
        "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "dez": 10, "vinte": 20, "trinta": 30,
        "quarenta": 40, "cinquenta": 50, "sessenta": 60, "cem": 100, "meia": 50,
    ]

    /// The first number in `words`: "50", "50%", "fifty", "twenty five", "seventy-five".
    static func number(in words: [String]) -> Int? {
        var index = 0
        while index < words.count {
            var word = words[index]
            if word.hasSuffix("%") { word.removeLast() }
            if let value = Int(word) { return value }
            let parts = word.split(separator: "-").map(String.init)
            if parts.count == 2, let tens = numberWords[parts[0]], let ones = numberWords[parts[1]], tens >= 20, ones < 10 { return tens + ones }
            if let value = numberWords[word], !["a", "an", "un", "une", "um", "uma"].contains(word) {
                if value >= 20, value < 100, index + 1 < words.count, let ones = numberWords[words[index + 1]], ones < 10, ones > 0 {
                    return value + ones
                }
                return value
            }
            index += 1
        }
        return nil
    }

    private static let units: [String: Int] = [
        "second": 1, "seconds": 1, "sec": 1, "secs": 1, "s": 1, "minute": 60, "minutes": 60, "min": 60, "mins": 60, "m": 60,
        "hour": 3600, "hours": 3600, "hr": 3600, "hrs": 3600, "h": 3600,
        "seconde": 1, "secondes": 1, "heure": 3600, "heures": 3600,
        "segundo": 1, "segundos": 1, "minuto": 60, "minutos": 60, "hora": 3600, "horas": 3600,
    ]

    /// "5 minutes", "five minute", "an hour", "half an hour", "1 hour 30 minutes", "90 seconds",
    /// "10 min", "une heure", "cinco minutos", "meia hora". Between 1 second and 24 hours.
    static func duration(_ words: [String]) -> Int? {
        let w = words
        if w.first == "half", w.count == 3, w[1] == "an", units[w[2]] == 3600 { return 1800 }
        if w == ["meia", "hora"] || w == ["une", "demi-heure"] || w == ["demi-heure"] { return 1800 }
        var total = 0, index = 0, matched = false
        while index < w.count {
            if w[index] == "and" || w[index] == "et" || w[index] == "e" { index += 1; continue }
            var value: Int?
            var word = w[index]
            // "5min", "10m"
            if let digits = word.firstIndex(where: { !$0.isNumber }), digits != word.startIndex, let n = Int(word[..<digits]),
               units[String(word[digits...])] != nil {
                total += n * units[String(word[digits...])]!; matched = true; index += 1; continue
            }
            if let n = Int(word) { value = n }
            else if let n = numberWords[word] {
                value = n
                if n >= 20, n < 100, index + 1 < w.count, let ones = numberWords[w[index + 1]], ones > 0, ones < 10, units[w[index + 1]] == nil {
                    value = n + ones; index += 1
                }
            } else if word.contains("-") {
                let parts = word.split(separator: "-").map(String.init)
                if parts.count == 2, let tens = numberWords[parts[0]], let ones = numberWords[parts[1]] { value = tens + ones }
                else if parts.count == 2, let n = Int(parts[0]) ?? numberWords[parts[0]], let unit = units[parts[1]] {
                    total += n * unit; matched = true; index += 1; continue
                }
            }
            guard let n = value, index + 1 < w.count else { return nil }
            word = w[index + 1]
            guard let unit = units[word] else { return nil }
            total += n * unit; matched = true
            index += 2
        }
        guard matched, total >= 1, total <= 86_400 else { return nil }
        return total
    }

    // MARK: Websites

    struct Site { let url: URL; let isPlainSite: Bool }

    /// Sites people open by name. `isPlainSite` false means an app of that name may exist and wins.
    private static let sites: [String: URL] = [
        "youtube": "https://www.youtube.com", "gmail": "https://mail.google.com", "google": "https://www.google.com",
        "github": "https://github.com", "netflix": "https://www.netflix.com", "reddit": "https://www.reddit.com",
        "twitter": "https://x.com", "linkedin": "https://www.linkedin.com", "facebook": "https://www.facebook.com",
        "instagram": "https://www.instagram.com", "wikipedia": "https://www.wikipedia.org", "amazon": "https://www.amazon.com",
        "chatgpt": "https://chatgpt.com", "google drive": "https://drive.google.com", "google docs": "https://docs.google.com",
        "google calendar": "https://calendar.google.com", "google maps": "https://maps.google.com", "hacker news": "https://news.ycombinator.com",
        "youtube music": "https://music.youtube.com", "whatsapp web": "https://web.whatsapp.com", "notion": "https://www.notion.so",
        "figma": "https://www.figma.com", "slack": "https://app.slack.com", "claude": "https://claude.ai", "spotify": "https://open.spotify.com",
        "discord": "https://discord.com/app", "outlook": "https://outlook.live.com", "whatsapp": "https://web.whatsapp.com",
    ].compactMapValues { URL(string: $0) }
    /// Names that are only websites (no Mac app by that name is common).
    private static let webOnly: Set<String> = ["gmail", "google", "github", "netflix", "reddit", "twitter", "linkedin", "facebook",
                                               "instagram", "wikipedia", "amazon", "google docs", "google drive", "google maps",
                                               "google calendar", "hacker news", "whatsapp web"]

    static func website(_ name: String) -> Site? {
        let key = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        guard let url = sites[key] else { return nil }
        return Site(url: url, isPlainSite: webOnly.contains(key))
    }

    /// "github.com", "https://example.org/x", "github dot com".
    static func url(from utterance: Utterance, range: Range<Int>) -> URL? {
        var text = utterance.original[range].joined(separator: " ").lowercased()
        text = text.replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " point ", with: ".").replacingOccurrences(of: " ponto ", with: ".")
        guard !text.contains(" ") else { return nil }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return URL(string: text) }
        let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }),
              let tld = labels.last, (2...12).contains(tld.count), tld.allSatisfy(\.isLetter) else { return nil }
        return URL(string: "https://" + text)
    }
}
