import Foundation
import Testing
@testable import ZeusCore

@Suite struct CodeIntentTests {
    private func parse(_ text: String) -> FastIntent? { FastIntent.parse(text) }

    // MARK: Terminals

    @Test func opensATerminal() {
        for phrase in ["open a terminal", "open terminal", "open the terminal", "Open a new terminal", "hey zeus open a terminal please", "launch a terminal window",
                       "can you open a terminal", "fire up a terminal", "open my terminal"] {
            #expect(parse(phrase) == .openTerminal(project: nil), "\(phrase)")
        }
        #expect(parse("ouvre un terminal") == .openTerminal(project: nil))
        #expect(parse("ouvre le terminal") == .openTerminal(project: nil))
        #expect(parse("abre um terminal") == .openTerminal(project: nil))
        #expect(parse("abre o terminal") == .openTerminal(project: nil))
    }

    @Test func opensATerminalInAProject() {
        #expect(parse("open a terminal in zeus") == .openTerminal(project: "zeus"))
        #expect(parse("open terminal in the zeus project") == .openTerminal(project: "zeus"))
        #expect(parse("open a new terminal in my polyglot repo") == .openTerminal(project: "polyglot"))
        #expect(parse("Open a terminal at metis backup") == .openTerminal(project: "metis backup"))
        #expect(parse("ouvre un terminal dans zeus") == .openTerminal(project: "zeus"))
        #expect(parse("ouvre un terminal dans le projet polyglot") == .openTerminal(project: "polyglot"))
        #expect(parse("abre um terminal no zeus") == .openTerminal(project: "zeus"))
        #expect(parse("abre o terminal na polyglot") == .openTerminal(project: "polyglot"))
    }

    @Test func opensAProjectInAnApp() {
        #expect(parse("open zeus in VS Code") == .openProject("zeus", in: .vscode))
        #expect(parse("open the zeus repo in Cursor") == .openProject("zeus", in: .cursor))
        #expect(parse("open my zeus repo in Finder") == .openProject("zeus", in: .finder))
        #expect(parse("open polyglot in Xcode") == .openProject("polyglot", in: .xcode))
        #expect(parse("open zeus in the terminal") == .openProject("zeus", in: .terminal))
        #expect(parse("open zeus in visual studio code") == .openProject("zeus", in: .vscode))
        #expect(parse("launch zeus in code") == .openProject("zeus", in: .vscode))
        #expect(parse("open zeus with cursor") == .openProject("zeus", in: .cursor))
        #expect(parse("ouvre zeus dans VS Code") == .openProject("zeus", in: .vscode))
        #expect(parse("ouvre le projet polyglot dans Xcode") == .openProject("polyglot", in: .xcode))
        #expect(parse("ouvre zeus dans le Finder") == .openProject("zeus", in: .finder))
        #expect(parse("abre o zeus no VS Code") == .openProject("zeus", in: .vscode))
        #expect(parse("abre a polyglot no Finder") == .openProject("polyglot", in: .finder))
        #expect(parse("abre o zeus no terminal") == .openProject("zeus", in: .terminal))
    }

    // MARK: Coding agent

    @Test func codeBuildFixInAProject() {
        #expect(parse("fix the login bug in zeus") == .codeAgent(tool: nil, project: "zeus", task: "fix the login bug"))
        #expect(parse("build the settings page in the polyglot project") == .codeAgent(tool: nil, project: "polyglot", task: "build the settings page"))
        #expect(parse("code a markdown exporter in zeus") == .codeAgent(tool: nil, project: "zeus", task: "code a markdown exporter"))
        #expect(parse("Hey Zeus, fix the failing tests in my zeus repo please") == .codeAgent(tool: nil, project: "zeus", task: "fix the failing tests"))
        #expect(parse("refactor the notch controller in zeus") == .codeAgent(tool: nil, project: "zeus", task: "refactor the notch controller"))
        #expect(parse("implement dark mode for polyglot") == .codeAgent(tool: nil, project: "polyglot", task: "implement dark mode"))
        // the project is the last "in", so a task may contain "in"
        #expect(parse("fix the crash in the parser in zeus") == .codeAgent(tool: nil, project: "zeus", task: "fix the crash in the parser"))
        #expect(parse("fix the crash in zeus using codex") == .codeAgent(tool: .codex, project: "zeus", task: "fix the crash"))
        #expect(parse("fix the crash in zeus with claude") == .codeAgent(tool: .claude, project: "zeus", task: "fix the crash"))
    }

