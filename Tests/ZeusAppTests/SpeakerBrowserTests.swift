import Testing
@testable import Zeus

@Suite("Step zero speaker browser")
struct SpeakerBrowserTests {
    private let browser = SpeakerBrowser.self

    @Test func twoDeclaredTypesAreTheOnlyNames() {
        #expect(browser.declared == [.airplay, .raop])
        #expect(browser.Service.allCases == browser.declared)
        #expect(browser.declared.count == 2)
        #expect(Set(browser.declared).count == 2)
        #expect(browser.Service.airplay.rawValue == "_airplay._tcp")
        #expect(browser.Service.raop.rawValue == "_raop._tcp")
        #expect(browser.Service.airplay.rawValue != browser.Service.raop.rawValue)
        for service in browser.declared {
            let raw = service.rawValue
            #expect(raw.utf8.contains(0) == false)
            #expect(raw.contains("\n") == false)
            #expect(raw.contains("\r") == false)
            #expect(browser.service(named: raw) == service)
        }
    }

    @Test func parametersUseTheDefaultDomainWithPeerToPeerOff() {
        for service in browser.declared {
            let shaped = browser.parameters(for: service)
            #expect(shaped.includePeerToPeer == false)
            guard case .bonjourTXT(let type, let domain) = shaped.descriptor else {
                Issue.record("a declared type had no browse descriptor")
                return
            }
            #expect(type == service.rawValue)
            #expect(domain == nil)
            #expect(type.utf8.count <= 13)
        }
        let airplay = browser.parameters(for: .airplay)
        let raop = browser.parameters(for: .raop)
        #expect(airplay != raop)
        #expect(airplay.includePeerToPeer == raop.includePeerToPeer)
    }

    @Test func aStartAsksEachDeclaredTypeOnceInOrder() {
        let tally = Tally()
        let slots = browser.start(make(tally, open: true))
        #expect(slots.map(\.service) == browser.declared)
        #expect(slots.allSatisfy { $0.opened })
        #expect(tally.kinds == ["make", "make"])
        #expect(tally.services == [.airplay, .raop])
        #expect(tally.peerToPeer == [false, false])
        #expect(tally.domains == [nil, nil])
        #expect(tally.types == ["_airplay._tcp", "_raop._tcp"])
        #expect(slots.map(\.parameters) == tally.parameters)
        #expect(tally.cancels.isEmpty)
    }

    @Test func aRefusalIsKeptAndTheOtherTypeIsStillAsked() {
        let airplayRefused = Tally()
        let first = browser.start(make(airplayRefused, openAirplay: false, openRaop: true))
        #expect(first.map(\.opened) == [false, true])
        #expect(airplayRefused.kinds == ["make", "make"])
        #expect(airplayRefused.services == [.airplay, .raop])
        #expect(airplayRefused.cancels.isEmpty)
        #expect(browser.cancel(first, cancel(airplayRefused)) == [.raop])
        #expect(airplayRefused.cancels == [.raop])

        let raopRefused = Tally()
        let second = browser.start(make(raopRefused, openAirplay: true, openRaop: false))
        #expect(second.map(\.opened) == [true, false])
        #expect(browser.cancel(second, cancel(raopRefused)) == [.airplay])
        #expect(raopRefused.kinds == ["make", "make", "cancel"])
        #expect(raopRefused.services == [.airplay, .raop])
    }

    @Test func bothRefusalsOpenNothing() {
        let tally = Tally()
        let slots = browser.start(make(tally, open: false))
        #expect(slots.map(\.opened) == [false, false])
        #expect(slots.map(\.service) == browser.declared)
        #expect(tally.kinds == ["make", "make"])
        #expect(browser.cancel(slots, cancel(tally)).isEmpty)
        #expect(tally.cancels.isEmpty)
        #expect(tally.kinds == ["make", "make"])
    }

    @Test func cancelAsksOnlyAnOpenedDeclaredTypeOnce() {
        let tally = Tally()
        let forward = browser.start(make(tally, open: true))
        let reversed = Array(forward.reversed())
        var crowded = reversed
        for _ in 0 ..< 40 {
            crowded.append(forward[1])
        }
        #expect(browser.cancel(reversed, cancel(tally)) == browser.declared)
        #expect(tally.cancels == [.airplay, .raop])
        #expect(browser.cancel(crowded, cancel(tally)) == browser.declared)
        #expect(tally.cancels == [.airplay, .raop, .airplay, .raop])
        #expect(tally.kinds.filter { $0 == "cancel" }.count == 4)
        #expect(tally.kinds.filter { $0 == "make" }.count == 2)
    }

