import Testing
@testable import ZeusCore

@Suite("Step zero helper line")
struct StepZeroHelperLineTests {
    @Test func eachCommandShape() {
        #expect(StepZeroHelperLine.decode("read") == .read)
        #expect(StepZeroHelperLine.decode("seek") == .seek)
        #expect(StepZeroHelperLine.decode("cmd 0") == .cmd(0))
        #expect(StepZeroHelperLine.decode("cmd 1") == .cmd(1))
        #expect(StepZeroHelperLine.decode("cmd 4") == .cmd(4))
        #expect(StepZeroHelperLine.decode("cmd 5") == .cmd(5))
        #expect(StepZeroHelperLine.decode("token a") == .token("a"))
        #expect(StepZeroHelperLine.decode("token abcdef0123456789") == .token("abcdef0123456789"))
        #expect(StepZeroHelperLine.decode("poll 0") == .poll(0))
        #expect(StepZeroHelperLine.decode("poll 30") == .poll(30))
        #expect(StepZeroHelperLine.decode("poll 1000000") == .poll(1_000_000))
    }

    @Test func eachAnswerShape() {
        #expect(StepZeroHelperLine.decode("yes") == .yes)
        #expect(StepZeroHelperLine.decode("no") == .no)
        #expect(StepZeroHelperLine.decode("none") == .nothing)
        #expect(StepZeroHelperLine.decode("missing 0") == .missing(0))
        #expect(StepZeroHelperLine.decode("missing 12") == .missing(12))
        #expect(StepZeroHelperLine.decode("cpu 30") == .cpu(30))
        #expect(StepZeroHelperLine.decode("elapsed 21") == .elapsed(21))
        #expect(StepZeroHelperLine.decode("rate 0") == .rate(0))
        #expect(StepZeroHelperLine.decode("rate 2") == .rate(2))
        #expect(StepZeroHelperLine.decode("playing yes") == .playing(true))
        #expect(StepZeroHelperLine.decode("playing no") == .playing(false))
        #expect(StepZeroHelperLine.decode("title yes") == .title(true))
        #expect(StepZeroHelperLine.decode("title no") == .title(false))
        #expect(StepZeroHelperLine.decode("same yes") == .same(true))
        #expect(StepZeroHelperLine.decode("same no") == .same(false))
        #expect(StepZeroHelperLine.decode("notify yes") == .notify(true))
        #expect(StepZeroHelperLine.decode("notify no") == .notify(false))
        #expect(StepZeroHelperLine.decode("seen yes") == .seen(true))
        #expect(StepZeroHelperLine.decode("seen no") == .seen(false))
        for kind in StepZeroHelperLine.AppClass.allCases {
            #expect(StepZeroHelperLine.decode("class \(kind.rawValue)") == .appClass(kind))
        }
        for kind in StepZeroHelperLine.Art.allCases {
            #expect(StepZeroHelperLine.decode("art \(kind.rawValue)") == .art(kind))
        }
        for kind in StepZeroHelperLine.Gate.allCases {
            #expect(StepZeroHelperLine.decode("gate \(kind.rawValue)") == .gate(kind))
        }
        for kind in StepZeroHelperLine.BundleCall.allCases {
            #expect(StepZeroHelperLine.decode("call \(kind.rawValue)") == .bundleCall(kind))
        }
        for kind in StepZeroHelperLine.Field.allCases {
            #expect(StepZeroHelperLine.decode("field \(kind.rawValue)") == .field(kind))
        }
    }

    @Test func aLetterOutsideTheClosedWordsIsBad() {
        let refused = [
            "hello",
            "YES",
            "Yes",
            "playing maybe",
            "playing Yes",
            "token zz",
            "token AB",
            "token abcG",
            "class music",
            "art gif",
            "gate none",
            "call absent",
            "field name",
            "cmd 2",
            "cmd 3",
            "cmd 6",
            "cmd 01",
            "cmd -1",
            "cmd",
            "seek 21",
            "poll",
            "poll -1",
            "token",
            "missing 00",
            "missing 1000001",
            "rate 01",
            "cpu 0001",
            "read now",
            "yes please",
            "none extra",
            "",
            " ",
            " yes",
            "yes ",
            "playing  yes",
            "yes\n",
            "playing\tyes",
            "token a b",
            "class other extra",
        ]
        for line in refused {
            #expect(StepZeroHelperLine.decode(line) == nil)
        }
    }

    @Test func aLinePast256BytesIsBadAndAFullLineOfHexIsKept() {
        let held = "token " + String(repeating: "a", count: 250)
        #expect(held.utf8.count == 256)
        #expect(StepZeroHelperLine.decode(held) == .token(String(repeating: "a", count: 250)))
        let oversized = "token " + String(repeating: "a", count: 251)
        #expect(oversized.utf8.count == 257)
        #expect(StepZeroHelperLine.decode(oversized) == nil)
        let letters = String(repeating: "a", count: 256)
        #expect(letters.utf8.count == 256)
        #expect(StepZeroHelperLine.decode(letters) == nil)
    }
}