    @Test func codeInFrenchAndPortuguese() {
        #expect(parse("corrige le bug de connexion dans zeus") == .codeAgent(tool: nil, project: "zeus", task: "corrige le bug de connexion"))
        #expect(parse("implemente le mode sombre dans le projet polyglot") == .codeAgent(tool: nil, project: "polyglot", task: "implemente le mode sombre"))
        #expect(parse("corrige o erro de login no zeus") == .codeAgent(tool: nil, project: "zeus", task: "corrige o erro de login"))
        #expect(parse("implementa o modo escuro na polyglot") == .codeAgent(tool: nil, project: "polyglot", task: "implementa o modo escuro"))
    }

    @Test func askAToolToDoSomething() {
        #expect(parse("ask claude to fix the login bug in zeus") == .codeAgent(tool: .claude, project: "zeus", task: "fix the login bug"))
        #expect(parse("ask codex to add unit tests for the parser") == .codeAgent(tool: .codex, project: nil, task: "add unit tests for the parser"))
        #expect(parse("ask gemini to review the readme in polyglot") == .codeAgent(tool: .gemini, project: "polyglot", task: "review the readme"))
        #expect(parse("ask claude code to refactor the router") == .codeAgent(tool: .claude, project: nil, task: "refactor the router"))
        #expect(parse("tell codex to fix the build in my zeus repo") == .codeAgent(tool: .codex, project: "zeus", task: "fix the build"))
        #expect(parse("have cursor agent write a changelog") == nil) // no "to": not the form
        #expect(parse("ask cursor to go to the store page in zeus") == .codeAgent(tool: .cursorAgent, project: "zeus", task: "go to the store page"))
        #expect(parse("demande à codex de corriger le bug dans zeus") == .codeAgent(tool: .codex, project: "zeus", task: "corriger le bug"))
        #expect(parse("demande à claude d'ajouter des tests") == .codeAgent(tool: .claude, project: nil, task: "ajouter des tests"))
        #expect(parse("pede ao codex para corrigir o bug no zeus") == .codeAgent(tool: .codex, project: "zeus", task: "corrigir o bug"))
        #expect(parse("pede ao claude para adicionar testes") == .codeAgent(tool: .claude, project: nil, task: "adicionar testes"))
    }

    @Test func aCodingTaskKeepsItsWordsAndCaseAndMayBeLong() {
        let long = "fix the race in the SessionStore actor so that two hooks arriving together never drop an event and add a regression test for it and then run the whole suite twice"
        #expect(parse(long + " in zeus") == .codeAgent(tool: nil, project: "zeus", task: long))
        #expect(parse("ask codex to rename FooBar to BazQux, then update the docs") == .codeAgent(tool: .codex, project: nil, task: "rename FooBar to BazQux, then update the docs"))
    }

    // MARK: Research

    @Test func quickResearch() {
        #expect(parse("research solid state batteries") == .research(topic: "solid state batteries", deep: false))
        #expect(parse("look up the history of the zipper") == .research(topic: "the history of the zipper", deep: false))
        #expect(parse("find out how heat pumps work") == .research(topic: "how heat pumps work", deep: false))
        #expect(parse("hey zeus, research Swift 6 strict concurrency please") == .research(topic: "Swift 6 strict concurrency", deep: false))
        #expect(parse("investigate the new EU AI act") == .research(topic: "the new EU AI act", deep: false))
        #expect(parse("do some research on rust async runtimes") == .research(topic: "rust async runtimes", deep: false))
        #expect(parse("do research about sourdough hydration") == .research(topic: "sourdough hydration", deep: false))
        #expect(parse("research about quantum computing") == .research(topic: "quantum computing", deep: false))
        #expect(parse("recherche les batteries solides") == .research(topic: "les batteries solides", deep: false))
        #expect(parse("renseigne-toi sur la loi européenne sur l'IA") == .research(topic: "la loi européenne sur l'IA", deep: false))
        #expect(parse("pesquisa sobre baterias de estado sólido") == .research(topic: "baterias de estado sólido", deep: false))
        #expect(parse("pesquise a história do zíper") == .research(topic: "a história do zíper", deep: false))
    }

