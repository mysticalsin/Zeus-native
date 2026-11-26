import Foundation
import Testing
@testable import ZeusCore

@Suite("Output routes") struct OutputRoutesTests {
    private let locale = Locale(identifier: "en_US")

    @Test func everyKnownCodeMapsAndUnknownCodesAreOther() {
        let wired = ["usb ", "thun", "1394", "pci ", "eavb"]
        let bluetooth = ["blue", "blea"]
        let display = ["hdmi", "dprt"]
        let virtual = ["virt", "grup"]
        #expect(OutputTransport(code: OutputTransport.fourCC("bltn")) == .builtIn)
        for code in wired { #expect(OutputTransport(code: OutputTransport.fourCC(code)) == .wired) }
        for code in bluetooth { #expect(OutputTransport(code: OutputTransport.fourCC(code)) == .bluetooth) }
        #expect(OutputTransport(code: OutputTransport.fourCC("airp")) == .wirelessSpeaker)
        for code in display { #expect(OutputTransport(code: OutputTransport.fourCC(code)) == .display) }
        for code in virtual { #expect(OutputTransport(code: OutputTransport.fourCC(code)) == .virtual) }
        #expect(OutputTransport(code: nil) == .other)
        #expect(OutputTransport(code: 0) == .other)
        #expect(OutputTransport(code: OutputTransport.fourCC("zzzz")) == .other)
        #expect(OutputTransport(code: 1) == .other)
        #expect(OutputTransport.fourCC("usb") == 0)
    }

    @Test func flagsThatFailTheListAreDroppedAndUnreadableFlagsStay() {
        let hidden = device(objectID: 1, uid: "hidden", isHidden: true)
        let dead = device(objectID: 2, uid: "dead", isAlive: false)
        let stuck = device(objectID: 3, uid: "stuck", canBeDefault: false)
        let silent = device(objectID: 4, uid: "silent", outputChannels: 0)
        let negative = device(objectID: 5, uid: "negative", outputChannels: -1)
        let ownUID = device(objectID: 6, uid: "app.zeus.eq.3F2A", name: "Tap")
        let spectrum = device(objectID: 7, uid: "11111111-2222-3333-4444-555555555555", name: "Zeus spectrum")
        let scribe = device(objectID: 8, uid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", name: "Zeus Scribe")
        let padded = device(objectID: 9, uid: "padded", name: "Zeus spectrum\n")
        let kept = device(objectID: 10, uid: "kept", name: "MacBook Pro Speakers")
        let routes = OutputRouteRules.routes(
            from: [hidden, dead, stuck, silent, negative, ownUID, spectrum, scribe, padded, kept],
            defaultObjectID: nil, locale: locale
        )
        #expect(routes.map(\.uid) == ["kept"])
    }

    @Test func aPlainUUIDAndAWiderZeusPrefixAreNotOwnAggregates() {
        let uuid = device(objectID: 1, uid: "6F2C1A40-0000-4000-8000-000000000001", name: "External Headphones")
        let wider = device(objectID: 2, uid: "app.zeus.equaliser", name: "Other")
        let routes = OutputRouteRules.routes(from: [uuid, wider], defaultObjectID: nil, locale: locale)
        #expect(routes.map(\.uid).sorted() == [uuid.uid, wider.uid].sorted())
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: wider.uid, name: wider.name))
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: uuid.uid, name: "Speakers"))
        #expect(ZeusAudioDevices.isOwnAggregate(uid: "app.zeus.eq.9", name: "Zeus EQ Music"))
        #expect(!ZeusAudioDevices.isOwnAggregate(uid: "x", name: "zeus spectrum"))
    }

    @Test func theCurrentDefaultSurvivesEveryFilterIncludingAZeusAggregate() {
        let own = device(objectID: 4, uid: "app.zeus.eq.live", name: "Zeus EQ", outputChannels: 0,
                         canBeDefault: false, isHidden: true, isAlive: false)
        let other = device(objectID: 8, uid: "speakers", name: "Speakers")
        let routes = OutputRouteRules.routes(from: [other, own], defaultObjectID: 4, locale: locale)
        #expect(routes.map(\.uid) == ["speakers", "app.zeus.eq.live"])
        #expect(routes.first { $0.uid == "app.zeus.eq.live" }?.isCurrent == true)
        #expect(routes.first { $0.uid == "speakers" }?.isCurrent == false)
    }

    @Test func anUnreadableNameOrUIDIsAbsentEvenWhenItIsTheDefault() {
        let blank = device(objectID: 1, uid: "", name: "Speakers")
        let controls = device(objectID: 2, uid: "controls", name: "\u{0001}\u{0007}")
        let routes = OutputRouteRules.routes(from: [blank, controls], defaultObjectID: 2, locale: locale)
        #expect(routes.isEmpty)
    }

    @Test func unreadableFlagsAreKeptAndAnUnknownCodeIsOther() {
        let fact = device(objectID: 3, uid: "unread", name: "Desk", transportCode: nil, outputChannels: nil,
                          canBeDefault: nil, isHidden: nil, isAlive: nil)
        let routes = OutputRouteRules.routes(from: [fact], defaultObjectID: nil, locale: locale)
        #expect(routes.count == 1)
        #expect(routes[0].transport == .other)
        #expect(routes[0].symbol == "hifispeaker")
        #expect(routes[0].name == "Desk")
    }

    @Test func orderIsGroupThenNameThenUIDAndANewDefaultDoesNotMoveRows() {
        let rows = [
            device(objectID: 1, uid: "b", name: "Speaker 10", transportCode: OutputTransport.fourCC("blue")),
            device(objectID: 2, uid: "a", name: "Speaker 2", transportCode: OutputTransport.fourCC("blue")),
            device(objectID: 3, uid: "c", name: "speaker 2", transportCode: OutputTransport.fourCC("blue")),
            device(objectID: 4, uid: "z", name: "Cafe", transportCode: OutputTransport.fourCC("virt")),
            device(objectID: 5, uid: "a", name: "Café", transportCode: OutputTransport.fourCC("virt")),
            device(objectID: 6, uid: "wire", name: "USB", transportCode: OutputTransport.fourCC("usb ")),
            device(objectID: 7, uid: "panel", name: "HDMI", transportCode: OutputTransport.fourCC("hdmi")),
            device(objectID: 8, uid: "mac", name: "MacBook", transportCode: OutputTransport.fourCC("bltn")),
            device(objectID: 9, uid: "air", name: "Living Room", transportCode: OutputTransport.fourCC("airp")),
            device(objectID: 10, uid: "else", name: "Something", transportCode: 1),
        ]
        let first = OutputRouteRules.routes(from: rows, defaultObjectID: 8, locale: locale)
        let second = OutputRouteRules.routes(from: rows, defaultObjectID: 6, locale: locale)
        let expected = ["mac", "wire", "panel", "a", "c", "b", "air", "a", "z", "else"]
        #expect(first.map(\.uid) == expected)
        #expect(second.map(\.uid) == expected)
        #expect(first.map(\.isCurrent) != second.map(\.isCurrent))
        #expect(first.first { $0.objectID == 8 }?.isCurrent == true)
        #expect(second.first { $0.objectID == 6 }?.isCurrent == true)
    }

    @Test func theCapKeepsThirtyTwoAndStillKeepsADefaultPastTheCut() {
        let facts = (1...33).map { index in
            device(objectID: UInt32(index), uid: String(format: "n%02d", index), name: String(format: "Row %02d", index))
        }
        let inside = OutputRouteRules.routes(from: facts, defaultObjectID: 1, locale: locale)
        #expect(inside.count == OutputRouteRules.cap)
        #expect(inside.map(\.uid).contains("n01"))
        #expect(!inside.map(\.uid).contains("n33"))
        let outside = OutputRouteRules.routes(from: facts, defaultObjectID: 33, locale: locale)
        #expect(outside.count == OutputRouteRules.cap)
        #expect(outside.map(\.uid).contains("n33"))
        #expect(outside.first { $0.uid == "n33" }?.isCurrent == true)
        #expect(!outside.map(\.uid).contains("n32"))
    }

    @Test func cleaningDropsHostileScalarsAndCapsTheLength() {
        #expect(OutputName.clean("A\u{202E}B") == "AB")
        #expect(OutputName.clean("Hello\nWorld") == "Hello World")
        #expect(OutputName.clean("  a   b  ") == "a b")
        #expect(OutputName.clean("A\u{200B}B") == "AB")
        #expect(OutputName.clean("\u{0001}\n\u{0007}") == nil)
        #expect(OutputName.clean(String(repeating: "a", count: 4_000)) == String(repeating: "a", count: 48))
        let astronaut = "👩‍🚀"
        #expect(OutputName.clean(astronaut) == astronaut)
        let kept = String(repeating: "a", count: 47) + astronaut
        #expect(OutputName.clean(kept) == kept)
        #expect(OutputName.clean(String(repeating: "a", count: 48) + astronaut) == String(repeating: "a", count: 48))
    }

    @Test func nameArtAppliesOnlyInsideBluetooth() {
        #expect(OutputSymbol.name(transport: .bluetooth, name: "AirPods Max") == "airpodsmax")
        #expect(OutputSymbol.name(transport: .bluetooth, name: "room airpods pro") == "airpodspro")
        #expect(OutputSymbol.name(transport: .bluetooth, name: "Beats Fit Pro") == "beats.headphones")
        #expect(OutputSymbol.name(transport: .bluetooth, name: "Headphones") == "headphones")
        #expect(OutputSymbol.name(transport: .virtual, name: "AirPods Pro") == "square.on.square.dashed")
        let plain = "Speakers"
        for transport in [OutputTransport.builtIn, .wired, .bluetooth, .wirelessSpeaker, .display, .virtual, .other] {
            #expect(OutputSymbol.all.contains(OutputSymbol.name(transport: transport, name: plain)))
        }
        #expect(OutputSymbol.fallback == "speaker.wave.2")
    }

    @Test func spokenValueJoinsTheTransportWordAndTheStatus() {
        let route = OutputRoute(
            uid: "b", objectID: 1, name: "AirPods", transport: .bluetooth, symbol: "airpods", isCurrent: true
        )
        #expect(OutputRouteRules.spokenValue(for: route, status: "current") == "Bluetooth, current")
        #expect(OutputRouteRules.spokenValue(for: route, status: "  ") == "Bluetooth")
    }

    @Test func wordsAndSymbolNamesHaveNoEmDashOrEnDash() {
        let transports: [OutputTransport] = [.builtIn, .wired, .bluetooth, .wirelessSpeaker, .display, .virtual, .other]
        let words = transports.map(\.word) + Array(OutputSymbol.all) + [OutputSymbol.fallback]
        for word in words {
            #expect(!word.contains("\u{2014}"))
            #expect(!word.contains("\u{2013}"))
        }
    }

    private func device(
        objectID: UInt32, uid: String, name: String = "Speakers", transportCode: UInt32? = OutputTransport.fourCC("bltn"),
        outputChannels: Int? = 2, canBeDefault: Bool? = true, isHidden: Bool? = false, isAlive: Bool? = true
    ) -> OutputDeviceFacts {
        OutputDeviceFacts(
            objectID: objectID, uid: uid, name: name, transportCode: transportCode, outputChannels: outputChannels,
            canBeDefault: canBeDefault, isHidden: isHidden, isAlive: isAlive
        )
    }
}
