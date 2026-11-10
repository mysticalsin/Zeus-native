import Foundation
import Testing
@testable import ZeusCore

/// Fake detection and status runners for the one-button Connect flow in Settings › Integrations.
private struct FakeMac {
    var executables: Set<String> = []
    var apps: Set<String> = []
    /// Fake `<cli> <status args>` results by binary name.
    var status: [String: (Int32, String)] = [:]

    func detect(_ provider: AIProvider) -> AIProviderDetection {
        AIProviderDetector.detect(provider, searchDirectories: ["/bin"], appDirectories: ["/Apps"],
                                  isExecutable: { executables.contains($0) }, exists: { apps.contains($0) })
    }

    /// What the app's real check does: the CLI's own status subcommand, read by AIConnectFlow.
    func signedIn(_ provider: AIProvider) -> Bool? {
        guard AIConnectFlow.statusArguments(provider) != nil, let binary = provider.binary,
              let result = status[binary] else { return nil }
        return AIConnectFlow.signedIn(provider, exitCode: result.0, output: result.1)
    }

    func facts(_ provider: AIProvider, linked: Bool = false, running: Bool = false) -> AIConnectFacts {
        AIConnectFacts(installed: detect(provider).isInstalled, signedIn: signedIn(provider), linked: linked, running: running)
    }
}

