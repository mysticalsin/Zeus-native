import Foundation
import Testing
@testable import ZeusCore

@Suite struct StepZeroCodecTests {
    @Test func aReportRoundTrips() {
        var report = stepZeroReport(version: "27.1", answers: [
            stepZeroAnswer("P1", "yes", [
                "p1.itemSeen": .flag(true),
                "p1.fields": .codes([ProbeCode("present")]),
                "p1.ownerSaysPlaying": .flag(false),
            ]),
            stepZeroAnswer("P4", "yes", [
                "p4.missing": .codes([]),
                "p4.pollCpuMs": .milliseconds(0),
            ]),
            stepZeroAnswer("L3", "notMeasured", [
                "l3.keyEventsReached": .count(1_000_000),
            ]),
            stepZeroAnswer("P2", "no", [
                "p2.plainSeen": .flag(false),
                "p2.gate": .code(ProbeCode("absent")),
            ]),
        ])
        report.systemBuild = ProbeTag.accept(.systemBuild, "24A335a")
        report.systemHardware = ProbeTag.accept(.systemHardware, "MacBookPro18,3")
        report.zeusVersion = ProbeTag.accept(.zeusVersion, "1.2.10")
        report.buildStamp = ProbeTag.accept(.buildStamp, "20261125000000-7")
        report.signing = ProbeCode("developerID")
        report.hardenedRuntime = true
        report.sections = [
            StepZeroSection(id: ProbeCode("P"), state: ProbeCode("done")),
            StepZeroSection(id: ProbeCode("L"), state: ProbeCode("partial")),
        ]
        report.restored = [StepZeroRestore(what: ProbeCode("playState"), ok: ProbeCode("unknown"))]
        report.notPutBack = [ProbeCode("skipCount")]
        report.grantsAtStart = [StepZeroGrantReading(grant: ProbeCode("localNetwork"), state: ProbeCode("unknown"))]
        report.leftOn = [ProbeCode("bluetooth")]
        report.takenOff = [ProbeCode("fullDiskAccess")]
        report = sealed(report)
        let data = StepZeroCodec.encode(report)
        #expect(data != nil)
        #expect(StepZeroCodec.decode(data!) == report)
    }

    @Test func eachRefusalDropsTheWholeFile() {
        let text = encoded(stepZeroReport(answers: [
            stepZeroAnswer("P1", "yes", ["p1.itemSeen": .flag(true)]),
            stepZeroAnswer("P2", "yes", ["p2.gate": .code(ProbeCode("present"))]),
            stepZeroAnswer("L4", "yes", ["l4.cycles": .count(1_000_000)]),
        ]))
        #expect(StepZeroCodec.decode(Data(text.replacing("\"version\":1", with: "\"version\":2").utf8)) == nil)
        #expect(StepZeroCodec.decode(Data(text.replacing("\"q\":\"P1\"", with: "\"q\":\"P99\"").utf8)) == nil)
        #expect(StepZeroCodec.decode(Data(text.replacing("\"p1.itemSeen\":true", with: "\"p1.itemSeen\":\"yes\"").utf8)) == nil)
        #expect(StepZeroCodec.decode(Data(text.replacing("\"present\"", with: "\"hello\"").utf8)) == nil)
        #expect(StepZeroCodec.decode(Data(text.replacing("1000000", with: "1000001").utf8)) == nil)
        #expect(StepZeroCodec.decode(Data(text.replacing("1000000", with: "-1").utf8)) == nil)
        #expect(StepZeroCodec.decode(Data(count: StepZeroCodec.maxBytes + 1)) == nil)
    }

    @Test func aRuntimeStringCannotBecomeAValue() {
        let title = ["Now", " ", "Playing"].joined()
        let samples: [ProbeValue] = [
            .flag(false),
            .count(0),
            .milliseconds(1),
            .code(ProbeCode("yes")),
            .codes([ProbeCode("no")]),
        ]
        for sample in samples {
            switch sample {
            case .flag, .count, .milliseconds, .code, .codes:
                #expect(String(describing: sample).contains(title) == false)
            }
        }
        #expect(ProbeTag.accept(.systemVersion, title).text == nil)
    }

    @Test func badTagTextIsWithheldAndGoodTagTextPasses() {
        let bad = [
            ["Now", " ", "Playing"].joined(),
            "0123456789ab",
            "C02ABC12DEFG",
            "Mac Book",
        ]
        let good: [(ProbeTag.Field, String)] = [
            (.systemVersion, "27.1"),
            (.systemBuild, "24A335a"),
            (.systemHardware, "MacBookPro18,3"),
            (.zeusVersion, "1.2.10"),
            (.buildStamp, "20261125000000-7"),
        ]
        for (field, raw) in good {
            let tag = ProbeTag.accept(field, raw)
            #expect(tag.text == raw)
            for sample in bad {
                let withheld = ProbeTag.accept(field, sample)
                #expect(withheld.text == nil)
                var report = stepZeroReport()
                switch field {
                case .systemVersion: report.systemVersion = withheld
                case .systemBuild: report.systemBuild = withheld
                case .systemHardware: report.systemHardware = withheld
                case .zeusVersion: report.zeusVersion = withheld
                case .buildStamp: report.buildStamp = withheld
                }
                let data = StepZeroCodec.encode(sealed(report))!
                #expect(String(decoding: data, as: UTF8.self).contains(sample) == false)
            }
        }
    }
}

private func encoded(_ report: StepZeroReport) -> String {
    let data = StepZeroCodec.encode(sealed(report))!
    return String(decoding: data, as: UTF8.self)
}
