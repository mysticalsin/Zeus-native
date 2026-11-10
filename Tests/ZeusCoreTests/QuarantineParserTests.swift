import Foundation
import Testing
@testable import ZeusCore

@Suite("QuarantineParser")
struct QuarantineParserTests {
    @Test func parsesAirDropQuarantineString() {
        let airDropSharingd = "0081;66512345;sharingd;4890B551-7892-4211-9A4B-346761A4DE5A"
        let parsed = QuarantineParser.parse(airDropSharingd)
        #expect(parsed.flags == "0081")
        #expect(parsed.timestamp == "66512345")
        #expect(parsed.agent == "sharingd")
        #expect(parsed.uuid == "4890B551-7892-4211-9A4B-346761A4DE5A")
        #expect(parsed.isAirDrop == true)
        #expect(QuarantineParser.isAirDrop(airDropSharingd) == true)
    }

    @Test func parsesAppleSharingdAgent() {
        let raw = "0083;66512345;com.apple.sharingd;12345"
        let parsed = QuarantineParser.parse(raw)
        #expect(parsed.agent == "com.apple.sharingd")
        #expect(parsed.isAirDrop == true)
    }

    @Test func parsesAirDropNamedAgent() {
        let raw = "0082;66512345;AirDrop;"
        let parsed = QuarantineParser.parse(raw)
        #expect(parsed.isAirDrop == true)
    }

    @Test func rejectsBrowserDownloads() {
        let safari = "0001;66512345;Safari;A1B2C3D4"
        let chrome = "0002;66512345;Google Chrome;E5F6G7H8"
        let firefox = "0001;66512345;Firefox;"
        let curl = "0001;66512345;curl;"

        #expect(QuarantineParser.isAirDrop(safari) == false)
        #expect(QuarantineParser.isAirDrop(chrome) == false)
        #expect(QuarantineParser.isAirDrop(firefox) == false)
        #expect(QuarantineParser.isAirDrop(curl) == false)
    }

    @Test func handlesMalformedAndEmptyStrings() {
        #expect(QuarantineParser.isAirDrop("") == false)
        #expect(QuarantineParser.isAirDrop(";;;") == false)
        #expect(QuarantineParser.isAirDrop("0081") == false)
        #expect(QuarantineParser.parse("").agent == nil)
    }
}
