import Foundation
import Testing
@testable import ZeusCore

@Suite("Output routes box")
struct OutputRoutesBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(OutputRoutesBox.blankScalars.contains(" "))
        #expect(OutputRoutesBox.blankScalars.contains("\t"))
        #expect(OutputRoutesBox.blankScalars.contains("\n"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{000B}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{000C}"))
        #expect(OutputRoutesBox.blankScalars.contains("\r"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{0085}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{00A0}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{1680}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{2000}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{200A}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{2028}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{2029}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{202F}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{205F}"))
        #expect(OutputRoutesBox.blankScalars.contains("\u{3000}"))
        #expect(!OutputRoutesBox.blankScalars.contains("\u{200B}"))
        #expect(OutputRoutesBox.trimmedStatus("\u{200B}") == "\u{200B}")
        #expect(OutputRoutesBox.trimmedStatus(" \u{200B} ") == "\u{200B}")
        #expect(OutputRoutesBox.trimmedStatus(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aStatusOfOnlyNamedBlanksIsEmpty() {
        #expect(OutputRoutesBox.trimmedStatus("") == "")
        #expect(OutputRoutesBox.trimmedStatus(" \t\n\r") == "")
        #expect(OutputRoutesBox.trimmedStatus("\u{00A0}") == "")
        #expect(OutputRoutesBox.trimmedStatus("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(OutputRoutesBox.trimmedStatus("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheStatus() {
        #expect(OutputRoutesBox.trimmedStatus("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(OutputRoutesBox.trimmedStatus("\u{200B}current") == "\u{200B}current")
        #expect(OutputRoutesBox.trimmedStatus("current\u{200B}") == "current\u{200B}")
        #expect(OutputRoutesBox.trimmedStatus(" \ncurrent\t") == "current")
    }

    @Test func aZeroWidthStatusStaysSpoken() {
        let route = airPods
        #expect(OutputRouteRules.spokenValue(for: route, status: "\u{200B}") == "Bluetooth, \u{200B}")
        #expect(OutputRouteRules.spokenValue(for: route, status: " \u{200B}\n") == "Bluetooth, \u{200B}")
        #expect(OutputRouteRules.spokenValue(for: route, status: "\u{200B}current") == "Bluetooth, \u{200B}current")
    }

    @Test func namedBlanksLeaveTheTransportWordAndARealStatusStays() {
        let route = airPods
        #expect(OutputRouteRules.spokenValue(for: route, status: "\u{00A0}") == "Bluetooth")
        #expect(OutputRouteRules.spokenValue(for: route, status: " \t\n") == "Bluetooth")
        #expect(OutputRouteRules.spokenValue(for: route, status: " current ") == "Bluetooth, current")
        #expect(OutputRouteRules.spokenValue(for: route, status: "\u{200B}") == "Bluetooth, \u{200B}")
    }

    private var airPods: OutputRoute {
        OutputRoute(
            uid: "b", objectID: 1, name: "AirPods", transport: .bluetooth, symbol: "airpods", isCurrent: true
        )
    }
}
