import Foundation
import Testing
@testable import ZeusCore

@Suite struct TerminalLaunchTests {
    // MARK: Quoting

    @Test func singleQuotesNeutraliseEverythingInsideThem() {
        #expect(ShellQuote.single("plain") == "'plain'")
        #expect(ShellQuote.single("it's") == "'it'\\''s'")
        #expect(ShellQuote.single("$(rm -rf ~)") == "'$(rm -rf ~)'")
        #expect(ShellQuote.single("`x`; echo \"y\" && z") == "'`x`; echo \"y\" && z'")
        #expect(ShellQuote.single("") == "''")
    }

    @Test func appleScriptAndYamlEscapes() {
        #expect(ShellQuote.appleScript("a\"b\\c") == "a\\\"b\\\\c")
        #expect(ShellQuote.yaml("a\"b\nc") == "a\\\"b\\nc")
    }

    /// What a POSIX shell would hand the program as arguments, for a single-quoted-only command line.
    private func unquote(_ line: String) -> [String] {
        var words: [String] = [], current = "", inQuote = false, started = false
        var index = line.startIndex
        while index < line.endIndex {
            let c = line[index]
            if inQuote { if c == "'" { inQuote = false } else { current.append(c) } }
            else if c == "'" { inQuote = true; started = true }
            else if c == "\\" { index = line.index(after: index); current.append(line[index]); started = true }
            else if c == " " { if started { words.append(current); current = ""; started = false } }
            else { current.append(c); started = true }
            index = line.index(after: index)
        }
        if started { words.append(current) }
        return words
    }

    @Test func aTaskStaysOneArgumentWhateverItContains() {
        let nasty = ["fix the bug", "it's broken", "$(touch /tmp/pwned)", "`id`", "a; rm -rf ~ #", "x' ; echo hacked ; '", "line one\nline two",
                     "--dangerously-skip-permissions", "-p", "emoji 🔥 \"quoted\" \\ back"]
        for task in nasty {
            let job = TerminalJob.agent(.claude, task: task, directory: "/tmp/x", binaryPath: "/opt/homebrew/bin/claude")
            let words = unquote(job.commandLine ?? "")
            #expect(words.count == 2, "\(task) -> \(words)")
            #expect(words.first == "/opt/homebrew/bin/claude")
            let expected = task.hasPrefix("-") ? "Task: " + task : task
            #expect(words.last == expected, "\(task)")
        }
    }

    @Test func leadingDashTasksCannotBecomeOptions() {
        #expect(CodingTool.claude.arguments(task: "--version") == ["Task: --version"])
        #expect(CodingTool.gemini.arguments(task: "-x do it") == ["-i", "Task: -x do it"])
    }

    @Test func eachToolStartsAnInteractiveSessionWithTheTaskAsItsFirstPrompt() {
        #expect(CodingTool.claude.arguments(task: "fix tests") == ["fix tests"])
        #expect(CodingTool.codex.arguments(task: "fix tests") == ["fix tests"])
        #expect(CodingTool.cursorAgent.arguments(task: "fix tests") == ["fix tests"])
        #expect(CodingTool.gemini.arguments(task: "fix tests") == ["-i", "fix tests"])
        #expect(CodingTool.claude.arguments(task: "   ").isEmpty)
        // Never headless, never a permission-skipping flag, never a model flag: the CLI keeps its own settings.
        for tool in CodingTool.allCases {
            let all = tool.arguments(task: "x").joined(separator: " ")
            #expect(!all.contains("--model") && !all.contains("-p ") && !all.contains("skip-permissions") && !all.contains("--yolo"))
        }
    }

    @Test func toolNamesAsSpoken() {
        #expect(CodingTool.named("Claude") == .claude)
        #expect(CodingTool.named("claude code") == .claude)
        #expect(CodingTool.named("Codex") == .codex)
        #expect(CodingTool.named("gemini") == .gemini)
        #expect(CodingTool.named("cursor") == .cursorAgent)
        #expect(CodingTool.named("cursor-agent") == .cursorAgent)
        #expect(CodingTool.named("copilot") == nil)
    }

    @Test func preferredToolDefaultsToClaudeCode() {
        let suite = UserDefaults(suiteName: "zeus.tests.tools.\(UUID().uuidString)")!
        #expect(CodingTool.preferred(defaults: suite) == .claude)
        suite.set("codex", forKey: CodingTool.preferenceKey)
        #expect(CodingTool.preferred(defaults: suite) == .codex)
        suite.set("nonsense", forKey: CodingTool.preferenceKey)
        #expect(CodingTool.preferred(defaults: suite) == .claude)
    }

    // MARK: Script

    @Test func scriptChangesDirectoryRunsTheCommandAndStaysOpen() {
        let job = TerminalJob.agent(.codex, task: "add a test", directory: "/Users/t/My Projects/zeus", binaryPath: "/opt/homebrew/bin/codex")
        let script = TerminalScript.contents(for: job, scriptPath: "/tmp/zeus-terminal/ab12.command")
        let lines = script.split(separator: "\n").map(String.init)
        #expect(lines.first == "#!/bin/zsh -il")
        #expect(lines.contains("rm -f -- '/tmp/zeus-terminal/ab12.command'"))
        #expect(lines.contains("cd -- '/Users/t/My Projects/zeus' || { echo \"Zeus: can't open that folder.\"; exec \"$SHELL\" -l; }"))
        #expect(lines.contains("'/opt/homebrew/bin/codex' 'add a test'"))
        #expect(lines.last == "exec \"$SHELL\" -l")
        // the agent line comes after the cd and before the closing shell
        let cd = lines.firstIndex { $0.hasPrefix("cd --") }!, run = lines.firstIndex { $0.hasPrefix("'/opt") }!
        #expect(cd < run && run < lines.count - 1)
    }

