import Foundation
import Testing
@testable import ZeusCore

@Suite("Step zero focus facts")
struct StepZeroFocusFactsTests {
    private let name = "Paper Lantern"
    private let otherName = "Other Lantern"
    private let symbol = "moon.fill"
    private let longSymbol = String(repeating: "a", count: 65)
    private let fitSymbol = String(repeating: "b", count: 64)

    @Test func aMissingKeyIsNoNotAnError() {
        let read = StepZeroFocusFacts.read(
            assertions: json(
                """
                {"data":[{"storeAssertionRecords":[{},{"assertionDetails":{}},\
                {"assertionDetailsModeIdentifier":"flat-id"},\
                {"assertionDetails":{"assertionDetailsModeIdentifier":""}},\
                {"assertionDetails":{"assertionDetailsModeIdentifier":"   "}},\
                {"assertionDetails":{"assertionDetailsModeIdentifier":12}},\
                {"assertionDetails":{"assertionDetailsModeIdentifier":null}},\
                {"name":"\(name)"}]}]}
                """
            ),
            configurations: nil
        )
        let quiet = StepZeroFocusFacts.Fact(
            hasModeId: false, idIsConfigKey: false, hasName: false, hasSymbol: false
        )
        #expect(read == .live(Array(repeating: quiet, count: 8)))
        let stored = storedStrings(read)
        #expect(stored.contains(name) == false)
        #expect(stored.contains("flat-id") == false)
    }

