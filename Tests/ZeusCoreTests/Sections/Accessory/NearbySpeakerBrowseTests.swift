import Foundation
import Testing
import ZeusCore

@Suite("Accessory nearby speakers")
struct NearbySpeakerBrowseTests {
    @Test func speakerNamesDoNotBrowseUntilLocalNetworkIsOn() {
        var machine = NearbySpeakerMachine()
        #expect(machine.phase == .off)
        let leaked = [NearbySpeaker(id: "kitchen", name: "Kitchen")]
        #expect(machine.handle(.found(leaked)).isEmpty)
        #expect(machine.phase == .off)
        #expect(machine.handle(.permissionAllowed).isEmpty)
        #expect(machine.handle(.permissionDenied).isEmpty)
        #expect(machine.handle(.searchFailed).isEmpty)
        #expect(machine.phase == .off)

        #expect(machine.handle(.userEnabled) == [.requestPermission])
        #expect(machine.phase == .askingPermission)
        #expect(machine.phase.isLoading == true)
        #expect(machine.handle(.found(leaked)).isEmpty)
        #expect(machine.phase == .askingPermission)

        #expect(machine.handle(.permissionDenied) == [.stopSearch])
        #expect(machine.phase == .unavailable(.denied))
        #expect(machine.phase.isUnavailable == true)
        #expect(machine.phase.status.contains("denied"))
        #expect(machine.handle(.found(leaked)).isEmpty)
        #expect(machine.phase == .unavailable(.denied))

        var allowed = NearbySpeakerMachine()
        #expect(allowed.handle(.userEnabled) == [.requestPermission])
        #expect(allowed.handle(.permissionAllowed) == [.startSearch])
        #expect(allowed.phase == .searching)
        #expect(allowed.phase.status == "Looking for nearby speakers.")
        let names = allowed.handle(.found(leaked))
        #expect(names.isEmpty)
        #expect(allowed.phase == .names(NearbySpeaker.normalize(leaked)))
    }

    @Test func turningSpeakersOffStopsTheSearchAndDropsNames() {
        var machine = NearbySpeakerMachine()
        _ = machine.handle(.userEnabled)
        _ = machine.handle(.permissionAllowed)
        _ = machine.handle(.found([NearbySpeaker(id: "a", name: "Alpha"), NearbySpeaker(id: "b", name: "Beta")]))
        #expect(machine.handle(.userDisabled) == [.stopSearch])
        #expect(machine.phase == .off)
        #expect(machine.handle(.found([NearbySpeaker(id: "a", name: "Alpha")])).isEmpty)
        #expect(machine.phase == .off)
        #expect(machine.handle(.userDisabled).isEmpty)
    }

    @Test func deniedAndRestrictedStayUnavailableAndEmptyIsNotAnError() {
        var denied = NearbySpeakerMachine()
        _ = denied.handle(.userEnabled)
        #expect(denied.handle(.permissionDenied) == [.stopSearch])
        #expect(denied.phase.accessibilityLabel.contains("unavailable"))
        #expect(denied.phase.isError == false)
        #expect(denied.phase.isEmpty == false)

        var restricted = NearbySpeakerMachine()
        _ = restricted.handle(.userEnabled)
        #expect(restricted.handle(.permissionRestricted) == [.stopSearch])
        #expect(restricted.phase == .unavailable(.restricted))
        #expect(restricted.phase.status.contains("restricted"))

        var empty = NearbySpeakerMachine()
        _ = empty.handle(.userEnabled)
        _ = empty.handle(.permissionAllowed)
        #expect(empty.handle(.found([])).isEmpty)
        #expect(empty.phase == .empty)
        #expect(empty.phase.isEmpty == true)
        #expect(empty.phase.isError == false)
        #expect(empty.phase.status == "No nearby speakers.")

        #expect(empty.handle(.searchFailed) == [.stopSearch])
        #expect(empty.phase == .error(.searchFailed))
        #expect(empty.phase.isError == true)
        #expect(empty.phase.status == "Nearby speaker names could not be loaded.")
        #expect(empty.handle(.found([NearbySpeaker(id: "a", name: "Alpha")])).isEmpty)
        #expect(empty.phase == .error(.searchFailed))
    }

