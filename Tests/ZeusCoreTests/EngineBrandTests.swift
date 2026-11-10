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
        for mark in EngineBrandMark.allCases where mark != .grok { #expect(mark.assetExtension == "pdf") }
        #expect(EngineBrand.resolve("x.ai") == .grok)
        #expect(EngineBrand.resolve("unlisted-provider") == .fallback)
        #expect(EngineBrand.resolve(provider: .anyLLM) == .fallback)
    }
}
