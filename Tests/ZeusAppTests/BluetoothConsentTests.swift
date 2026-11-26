import Testing
@testable import Zeus

@Suite("Step zero bluetooth consent")
struct BluetoothConsentTests {
    private let consent = BluetoothConsent.self

    @Test func fourClassPropertyValuesAreTheOnlyGrants() {
        #expect(consent.ClassProperty.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(consent.Access.allCases == [.notAsked, .restricted, .denied, .allowed])
        #expect(consent.ClassProperty.allCases.count == consent.Access.allCases.count)
        #expect(Set(consent.ClassProperty.allCases.map(\.rawValue)).count == 4)
        let expected: [BluetoothConsent.ClassProperty: BluetoothConsent.Access] = [
            .notDetermined: .notAsked,
            .restricted: .restricted,
            .denied: .denied,
            .allowedAlways: .allowed,
        ]
        for property in consent.ClassProperty.allCases {
            #expect(consent.access(from: property.rawValue) == expected[property])
            #expect(consent.current(read(raw: property.rawValue)) == expected[property])
        }
    }

    @Test func aValueOutsideTheFourIsNotAGrant() {
        let refused = [-1, 4, 5, 8, 16, 100, 255, -255, 1_000, 1_048_576, Int.max, Int.min]
        for raw in refused {
            #expect(consent.access(from: raw) == nil)
            #expect(consent.current(read(raw: raw)) == nil)
        }
        #expect(consent.access(from: 0) == .notAsked)
        #expect(consent.access(from: 3) == .allowed)
    }

    @Test func currentReadsTheClassPropertyOnce() {
        let tally = Tally()
        let access = consent.current(read(tally, raw: consent.ClassProperty.allowedAlways.rawValue))
        #expect(access == .allowed)
        #expect(tally.kinds == ["read"])
        #expect(tally.reads == [3])
        #expect(tally.makes.isEmpty)
        #expect(tally.releases == 0)
        let again = consent.current(read(tally, raw: consent.ClassProperty.notDetermined.rawValue))
        #expect(again == .notAsked)
        #expect(again != access)
        #expect(tally.kinds == ["read", "read"])
        #expect(tally.makes.isEmpty)
    }

    @Test func aDecidedOrUnknownGrantMakesNoManager() {
        let decided: [Int: BluetoothConsent.Access] = [
            1: .restricted,
            2: .denied,
            3: .allowed,
        ]
        for (raw, access) in decided {
            let tally = Tally()
            let hold = consent.request(read(tally, raw: raw), held: false, make(tally, created: true))
            #expect(hold.created == false)
            #expect(hold.access == access)
            #expect(tally.kinds == ["read"])
            #expect(tally.makes.isEmpty)
            #expect(tally.alerts.isEmpty)
            #expect(tally.scans.isEmpty)
        }
        let tally = Tally()
        let unknown = consent.request(read(tally, raw: 4), held: false, make(tally, created: true))
        #expect(unknown == consent.Hold(created: false, access: nil))
        #expect(tally.kinds == ["read"])
        #expect(tally.makes.isEmpty)
        let negative = consent.request(read(tally, raw: -1), held: false, make(tally, created: true))
        #expect(negative.created == false)
        #expect(negative.access == nil)
        #expect(tally.kinds == ["read", "read"])
    }

    @Test func notAskedMakesOneManagerWithThePowerAlertOff() {
        let tally = Tally()
        let options = consent.Options()
        #expect(options.showPowerAlert == false)
        #expect(options.scans == false)
        #expect(options == consent.Options())
        let hold = consent.request(read(tally, raw: 0), held: false, make(tally, created: true))
        #expect(hold == consent.Hold(created: true, access: .notAsked))
        #expect(tally.kinds == ["read", "make"])
        #expect(tally.reads == [0])
        #expect(tally.makes == [true])
        #expect(tally.alerts == [false])
        #expect(tally.scans == [false])
        #expect(tally.releases == 0)
    }

    @Test func aHeldManagerIsNotMadeAgain() {
        let tally = Tally()
        let held = consent.request(read(tally, raw: 0), held: true, make(tally, created: true))
        #expect(held == consent.Hold(created: false, access: .notAsked))
        #expect(tally.kinds == ["read"])
        #expect(tally.makes.isEmpty)
        let decided = consent.request(read(tally, raw: 3), held: true, make(tally, created: true))
        #expect(decided == consent.Hold(created: false, access: .allowed))
        #expect(tally.kinds == ["read", "read"])
        #expect(tally.makes.isEmpty)
        #expect(tally.alerts.isEmpty)
    }

    @Test func aRefusedMakeIsNotAskedAgainInsideTheCall() {
        let tally = Tally()
        let hold = consent.request(read(tally, raw: 0), held: false, make(tally, created: false))
        #expect(hold == consent.Hold(created: false, access: .notAsked))
        #expect(tally.kinds == ["read", "make"])
        #expect(tally.makes == [false])
        #expect(tally.alerts == [false])
        #expect(tally.scans == [false])
        #expect(tally.kinds.filter { $0 == "make" }.count == 1)
    }