    @Test func namesThatArriveWhileAskingAreHeldUntilPermissionAndDroppedWhenDenied() {
        let found = [NearbySpeaker(id: "a", name: "Alpha")]
        var held = NearbySpeakerMachine()
        _ = held.handle(.userEnabled)
        #expect(held.handle(.found(found)).isEmpty)
        #expect(held.phase == .askingPermission)
        #expect(held.handle(.permissionAllowed) == [.startSearch])
        #expect(held.phase == .names(found))

        var noneYet = NearbySpeakerMachine()
        _ = noneYet.handle(.userEnabled)
        #expect(noneYet.handle(.permissionAllowed) == [.startSearch])
        #expect(noneYet.phase == .searching)

        var empty = NearbySpeakerMachine()
        _ = empty.handle(.userEnabled)
        _ = empty.handle(.found([]))
        #expect(empty.handle(.permissionAllowed) == [.startSearch])
        #expect(empty.phase == .empty)

        var dropped = NearbySpeakerMachine()
        _ = dropped.handle(.userEnabled)
        _ = dropped.handle(.found(found))
        #expect(dropped.handle(.permissionDenied) == [.stopSearch])
        #expect(dropped.phase == .unavailable(.denied))
    }

    @Test func aDenialAfterNamesFailsClosed() {
        var machine = NearbySpeakerMachine()
        _ = machine.handle(.userEnabled)
        _ = machine.handle(.permissionAllowed)
        _ = machine.handle(.found([NearbySpeaker(id: "a", name: "Alpha")]))
        #expect(machine.handle(.permissionDenied) == [.stopSearch])
        #expect(machine.phase == .unavailable(.denied))
        #expect(machine.handle(.permissionAllowed).isEmpty)
        #expect(machine.phase == .unavailable(.denied))
    }

    @Test func speakerNamesAreTrimmedDedupedAndSorted() {
        let raw = [
            NearbySpeaker(id: " b ", name: "  Beta "),
            NearbySpeaker(id: "a", name: " alpha "),
            NearbySpeaker(id: "b", name: "Other"),
            NearbySpeaker(id: " ", name: "Gone"),
            NearbySpeaker(id: "c", name: " "),
            NearbySpeaker(id: "d", name: String(repeating: "N", count: 65)),
        ]
        let names = NearbySpeaker.normalize(raw)
        #expect(names.map(\.id) == ["a", "b", "d"])
        #expect(names.map(\.name) == ["alpha", "Beta", String(repeating: "N", count: 65)])
        #expect(names[2].displayName == String(repeating: "N", count: 61) + "...")
        #expect(names[2].name.count == 65)
        let exact = NearbySpeaker(id: "e", name: String(repeating: "Z", count: 64))
        #expect(NearbySpeaker.normalize([exact])[0].displayName == exact.name)
        #expect(NearbySpeaker.normalize(names) == names)
    }