    @Test func deepResearch() {
        #expect(parse("deep research solid state batteries") == .research(topic: "solid state batteries", deep: true))
        #expect(parse("deep research on the EU AI act") == .research(topic: "the EU AI act", deep: true))
        #expect(parse("do a deep research about heat pumps") == .research(topic: "heat pumps", deep: true))
        #expect(parse("thorough research into rust async runtimes") == .research(topic: "rust async runtimes", deep: true))
        #expect(parse("recherche approfondie sur les batteries solides") == .research(topic: "les batteries solides", deep: true))
        #expect(parse("pesquisa aprofundada sobre baterias") == .research(topic: "baterias", deep: true))
    }

    // MARK: Negatives

    @Test func similarSentencesAreNotOurs() {
        for phrase in [
            "research",                         // no topic
            "look up",                          // no topic
            "open terminal in",                 // no project
            "open zeus in",                     // no target
            "open Spotify in Chrome",           // a target we don't know
            "fix",                              // nothing to fix
            "fix the bug",                      // no project: the LLM decides where
            "build the project",                // no "in <project>"
            "ask claude what time it is",       // no "to": a question, not a task
            "ask claude to",                    // empty task
            "ask copilot to fix it in zeus",    // not a tool we start
            "what is the difference between research and development",
            "I did some research yesterday",
            "terminal",
            "open it in finder",                // a pronoun is not a project
            "fix this in that",
            "close the terminal",               // quitting stays with the app rules
            "the research is done",
            "code",
        ] {
            let result = parse(phrase)
            let ours: Bool = switch result {
            case .openTerminal?, .openProject?, .codeAgent?, .research?: true
            default: false
            }
            #expect(!ours, "\(phrase) -> \(String(describing: result))")
        }
    }

    @Test func existingCommandsAreUntouched() {
        #expect(parse("open Spotify") == .openApp("Spotify", website: URL(string: "https://open.spotify.com")))
        #expect(parse("launch VS Code") == .openApp("VS Code", website: nil))
        #expect(parse("quit Terminal") == .quitApp("Terminal"))
        #expect(parse("set a timer for 5 minutes") == .timer(seconds: 300))
        #expect(parse("play Daft Punk on Spotify") == .playOnSpotify("Daft Punk"))
        #expect(parse("add milk to my todo list") == .addTodos(["milk"]))
        #expect(parse("mute") == .volume(.mute))
        #expect(parse("go to github.com")?.intentLabel == "browser.open")
    }

    @Test func labelsForTheDecisionHistory() {
        #expect(FastIntent.openTerminal(project: nil).intentLabel == "terminal.open")
        #expect(FastIntent.openProject("zeus", in: .finder).intentLabel == "project.open")
        #expect(FastIntent.codeAgent(tool: nil, project: nil, task: "x").intentLabel == "terminal.agent")
        #expect(FastIntent.research(topic: "x", deep: false).intentLabel == "research")
        // an engine (Laya/Jev) can't produce these: only the rules and the LLM do
        for label in ["terminal.open", "project.open", "terminal.agent", "research"] { #expect(!FastIntent.actionableLabels.contains(label)) }
    }

    @Test func acknowledgementsAreShortAndPlain() {
        let ack = AckLines.neutral
        #expect(ack.line(.terminal(project: "zeus")) == "Opening a terminal in zeus.")
        #expect(ack.line(.terminal(project: nil)) == "Opening a terminal.")
        #expect(ack.line(.project("zeus", .vscode)) == "Opening zeus in VS Code.")
        #expect(ack.line(.agent(.codex, project: "zeus")) == "Starting Codex in zeus.")
        #expect(ack.line(.research("heat pumps", deep: false)) == "Looking into heat pumps.")
        #expect(ack.line(.research("heat pumps", deep: true)) == "Researching heat pumps in depth.")
    }
}
