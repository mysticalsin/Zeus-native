import Foundation
import Testing
@testable import ZeusCore

@Suite("Model cap: Haiku or Sonnet size at most")
struct ModelCapTests {
    private func store() -> UserDefaults {
        let name = "zeus.tests.modelcap.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func claudeUsesHaikuForQuickTurnsAndSonnetAtMost() {
        let defaults = store()
        #expect(ModelCap.arguments(for: .claude, tier: .fast, defaults: defaults) == ["--model", "haiku"])
        #expect(ModelCap.arguments(for: .claude, tier: .deep, defaults: defaults) == ["--model", "sonnet"])
    }

    @Test func codexEffortNeverGoesAboveMedium() {
        let defaults = store()
        #expect(ModelCap.arguments(for: .codex, tier: .fast, defaults: defaults) == ["-c", "model_reasoning_effort=\"low\""])
        #expect(ModelCap.arguments(for: .codex, tier: .deep, defaults: defaults) == ["-c", "model_reasoning_effort=\"medium\""])
    }

    @Test func everyEngineThatTakesAModelGetsOneOnEveryLaunch() {
        let defaults = store()
        for engine in [RouterEngine.claude, .codex, .gemini, .cursorAgent] {
            for tier in [ModelTier.fast, .deep] {
                let arguments = engine.headlessArguments(prompt: "hi", tier: tier, defaults: defaults)
                #expect(arguments.contains("--model") || arguments.contains("-m") || arguments.contains("-c"),
                        "\(engine) \(tier) launched without a pinned model")
            }
        }
    }

    @Test func largeModelsAreRefusedEvenAsOverrides() {
        for name in ["claude-opus-5-5", "opus", "claude-fable-5", "gemini-3-pro", "gpt-5.6-sol-xhigh", "gpt-6-astra"] {
            #expect(!ModelCap.isAllowed(name), "\(name) should be refused")
        }
        for name in ["haiku", "sonnet", "claude-sonnet-5-thinking-high", "gemini-3.7-flash", "gpt-5-mini"] {
            #expect(ModelCap.isAllowed(name), "\(name) should be allowed")
        }
        let defaults = store()
        defaults.set("opus", forKey: "modelCap.claude.deep")
        #expect(ModelCap.arguments(for: .claude, tier: .deep, defaults: defaults) == ["--model", "sonnet"])
        defaults.set("claude-sonnet-5-thinking-high", forKey: "modelCap.claude.deep")
        #expect(ModelCap.arguments(for: .claude, tier: .deep, defaults: defaults) == ["--model", "claude-sonnet-5-thinking-high"])
    }

    @Test func httpModelNamesStayInsideTheCap() {
        let defaults = store()
        _ = defaults
        #expect(ModelCap.httpModel(.anthropic, tier: .fast) == "claude-haiku-4-5")
        #expect(ModelCap.httpModel(.ollama, tier: .fast) == "llama3.2")
        #expect(ModelCap.httpModel(.openAI, tier: .fast) == "gpt-4o-mini")
        #expect(ModelCap.gatedHTTPModel("claude-opus-4-5") == nil)
        #expect(ModelCap.gatedHTTPModel("claude-haiku-4-5") == "claude-haiku-4-5")
        for preset in [ModelCap.HTTPPreset.ollama, .anthropic, .openAI] {
            for tier in [ModelTier.fast, .deep] {
                if let name = ModelCap.httpModel(preset, tier: tier) {
                    #expect(ModelCap.isAllowed(name))
                }
            }
        }
    }

    @Test func noDefaultModelIsTooLarge() {
        for engine in RouterEngine.allCases {
            for tier in [ModelTier.fast, .deep] {
                if let model = ModelCap.model(for: engine, tier: tier, defaults: store()) {
                    #expect(ModelCap.isAllowed(model))
                }
            }
        }
    }
}