    @Test func normalizedNamesStayIdempotentAcrossRandomLists() {
        var rng = AccessorySplitMix(seed: 0x5EE_D)
        for _ in 0..<80 {
            let count = Int(rng.next() % 8)
            let raw = (0..<count).map { _ in
                NearbySpeaker(id: rng.token(), name: rng.token())
            }
            let once = NearbySpeaker.normalize(raw)
            #expect(NearbySpeaker.normalize(once) == once)
            #expect(Set(once.map(\.id)).count == once.count)
            for speaker in once {
                #expect(!speaker.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!speaker.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let ordered = once.map { $0.name.lowercased() + "\u{0}" + $0.id }
            #expect(ordered == ordered.sorted())
        }
    }

    @Test func anOffMachineNeverSearchesAcrossRandomEvents() {
        var rng = AccessorySplitMix(seed: 0x0FF)
        for _ in 0..<160 {
            var machine = NearbySpeakerMachine()
            for _ in 0..<Int(rng.next() % 12) + 1 {
                let event = rng.speakerEvent(allowEnable: false)
                let effects = machine.handle(event)
                #expect(machine.phase == .off)
                #expect(!effects.contains(.requestPermission))
                #expect(!effects.contains(.startSearch))
            }
        }
    }

    @Test func disablingAlwaysReturnsToOffAndClearsNames() {
        var rng = AccessorySplitMix(seed: 0xD15A_B1E)
        for _ in 0..<80 {
            var machine = NearbySpeakerMachine()
            _ = machine.handle(.userEnabled)
            if rng.next() % 2 == 0 {
                _ = machine.handle(.permissionAllowed)
                _ = machine.handle(.found([NearbySpeaker(id: "a", name: "Alpha")]))
            }
            let effects = machine.handle(.userDisabled)
            #expect(effects == [.stopSearch])
            #expect(machine.phase == .off)
            #expect(machine.handle(.found([NearbySpeaker(id: "a", name: "Alpha")])).isEmpty)
            #expect(machine.phase == .off)
        }
    }

    @Test func browserSignalsFailClosedWhenLocalNetworkIsDenied() {
        let names = [NearbySpeaker(id: "a", name: "Alpha")]
        #expect(NearbySpeakerBrowserRules.events(dnsCode: NearbySpeakerBrowserRules.deniedDNSCode, failed: false, ready: true, names: names) == [.permissionDenied])
        #expect(NearbySpeakerBrowserRules.events(dnsCode: -65570, failed: true, ready: false, names: names) == [.permissionDenied])
        #expect(NearbySpeakerBrowserRules.deniedDNSCode == -65570)
        #expect(NearbySpeakerBrowserRules.events(dnsCode: -65569, failed: false, ready: false, names: names) == [.found(names)])
        #expect(NearbySpeakerBrowserRules.events(dnsCode: 0, failed: false, ready: true, names: []) == [.permissionAllowed, .found([])])
        #expect(NearbySpeakerBrowserRules.events(dnsCode: nil, failed: true, ready: true, names: names) == [.searchFailed])
        #expect(NearbySpeakerBrowserRules.events(dnsCode: nil, failed: false, ready: false, names: nil).isEmpty)
        #expect(NearbySpeakerBrowserRules.events(dnsCode: Int.min, failed: false, ready: true, names: nil) == [.permissionAllowed])
        #expect(!NearbySpeakerDiscovery.serviceTypes.isEmpty)
        #expect(!NearbySpeakerDiscovery.serviceTypes.contains("_zeus-fling._tcp"))
        #expect(Set(NearbySpeakerDiscovery.serviceTypes).count == NearbySpeakerDiscovery.serviceTypes.count)
    }

    @Test func thePlistDeclaresTheSpeakerServiceTypesAndSaysWhy() throws {
        let root = accessoryRepositoryRoot()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let reason = try #require(plist["NSLocalNetworkUsageDescription"] as? String)
        #expect(reason.contains("Fling"))
        #expect(reason.contains("speaker"))
        #expect(!reason.contains("AirPlay"))
        let services = try #require(plist["NSBonjourServices"] as? [String])
        #expect(services.contains("_zeus-fling._tcp"))
        for type in NearbySpeakerDiscovery.serviceTypes {
            #expect(services.contains(type))
        }
    }
}

extension AccessorySplitMix {
    mutating func token() -> String {
        switch next() % 5 {
        case 0: return " "
        case 1: return "  Alpha "
        case 2: return "beta"
        case 3: return String(repeating: "Q", count: Int(next() % 70))
        default: return "id-\(next() % 4)"
        }
    }

    mutating func speakerEvent(allowEnable: Bool) -> NearbySpeakerEvent {
        switch next() % 7 {
        case 0: return allowEnable ? .userEnabled : .userDisabled
        case 1: return .userDisabled
        case 2: return .permissionAllowed
        case 3: return .permissionDenied
        case 4: return .permissionRestricted
        case 5: return .searchFailed
        default:
            return .found([NearbySpeaker(id: token(), name: token())])
        }
    }
}
