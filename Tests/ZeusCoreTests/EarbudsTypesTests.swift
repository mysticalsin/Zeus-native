import Testing
@testable import ZeusCore

@Suite("Step zero bluetooth access")
struct EarbudsTypesTests {
    @Test func fourHeaderCodesAreTheOnlyAccessValues() {
        #expect(BluetoothAccess.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(BluetoothAccess.allCases == [.notAsked, .restricted, .denied, .allowed])
        #expect(Set(BluetoothAccess.allCases.map(\.rawValue)).count == 4)
        let expected: [Int: BluetoothAccess] = [
            0: .notAsked,
            1: .restricted,
            2: .denied,
            3: .allowed,
        ]
        for (code, access) in expected {
            #expect(BluetoothAccess.read(code) == access)
            #expect(BluetoothAccess(rawValue: code) == access)
        }
    }

    @Test func aCodeOutsideTheFourIsNotAnAccess() {
        let refused = [-1, 4, 5, 8, 16, 100, 255, -255, 1_000, 1_048_576, Int.max, Int.min]
        for code in refused {
            #expect(BluetoothAccess.read(code) == nil)
            #expect(BluetoothAccess(rawValue: code) == nil)
        }
        #expect(BluetoothAccess.read(0) == .notAsked)
        #expect(BluetoothAccess.read(3) == .allowed)
    }

    @Test func zeroIsNotAskedAndThreeIsAllowed() {
        #expect(BluetoothAccess.read(0) == .notAsked)
        #expect(BluetoothAccess.read(3) == .allowed)
        #expect(BluetoothAccess.read(0) != BluetoothAccess.read(3))
        #expect(BluetoothAccess.notAsked.rawValue == 0)
        #expect(BluetoothAccess.restricted.rawValue == 1)
        #expect(BluetoothAccess.denied.rawValue == 2)
        #expect(BluetoothAccess.allowed.rawValue == 3)
    }

    @Test func onlyAllowedAllowsClassicCalls() {
        #expect(BluetoothAccess.allowed.allowsClassicCalls)
        for access in BluetoothAccess.allCases where access != .allowed {
            #expect(access.allowsClassicCalls == false)
        }
        #expect(BluetoothAccess.allCases.filter(\.allowsClassicCalls) == [.allowed])
    }

    @Test func onlyNotAskedMayAsk() {
        #expect(BluetoothAccess.notAsked.mayAsk)
        for access in BluetoothAccess.allCases where access != .notAsked {
            #expect(access.mayAsk == false)
        }
        #expect(BluetoothAccess.allCases.filter(\.mayAsk) == [.notAsked])
    }

    @Test func deniedAndRestrictedNeitherAskNorAllow() {
        for access in [BluetoothAccess.denied, BluetoothAccess.restricted] {
            #expect(access.mayAsk == false)
            #expect(access.allowsClassicCalls == false)
            #expect(access != .notAsked)
            #expect(access != .allowed)
        }
        #expect(BluetoothAccess.denied != .restricted)
        #expect(BluetoothAccess.read(1) == .restricted)
        #expect(BluetoothAccess.read(2) == .denied)
        #expect(BluetoothAccess.read(1)?.mayAsk == false)
        #expect(BluetoothAccess.read(2)?.allowsClassicCalls == false)
    }

    @Test func theSameCodeReadsTheSameAccess() {
        let first = BluetoothAccess.read(2)
        let second = BluetoothAccess.read(2)
        #expect(first == second)
        #expect(first == .denied)
        let other = BluetoothAccess.read(1)
        #expect(other == .restricted)
        #expect(other != first)
        #expect(BluetoothAccess.read(2) == first)
        #expect(BluetoothAccess.read(Int.max) == nil)
        #expect(BluetoothAccess.read(Int.max) == BluetoothAccess.read(Int.min))
    }

    @Test func theFourCasesStayDistinct() {
        let cases = BluetoothAccess.allCases
        #expect(cases.count == 4)
        #expect(Set(cases).count == 4)
        for left in cases {
            for right in cases {
                #expect((left == right) == (left.rawValue == right.rawValue))
            }
        }
    }

    @Test func aReadingCarriesNoDeviceName() {
        let planted = "Secret"
        let address = "AA:BB:CC:DD:EE:FF"
        let labels = ["notAsked", "restricted", "denied", "allowed"]
        #expect(BluetoothAccess.allCases.map { String(describing: $0) } == labels)
        for access in BluetoothAccess.allCases {
            let described = String(describing: access)
            let reflected = String(reflecting: access)
            var dumped = ""
            dump(access, to: &dumped)
            let mirror = Mirror(reflecting: access)
            #expect(mirror.displayStyle == .enum)
            #expect(Array(mirror.children).isEmpty)
            for text in [described, reflected, dumped] {
                #expect(text.contains(planted) == false)
                #expect(text.contains(address) == false)
            }
            #expect(reflected.hasSuffix(described))
            #expect(dumped.contains(described))
        }
    }

    @Test func eachCaseRoundTripsThroughItsCode() {
        for access in BluetoothAccess.allCases {
            #expect(BluetoothAccess.read(access.rawValue) == access)
            #expect(BluetoothAccess(rawValue: access.rawValue) == access)
        }
        #expect(BluetoothAccess.read(BluetoothAccess.notAsked.rawValue)?.mayAsk == true)
        #expect(BluetoothAccess.read(BluetoothAccess.allowed.rawValue)?.allowsClassicCalls == true)
        #expect(BluetoothAccess.read(BluetoothAccess.denied.rawValue)?.allowsClassicCalls == false)
        #expect(BluetoothAccess.read(BluetoothAccess.restricted.rawValue)?.mayAsk == false)
        #expect(BluetoothAccess.read(4) == nil)
    }
}
