import Testing
import ZeusCore

@Suite("Consent request single flight")
struct RequestFlightTests {
    @Test func firstRequestBeginsAndMovesToAsking() {
        let (state, effects) = RequestFlight.reduce(.idle, .requested(token: 1))
        #expect(state == .asking(token: 1))
        #expect(effects == [.begin(token: 1)])
    }

    @Test func doubleClickJoinsTheLivePromptInsteadOfAskingAgain() {
        let (asking, _) = RequestFlight.reduce(.idle, .requested(token: 1))
        let (state, effects) = RequestFlight.reduce(asking, .requested(token: 2))
        #expect(state == .asking(token: 1))
        #expect(effects == [.join(token: 1)])
    }

    @Test func finishingWithTheLiveTokenReturnsToIdle() {
        let (state, effects) = RequestFlight.reduce(.asking(token: 3), .finished(token: 3))
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func staleFinishIsIgnored() {
        let (state, effects) = RequestFlight.reduce(.asking(token: 4), .finished(token: 3))
        #expect(state == .asking(token: 4))
        #expect(effects.isEmpty)
    }

    @Test func finishWhileIdleIsIgnored() {
        let (state, effects) = RequestFlight.reduce(.idle, .finished(token: 1))
        #expect(state == .idle)
        #expect(effects.isEmpty)
    }

    @Test func abandonFromEveryStateReachesIdle() {
        #expect(RequestFlight.reduce(.idle, .abandoned).0 == .idle)
        #expect(RequestFlight.reduce(.asking(token: 9), .abandoned).0 == .idle)
    }

    @Test func requestAfterFailureAsksAgain() {
        var flights = RequestFlights<String>()
        guard case .begin(let first) = flights.request("voice") else {
            Issue.record("first request must begin")
            return
        }
        #expect(flights.finish("voice", token: first))
        #expect(!flights.isAsking("voice"))
        guard case .begin(let second) = flights.request("voice") else {
            Issue.record("a retry after the answer must begin again")
            return
        }
        #expect(second != first)
    }

    @Test func keysAreIndependentAndJoinSharesTheLiveToken() {
        var flights = RequestFlights<String>()
        guard case .begin(let voice) = flights.request("voice") else { Issue.record("begin"); return }
        guard case .begin(let camera) = flights.request("camera") else { Issue.record("camera is its own prompt"); return }
        #expect(voice != camera)
        #expect(flights.request("voice") == .join(token: voice))
        #expect(flights.request("camera") == .join(token: camera))
    }

    @Test func staleTokenCannotFinishANewerRequest() {
        var flights = RequestFlights<String>()
        guard case .begin(let first) = flights.request("voice") else { Issue.record("begin"); return }
        flights.abandon("voice")
        guard case .begin(let second) = flights.request("voice") else { Issue.record("begin after abandon"); return }
        #expect(!flights.finish("voice", token: first))
        #expect(flights.isAsking("voice"))
        #expect(flights.finish("voice", token: second))
    }

    @Test func abandonAllClearsEveryKey() {
        var flights = RequestFlights<String>()
        _ = flights.request("a")
        _ = flights.request("b")
        flights.abandonAll()
        #expect(!flights.isAsking("a"))
        #expect(!flights.isAsking("b"))
    }
}
