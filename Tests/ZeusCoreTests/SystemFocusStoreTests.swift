import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import ZeusCore

@Suite("Focus store") struct SystemFocusStoreTests {
    private let id = "com.apple.focus.work"

    @Test func oneRecordWithAMatchingMode() {
        let reading = parse(
            assertions: """
            {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\(id)"},"assertionStartDateTimestamp":10}]}],"unused":true}
            """,
            configurations: """
            {"data":[{"modeConfigurations":{"\(id)":{"mode":{"name":"Work","symbolImageName":"moon.fill","tintColorName":"blue"}}}}]}
            """
        )
        #expect(reading == .ok(.on(.init(id: id, name: "Work", symbol: "moon.fill"))))
    }

    @Test func anEmptyListAndAnAbsentKeyAreOff() {
        #expect(parse(assertions: #"{"data":[{"storeAssertionRecords":[]}]}"#) == .ok(.off))
        #expect(parse(assertions: #"{"data":[{}]}"#) == .ok(.off))
        #expect(parse(assertions: #"{"data":[]}"#) == .ok(.off))
        #expect(parse(assertions: #"{"data":[1,{"storeAssertionRecords":[]}]}"#) == .ok(.off))
    }

    @Test func theLaterTimestampWinsAndNoTimestampsKeepTheFirst() {
        let later = parse(assertions: """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"early"},"assertionStartDateTimestamp":1},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"late"},"assertionStartDateTimestamp":9}
        ]}]}
        """)
        #expect(later == .ok(.on(.init(id: "late"))))

        let tie = parse(assertions: """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"first"},"assertionStartDateTimestamp":4},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"second"},"assertionStartDateTimestamp":4}
        ]}]}
        """)
        #expect(tie == .ok(.on(.init(id: "first"))))

        let none = parse(assertions: """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"first"}},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"second"}}
        ]}]}
        """)
        #expect(none == .ok(.on(.init(id: "first"))))

        let stampedBeatsPlain = parse(assertions: """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"plain"}},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"stamped"},"assertionStartDateTimestamp":1}
        ]}]}
        """)
        #expect(stampedBeatsPlain == .ok(.on(.init(id: "stamped"))))
    }