    @Test func aHostileSlotIsNotCancelled() {
        let tally = Tally()
        let evil = browser.Slot(
            service: .airplay,
            parameters: browser.Parameters(descriptor: .bonjourTXT(type: "evil._tcp", domain: "example.com")),
            opened: true
        )
        let local = browser.Slot(
            service: .raop,
            parameters: browser.Parameters(descriptor: .bonjourTXT(type: "_raop._tcp", domain: "local.")),
            opened: true
        )
        let closed = browser.Slot(
            service: .airplay,
            parameters: browser.parameters(for: .airplay),
            opened: false
        )
        let swapped = browser.Slot(
            service: .raop,
            parameters: browser.parameters(for: .airplay),
            opened: true
        )
        #expect(browser.cancel([evil, local, closed, swapped], cancel(tally)).isEmpty)
        #expect(tally.cancels.isEmpty)
        #expect(tally.kinds.isEmpty)

        let opened = browser.Slot(
            service: .airplay,
            parameters: browser.parameters(for: .airplay),
            opened: true
        )
        #expect(browser.cancel([evil, opened, local], cancel(tally)) == [.airplay])
        #expect(tally.cancels == [.airplay])
    }

    @Test func aNameOutsideTheTwoIsRefused() {
        let refused = [
            "",
            " ",
            "\n",
            "\r",
            "\0",
            "\t",
            "_airplay._tcp\0",
            "_airplay._tcp\n",
            "_airplay._tcp\r",
            "_Airplay._tcp",
            "_AIRPLAY._TCP",
            "airplay",
            "_airplay._udp",
            "_airplay._tcp.",
            "_airplay._tcp ",
            " _airplay._tcp",
            "_raop._tcp.local",
            "_raop._tcp\t",
            "\t_raop._tcp",
            "_sleep-proxy._udp",
            "_airplay._tcp_raop._tcp",
            String(repeating: "a", count: 14),
            String(repeating: "b", count: 64),
            String(repeating: "c", count: 4096),
        ]
        for name in refused {
            #expect(browser.service(named: name) == nil)
        }
        #expect(browser.service(named: "_airplay._tcp") == .airplay)
        #expect(browser.service(named: "_raop._tcp") == .raop)
    }

    @Test func aSecondCallStartsEmpty() {
        let tally = Tally()
        let first = browser.start(make(tally, open: true))
        let second = browser.start(make(tally, open: false))
        #expect(first.map(\.opened) == [true, true])
        #expect(second.map(\.opened) == [false, false])
        #expect(first != second)
        #expect(tally.kinds == ["make", "make", "make", "make"])
        #expect(tally.services == [.airplay, .raop, .airplay, .raop])
        #expect(browser.cancel(first, cancel(tally)) == browser.declared)
        #expect(browser.cancel(second, cancel(tally)).isEmpty)
        #expect(tally.cancels == [.airplay, .raop])
    }

    @Test func cancelDoesNotOpenAndStartDoesNotCancel() {
        let startOnly = Tally()
        let slots = browser.start(make(startOnly, open: true))
        #expect(startOnly.kinds == ["make", "make"])
        #expect(startOnly.cancels.isEmpty)
        #expect(slots.count == browser.declared.count)

        let cancelOnly = Tally()
        #expect(browser.cancel([], cancel(cancelOnly)).isEmpty)
        #expect(cancelOnly.kinds.isEmpty)
        #expect(browser.cancel(slots, cancel(cancelOnly)) == browser.declared)
        #expect(cancelOnly.kinds == ["cancel", "cancel"])
        #expect(cancelOnly.services.isEmpty)
        #expect(cancelOnly.parameters.isEmpty)
    }

    private func make(_ tally: Tally, open: Bool) -> SpeakerBrowser.MakeGate {
        make(tally, openAirplay: open, openRaop: open)
    }

    private func make(_ tally: Tally, openAirplay: Bool, openRaop: Bool) -> SpeakerBrowser.MakeGate {
        SpeakerBrowser.MakeGate { parameters in
            tally.note("make", parameters)
            guard case .bonjourTXT(let type, _) = parameters.descriptor else { return false }
            if type == browser.Service.airplay.rawValue { return openAirplay }
            if type == browser.Service.raop.rawValue { return openRaop }
            return false
        }
    }

    private func cancel(_ tally: Tally) -> SpeakerBrowser.CancelGate {
        SpeakerBrowser.CancelGate { service in
            tally.kinds.append("cancel")
            tally.cancels.append(service)
        }
    }
}

private final class Tally: @unchecked Sendable {
    var kinds: [String] = []
    var services: [SpeakerBrowser.Service] = []
    var parameters: [SpeakerBrowser.Parameters] = []
    var types: [String] = []
    var domains: [String?] = []
    var peerToPeer: [Bool] = []
    var cancels: [SpeakerBrowser.Service] = []

    func note(_ kind: String, _ parameters: SpeakerBrowser.Parameters) {
        kinds.append(kind)
        self.parameters.append(parameters)
        peerToPeer.append(parameters.includePeerToPeer)
        guard case .bonjourTXT(let type, let domain) = parameters.descriptor else { return }
        types.append(type)
        domains.append(domain)
        if let service = SpeakerBrowser.service(named: type) {
            services.append(service)
        }
    }
}
