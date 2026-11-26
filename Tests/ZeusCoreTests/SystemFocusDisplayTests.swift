import Foundation
import Testing
@testable import ZeusCore

/// The words the notch and the settings row draw. docs/NOTCH-FOCUS-PLAN.md, F2.
@Suite("Focus display")
struct SystemFocusDisplayTests {
    typealias Machine = SystemFocusMachine
    typealias Display = SystemFocusDisplay

    func state(
        route: Machine.Route,
        reading: Machine.Reading = .unknown,
        hidden: Bool = false
    ) -> Machine.State {
        Machine.State(enabled: route != .off, route: route, reading: reading, detailsHidden: hidden)
    }

    func focus(_ name: String?, symbol: String?) -> Machine.Reading {
        .on(Machine.Focus(id: "work", name: name, symbol: symbol))
    }

    static func lacksRuledDash(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value != 0x2014 && $0.value != 0x2013 }
    }

    @Test func everyRouteDrawsItsSurface() {
        let checking = Display.surface(for: state(route: .checking))
        #expect(checking == Display.Surface(shown: .none, row: .checking))
        let off = Display.surface(for: state(route: .off, reading: focus("Work", symbol: "moon.fill")))
        #expect(off == Display.Surface(shown: .none, row: .off))
        let needs = Display.surface(for: state(route: .needsAccess))
        #expect(needs == Display.Surface(shown: .none, row: .needsAccess))
        let missing = Display.surface(for: state(route: .unavailable(.missing)))
        #expect(missing.shown == .none)
        #expect(missing.row == .unavailable)
        let refused = Display.surface(for: state(route: .unavailable(.unreadable(.refused))))
        #expect(refused.row == .unavailable)
        let namedOff = Display.surface(for: state(route: .named, reading: .off))
        #expect(namedOff == Display.Surface(shown: .none, row: .allowed))
        let unknown = Display.surface(for: state(route: .named, reading: .unknown))
        #expect(unknown.shown == .none)
        let named = Display.surface(for: state(route: .named, reading: focus("Work", symbol: "moon.fill")))
        #expect(named == Display.Surface(shown: .on(label: "Work", symbol: "moon.fill"), row: .allowed))
    }

    @Test func hiddenDetailsReplaceTheNameAndSymbol() {
        let hidden = state(route: .named, reading: focus("Work", symbol: "house"), hidden: true)
        #expect(Display.surface(for: hidden).shown == .on(label: "Focus on", symbol: "moon.fill"))
        let shown = state(route: .named, reading: focus("Work", symbol: "house"), hidden: false)
        #expect(Display.surface(for: shown).shown == .on(label: "Work", symbol: "house"))
    }

    @Test func aMissingNameOrSymbolUsesThePlainMoon() {
        let noName = state(route: .named, reading: focus(nil, symbol: "house"))
        #expect(Display.surface(for: noName).shown == .on(label: "Focus on", symbol: "house"))
        let noSymbol = state(route: .named, reading: focus("Work", symbol: nil))
        #expect(Display.surface(for: noSymbol).shown == .on(label: "Work", symbol: "moon.fill"))
        let neither = state(route: .named, reading: focus(nil, symbol: nil))
        #expect(Display.surface(for: neither).shown == .on(label: "Focus on", symbol: "moon.fill"))
        let empty = state(route: .named, reading: focus("", symbol: ""))
        #expect(Display.surface(for: empty).shown == .on(label: "Focus on", symbol: "moon.fill"))
    }

    @Test func aCJKNameAndAnEmojiNamePassThroughWhole() {
        let cjk = "专注模式"
        let emoji = "👨‍👩‍👧‍👦"
        let flag = "🇧🇷"
        #expect(Display.surface(for: state(route: .named, reading: focus(cjk, symbol: "moon.fill"))).shown
            == .on(label: cjk, symbol: "moon.fill"))
        #expect(Display.surface(for: state(route: .named, reading: focus(emoji, symbol: "moon.fill"))).shown
            == .on(label: emoji, symbol: "moon.fill"))
        #expect(Display.accessibilityLabel(state(route: .named, reading: focus(flag, symbol: "flag")))
            == "Focus on, \(flag)")
        #expect(cjk.count == 4)
        #expect(emoji.unicodeScalars.contains { $0.value == 0x200D })
    }

    @Test func cuesUseTheNewNameAndTheOffMoon() {
        let turnedOn = Display.cue(for: .turnedOn, reading: focus("Work", symbol: "moon.fill"), hidden: false)
        #expect(turnedOn == Machine.Cue(label: "Work", symbol: "moon.fill", on: true))
        let replaced = Display.cue(for: .replaced, reading: focus("Home", symbol: nil), hidden: false)
        #expect(replaced == Machine.Cue(label: "Home", symbol: "moon.fill", on: true))
        let off = Display.cue(for: .turnedOff, reading: .off, hidden: false)
        #expect(off == Machine.Cue(label: "Focus off", symbol: "moon", on: false))
    }

    @Test func hiddenCuesDropTheName() {
        let turnedOn = Display.cue(for: .turnedOn, reading: focus("Work", symbol: "house"), hidden: true)
        #expect(turnedOn == Machine.Cue(label: "Focus on", symbol: "moon.fill", on: true))
        let replaced = Display.cue(for: .replaced, reading: focus("Home", symbol: "house"), hidden: true)
        #expect(replaced == Machine.Cue(label: "Focus on", symbol: "moon.fill", on: true))
        let off = Display.cue(for: .turnedOff, reading: .off, hidden: true)
        #expect(off == Machine.Cue(label: "Focus off", symbol: "moon", on: false))
    }

    @Test func rowWordsAndSymbols() {
        let samples: [(Machine.Route, String?, String?)] = [
            (.off, nil, nil),
            (.checking, nil, nil),
            (.named, "Allowed", "checkmark.circle.fill"),
            (.needsAccess, "Not allowed", "exclamationmark.circle"),
            (.unavailable(.missing), "Not available on this macOS", "exclamationmark.circle"),
            (.unavailable(.unreadable(.tooLarge)), "Not available on this macOS", "exclamationmark.circle"),
        ]
        for (route, word, symbol) in samples {
            let sample = state(route: route, reading: .off)
            #expect(Display.rowWord(sample) == word)
            #expect(Display.rowSymbol(sample) == symbol)
        }
        let showing = state(route: .named, reading: focus("Work", symbol: "moon.fill"))
        #expect(Display.rowWord(showing) == "Allowed")
        #expect(Display.rowSymbol(showing) == "checkmark.circle.fill")
    }

    @Test func accessibilityLabels() {
        #expect(Display.accessibilityLabel(state(route: .named, reading: focus("Work", symbol: "moon.fill")))
            == "Focus on, Work")
        #expect(Display.accessibilityLabel(state(route: .named, reading: focus(nil, symbol: "moon.fill")))
            == "Focus on")
        #expect(Display.accessibilityLabel(state(route: .named, reading: focus("Work", symbol: "house"), hidden: true))
            == "Focus on")
        #expect(Display.accessibilityLabel(state(route: .named, reading: .off)) == "Focus off")
        #expect(Display.accessibilityLabel(state(route: .checking)) == "Focus off")
        #expect(Display.accessibilityLabel(state(route: .off)) == "Focus off")
        #expect(Display.accessibilityLabel(state(route: .needsAccess)) == "Focus off")
        #expect(Display.accessibilityLabel(state(route: .unavailable(.missing))) == "Focus off")
    }

    @Test func noDrawnStringHoldsAnEmDashOrEnDash() {
        var drawn: [String] = [
            Display.onLabel, Display.offLabel, Display.plainSymbol, Display.offSymbol,
            "Allowed", "Not allowed", "Not available on this macOS", "checkmark.circle.fill",
            "exclamationmark.circle",
        ]
        let routes: [Machine.Route] = [
            .off, .checking, .named, .needsAccess, .unavailable(.missing), .unavailable(.unreadable(.other)),
        ]
        let readings: [Machine.Reading] = [.unknown, .off, focus("Work", symbol: "moon.fill"), focus("专注", symbol: "moon.fill")]
        for route in routes {
            for reading in readings {
                for hidden in [false, true] {
                    let sample = state(route: route, reading: reading, hidden: hidden)
                    let surface = Display.surface(for: sample)
                    if case .on(let label, let symbol) = surface.shown {
                        drawn.append(label)
                        drawn.append(symbol)
                    }
                    drawn.append(Display.accessibilityLabel(sample))
                    if let word = Display.rowWord(sample) { drawn.append(word) }
                    if let symbol = Display.rowSymbol(sample) { drawn.append(symbol) }
                }
            }
        }
        for edge in [SystemFocusEdge.turnedOn, .replaced, .turnedOff] {
            for hidden in [false, true] {
                let cue = Display.cue(for: edge, reading: focus("Work", symbol: "moon.fill"), hidden: hidden)
                drawn.append(cue.label)
                drawn.append(cue.symbol)
            }
        }
        #expect(drawn.allSatisfy(Self.lacksRuledDash))
    }
}
