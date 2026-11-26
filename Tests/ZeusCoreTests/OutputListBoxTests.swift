import Foundation
import Testing
@testable import ZeusCore

@Suite("Output list box")
struct OutputListBoxTests {
    @Test func aZeroWidthSpaceIsNotABlank() {
        #expect(OutputListBox.isBlank("") == false)
        #expect(OutputListBox.isBlank("\u{200B}") == false)
        #expect(OutputListBox.isBlank(" \u{200B}") == false)
        #expect(OutputListBox.isBlank("Speakers") == false)
        let named = ["\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}", "\u{0020}", "\u{0085}", "\u{00A0}", "\u{1680}", "\u{2000}", "\u{200A}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}"]
        for blank in named {
            #expect(OutputListBox.isBlank(blank))
        }
    }

    @Test func trimmingKeepsAZeroWidthSpaceAndDropsNamedBlanks() {
        #expect(OutputListBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(OutputListBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(OutputListBox.trimmed("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(OutputListBox.trimmed("\n\u{200B}Speakers\t") == "\u{200B}Speakers")
        #expect(OutputListBox.trimmed("  Speakers  ") == "Speakers")
        #expect(OutputListBox.trimmed("\u{00A0}Speakers\u{3000}") == "Speakers")
    }

    @Test func aUsableNameKeepsAZeroWidthSpace() {
        #expect(OutputListBox.usable(nil) == nil)
        #expect(OutputListBox.usable("") == nil)
        #expect(OutputListBox.usable("  ") == nil)
        #expect(OutputListBox.usable("\u{00A0}") == nil)
        #expect(OutputListBox.usable("\u{200B}") == "\u{200B}")
        #expect(OutputListBox.usable(" \u{200B}Speakers ") == "\u{200B}Speakers")
        #expect(OutputListBox.usable("  Speakers  ") == "Speakers")
    }

    @Test func theListKeepsAZeroWidthNameWhenSoundLeaves() {
        let (failed, effects) = leave(currentName: "\u{200B}")
        #expect(failure(failed)?.reason == .left(current: "\u{200B}"))
        #expect(effects == [.announce(OutputListText.soundMoved(to: "\u{200B}"))])
    }

    @Test func aNamedBlankAroundAZeroWidthSpaceStaysWhenSoundLeaves() {
        let (kept, keptEffects) = leave(currentName: "\u{00A0}\u{200B}\u{00A0}")
        #expect(failure(kept)?.reason == .left(current: "\u{200B}"))
        #expect(keptEffects == [.announce(OutputListText.soundMoved(to: "\u{200B}"))])
        let (blank, blankEffects) = leave(currentName: "\u{00A0}")
        #expect(failure(blank)?.reason == .left(current: nil))
        #expect(blankEffects == [.announce(OutputListText.soundLeft("Headphones"))])
    }

    private func leave(currentName: String) -> (OutputList.State, [OutputList.Effect]) {
        let routes = [
            OutputList.Route(uid: "a", objectID: 1, name: "Speakers", symbol: "speaker.wave.2", isCurrent: true),
            OutputList.Route(uid: "b", objectID: 2, name: "Headphones", symbol: "headphones", isCurrent: false),
        ]
        let (listening, _) = OutputList.reduce(.closed(run: 0), .toggled)
        guard case .open(let open) = listening, let token = open.reading else {
            preconditionFailure("open did not start a read")
        }
        let loaded = OutputList.reduce(listening, .facts(token: token, routes: routes)).0
        var state = OutputList.reduce(loaded, .picked("b")).0
        state = OutputList.reduce(state, .writeFinished(token: 2, status: 0)).0
        state = OutputList.reduce(state, .readBack(token: 2, uid: "b", name: "Headphones")).0
        return OutputList.reduce(state, .readBack(token: 2, uid: "a", name: currentName))
    }

    private func failure(_ state: OutputList.State) -> OutputList.Failure? {
        if case .open(let open) = state { return open.failure }
        return nil
    }
}