    @Test func aRecordWithNoIdDoesNotHideAGoodOne() {
        let reading = parse(assertions: """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"good"},"assertionStartDateTimestamp":1},
          {"assertionDetails":{},"assertionStartDateTimestamp":50},
          {"assertionStartDateTimestamp":80},
          "not-a-record",
          {"assertionDetails":{"assertionDetailsModeIdentifier":""},"assertionStartDateTimestamp":90},
          {"assertionDetails":{"assertionDetailsModeIdentifier":"\(String(repeating: "a", count: 201))"},"assertionStartDateTimestamp":100}
        ]}]}
        """)
        #expect(reading == .ok(.on(.init(id: "good"))))

        let exact = String(repeating: "b", count: 200)
        #expect(parse(assertions: """
        {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\(exact)"}}]}]}
        """) == .ok(.on(.init(id: exact))))
    }

    @Test func recordsWithNoUsableIdAreOnWithoutAName() {
        let reading = parse(assertions: """
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":""}},
          {"assertionDetails":{"assertionDetailsModeIdentifier":12}},
          {"assertionDetails":{}},
          4
        ]}]}
        """)
        #expect(reading == .ok(.on(.init())))
        if case .unreadable = reading {
            Issue.record("a record without an id must not be unreadable")
        }
    }

    @Test func aSystemRaisedRecordResolvesLikeAnyOther() {
        let reading = parse(
            assertions: """
            {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\(id)","assertionDetailsReason":"system-state"},"assertionStartDateTimestamp":3}]}]}
            """,
            configurations: modeJSON(id: id, name: "Work", symbol: "moon.fill")
        )
        #expect(reading == .ok(.on(.init(id: id, name: "Work", symbol: "moon.fill"))))
    }

    @Test func historyListsAloneAreOff() {
        let reading = parse(assertions: """
        {"data":[{"storeAssertionRecordsHistory":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\(id)"},"assertionStartDateTimestamp":9}]}]}
        """)
        #expect(reading == .ok(.off))
    }

    @Test func aMissingOrBadConfigurationsFileLeavesTheNameNil() {
        let assertions = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(id)"}}]}]}"#
        #expect(parse(assertions: assertions, configurations: nil) == .ok(.on(.init(id: id))))
        #expect(parse(assertions: assertions, configurations: "{") == .ok(.on(.init(id: id))))
        #expect(parse(assertions: assertions, configurations: "[]") == .ok(.on(.init(id: id))))
        #expect(parse(assertions: assertions, configurations: #"{"data":[]}"#) == .ok(.on(.init(id: id))))
        #expect(parse(assertions: assertions, configurations: #"{"data":[{}]}"#) == .ok(.on(.init(id: id))))
        #expect(parse(assertions: assertions, configurations: #"{"data":[{"modeConfigurations":{"other":{"mode":{"name":"Other","symbolImageName":"moon"}}}}]}"#) == .ok(.on(.init(id: id))))
        let onlyOnTheSecond = """
        {"data":[{},{"modeConfigurations":{"\(id)":{"mode":{"name":"Work","symbolImageName":"moon.fill"}}}}]}
        """
        #expect(parse(assertions: assertions, configurations: onlyOnTheSecond) == .ok(.on(.init(id: id))))
    }

    @Test func oneBadModeDoesNotHideAGoodOne() {
        let reading = parse(
            assertions: #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"good"}}]}]}"#,
            configurations: """
            {"data":[{"modeConfigurations":{"bad":"nope","good":{"mode":{"name":"Work","symbolImageName":"moon.fill"}},"also":[1,2]}}]}
            """
        )
        #expect(reading == .ok(.on(.init(id: "good", name: "Work", symbol: "moon.fill"))))
    }

    @Test func pastSixtyFourModesTheRestAreUnread() {
        var modes: [String: Any] = [:]
        for index in 0..<65 {
            let key = String(format: "k%02d", index)
            modes[key] = ["mode": ["name": "Name\(index)", "symbolImageName": "moon.fill"]]
        }
        let body: [String: Any] = ["data": [["modeConfigurations": modes]]]
        guard let configurations = try? JSONSerialization.data(withJSONObject: body) else {
            Issue.record("the fixture must encode")
            return
        }
        let kept = parse(
            assertions: #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"k00"}}]}]}"#,
            configurations: configurations
        )
        #expect(kept == .ok(.on(.init(id: "k00", name: "Name0", symbol: "moon.fill"))))
        let dropped = parse(
            assertions: #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"k64"}}]}]}"#,
            configurations: configurations
        )
        #expect(dropped == .ok(.on(.init(id: "k64"))))
    }

    @Test func extraKeysAreIgnoredAndANumericNameIsNil() {
        let reading = parse(
            assertions: #"{"extra":1,"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(id)"},"unused":true}]}]}"#,
            configurations: """
            {"data":[{"modeConfigurations":{"\(id)":{"mode":{"name":12,"symbolImageName":"moon.fill","tintColorName":"blue"},"other":false}}}]}
            """
        )
        #expect(reading == .ok(.on(.init(id: id, name: nil, symbol: "moon.fill"))))
    }

    @Test func namesAreCleanedAndBounded() {
        #expect(SystemFocusText.cleanName("  Work   Focus  ") == "Work Focus")
        #expect(SystemFocusText.cleanName("Work\u{00A0}Focus") == "Work Focus")
        #expect(SystemFocusText.cleanName("   ") == nil)
        #expect(SystemFocusText.cleanName("\u{0007}Work") == "Work")
        #expect(SystemFocusText.cleanName("\u{202E}Work") == "Work")
        #expect(SystemFocusText.cleanName("\u{2066}Work\u{2069}") == "Work")
        #expect(SystemFocusText.cleanName("Wo\u{200B}rk") == "Work")
        #expect(SystemFocusText.cleanName("Work\nFocus") == "WorkFocus")
        #expect(SystemFocusText.cleanName("Work\u{2028}Focus") == "WorkFocus")
        #expect(SystemFocusText.cleanName("A\u{200D}B") == "AB")
        #expect(SystemFocusText.cleanName("👨‍👩‍👧") == "👨‍👩‍👧")
        #expect(SystemFocusText.cleanName("🇯🇵") == "🇯🇵")
        let cjk = String(repeating: "焦", count: 20)
        #expect(SystemFocusText.cleanName(cjk) == cjk)
        let long = String(repeating: "a", count: 10_000)
        #expect(SystemFocusText.cleanName(long) == String(repeating: "a", count: 64))
        let flag = "🇯🇵"
        let sixtyThree = String(repeating: "a", count: 63) + flag
        #expect(SystemFocusText.cleanName(sixtyThree) == sixtyThree)
        let sixtyFour = String(repeating: "a", count: 64) + flag
        #expect(SystemFocusText.cleanName(sixtyFour) == String(repeating: "a", count: 64))
        #expect(SystemFocusText.cleanName(sixtyFour)?.contains("🇯") == false)

        let cleaned = parse(
            assertions: #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"\#(id)"}}]}]}"#,
            configurations: modeJSON(id: id, name: "  Work  ", symbol: "moon.fill")
        )
        #expect(cleaned == .ok(.on(.init(id: id, name: "Work", symbol: "moon.fill"))))
    }

    @Test func symbolsKeepTheClosedAlphabet() {
        #expect(SystemFocusText.cleanSymbol("moon.fill") == "moon.fill")
        #expect(SystemFocusText.cleanSymbol(String(repeating: "a", count: 64)) == String(repeating: "a", count: 64))
        #expect(SystemFocusText.cleanSymbol(String(repeating: "a", count: 65)) == nil)
        #expect(SystemFocusText.cleanSymbol("") == nil)
        #expect(SystemFocusText.cleanSymbol("../x") == nil)
        #expect(SystemFocusText.cleanSymbol("Moon Fill") == nil)
        #expect(SystemFocusText.cleanSymbol("Moon.fill") == nil)
        #expect(SystemFocusText.cleanSymbol("moon fill") == nil)
        #expect(SystemFocusText.cleanSymbol("moon-fill") == nil)
    }

    @Test func aFileOverTheCapIsUnreadableBeforeDecode() {
        let over = Data(count: SystemFocusStore.maxBytes + 1)
        #expect(SystemFocusStore.parse(assertions: over, configurations: nil) == .unreadable(.tooLarge))
        let small = Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)
        #expect(SystemFocusStore.parse(assertions: small, configurations: over) == .unreadable(.tooLarge))
        let exact = Data(count: SystemFocusStore.maxBytes)
        #expect(SystemFocusStore.parse(assertions: exact, configurations: nil) == .unreadable(.malformed))
    }

    @Test func aBadShapeIsMalformed() {
        #expect(parse(assertions: "not json") == .unreadable(.malformed))
        #expect(parse(assertions: "[]") == .unreadable(.malformed))
        #expect(parse(assertions: "12") == .unreadable(.malformed))
        #expect(parse(assertions: #"{"storeAssertionRecords":[]}"#) == .unreadable(.malformed))
        #expect(parse(assertions: #"{"data":{}}"#) == .unreadable(.malformed))
        #expect(parse(assertions: #"{"data":[{"storeAssertionRecords":"no"}]}"#) == .unreadable(.malformed))
        #expect(parse(assertions: "") == .unreadable(.malformed))
    }

    @Test func aScheduleWithoutARecordIsOff() {
        let reading = parse(assertions: """
        {"data":[{"storeAssertionRecords":[],"triggers":[{"enabled":true,"hour":9,"minute":0}]}]}
        """)
        #expect(reading == .ok(.off))
    }

    @Test func everyErrnoMapsForEachPlace() {
        #expect(SystemFocusStore.read(forErrno: EPERM, at: .folder) == .denied)
        #expect(SystemFocusStore.read(forErrno: EACCES, at: .folder) == .denied)
        #expect(SystemFocusStore.read(forErrno: ENOENT, at: .folder) == .missing)
        #expect(SystemFocusStore.read(forErrno: ENOTDIR, at: .folder) == .unreadable(.notAFile))
        #expect(SystemFocusStore.read(forErrno: ELOOP, at: .folder) == .unreadable(.notAFile))
        #expect(SystemFocusStore.read(forErrno: EIO, at: .folder) == .unreadable(.other))
        #expect(SystemFocusStore.read(forErrno: 0, at: .folder) == .unreadable(.other))

        #expect(SystemFocusStore.read(forErrno: EPERM, at: .assertions) == .denied)
        #expect(SystemFocusStore.read(forErrno: EACCES, at: .assertions) == .denied)
        #expect(SystemFocusStore.read(forErrno: ENOENT, at: .assertions) == .ok(.off))
        #expect(SystemFocusStore.read(forErrno: ELOOP, at: .assertions) == .unreadable(.notAFile))
        #expect(SystemFocusStore.read(forErrno: ENOTDIR, at: .assertions) == .unreadable(.other))
        #expect(SystemFocusStore.read(forErrno: EIO, at: .assertions) == .unreadable(.other))

        let empty = SystemFocusStore.Read.ok(.on(.init()))
        for code in [EPERM, EACCES, ENOENT, ENOTDIR, ELOOP, EIO, Int32(0), Int32(999)] {
            let answer = SystemFocusStore.read(forErrno: code, at: .configurations)
            #expect(answer == empty)
            #expect(answer != .denied)
            #expect(answer != .missing)
            #expect(answer != .unreadable(.other))
        }
    }

    private func parse(assertions: String, configurations: String? = nil) -> SystemFocusStore.Read {
        SystemFocusStore.parse(assertions: Data(assertions.utf8), configurations: configurations.map { Data($0.utf8) })
    }

    private func parse(assertions: String, configurations: Data) -> SystemFocusStore.Read {
        SystemFocusStore.parse(assertions: Data(assertions.utf8), configurations: configurations)
    }

    private func modeJSON(id: String, name: String, symbol: String) -> String {
        #"{"data":[{"modeConfigurations":{"\#(id)":{"mode":{"name":"\#(name)","symbolImageName":"\#(symbol)"}}}}]}"#
    }
}
