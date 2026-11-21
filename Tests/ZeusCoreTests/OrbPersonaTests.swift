import Foundation
import Testing
@testable import ZeusCore

@Suite("Orb persona")
struct OrbPersonaTests {
    @Test func spokenLinesStayAtTenWordsOrFewer() {
        #expect(!JarvisPersona.spokenLines.isEmpty)
        for line in JarvisPersona.spokenLines {
            let words = line.split(whereSeparator: \.isWhitespace)
            #expect(words.count <= 10, "\(line) has \(words.count) words")
            #expect(words.count >= 1)
        }
    }

    @Test func addendumKeepsTheSpokenMannerAndDropsClaudeCodeSpecifics() {
        let text = JarvisPersona.addendum
        #expect(text.contains("JARVIS"))
        #expect(text.contains("sir"))
        #expect(text.contains("ONE sentence"))
        #expect(text.contains("I'm afraid I don't have that, sir."))
        #expect(text.contains("That's beyond my reach at the moment, sir."))
        #expect(!text.contains("http://"))
        #expect(!text.contains("https://"))
        #expect(!text.contains("JARVIS (MCU)"))
        for token in JarvisPersona.removedTokens {
            #expect(!text.contains(token), "addendum still contains \(token)")
        }
        #expect(JarvisPersona.edits.count >= 8)
    }

    @Test func phaseMapIsLocalUntilTheTurnMachineLands() {
        #expect(OrbVisualState.allCases.map(\.rawValue) == ["idle", "listening", "thinking", "speaking", "compacting"])
        #expect(OrbVisualStateMap.visualState(forPhaseName: "listening") == .listening)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "transcribing") == .thinking)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "thinking") == .thinking)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "speaking") == .speaking)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "compacting") == .compacting)
        // frontend/src/orb.ts has no error targets. Idle stands in until S1's phase type exists.
        #expect(OrbVisualStateMap.visualState(forPhaseName: "error") == .idle)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "interrupted") == .idle)
        #expect(OrbVisualStateMap.visualState(forPhaseName: "idle") == .idle)
    }

    @Test func nativeRenderProofStaysMacPending() {
        #expect(OrbMacProof.status == "MAC-PENDING")
        #expect(OrbMacProof.linuxNote.contains("no Metal"))
        #expect(OrbMacProof.budgets.contains("60"))
        #expect(OrbMacProof.budgets.contains("120"))
        #expect(OrbMacProof.artifacts.contains("idle.png"))
        #expect(OrbMacProof.artifacts.contains("frame-times.csv"))
    }

    @Test func personaAndOrbSourcesMakeNoNetworkOrLLMCalls() throws {
        let root = repoRoot()
        var files = try swiftFiles(at: root.appendingPathComponent("Sources/ZeusCore/Companion"))
        let appCompanion = root.appendingPathComponent("Sources/Zeus/Companion")
        if FileManager.default.fileExists(atPath: appCompanion.path) {
            files += try swiftFiles(at: appCompanion)
        }
        #expect(!files.isEmpty)
        let banned = ["URLSession", "URLRequest", "NWConnection", "import Network", "http://", "https://",
                      "AnthropicAPI", "ClaudeCLI", "URLSession.shared", "Process("]
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in banned {
                #expect(!text.contains(token), "\(url.lastPathComponent) contains \(token)")
            }
        }
    }

    @Test func portedFilesCarryTheSourceAttribution() throws {
        let root = repoRoot()
        let required = [
            "Sources/ZeusCore/Companion/OrbSimulation.swift",
            "Sources/ZeusCore/Companion/JarvisPersona.swift",
            "Sources/Zeus/Companion/Orb/OrbMetalRenderer.swift",
            "Sources/Zeus/Companion/Orb/OrbOffscreenHarness.swift",
        ]
        for relative in required {
            let url = root.appendingPathComponent(relative)
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("16e37bd801eb797798e02540665f8b3804b0fe14"))
            #expect(text.contains("Ethan Rogers"))
            #expect(text.contains("jarvis2.0"))
            #expect(text.contains("LICENSES/jarvis2.0-LICENSE"))
        }
    }

    @Test func licenseFileIsTheUpstreamTextVerbatim() throws {
        let url = repoRoot().appendingPathComponent("LICENSES/jarvis2.0-LICENSE")
        let data = try Data(contentsOf: url)
        #expect(data.count == 1677)
        #expect(data.reduce(0) { $0 + Int($1) } == 138619)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("JARVIS Voice AI Assistant\nCopyright (c) 2026 Ethan Rogers\n"))
        #expect(text.contains("COMMERCIAL USE PROHIBITED WITHOUT LICENSE"))
        #expect(text.contains("https://ethanplus.ai"))
        #expect(text.hasSuffix("SOFTWARE.\n"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(at directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}
