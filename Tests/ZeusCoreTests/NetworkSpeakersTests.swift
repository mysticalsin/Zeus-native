import Foundation
import Testing
@testable import ZeusCore

@Suite("Network speakers")
struct NetworkSpeakersTests {
    @Test func serviceTypesAndModelKeys() {
        #expect(SpeakerService.airplay.type == "_airplay._tcp")
        #expect(SpeakerService.airplay.modelKey == "model")
        #expect(SpeakerService.raop.type == "_raop._tcp")
        #expect(SpeakerService.raop.modelKey == "am")
        #expect(NetworkSpeakerRules.sightingCap == 128)
        #expect(NetworkSpeakerRules.rowCap == 24)
        #expect(NetworkSpeakerRules.nameLimit == 48)
        #expect(SpeakerKind.modelLimit == 64)
    }

    @Test func theIdentifierPrefixIsRemovedOnlyForRaopAndOnlyInThatShape() {
        #expect(NetworkSpeakerRules.displayName(prefixed(12, "Living Room"), service: .raop) == "Living Room")
        #expect(NetworkSpeakerRules.displayName(prefixed(14, "Living Room"), service: .raop) == "Living Room")
        #expect(NetworkSpeakerRules.displayName(prefixed(16, "Living Room"), service: .raop) == "Living Room")
        #expect(NetworkSpeakerRules.displayName(prefixed(11, "Living Room"), service: .raop) == prefixed(11, "Living Room"))
        #expect(NetworkSpeakerRules.displayName(prefixed(17, "Living Room"), service: .raop) == prefixed(17, "Living Room"))
        #expect(NetworkSpeakerRules.displayName(prefixed(12, "Living Room"), service: .airplay) == prefixed(12, "Living Room"))
        #expect(NetworkSpeakerRules.displayName("aabbccddeeff@Kitchen", service: .raop) == "Kitchen")
        #expect(NetworkSpeakerRules.displayName("AABBCCDDEEFF@Kitchen", service: .raop) == "Kitchen")
        #expect(NetworkSpeakerRules.displayName("001122334455Living Room", service: .raop) == "001122334455Living Room")
        #expect(NetworkSpeakerRules.displayName("g011223344556@Kitchen", service: .raop) == "g011223344556@Kitchen")
        #expect(NetworkSpeakerRules.displayName("@Kitchen", service: .raop) == "@Kitchen")
        #expect(NetworkSpeakerRules.displayName(prefixed(12, ""), service: .raop) == nil)
    }

    @Test func hostileNamesAreCleanedOrDropped() {
        #expect(NetworkSpeakerRules.displayName("A\u{202E}B", service: .airplay) == "AB")
        #expect(NetworkSpeakerRules.displayName("Hello\nWorld", service: .airplay) == "Hello World")
        #expect(NetworkSpeakerRules.displayName("  a   b  ", service: .airplay) == "a b")
        #expect(NetworkSpeakerRules.displayName("A\u{200B}B", service: .airplay) == "AB")
        #expect(NetworkSpeakerRules.displayName("\u{0001}\n\u{0007}", service: .airplay) == nil)
        #expect(NetworkSpeakerRules.displayName(String(repeating: "a", count: 4_000), service: .airplay) == String(repeating: "a", count: 48))
        let astronaut = "👩‍🚀"
        #expect(NetworkSpeakerRules.displayName(astronaut, service: .airplay) == astronaut)
        let kept = String(repeating: "a", count: 47) + astronaut
        #expect(NetworkSpeakerRules.displayName(kept, service: .airplay) == kept)
        #expect(NetworkSpeakerRules.displayName(String(repeating: "a", count: 48) + astronaut, service: .airplay) == String(repeating: "a", count: 48))
        #expect(NetworkSpeakerRules.displayName("\u{200D}", service: .raop) == nil)
        let hostile = SpeakerSighting(service: .raop, rawName: "\u{0000}\n", model: "Sonos")
        #expect(NetworkSpeakerRules.merge([hostile], ownName: "").isEmpty)
    }