    @Test func aNumberAnEmptyStringOrABadSymbolIsNo() {
        let config = """
        {"data":[{"modeConfigurations":{\
        "mode-a":{"name":"\(name)","mode":{"name":12,"symbolImageName":"Moon Fill"}},\
        "mode-b":{"mode":{"name":"","symbolImageName":"../x"}},\
        "mode-c":{"mode":{"name":"   ","symbolImageName":""}},\
        "mode-d":{"mode":{"name":"\(name)","symbolImageName":"\(longSymbol)"}},\
        "mode-e":{"mode":{"symbolImageName":"\(symbol)","allowedContacts":["\(otherName)"]}}\
        }}]}
        """
        let assertions = """
        {"data":[{"storeAssertionRecords":[\
        {"assertionDetails":{"assertionDetailsModeIdentifier":"mode-a"}},\
        {"assertionDetails":{"assertionDetailsModeIdentifier":"mode-b"}},\
        {"assertionDetails":{"assertionDetailsModeIdentifier":"mode-c"}},\
        {"assertionDetails":{"assertionDetailsModeIdentifier":"mode-d"}},\
        {"assertionDetails":{"assertionDetailsModeIdentifier":"mode-e"}}\
        ]}]}
        """
        let read = StepZeroFocusFacts.read(assertions: json(assertions), configurations: json(config))
        #expect(
            read == .live([
                fact(true, true, false, false),
                fact(true, true, false, false),
                fact(true, true, false, false),
                fact(true, true, true, false),
                fact(true, true, false, true),
            ])
        )
        let stored = storedStrings(read)
        #expect(stored.contains(name) == false)
        #expect(stored.contains(otherName) == false)
        #expect(stored.contains(symbol) == false)
        #expect(stored.contains(longSymbol) == false)
        #expect(stored.contains("Moon Fill") == false)
        #expect(stored.contains("../x") == false)
    }

    @Test func noNameSurvivesIntoAFact() {
        let id = "mode-a"
        let read = StepZeroFocusFacts.read(
            assertions: json(live(id)),
            configurations: json(config(id, name: name, symbol: fitSymbol))
        )
        #expect(read == .live([fact(true, true, true, true)]))
        let stored = storedStrings(read)
        #expect(stored.contains(name) == false)
        #expect(stored.contains(id) == false)
        #expect(stored.contains(fitSymbol) == false)
        #expect(stored.isEmpty)
    }

    @Test func aHistoryListAndAScheduleAreNotRead() {
        let historyOnly = StepZeroFocusFacts.read(
            assertions: json(
                """
                {"data":[{"scheduleName":"\(name)","triggers":[{"name":"\(name)","hours":[9]}],\
                "assertionHistory":[{"name":"\(name)","assertionDetails":{"assertionDetailsModeIdentifier":"history-id"},\
                "mode":{"name":"\(name)","symbolImageName":"\(symbol)"}}],\
                "storeAssertionRecords":[]}]}
                """
            ),
            configurations: json(config("history-id", name: name, symbol: symbol))
        )
        #expect(historyOnly == .off)
        #expect(storedStrings(historyOnly).contains(name) == false)
        #expect(storedStrings(historyOnly).contains("history-id") == false)

        let later = StepZeroFocusFacts.read(
            assertions: json(
                """
                {"data":[{"assertionHistory":[{"name":"\(otherName)"}]},\
                {"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"live-id"}}]}]}
                """
            ),
            configurations: nil
        )
        #expect(later == .live([fact(true, false, false, false)]))
        let stored = storedStrings(later)
        #expect(stored.contains(otherName) == false)
        #expect(stored.contains("live-id") == false)
    }

    @Test func theRecordCapDropsTheSixtyFifth() {
        let filler = #"{"assertionDetails":{}}"#
        let hidden = #"{"assertionDetails":{"assertionDetailsModeIdentifier":"mode-a"}}"#
        let records = Array(repeating: filler, count: 64).joined(separator: ",") + "," + hidden
        let dropped = StepZeroFocusFacts.read(
            assertions: json(#"{"data":[{"storeAssertionRecords":[\#(records)]}]}"#),
            configurations: json(config("mode-a", name: name, symbol: symbol))
        )
        let quiet = fact(false, false, false, false)
        #expect(dropped == .live(Array(repeating: quiet, count: 64)))
        #expect(storedStrings(dropped).contains(name) == false)
        #expect(storedStrings(dropped).contains("mode-a") == false)

        let keptRecords = Array(repeating: filler, count: 63).joined(separator: ",") + "," + hidden
        let kept = StepZeroFocusFacts.read(
            assertions: json(#"{"data":[{"storeAssertionRecords":[\#(keptRecords)]}]}"#),
            configurations: json(config("mode-a", name: name, symbol: symbol))
        )
        #expect(kept == .live(Array(repeating: quiet, count: 63) + [fact(true, true, true, true)]))
        #expect(storedStrings(kept).contains(name) == false)

        let numbers = Array(repeating: "1", count: 64).joined(separator: ",")
        let buried = StepZeroFocusFacts.read(
            assertions: json(
                #"{"data":[{"storeAssertionRecords":[\#(numbers),\#(hidden)]}]}"#
            ),
            configurations: json(config("mode-a", name: name, symbol: symbol))
        )
        #expect(buried == .off)
        #expect(storedStrings(buried).contains(name) == false)
        #expect(storedStrings(buried).contains("mode-a") == false)
    }

    @Test func theModeCapDropsAKeyPastSixtyFour() {
        var modes: [String] = []
        for index in 0..<64 {
            let key = String(format: "m%02d", index)
            modes.append(#""\#(key)":{"mode":{"symbolImageName":"\#(symbol)"}}"#)
        }
        modes.append(#""m64":{"mode":{"name":"\#(name)","symbolImageName":"\#(symbol)"}}"#)
        let config = #"{"data":[{"modeConfigurations":{\#(modes.joined(separator: ","))}}]}"#
        let read = StepZeroFocusFacts.read(
            assertions: json(
                """
                {"data":[{"storeAssertionRecords":[\
                {"assertionDetails":{"assertionDetailsModeIdentifier":"m00"}},\
                {"assertionDetails":{"assertionDetailsModeIdentifier":"m64"}}\
                ]}]}
                """
            ),
            configurations: json(config)
        )
        #expect(
            read == .live([
                fact(true, true, false, true),
                fact(true, false, false, false),
            ])
        )
        let stored = storedStrings(read)
        #expect(stored.contains(name) == false)
        #expect(stored.contains(symbol) == false)
        #expect(stored.contains("m64") == false)
        #expect(stored.contains("m00") == false)
    }

    @Test func bytesOverFourMegabytesAreRefusedBeforeAParse() {
        let core = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"kept-id"}}]}]}"#
        var over = Data(core.utf8)
        over.append(Data(repeating: 0x20, count: StepZeroFocusFacts.maxBytes + 1 - over.count))
        #expect(over.count == StepZeroFocusFacts.maxBytes + 1)
        let refused = StepZeroFocusFacts.read(assertions: over, configurations: Data(name.utf8))
        #expect(refused == .tooLarge)
        #expect(storedStrings(refused).contains(name) == false)
        #expect(storedStrings(refused).contains("kept-id") == false)

        var exact = Data(core.utf8)
        exact.append(Data(repeating: 0x20, count: StepZeroFocusFacts.maxBytes - exact.count))
        #expect(exact.count == StepZeroFocusFacts.maxBytes)
        let parsed = StepZeroFocusFacts.read(assertions: exact, configurations: nil)
        #expect(parsed == .live([fact(true, false, false, false)]))
        #expect(storedStrings(parsed).contains("kept-id") == false)

        let configCore = config("mode-a", name: name, symbol: symbol)
        var wide = Data(configCore.utf8)
        wide.append(Data(repeating: 0x20, count: StepZeroFocusFacts.maxBytes + 1 - wide.count))
        #expect(wide.count == StepZeroFocusFacts.maxBytes + 1)
        let unread = StepZeroFocusFacts.read(assertions: json(live("mode-a")), configurations: wide)
        #expect(unread == .live([fact(true, false, false, false)]))
        #expect(storedStrings(unread).contains(name) == false)
        #expect(storedStrings(unread).contains(symbol) == false)
    }

    @Test func aMalformedDocumentIsNotOff() {
        let bad = [
            "not json",
            "[]",
            "{}",
            #"{"data":{}}"#,
            #"{"data":[{"storeAssertionRecords":{}}]}"#,
            #"{"data":[{"storeAssertionRecords":"x"}]}"#,
            "",
        ]
        for text in bad {
            #expect(StepZeroFocusFacts.read(assertions: json(text), configurations: nil) == .malformed)
        }
        let quiet = [
            #"{"data":[]}"#,
            #"{"data":[{}]}"#,
            #"{"data":[{"storeAssertionRecords":[]}]}"#,
            #"{"data":[{"storeAssertionRecords":null}]}"#,
            #"{"data":[1]}"#,
        ]
        for text in quiet {
            #expect(StepZeroFocusFacts.read(assertions: json(text), configurations: nil) == .off)
        }
        let brokenConfig = StepZeroFocusFacts.read(
            assertions: json(live("mode-a")),
            configurations: json("not json")
        )
        #expect(brokenConfig == .live([fact(true, false, false, false)]))
    }

    @Test func anIdentifierOfTwoHundredCharactersIsReadAndThenDropped() {
        let fit = String(repeating: "q", count: 200)
        let over = String(repeating: "q", count: 201)
        let read = StepZeroFocusFacts.read(
            assertions: json(
                """
                {"data":[{"storeAssertionRecords":[\
                {"assertionDetails":{"assertionDetailsModeIdentifier":"\(fit)"}},\
                {"assertionDetails":{"assertionDetailsModeIdentifier":"\(over)"}}\
                ]}]}
                """
            ),
            configurations: json(config(fit, name: name, symbol: symbol))
        )
        #expect(
            read == .live([
                fact(true, true, true, true),
                fact(false, false, false, false),
            ])
        )
        let stored = storedStrings(read)
        #expect(stored.contains(fit) == false)
        #expect(stored.contains(over) == false)
        #expect(stored.contains(name) == false)
        #expect(stored.contains(symbol) == false)
    }

    @Test func aSecondReadStartsEmpty() {
        let first = StepZeroFocusFacts.read(
            assertions: json(live("mode-a")),
            configurations: json(config("mode-a", name: name, symbol: symbol))
        )
        #expect(first == .live([fact(true, true, true, true)]))
        let second = StepZeroFocusFacts.read(
            assertions: json(#"{"data":[{"storeAssertionRecords":[]}]}"#),
            configurations: json(config("mode-a", name: name, symbol: symbol))
        )
        #expect(second == .off)
        let again = StepZeroFocusFacts.read(
            assertions: json(live("mode-a")),
            configurations: json(config("mode-a", name: name, symbol: symbol))
        )
        #expect(again == first)
        #expect(storedStrings(first).isEmpty)
        #expect(storedStrings(second).isEmpty)
        #expect(storedStrings(again).isEmpty)
    }

    private func fact(_ id: Bool, _ key: Bool, _ hasName: Bool, _ hasSymbol: Bool) -> StepZeroFocusFacts.Fact {
        StepZeroFocusFacts.Fact(
            hasModeId: id, idIsConfigKey: key, hasName: hasName, hasSymbol: hasSymbol
        )
    }

    private func live(_ id: String) -> String {
        #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(id)"}}]}]}"#
    }

    private func config(_ id: String, name: String, symbol: String) -> String {
        #"{"data":[{"modeConfigurations":{"\#(id)":{"mode":{"name":"\#(name)","symbolImageName":"\#(symbol)"}}}}]}"#
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func storedStrings(_ read: StepZeroFocusFacts.Read) -> [String] {
        var found: [String] = []
        func walk(_ value: Any) {
            if let text = value as? String {
                found.append(text)
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first {
                    walk(child.value)
                }
                return
            }
            for child in mirror.children {
                walk(child.value)
            }
        }
        walk(read)
        return found
    }
}
