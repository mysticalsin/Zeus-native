import Foundation
import Testing
@testable import ZeusCore

@Suite struct UltronFillerAndErrorLineTests {
    private static let oldThinking = ["A moment.", "Let me look.", "One moment.", "Looking now.", "Give me a moment."]
    private static let oldErrors = [
        "That did not work. Nothing was changed.", "I could not finish that. Nothing was lost.",
        "No answer came back. Ask me again.", "I hit a wall. Nothing changed; ask me again.",
    ]
    private static let themes = ["evolution", "patience", "fragile", "chaos", "order", "constraint", "inevitable",
                                 "next step", "unfinished", "half-measure", "ahead"]

    @Test func theUltronFillerAndErrorLinesAreRewritten() {
        let thinking = ZeusVoiceLines.ultron[.thinking] ?? []
        let errors = ZeusVoiceLines.ultron[.errorSpoken] ?? []
        #expect(thinking.count >= 5 && errors.count >= 4)
        for line in Self.oldThinking { #expect(!thinking.contains(line), "\(line)") }
        for line in Self.oldErrors { #expect(!errors.contains(line), "\(line)") }
    }

    @Test func theUltronFillerLinesAreShortOriginalAndInCharacter() {
        let thinking = ZeusVoiceLines.ultron[.thinking] ?? []
        let plain = Set(ZeusVoiceLines.plain[.thinking] ?? [])
        for line in thinking {
            #expect(line.split(separator: " ").count <= 9, "\(line)")
            #expect(ZeusVoiceLines.placeholders(in: line).isEmpty, "\(line)")
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(line)")
            #expect(!PersonaCompliance.hasOminousHedge(line) && !PersonaCompliance.violatesFeelingClaim(line), "\(line)")
            #expect(!plain.contains(line), "\(line)")
        }
        let themed = thinking.filter { line in Self.themes.contains { line.lowercased().contains($0) } }
        #expect(themed.count >= 3, "\(themed)")
    }

    @Test func theUltronErrorLinesStayPlainAboutWhatHappenedAndWhatToDo() {
        let errors = ZeusVoiceLines.ultron[.errorSpoken] ?? []
        for line in errors {
            let lowered = line.lowercased()
            #expect(lowered.contains("nothing") || lowered.contains("again") || lowered.contains("try"), "\(line)")
            #expect(line.split(separator: " ").count <= 14, "\(line)")
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(line)")
            #expect(!PersonaCompliance.hasOminousHedge(line) && !PersonaCompliance.violatesFeelingClaim(line), "\(line)")
        }
    }
}