    @Test func kindsFollowThePrefixAndAComputerIsDropped() {
        #expect(SpeakerKind(model: "AudioAccessory1,1") == .homeSpeaker)
        #expect(SpeakerKind(model: "AppleTV6,2") == .television)
        #expect(SpeakerKind(model: nil) == .speaker)
        #expect(SpeakerKind(model: "") == .speaker)
        #expect(SpeakerKind(model: "Sonos") == .speaker)
        #expect(SpeakerKind(model: "audioaccessory") == .speaker)
        #expect(SpeakerKind(model: "appletv") == .speaker)
        #expect(SpeakerKind(model: "macbookpro") == .speaker)
        #expect(SpeakerKind(model: "MacBookPro18,3") == nil)
        #expect(SpeakerKind(model: "iMac20,1") == nil)
        #expect(SpeakerKind(model: "Macmini9,1") == nil)
        #expect(SpeakerKind(model: "Mac") == nil)
        #expect(SpeakerKind(model: "Mac" + String(repeating: "x", count: 61)) == nil)
        #expect(SpeakerKind(model: "Mac" + String(repeating: "x", count: 62)) == .speaker)
        #expect(SpeakerKind(model: "MacBook\u{00E9}") == .speaker)
        #expect(SpeakerKind(model: "AudioAccessory\u{2122}") == .speaker)
        #expect(SpeakerKind.homeSpeaker.symbol == "homepod")
        #expect(SpeakerKind.television.symbol == "appletv")
        #expect(SpeakerKind.speaker.symbol == "hifispeaker")

        let kept = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .airplay, rawName: "Kitchen", model: "macbookpro"),
            SpeakerSighting(service: .airplay, rawName: "Office", model: "MacBookPro18,3"),
            SpeakerSighting(service: .raop, rawName: prefixed(12, "Studio"), model: "iMac20,1"),
            SpeakerSighting(service: .airplay, rawName: "Den", model: "Macmini9,1"),
        ], ownName: "")
        #expect(kept.map(\.name) == ["Kitchen"])
        #expect(kept[0].kind == .speaker)
    }

    @Test func bothServicesFoldToOneRowAndAirPlaySuppliesTheKind() {
        let speakers = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .raop, rawName: "AABBCCDDEEFF@Living Room", model: "Sonos"),
            SpeakerSighting(service: .airplay, rawName: "living room", model: "AudioAccessory1,1"),
        ], ownName: "Office")
        #expect(speakers.count == 1)
        #expect(speakers[0].kind == .homeSpeaker)
        #expect(speakers[0].name == "Living Room")

        let cafe = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .raop, rawName: prefixed(12, "Cafe"), model: "Sonos"),
            SpeakerSighting(service: .airplay, rawName: "Café", model: "AppleTV5,3"),
        ], ownName: "")
        #expect(cafe.count == 1)
        #expect(cafe[0].kind == .television)

        let firstAirPlay = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .airplay, rawName: "Patio", model: "AudioAccessory5,1"),
            SpeakerSighting(service: .raop, rawName: prefixed(12, "Patio"), model: "AppleTV6,2"),
        ], ownName: "")
        #expect(firstAirPlay == [NetworkSpeaker(name: "Patio", kind: .homeSpeaker)])
    }

    @Test func theMacOwnNameIsDropped() {
        let speakers = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .airplay, rawName: "Studio", model: nil),
            SpeakerSighting(service: .raop, rawName: prefixed(12, "Kitchen"), model: "Sonos"),
            SpeakerSighting(service: .airplay, rawName: "Café", model: nil),
        ], ownName: "  cafe  ")
        #expect(speakers.map(\.name) == ["Studio", "Kitchen"])

        let poisoned = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .raop, rawName: prefixed(12, "Den"), model: "Sonos"),
            SpeakerSighting(service: .airplay, rawName: "Den", model: "MacBookPro18,3"),
        ], ownName: "")
        #expect(poisoned.isEmpty)
    }

    @Test func aListedRouteIsNotRepeated() {
        let found = NetworkSpeakerRules.merge([
            SpeakerSighting(service: .airplay, rawName: "Living Room", model: "AudioAccessory1,1"),
            SpeakerSighting(service: .airplay, rawName: "Kitchen", model: nil),
        ], ownName: "")
        let rows = NetworkSpeakerRules.rows(found: found, routes: ["living room"])
        #expect(rows.map(\.name) == ["Kitchen"])

        let spaced = NetworkSpeakerRules.rows(found: found, routes: ["  Kitchen\n"])
        #expect(spaced.map(\.name) == ["Living Room"])
    }

    @Test func theCapsStopTheFlood() {
        let pastTheRead = (0..<129).map { index in
            SpeakerSighting(service: .airplay, rawName: String(format: "N%03d", index), model: "Sonos")
        }
        let merged = NetworkSpeakerRules.merge(pastTheRead, ownName: "")
        #expect(merged.count == 128)
        #expect(merged.contains { $0.name == "N000" })
        #expect(!merged.contains { $0.name == "N128" })

        var ignored = Array(repeating: SpeakerSighting(service: .airplay, rawName: "\u{0001}", model: nil), count: 128)
        ignored.append(SpeakerSighting(service: .airplay, rawName: "Real", model: nil))
        #expect(NetworkSpeakerRules.merge(ignored, ownName: "").isEmpty)

        let many = (0..<25).map { index in
            NetworkSpeaker(name: String(format: "Speaker %02d", index), kind: .speaker)
        }
        let rows = NetworkSpeakerRules.rows(found: many, routes: [])
        #expect(rows.count == 24)
        #expect(rows.contains { $0.name == "Speaker 00" })
        #expect(!rows.contains { $0.name == "Speaker 24" })
    }

    @Test func withKindSymbolsTouchesOnlyWirelessSpeakerRoutes() {
        let found = [
            NetworkSpeaker(name: "Living Room", kind: .homeSpeaker),
            NetworkSpeaker(name: "Den", kind: .speaker),
        ]
        let routes = [
            SpeakerListedRoute(name: "Living Room", transport: .wirelessSpeaker, symbol: "airplayaudio"),
            SpeakerListedRoute(name: "living room", transport: .bluetooth, symbol: "headphones"),
            SpeakerListedRoute(name: "Desk", transport: .wired, symbol: "cable.connector"),
            SpeakerListedRoute(name: "Other Room", transport: .wirelessSpeaker, symbol: "airplayaudio"),
            SpeakerListedRoute(name: "Den", transport: .display, symbol: "display"),
            SpeakerListedRoute(name: "Den", transport: .wirelessSpeaker, symbol: "airplayaudio"),
            SpeakerListedRoute(name: "Hall", transport: .builtIn, symbol: "speaker.wave.2"),
            SpeakerListedRoute(name: "Hall", transport: .virtual, symbol: "square.on.square.dashed"),
            SpeakerListedRoute(name: "Hall", transport: .other, symbol: "hifispeaker"),
        ]
        let updated = NetworkSpeakerRules.withKindSymbols(routes, found: found)
        #expect(updated[0].symbol == "homepod")
        #expect(updated[0].name == "Living Room")
        #expect(updated[0].transport == .wirelessSpeaker)
        #expect(updated[1] == routes[1])
        #expect(updated[2] == routes[2])
        #expect(updated[3] == routes[3])
        #expect(updated[4] == routes[4])
        #expect(updated[5].symbol == "hifispeaker")
        #expect(updated[5].transport == .wirelessSpeaker)
        #expect(updated[6] == routes[6])
        #expect(updated[7] == routes[7])
        #expect(updated[8] == routes[8])
        #expect(NetworkSpeakerRules.withKindSymbols(routes, found: []) == routes)
    }

    private func prefixed(_ count: Int, _ rest: String) -> String {
        String(repeating: "a", count: count) + (rest.isEmpty ? "@" : "@" + rest)
    }
}