@Suite("AI connect button")
struct AIConnectFlowTests {
    @Test func claudeCodeGoesInstallSignInConnectConnected() {
        var mac = FakeMac()
        #expect(AIConnectFlow.step(for: .claudeCode, facts: mac.facts(.claudeCode)) == .install)
        mac.executables = ["/bin/claude"]
        mac.status["claude"] = (1, #"{"loggedIn": false, "authMethod": "none"}"#)
        #expect(AIConnectFlow.step(for: .claudeCode, facts: mac.facts(.claudeCode)) == .signIn)
        mac.status["claude"] = (0, #"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "max"}"#)
        #expect(AIConnectFlow.step(for: .claudeCode, facts: mac.facts(.claudeCode)) == .connect)
        #expect(AIConnectFlow.step(for: .claudeCode, facts: mac.facts(.claudeCode, linked: true)) == .connected)
    }

    @Test func codexReadsLoginStatus() {
        var mac = FakeMac(executables: ["/bin/codex"])
        mac.status["codex"] = (1, "Not logged in")
        #expect(mac.signedIn(.codex) == false)
        #expect(AIConnectFlow.step(for: .codex, facts: mac.facts(.codex)) == .signIn)
        mac.status["codex"] = (0, "Logged in using ChatGPT")
        #expect(mac.signedIn(.codex) == true)
        #expect(AIConnectFlow.step(for: .codex, facts: mac.facts(.codex, linked: true)) == .connected)
        // Hooks in place but signed out since: back to Sign in.
        mac.status["codex"] = (1, "Not logged in")
        #expect(AIConnectFlow.step(for: .codex, facts: mac.facts(.codex, linked: true)) == .signIn)
    }

    @Test func cursorAgentReadsStatusJSON() {
        var mac = FakeMac(executables: ["/bin/cursor-agent"])
        mac.status["cursor-agent"] = (0, #"{"status":"authenticated","isAuthenticated":true}"#)
        #expect(mac.signedIn(.cursor) == true)
        mac.status["cursor-agent"] = (1, #"{"status":"unauthenticated","isAuthenticated":false}"#)
        #expect(AIConnectFlow.step(for: .cursor, facts: mac.facts(.cursor)) == .signIn)
        mac.status["cursor-agent"] = (0, "✓ Logged in as someone")
        #expect(mac.signedIn(.cursor) == true)
    }

    @Test func geminiHasNoStatusCommandSoItsFilesAreRead() {
        #expect(AIConnectFlow.statusArguments(.gemini) == nil)
        #expect(!AIConnectFlow.geminiSignedIn(oauthCredentialsExist: false, settings: nil, environment: [:]))
        #expect(AIConnectFlow.geminiSignedIn(oauthCredentialsExist: true, settings: nil, environment: [:]))
        #expect(AIConnectFlow.geminiSignedIn(oauthCredentialsExist: false, settings: nil, environment: ["GEMINI_API_KEY": "k"]))
        let vertex = Data(#"{"security":{"auth":{"selectedType":"vertex-ai"}}}"#.utf8)
        #expect(AIConnectFlow.geminiSignedIn(oauthCredentialsExist: false, settings: vertex, environment: [:]))
        let oauthOnly = Data(#"{"security":{"auth":{"selectedType":"oauth-personal"}}}"#.utf8)
        #expect(!AIConnectFlow.geminiSignedIn(oauthCredentialsExist: false, settings: oauthOnly, environment: [:]))
        let facts = AIConnectFacts(installed: true, signedIn: false)
        #expect(AIConnectFlow.step(for: .gemini, facts: facts) == .signIn)
    }

    @Test func unknownStatusLeavesConnectAvailable() {
        #expect(AIConnectFlow.signedIn(.claudeCode, exitCode: 1, output: "error: unknown command 'auth'") == nil)
        #expect(AIConnectFlow.step(for: .claudeCode, facts: AIConnectFacts(installed: true, signedIn: nil)) == .connect)
    }

    @Test func statusAndLoginCommandsMatchTheCLIs() {
        #expect(AIConnectFlow.statusArguments(.claudeCode) == ["auth", "status", "--json"])
        #expect(AIConnectFlow.statusArguments(.codex) == ["login", "status"])
        #expect(AIConnectFlow.statusArguments(.cursor) == ["status", "--format", "json"])
        #expect(AIConnectFlow.loginArguments(.claudeCode) == ["auth", "login"])
        #expect(AIConnectFlow.loginArguments(.codex) == ["login"])
        #expect(AIConnectFlow.loginArguments(.cursor) == ["login"])
        #expect(AIConnectFlow.loginArguments(.gemini) == [])
        #expect(AIConnectFlow.loginArguments(.chatgpt) == nil)
    }

    @Test func signInScriptRunsTheCLIsOwnLogin() throws {
        let script = try #require(AIConnectFlow.signInScript(.codex, executable: "/opt/homebrew/bin/codex"))
        #expect(script.hasPrefix("#!/bin/zsh -l\n"))
        #expect(script.contains("'/opt/homebrew/bin/codex' 'login'"))
        let odd = try #require(AIConnectFlow.signInScript(.claudeCode, executable: "/Users/o'neil/bin/claude"))
        #expect(odd.contains(#"'/Users/o'\''neil/bin/claude' 'auth' 'login'"#))
        #expect(AIConnectFlow.signInScript(.ollama, executable: "/bin/ollama") == nil)
    }

    @Test func installShowsTheOfficialCommandNeverRunsIt() {
        for provider in [AIProvider.claudeCode, .codex, .gemini, .cursor] {
            #expect(AIConnectFlow.installCommand(provider) != nil, "\(provider)")
            #expect(AIConnectFlow.docsURL(provider)?.scheme == "https", "\(provider)")
            #expect(AIConnectFlow.step(for: provider, facts: AIConnectFacts()) == .install)
        }
        #expect(AIConnectFlow.installCommand(.codex) == "npm install -g @openai/codex")
        #expect(AIConnectFlow.installCommand(.gemini) == "npm install -g @google/gemini-cli")
    }

    @Test func appsOpenThenCountAsConnected() {
        var mac = FakeMac()
        #expect(AIConnectFlow.step(for: .chatgpt, facts: mac.facts(.chatgpt)) == .install)
        mac.apps = ["/Apps/ChatGPT.app"]
        #expect(AIConnectFlow.step(for: .chatgpt, facts: mac.facts(.chatgpt)) == .openApp)
        #expect(AIConnectFlow.step(for: .chatgpt, facts: mac.facts(.chatgpt, running: true)) == .connected)
        mac.apps = ["/Apps/Grok Bot.app"]
        #expect(AIConnectFlow.step(for: .grok, facts: mac.facts(.grok, linked: true)) == .connected)
    }

    @Test func localServersStartThenConnect() {
        let mac = FakeMac(executables: ["/bin/ollama"])
        #expect(AIConnectFlow.step(for: .ollama, facts: mac.facts(.ollama)) == .startServer)
        #expect(AIConnectFlow.step(for: .ollama, facts: mac.facts(.ollama, running: true)) == .connected)
        #expect(AIConnectFlow.step(for: .lmStudio, facts: FakeMac().facts(.lmStudio)) == .install)
        #expect(AIConnectFlow.startCommand(.ollama, appInstalled: true)?.app == "Ollama")
        #expect(AIConnectFlow.startCommand(.ollama, appInstalled: false)?.arguments == ["serve"])
        #expect(AIConnectFlow.startCommand(.lmStudio, appInstalled: false)?.arguments == ["server", "start"])
    }

    @Test func endpointNeedsConfigThenAPassingTestWithASmallModel() {
        #expect(AIConnectFlow.step(for: .anyLLM, facts: AIConnectFacts()) == .configure)
        #expect(AIConnectFlow.step(for: .anyLLM, facts: AIConnectFacts(configured: true)) == .test)
        #expect(AIConnectFlow.step(for: .anyLLM, facts: AIConnectFacts(configured: true, testPassed: false)) == .test)
        #expect(AIConnectFlow.step(for: .anyLLM, facts: AIConnectFacts(configured: true, testPassed: true)) == .connected)
        #expect(AIConnectFlow.endpointModelProblem("gpt-5-mini") == nil)
        #expect(AIConnectFlow.endpointModelProblem("claude-haiku-4-5") == nil)
        #expect(AIConnectFlow.endpointModelProblem("claude-opus-4") != nil)
        #expect(AIConnectFlow.endpointModelProblem("") != nil)
        #expect(AIConnectFlow.endpointPresets.allSatisfy { AIConnectFlow.endpointModelProblem($0.model) == nil })
    }

    @Test func everyStepHasAButtonTitle() {
        let steps: [AIConnectStep] = [.install, .signIn, .connect, .openApp, .startServer, .configure, .test, .connected]
        #expect(Set(steps.map(\.buttonTitle)).count == steps.count)
        #expect(AIConnectStep.signIn.buttonTitle == "Sign in")
    }
}
