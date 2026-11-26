import Foundation
import Testing
@testable import ZeusCore

@Suite("System source rules box")
struct SystemSourceRulesBoxTests {
    private let received = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(SystemSourceRulesBox.blankScalars.contains(" "))
        #expect(SystemSourceRulesBox.blankScalars.contains("\t"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\n"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{000B}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{000C}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\r"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{0085}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{00A0}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{1680}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{2000}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{200A}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{2028}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{2029}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{202F}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{205F}"))
        #expect(SystemSourceRulesBox.blankScalars.contains("\u{3000}"))
        #expect(!SystemSourceRulesBox.blankScalars.contains("\u{200B}"))
        #expect(SystemSourceRulesBox.trimmedName("\u{200B}") == "\u{200B}")
        #expect(SystemSourceRulesBox.trimmedName(" \u{200B} ") == "\u{200B}")
        #expect(SystemSourceRulesBox.trimmedName(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aNameOfOnlyNamedBlanksIsEmpty() {
        #expect(SystemSourceRulesBox.trimmedName("") == "")
        #expect(SystemSourceRulesBox.trimmedName(" \t\n\r") == "")
        #expect(SystemSourceRulesBox.trimmedName("\u{00A0}") == "")
        #expect(SystemSourceRulesBox.trimmedName("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(SystemSourceRulesBox.trimmedName("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheName() {
        #expect(SystemSourceRulesBox.trimmedName("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(SystemSourceRulesBox.trimmedName("\u{200B}VLC") == "\u{200B}VLC")
        #expect(SystemSourceRulesBox.trimmedName("VLC\u{200B}") == "VLC\u{200B}")
        #expect(SystemSourceRulesBox.trimmedName(" \nVLC\t") == "VLC")
    }

    @Test func aZeroWidthAppNameStaysShown() {
        let shown = SystemSourceRules.nowPlaying(item(), appName: "\u{200B}", receivedAt: received)
        #expect(shown.appName == "\u{200B}")
        #expect(shown.appName != SystemSourceRules.unknownAppName)
        let padded = SystemSourceRules.nowPlaying(item(), appName: " \u{200B} ", receivedAt: received)
        #expect(padded.appName == "\u{200B}")
        let marked = SystemSourceRules.nowPlaying(item(), appName: "\u{200B}VLC", receivedAt: received)
        #expect(marked.appName == "\u{200B}VLC")
        #expect(marked.title == "Film")
        #expect(marked.artist == "Director")
    }

    @Test func namedBlanksReadThisMacAndARealNameStays() {
        let blanks = SystemSourceRules.nowPlaying(item(), appName: "\u{00A0}", receivedAt: received)
        #expect(blanks.appName == SystemSourceRules.unknownAppName)
        let spaces = SystemSourceRules.nowPlaying(item(), appName: " \t\n\r\u{3000}", receivedAt: received)
        #expect(spaces.appName == "This Mac")
        let empty = SystemSourceRules.nowPlaying(item(), appName: "", receivedAt: received)
        #expect(empty.appName == "This Mac")
        let named = SystemSourceRules.nowPlaying(item(key: "k9"), appName: " \nVLC\t", receivedAt: received)
        #expect(named.appName == "VLC")
        #expect(named.appBundleID == "org.videolan.vlc")
        #expect(named.key == "k9")
        let marked = SystemSourceRules.nowPlaying(item(), appName: "VLC\u{200B}", receivedAt: received)
        #expect(marked.appName == "VLC\u{200B}")
    }

    private func item(key: String = "k1") -> SystemSourceRules.Item {
        SystemSourceRules.Item(app: "org.videolan.vlc", title: "Film", artist: "Director", album: "Album",
                               duration: 120, elapsed: 10, rate: 1, key: key)
    }
}
