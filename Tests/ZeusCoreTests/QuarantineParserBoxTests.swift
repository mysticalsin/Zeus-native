import Foundation
import Testing
@testable import ZeusCore

@Suite("Quarantine parser box")
struct QuarantineParserBoxTests {
    @Test func sharingdKeepsEachField() {
        let raw = "0081;66512345;sharingd;4890B551-7892-4211-9A4B-346761A4DE5A"
        let fields = QuarantineParserBox.fields(raw)
        #expect(fields.flags == "0081")
        #expect(fields.timestamp == "66512345")
        #expect(fields.agent == "sharingd")
        #expect(fields.uuid == "4890B551-7892-4211-9A4B-346761A4DE5A")
        #expect(QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func appleSharingdIsAirDrop() {
        let fields = QuarantineParserBox.fields("0083;66512345;com.apple.sharingd;12345")
        #expect(fields.agent == "com.apple.sharingd")
        #expect(fields.uuid == "12345")
        #expect(QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func anAirDropNameDropsAnEmptyUuid() {
        let fields = QuarantineParserBox.fields("0082;66512345;AirDrop;")
        #expect(fields.flags == "0082")
        #expect(fields.timestamp == "66512345")
        #expect(fields.agent == "AirDrop")
        #expect(fields.uuid == nil)
        #expect(QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func aBrowserDownloadIsNotAirDrop() {
        let safari = QuarantineParserBox.fields("0001;66512345;Safari;A1B2C3D4")
        let chrome = QuarantineParserBox.fields("0002;66512345;Google Chrome;E5F6G7H8")
        let firefox = QuarantineParserBox.fields("0001;66512345;Firefox;")
        let curl = QuarantineParserBox.fields("0001;66512345;curl;")
        #expect(safari.agent == "Safari")
        #expect(chrome.agent == "Google Chrome")
        #expect(firefox.uuid == nil)
        #expect(curl.agent == "curl")
        #expect(!QuarantineParserBox.isAirDrop(agent: safari.agent))
        #expect(!QuarantineParserBox.isAirDrop(agent: chrome.agent))
        #expect(!QuarantineParserBox.isAirDrop(agent: firefox.agent))
        #expect(!QuarantineParserBox.isAirDrop(agent: curl.agent))
    }

    @Test func anEmptyStringHasNoFields() {
        let fields = QuarantineParserBox.fields("")
        #expect(fields.flags == "")
        #expect(fields.timestamp == nil)
        #expect(fields.agent == nil)
        #expect(fields.uuid == nil)
        #expect(!QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func semicolonsAloneHaveNoFields() {
        let fields = QuarantineParserBox.fields(";;;")
        #expect(fields.flags == "")
        #expect(fields.timestamp == nil)
        #expect(fields.agent == nil)
        #expect(fields.uuid == nil)
        #expect(!QuarantineParserBox.isAirDrop(agent: nil))
    }

    @Test func flagsAloneHaveNoAgent() {
        let fields = QuarantineParserBox.fields("0081")
        #expect(fields.flags == "0081")
        #expect(fields.timestamp == nil)
        #expect(fields.agent == nil)
        #expect(fields.uuid == nil)
        #expect(!QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func aFifthFieldIsIgnored() {
        let fields = QuarantineParserBox.fields("a;b;c;d;e")
        #expect(fields.flags == "a")
        #expect(fields.timestamp == "b")
        #expect(fields.agent == "c")
        #expect(fields.uuid == "d")
        #expect(!QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func emptyMiddleFieldsAreAbsent() {
        let fields = QuarantineParserBox.fields(";;sharingd;")
        #expect(fields.flags == "")
        #expect(fields.timestamp == nil)
        #expect(fields.agent == "sharingd")
        #expect(fields.uuid == nil)
        #expect(QuarantineParserBox.isAirDrop(agent: fields.agent))
    }

    @Test func theAgentMatchIgnoresCase() {
        #expect(QuarantineParserBox.fields("0081;1;SharingD;u").agent == "SharingD")
        #expect(QuarantineParserBox.isAirDrop(agent: "SharingD"))
        #expect(QuarantineParserBox.isAirDrop(agent: "AIRDROP"))
        #expect(QuarantineParserBox.isAirDrop(agent: "Com.Apple.SharingD"))
    }

    @Test func aNameThatContainsTheWordIsAirDrop() {
        #expect(QuarantineParserBox.fields("1;2;helper-sharingd;3").agent == "helper-sharingd")
        #expect(QuarantineParserBox.isAirDrop(agent: "helper-sharingd"))
        #expect(QuarantineParserBox.isAirDrop(agent: "preAirDrop"))
        #expect(QuarantineParserBox.isAirDrop(agent: "AirDrop.framework"))
    }

    @Test func aNearMissIsNotAirDrop() {
        #expect(QuarantineParserBox.fields("1;2;sharing;3").agent == "sharing")
        #expect(!QuarantineParserBox.isAirDrop(agent: "sharing"))
        #expect(!QuarantineParserBox.isAirDrop(agent: "air"))
        #expect(!QuarantineParserBox.isAirDrop(agent: "drop"))
        #expect(!QuarantineParserBox.isAirDrop(agent: " share "))
    }

    @Test func surroundingSpaceStaysInTheAgent() {
        let fields = QuarantineParserBox.fields("0081;9; sharingd ;uuid")
        #expect(fields.agent == " sharingd ")
        #expect(fields.uuid == "uuid")
        #expect(QuarantineParserBox.isAirDrop(agent: fields.agent))
        let blank = QuarantineParserBox.fields("0081;9; ;uuid")
        #expect(blank.agent == " ")
        #expect(!QuarantineParserBox.isAirDrop(agent: blank.agent))
    }

    @Test func thePublicParserReadsTheBox() {
        let samples = [
            "0081;66512345;sharingd;4890B551-7892-4211-9A4B-346761A4DE5A",
            "0001;66512345;Safari;A1B2C3D4",
            "",
            ";;;",
            "0082;66512345;AirDrop;",
            "a;b;c;d;e",
        ]
        for raw in samples {
            let fields = QuarantineParserBox.fields(raw)
            let parsed = QuarantineParser.parse(raw)
            #expect(parsed.raw == raw)
            #expect(parsed.flags == fields.flags)
            #expect(parsed.timestamp == fields.timestamp)
            #expect(parsed.agent == fields.agent)
            #expect(parsed.uuid == fields.uuid)
            #expect(parsed.isAirDrop == QuarantineParserBox.isAirDrop(agent: fields.agent))
            #expect(QuarantineParser.isAirDrop(raw) == parsed.isAirDrop)
        }
    }
}
