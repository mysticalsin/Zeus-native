import Testing
@testable import Zeus

@Suite("Step zero battery probe")
struct EarbudsBatteryProbeTests {
    private let probe = EarbudsBatteryProbe.self

    @Test func fourNamesShareOneStemAndKeepNoBlank() {
        let names = probe.Key.allCases.map { probe.name($0) }
        #expect(probe.Key.allCases == [.left, .right, .budCase, .single])
        #expect(Set(names).count == 4)
        let stem = commonPrefix(names)
        #expect(stem.count == 14)
        #expect(stem.allSatisfy { $0.isASCII && $0.isLetter })
        #expect(stem.first == "b")
        #expect(stem.last == "t")
        #expect(probe.name(.left) == stem + "Left")
        #expect(probe.name(.right) == stem + "Right")
        #expect(probe.name(.budCase) == stem + "Case")
        #expect(probe.name(.single) == stem + "Single")
        #expect(names.allSatisfy { name in
            !name.contains(" ") && !name.contains("\n") && !name.contains("\0") && !name.contains("/")
        })
        #expect(probe.name(.left) != probe.Key.left.rawValue)
        #expect(probe.name(.left) == probe.name(.left))
    }

    @Test func encodingsOutsideTheIntegerTableStayClosed() {
        #expect(probe.returnType(encoding: nil) == .none)
        #expect(probe.returnType(encoding: "") == .none)
        for scalar in ["c", "i", "s", "l", "q", "C", "I", "S", "L", "Q"] {
            #expect(probe.returnType(encoding: scalar + "16@0:8") == .integer)
        }
        #expect(probe.returnType(encoding: "ri16@0:8") == .integer)
        #expect(probe.returnType(encoding: "rnrnri") == .integer)
        #expect(probe.returnType(encoding: "V@") == .object)
        #expect(probe.returnType(encoding: "@16@0:8") == .object)
        #expect(probe.returnType(encoding: "@\"NSNumber\"16@0:8") == .object)
        #expect(probe.returnType(encoding: "@?16@0:8") == .other)
        #expect(probe.returnType(encoding: "r@?") == .other)
        for other in ["f16@0:8", "d16@0:8", "B16@0:8", "^q16@0:8", "v16@0:8", "{Int=i}", "[4i]", "b1", "*", ":", "#", "?", " q", "r"] {
            #expect(probe.returnType(encoding: other) == .other)
        }
        let exact = String(repeating: "i", count: probe.maxEncodingBytes)
        let over = String(repeating: "i", count: probe.maxEncodingBytes + 1)
        #expect(probe.returnType(encoding: exact) == .integer)
        #expect(probe.returnType(encoding: over) == .other)
        #expect(probe.returnType(encoding: "q\0") == .other)
        #expect(probe.returnType(encoding: "q\n") == .other)
        #expect(probe.returnType(encoding: "q\r") == .other)
    }

    @Test func routeOpensOnlyForLeftOrSingleAndOnlyWhenAllowed() {
        let tally = Tally()
        #expect(probe.routeOpen(allowed: false) {
            tally.route += 1
            return (left: true, single: true)
        } == false)
        #expect(tally.route == 0)
        #expect(probe.routeOpen(allowed: true) {
            tally.route += 1
            return (left: true, single: false)
        })
        #expect(probe.routeOpen(allowed: true) { (left: false, single: true) })
        #expect(probe.routeOpen(allowed: true) { (left: true, single: true) })
        #expect(probe.routeOpen(allowed: true) { (left: false, single: false) } == false)
        #expect(tally.route == 1)
        let again = probe.routeOpen(allowed: true) { (left: false, single: false) }
        #expect(again == false)
    }

    @Test func aRefusedGrantDoesNotAskForSlots() {
        let tally = Tally()
        let refused = probe.read(allowed: false) {
            tally.slots += 1
            return [.left: slot(tally, payload: .value(.number(80)))]
        }
        #expect(refused == .refused)
        #expect(tally.slots == 0)
        #expect(tally.encoding == 0)
        #expect(tally.payload == 0)
    }

    @Test func aMissingClassDoesNotReadTheEncodingOrTheValue() {
        let tally = Tally()
        let read = probe.read(allowed: true) {
            tally.slots += 1
            return [
                .left: slot(tally, classResponds: false, encoding: "q24@0:8", payload: .value(.number(80))),
                .right: slot(tally, classResponds: true, encoding: nil, payload: .value(.number(1))),
            ]
        }
        guard case .parts(let parts) = read else {
            Issue.record("expected four parts")
            return
        }
        #expect(parts.map(\.key) == [.left, .right, .budCase, .single])
        #expect(parts[0].returnType == .none)
        #expect(parts[0].answering == false)
        #expect(parts[0].classResponds == false)
        #expect(parts[0].instanceResponds == false)
        #expect(parts[0].valueClass == nil)
        #expect(parts[0].level == nil)
        #expect(parts[1].returnType == .none)
        #expect(parts[1].answering == false)
        #expect(parts[1].valueClass == nil)
        #expect(parts[2].returnType == .none)
        #expect(parts[3].returnType == .none)
        #expect(parts[2].name == probe.name(.budCase))
        #expect(tally.slots == 1)
        #expect(tally.encoding == 1)
        #expect(tally.payload == 0)
    }

    @Test func onlyAnIntegerOnARespondingInstanceIsRead() {
        let tally = Tally()
        let read = probe.read(allowed: true) {
            [
                .left: slot(tally, encoding: "@16@0:8", payload: .value(.number(80))),
                .right: slot(tally, encoding: "f16@0:8", payload: .value(.number(80))),
                .budCase: slot(tally, instanceResponds: false, encoding: "q24@0:8", payload: .value(.number(80))),
                .single: slot(tally, encoding: "q24@0:8", payload: .value(.number(80))),
            ]
        }
        guard case .parts(let parts) = read else {
            Issue.record("expected four parts")
            return
        }
        #expect(parts[0].returnType == .object)
        #expect(parts[0].answering == false)
        #expect(parts[0].level == nil)
        #expect(parts[1].returnType == .other)
        #expect(parts[1].answering == false)
        #expect(parts[2].returnType == .integer)
        #expect(parts[2].instanceResponds == false)
        #expect(parts[2].answering == false)
        #expect(parts[2].valueClass == nil)
        #expect(parts[3].answering == true)
        #expect(parts[3].returnType == .integer)
        #expect(parts[3].valueClass == .number)
        #expect(parts[3].level == .inRange(80))
        #expect(tally.encoding == 4)
        #expect(tally.payload == 1)
    }

    @Test func levelsAndValueClassesDropAnythingOutsideTheTable() {
        #expect(probe.Level.classify(0) == .zero)
        #expect(probe.Level.classify(1) == .inRange(1))
        #expect(probe.Level.classify(100) == .inRange(100))
        #expect(probe.Level.classify(101) == .other)
        #expect(probe.Level.classify(255) == .n255)
        #expect(probe.Level.classify(-1) == .other)
        #expect(probe.Level.classify(254) == .other)
        #expect(probe.Level.classify(256) == .other)
        #expect(probe.Level.classify(Int.min) == .other)
        #expect(probe.Level.classify(Int.max) == .other)

        let tally = Tally()
        let cases: [(EarbudsBatteryProbe.Key, EarbudsBatteryProbe.Payload, EarbudsBatteryProbe.ValueClass, EarbudsBatteryProbe.Level?)] = [
            (.left, .value(.number(1)), .number, .inRange(1)),
            (.right, .value(.number(0)), .number, .zero),
            (.budCase, .value(.number(255)), .number, .n255),
            (.single, .raised, .raised, nil),
        ]
        let first = answers(tally, cases)
        #expect(first[0].level == .inRange(1))
        #expect(first[1].level == .zero)
        #expect(first[1].valueClass == .number)
        #expect(first[2].level == .n255)
        #expect(first[3].valueClass == .raised)
        #expect(first[3].level == nil)
        #expect(tally.payload == 4)

        let secondCases: [(EarbudsBatteryProbe.Key, EarbudsBatteryProbe.Payload, EarbudsBatteryProbe.ValueClass, EarbudsBatteryProbe.Level?)] = [
            (.left, .value(.number(101)), .number, .other),
            (.right, .value(.text), .string, nil),
            (.budCase, .value(.null), .null, nil),
            (.single, .value(.other), .other, nil),
        ]
        let second = answers(tally, secondCases)
        #expect(second[0].level == .other)
        #expect(second[0].valueClass == .number)
        #expect(second[1].valueClass == .string)
        #expect(second[1].level == nil)
        #expect(second[2].valueClass == .null)
        #expect(second[3].valueClass == .other)
        #expect(second != first)
        #expect(tally.payload == 8)
    }

    @Test func anOverlongEncodingIsOtherAndIsNotRead() {
        let tally = Tally()
        let over = String(repeating: "q", count: probe.maxEncodingBytes + 1)
        let exact = String(repeating: "q", count: probe.maxEncodingBytes)
        let read = probe.read(allowed: true) {
            [
                .left: slot(tally, encoding: over, payload: .value(.number(40))),
                .single: slot(tally, encoding: exact, payload: .value(.number(40))),
            ]
        }
        guard case .parts(let parts) = read else {
            Issue.record("expected four parts")
            return
        }
        #expect(parts[0].returnType == .other)
        #expect(parts[0].answering == false)
        #expect(parts[0].level == nil)
        #expect(parts[3].returnType == .integer)
        #expect(parts[3].level == .inRange(40))
        #expect(tally.encoding == 2)
        #expect(tally.payload == 1)
    }

    private func answers(
        _ tally: Tally,
        _ rows: [(EarbudsBatteryProbe.Key, EarbudsBatteryProbe.Payload, EarbudsBatteryProbe.ValueClass, EarbudsBatteryProbe.Level?)]
    ) -> [EarbudsBatteryProbe.PartAnswer] {
        let map = Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.0, slot(tally, payload: row.1))
        })
        let read = probe.read(allowed: true) { map }
        guard case .parts(let parts) = read else {
            Issue.record("expected four parts")
            return []
        }
        for row in rows {
            let part = parts.first { $0.key == row.0 }
            #expect(part?.valueClass == row.2)
            #expect(part?.level == row.3)
            #expect(part?.answering == true)
        }
        return parts
    }

    private func slot(
        _ tally: Tally,
        classResponds: Bool = true,
        instanceResponds: Bool = true,
        encoding: String? = "q24@0:8",
        payload: EarbudsBatteryProbe.Payload
    ) -> EarbudsBatteryProbe.Slot {
        EarbudsBatteryProbe.Slot(
            classResponds: classResponds,
            instanceResponds: instanceResponds,
            encoding: {
                tally.encoding += 1
                return encoding
            },
            payload: {
                tally.payload += 1
                return payload
            }
        )
    }

    private func commonPrefix(_ values: [String]) -> String {
        guard var prefix = values.first else { return "" }
        for value in values.dropFirst() {
            while !value.hasPrefix(prefix) && !prefix.isEmpty {
                prefix.removeLast()
            }
        }
        return prefix
    }
}

private final class Tally: @unchecked Sendable {
    var encoding = 0
    var payload = 0
    var slots = 0
    var route = 0
}
