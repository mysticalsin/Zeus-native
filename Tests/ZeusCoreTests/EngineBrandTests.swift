import Testing
import ZeusCore

@Suite struct EngineBrandTests {
    @Test func aliasSamplesResolve() {
        for (raw, expected) in EngineBrand.aliasSamples {
            #expect(EngineBrand.resolve(raw) == expected, "\(raw) should map to \(expected)")
        }
    }

    @Test func everyMarkHasDistinctAssetName() {
        var names = Set<String>()
        for mark in EngineBrandMark.allCases {
            #expect(names.insert(mark.assetName).inserted, "duplicate asset for \(mark)")
        }
    }

    @Test func providersAndRouterEnginesUseTable() {
        #expect(EngineBrand.resolve(provider: .cursor) == .cursor)
        #expect(EngineBrand.resolve(provider: .grok) == .grok)
        #expect(EngineBrand.resolve(engine: .grok) == .grok)
        #expect(EngineBrand.resolve(engine: .codex) == .openai)
        #expect(EngineBrand.resolve(tool: .cursorAgent) == .cursor)
    }

    @Test func officialGrokUsesOriginalSVGAndUnknownProvidersKeepFallback() {
        #expect(EngineBrandMark.grok.assetName == "engine-grok")
        #expect(EngineBrandMark.grok.assetExtension == "svg")
        #expect(EngineBrandMark.grok.title == "Grok")
        let svgMarks: [EngineBrandMark] = [.grok, .ollama, .lmStudio]
        for mark in EngineBrandMark.allCases where !svgMarks.contains(mark) { #expect(mark.assetExtension == "pdf") }
        #expect(EngineBrand.resolve("x.ai") == .grok)
        #expect(EngineBrand.resolve("unlisted-provider") == .fallback)
        #expect(EngineBrand.resolve(provider: .anyLLM) == .fallback)
    }

    @Test func everyNamedSupportedIntegrationUsesItsOwnProviderMark() {
        for provider in AIProvider.allCases where provider != .anyLLM {
            #expect(EngineBrand.resolve(provider: provider) != .fallback, "Missing provider identity for \(provider.title)")
        }
        for engine in RouterEngine.allCases {
            #expect(EngineBrand.resolve(engine.title) == EngineBrand.resolve(engine: engine))
        }
        for tool in CodingTool.allCases {
            #expect(EngineBrand.resolve(tool.title) == EngineBrand.resolve(tool: tool))
        }
        #expect(EngineBrand.resolve(provider: .ollama) == .ollama)
        #expect(EngineBrand.resolve(provider: .lmStudio) == .lmStudio)
        #expect(EngineBrandMark.ollama.assetExtension == "svg")
        #expect(EngineBrandMark.lmStudio.assetExtension == "svg")
        #expect(EngineBrand.resolve(provider: .codex) == .openai)
        #expect(EngineBrand.resolve("Anthropic") == .anthropic)
        #expect(EngineBrand.resolve(provider: .anyLLM) == .fallback)
    }
}