    @Test func aDirectoryWithQuotesCannotBreakOutOfTheScript() {
        let job = TerminalJob(directory: "/tmp/x'; touch /tmp/pwned; '", commandLine: nil)
        let script = TerminalScript.contents(for: job, scriptPath: "/tmp/s.command")
        #expect(script.contains("cd -- '/tmp/x'\\''; touch /tmp/pwned; '\\'''"))
        #expect(!script.contains("\ntouch /tmp/pwned"))
    }

    @Test func aPlainTerminalHasNoCommandLine() {
        let script = TerminalScript.contents(for: TerminalJob(directory: "/tmp"), scriptPath: "/tmp/s.command")
        #expect(script.split(separator: "\n").count == 7) // shebang, comment, rm, PATH, cd, title, exec shell
        #expect(script.hasSuffix("exec \"$SHELL\" -l\n"))
    }

    @Test func aShellCommandJobKeepsTheCommandVerbatim() {
        let job = TerminalJob.command("git status", directory: "/tmp/z")
        #expect(TerminalScript.contents(for: job, scriptPath: "/tmp/s.command").contains("\ngit status\n"))
    }

    // MARK: Opening it in each terminal app

    @Test func terminalAndITermOpenTheScriptByName() {
        #expect(TerminalScript.steps(app: .terminal, scriptPath: "/tmp/a b/x.command", directory: "/d", token: "t")
                == [.run(executable: "/usr/bin/open", arguments: ["-a", "Terminal", "/tmp/a b/x.command"])])
        #expect(TerminalScript.steps(app: .iterm, scriptPath: "/tmp/x.command", directory: "/d", token: "t")
                == [.run(executable: "/usr/bin/open", arguments: ["-a", "iTerm", "/tmp/x.command"])])
    }

    @Test func ghosttyRunsTheScriptAsItsCommand() {
        #expect(TerminalScript.steps(app: .ghostty, scriptPath: "/tmp/x.command", directory: "/d", token: "t")
                == [.run(executable: "/usr/bin/open", arguments: ["-na", "Ghostty", "--args", "-e", "/bin/zsh", "/tmp/x.command"])])
    }

    @Test func warpGetsALaunchConfigurationWithEscapedValues() {
        let steps = TerminalScript.steps(app: .warp, scriptPath: "/tmp/it's \"x\".command", directory: "/Users/t/dir \"q\"", token: "ab12", home: "/Users/t")
        #expect(steps.count == 2)
        guard case .writeFile(let path, let yaml) = steps[0] else { Issue.record("expected a file first"); return }
        #expect(path == "/Users/t/.warp/launch_configurations/zeus-ab12.yaml")
        #expect(yaml.contains("name: \"zeus-ab12\""))
        #expect(yaml.contains("cwd: \"/Users/t/dir \\\"q\\\"\""))
        #expect(yaml.contains("exec: \"/bin/zsh '/tmp/it'\\\\''s \\\"x\\\".command'\""))
        #expect(steps[1] == .run(executable: "/usr/bin/open", arguments: ["warp://launch/zeus-ab12"]))
    }

    @Test func noStepEverPutsTheTaskOrACommandOnAProcessCommandLine() {
        // The task lives only inside the script file: process arguments carry just the script's path.
        let job = TerminalJob.agent(.claude, task: "$(rm -rf ~)", directory: "/tmp")
        for app in TerminalApp.allCases {
            for step in TerminalScript.steps(app: app, scriptPath: "/tmp/x.command", directory: "/tmp", token: "t") {
                if case .run(_, let arguments) = step { #expect(!arguments.joined(separator: " ").contains("rm -rf")) }
            }
        }
        #expect(job.commandLine?.contains("'$(rm -rf ~)'") == true)
    }

    // MARK: Which terminal

    @Test func settingsChoiceWins() {
        #expect(TerminalApp.choose(preference: "warp", frontmost: "com.mitchellh.ghostty", running: [], commandHandler: nil, installed: []) == .warp)
    }

    @Test func autoPrefersTheTerminalThatIsOpen() {
        let ghostty = TerminalApp.ghostty.bundleID, iterm = TerminalApp.iterm.bundleID, terminal = TerminalApp.terminal.bundleID
        #expect(TerminalApp.choose(preference: "auto", frontmost: iterm, running: [terminal, iterm], commandHandler: nil, installed: []) == .iterm)
        #expect(TerminalApp.choose(preference: nil, frontmost: "com.apple.finder", running: [terminal, ghostty], commandHandler: nil, installed: []) == .ghostty)
        #expect(TerminalApp.choose(preference: nil, frontmost: nil, running: [terminal], commandHandler: nil, installed: [ghostty]) == .terminal)
    }

    @Test func autoFallsBackToTheHandlerThenInstalledThenTerminal() {
        let warp = TerminalApp.warp.bundleID, iterm = TerminalApp.iterm.bundleID
        #expect(TerminalApp.choose(preference: nil, frontmost: nil, running: [], commandHandler: warp, installed: [iterm]) == .warp)
        #expect(TerminalApp.choose(preference: nil, frontmost: nil, running: [], commandHandler: TerminalApp.terminal.bundleID, installed: [iterm]) == .iterm)
        #expect(TerminalApp.choose(preference: nil, frontmost: nil, running: [], commandHandler: nil, installed: []) == .terminal)
        #expect(TerminalApp.choose(preference: "bogus", frontmost: nil, running: [], commandHandler: nil, installed: []) == .terminal)
    }
}