    @Test func aSecondCallStartsEmpty() {
        let tally = Tally()
        let first = consent.request(read(tally, raw: 0), held: false, make(tally, created: true))
        let second = consent.request(read(tally, raw: 0), held: false, make(tally, created: false))
        #expect(first == consent.Hold(created: true, access: .notAsked))
        #expect(second == consent.Hold(created: false, access: .notAsked))
        #expect(first != second)
        #expect(tally.kinds == ["read", "make", "read", "make"])
        #expect(tally.makes == [true, false])
        #expect(tally.alerts == [false, false])
        let blocked = consent.request(read(tally, raw: 0), held: true, make(tally, created: true))
        #expect(blocked.created == false)
        #expect(tally.makes == [true, false])
        #expect(tally.kinds == ["read", "make", "read", "make", "read"])
    }

    @Test func aStateChangeFinishesOnlyWhenThePropertyIsDecided() {
        let waiting = Tally()
        let open = consent.stateChanged(read(waiting, raw: 0))
        #expect(open == consent.Notice(finished: false, access: .notAsked))
        #expect(waiting.kinds == ["read"])
        #expect(waiting.makes.isEmpty)
        let unknown = consent.stateChanged(read(waiting, raw: 9))
        #expect(unknown == consent.Notice(finished: false, access: nil))
        #expect(waiting.kinds == ["read", "read"])
        let denied = consent.stateChanged(read(waiting, raw: 2))
        #expect(denied == consent.Notice(finished: true, access: .denied))
        let allowed = consent.stateChanged(read(waiting, raw: 3))
        #expect(allowed == consent.Notice(finished: true, access: .allowed))
        let restricted = consent.stateChanged(read(waiting, raw: 1))
        #expect(restricted == consent.Notice(finished: true, access: .restricted))
        #expect(waiting.makes.isEmpty)
        #expect(waiting.releases == 0)
        #expect(waiting.kinds.allSatisfy { $0 == "read" })
        #expect(waiting.kinds.count == 5)

        let step = RawBox(0)
        let sequenced = consent.ReadGate {
            step.raw += 1
            return step.raw == 1 ? 0 : 2
        }
        let first = consent.stateChanged(sequenced)
        let second = consent.stateChanged(sequenced)
        #expect(first.finished == false)
        #expect(first.access == .notAsked)
        #expect(second.finished)
        #expect(second.access == .denied)
        #expect(step.raw == 2)
    }

    @Test func abandonReleasesAHeldManagerAndReadsAtThatMoment() {
        let raw = RawBox(0)
        let changed = consent.abandon(
            held: true,
            consent.ReleaseGate(
                release: { raw.raw = 2 },
                authorization: { raw.raw }
            )
        )
        #expect(changed == consent.Released(released: true, access: .denied))
        #expect(raw.raw == 2)

        let tally = Tally()
        let held = consent.abandon(held: true, release(tally, raw: 0))
        #expect(held == consent.Released(released: true, access: .notAsked))
        #expect(tally.kinds == ["release", "read"])
        #expect(tally.releases == 1)
        #expect(tally.reads == [0])
        #expect(tally.makes.isEmpty)

        let idle = consent.abandon(held: false, release(tally, raw: 3))
        #expect(idle == consent.Released(released: false, access: .allowed))
        #expect(tally.kinds == ["release", "read", "read"])
        #expect(tally.releases == 1)
        #expect(tally.reads == [0, 3])
        #expect(tally.makes.isEmpty)

        let unknown = consent.abandon(held: true, release(tally, raw: Int.min))
        #expect(unknown == consent.Released(released: true, access: nil))
        #expect(tally.kinds == ["release", "read", "read", "release", "read"])
        #expect(tally.releases == 2)
        #expect(tally.makes.isEmpty)
    }

    private func read(raw: Int) -> BluetoothConsent.ReadGate {
        BluetoothConsent.ReadGate { raw }
    }

    private func read(_ tally: Tally, raw: Int) -> BluetoothConsent.ReadGate {
        BluetoothConsent.ReadGate {
            tally.kinds.append("read")
            tally.reads.append(raw)
            return raw
        }
    }

    private func make(_ tally: Tally, created: Bool) -> BluetoothConsent.MakeGate {
        BluetoothConsent.MakeGate { options in
            tally.kinds.append("make")
            tally.makes.append(created)
            tally.alerts.append(options.showPowerAlert)
            tally.scans.append(options.scans)
            return created
        }
    }

    private func release(_ tally: Tally, raw: Int) -> BluetoothConsent.ReleaseGate {
        BluetoothConsent.ReleaseGate(
            release: {
                tally.kinds.append("release")
                tally.releases += 1
            },
            authorization: {
                tally.kinds.append("read")
                tally.reads.append(raw)
                return raw
            }
        )
    }
}

private final class RawBox: @unchecked Sendable {
    var raw: Int
    init(_ raw: Int) { self.raw = raw }
}

private final class Tally: @unchecked Sendable {
    var kinds: [String] = []
    var reads: [Int] = []
    var makes: [Bool] = []
    var alerts: [Bool] = []
    var scans: [Bool] = []
    var releases = 0
}
