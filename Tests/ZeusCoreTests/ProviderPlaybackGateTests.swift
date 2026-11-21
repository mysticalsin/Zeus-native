import Testing
@testable import ZeusCore

@Suite("Provider playback gate")
struct ProviderPlaybackGateTests {
    @Test func theNextLineWaitsUntilProviderPlaybackEnds() {
        let gate = ProviderPlaybackGate()
        #expect(!gate.isPlaying)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        let first = gate.begin()
        #expect(gate.isPlaying)
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        #expect(ProviderSentencePump.holds(chainPlaying: false, systemRendering: false, providerPlaying: gate.isPlaying))
        #expect(ProviderSentencePump.isSpeaking(synthesizer: false, pump: false, chainPlaying: false, systemRendering: false, providerPlaying: gate.isPlaying))
        var spoken: [String] = []
        var queue = ["first sentence", "second sentence"]
        if ProviderSentencePump.canDequeue(queueEmpty: queue.isEmpty, providerPlaying: gate.isPlaying) {
            spoken.append(queue.removeFirst())
        }
        #expect(spoken.isEmpty)
        gate.end(first)
        #expect(!gate.isPlaying)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: queue.isEmpty, providerPlaying: gate.isPlaying))
        if ProviderSentencePump.canDequeue(queueEmpty: queue.isEmpty, providerPlaying: gate.isPlaying) {
            spoken.append(queue.removeFirst())
        }
        #expect(spoken == ["first sentence"])
        #expect(!ProviderSentencePump.isSpeaking(synthesizer: false, pump: false, chainPlaying: false, systemRendering: false, providerPlaying: false))
    }

    @Test func aLateFinishDoesNotClearANewerPlayback() {
        let gate = ProviderPlaybackGate()
        let first = gate.begin()
        gate.reset()
        let second = gate.begin()
        gate.end(first)
        #expect(gate.isPlaying)
        gate.end(second)
        #expect(!gate.isPlaying)
    }

    /// ZB-027: a second clip bumps the generation, so ending the first token is ignored and
    /// ending the second only drops one level. The gate stays engaged after both clips are done.
    @Test func overlappingClipsLeaveTheGateEngaged() {
        let gate = ProviderPlaybackGate()
        let first = gate.begin()
        let second = gate.begin()
        #expect(first != second)
        #expect(gate.isPlaying)
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        gate.end(first)
        #expect(gate.isPlaying)
        gate.end(second)
        #expect(!gate.isPlaying)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
    }

    @Test func overlappingPlayersReleaseWhenEachEnds() {
        let stands = [ClipStandIn(1), ClipStandIn(2)]
        let gate = ProviderPlaybackGate()
        _ = gate.begin(player: ObjectIdentifier(stands[0]))
        _ = gate.begin(player: ObjectIdentifier(stands[1]))
        gate.endPlayer(ObjectIdentifier(stands[0]))
        #expect(gate.active == 1)
        #expect(gate.isPlaying)
        #expect(!gate.isOpen)
        gate.endPlayer(ObjectIdentifier(stands[1]))
        #expect(gate.active == 0)
        #expect(gate.isOpen)
        gate.endPlayer(ObjectIdentifier(stands[0]))
        #expect(gate.isOpen)
    }

    @Test func endingTheNewestTokenTwiceDoesNotReleaseTheOlderClip() {
        let gate = ProviderPlaybackGate()
        let older = gate.begin()
        let newer = gate.begin()
        gate.end(newer)
        gate.end(newer, .finished)
        #expect(gate.active == 1)
        #expect(gate.isPlaying)
        gate.end(older)
        #expect(gate.isOpen)
        gate.end(older)
        #expect(gate.active == 0)
    }

    @Test func endingTheOlderClipFirstStillLeavesTheNewerOnePlaying() {
        let gate = ProviderPlaybackGate()
        let older = gate.begin()
        let middle = gate.begin()
        let newer = gate.begin()
        gate.end(middle, .cancelled)
        #expect(gate.active == 2)
        gate.fail(older)
        #expect(gate.active == 1)
        #expect(gate.isPlaying)
        gate.end(newer)
        #expect(gate.isOpen)
    }

    @Test func finishCancelAndFailureEachReleaseOneClip() {
        let gate = ProviderPlaybackGate()
        let finished = gate.begin()
        let cancelled = gate.begin()
        let failed = gate.begin()
        #expect(gate.active == 3)
        gate.end(finished, .finished)
        #expect(gate.active == 2)
        gate.cancel(cancelled)
        #expect(gate.active == 1)
        #expect(!gate.isOpen)
        gate.fail(failed)
        #expect(gate.active == 0)
        #expect(gate.isOpen)
        gate.end(finished)
        gate.cancel(cancelled)
        gate.fail(failed)
        #expect(gate.isOpen)
    }

    @Test func eachResolutionReturnsASingleClipToOpen() {
        let resolutions: [ProviderClipResolution] = [.finished, .cancelled, .failed]
        for resolution in resolutions {
            let gate = ProviderPlaybackGate()
            #expect(gate.isOpen)
            #expect(gate.active == 0)
            let token = gate.begin()
            #expect(!gate.isOpen)
            #expect(gate.active == 1)
            gate.end(token, resolution)
            #expect(gate.isOpen)
            #expect(!gate.isPlaying)
            gate.end(token, resolution)
            #expect(gate.active == 0)
        }
    }

    @Test func anUnknownTokenDoesNotMoveTheGate() {
        let stand = ClipStandIn(9)
        let gate = ProviderPlaybackGate()
        gate.end(0)
        gate.end(-1)
        gate.cancel(3)
        gate.fail(-8)
        gate.endPlayer(ObjectIdentifier(stand))
        #expect(gate.isOpen)
        let token = gate.begin()
        gate.end(token &- 1, .failed)
        gate.cancel(token &+ 1)
        #expect(gate.active == 1)
        #expect(gate.isPlaying)
        gate.end(token)
        #expect(gate.isOpen)
    }

    @Test func resetCancelsEveryOutstandingClip() {
        let stands = [ClipStandIn(1), ClipStandIn(2)]
        let gate = ProviderPlaybackGate()
        let first = gate.begin()
        let second = gate.begin(player: ObjectIdentifier(stands[0]))
        let third = gate.begin(player: ObjectIdentifier(stands[1]))
        gate.reset()
        #expect(gate.isOpen)
        gate.end(first)
        gate.cancel(second)
        gate.fail(third)
        gate.endPlayer(ObjectIdentifier(stands[0]))
        gate.endPlayer(ObjectIdentifier(stands[1]))
        #expect(gate.active == 0)
        let fourth = gate.begin()
        gate.end(first)
        #expect(gate.active == 1)
        #expect(!gate.isOpen)
        gate.end(fourth, .finished)
        #expect(gate.isOpen)
    }

    @Test func beginningTheSamePlayerTwiceKeepsTheOlderToken() {
        let stand = ClipStandIn(4)
        let id = ObjectIdentifier(stand)
        let gate = ProviderPlaybackGate()
        let older = gate.begin(player: id)
        let newer = gate.begin(player: id)
        #expect(older != newer)
        gate.endPlayer(id)
        #expect(gate.active == 1)
        #expect(gate.isPlaying)
        gate.endPlayer(id)
        #expect(gate.active == 1)
        gate.end(older, .cancelled)
        #expect(gate.isOpen)
        gate.end(newer, .failed)
        #expect(gate.isOpen)
    }

    @Test func endingByTokenAndByPlayerReleasesTheClipOnce() {
        let stand = ClipStandIn(5)
        let id = ObjectIdentifier(stand)
        let gate = ProviderPlaybackGate()
        let keep = gate.begin()
        let token = gate.begin(player: id)
        gate.end(token)
        gate.endPlayer(id)
        gate.fail(token)
        #expect(gate.active == 1)
        gate.cancel(keep)
        #expect(gate.isOpen)

        let again = ProviderPlaybackGate()
        let held = again.begin()
        let played = again.begin(player: id)
        again.endPlayer(id)
        again.end(played, .finished)
        again.cancel(played)
        #expect(again.active == 1)
        again.fail(held)
        #expect(again.isOpen)
    }

    @Test func aHundredOverlappingClipsReleaseInEitherOrder() {
        for reversed in [false, true] {
            let gate = ProviderPlaybackGate()
            var tokens: [Int] = []
            for _ in 0..<100 {
                tokens.append(gate.begin())
            }
            #expect(gate.active == 100)
            #expect(!gate.isOpen)
            if reversed { tokens.reverse() }
            for (index, token) in tokens.enumerated() {
                if index.isMultiple(of: 3) {
                    gate.cancel(token)
                } else if index.isMultiple(of: 3) == false && index.isMultiple(of: 2) {
                    gate.fail(token)
                } else {
                    gate.end(token)
                }
                #expect(gate.active == 100 - index - 1)
                #expect(gate.isOpen == (gate.active == 0))
            }
            #expect(gate.isOpen)
            #expect(!gate.isPlaying)
        }
    }

    @Test func thePumpDequeuesOnlyWhenTheQueueHasALineAndTheGateIsOpen() {
        let gate = ProviderPlaybackGate()
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: true, providerPlaying: gate.isPlaying))
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying) == gate.isOpen)
        let token = gate.begin()
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        #expect(ProviderSentencePump.holds(chainPlaying: false, systemRendering: false, providerPlaying: gate.isPlaying))
        gate.cancel(token)
        #expect(gate.isOpen)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying))
        #expect(!ProviderSentencePump.canDequeue(queueEmpty: true, providerPlaying: gate.isPlaying))
        #expect(!ProviderSentencePump.isSpeaking(synthesizer: false, pump: false, chainPlaying: false, systemRendering: false, providerPlaying: gate.isPlaying))
    }

    @Test func theMachineReleasesOnlyTheTokenNamedByFinishCancelOrFailure() {
        let stand = ClipStandIn(7)
        let id = ObjectIdentifier(stand)
        var machine = ProviderPlaybackMachine()
        #expect(machine.isOpen)
        #expect(machine.active == 0)
        let first = machine.reduce(.begin)
        let second = machine.reduce(.beginPlayer(id))
        #expect(first != nil)
        #expect(second != nil)
        #expect(machine.active == 2)
        machine.reduce(.finished(first!))
        machine.reduce(.finished(first!))
        #expect(machine.active == 1)
        #expect(machine.isPlaying)
        machine.reduce(.endPlayer(id))
        machine.reduce(.endPlayer(id))
        #expect(machine.isOpen)
        let third = machine.reduce(.begin)!
        machine.reduce(.failed(third))
        #expect(machine.active == 0)
        let fourth = machine.reduce(.begin)!
        machine.reduce(.cancelled(fourth))
        #expect(machine.isOpen)
        machine.reduce(.reset)
        machine.reduce(.failed(fourth))
        machine.reduce(.endPlayer(id))
        #expect(machine.active == 0)
        #expect(machine.isOpen == (machine.active == 0))
    }

    @Test func randomStartAndStopInterleavingsLeaveTheGateOpenExactlyWhenNothingIsActive() {
        let stands = (0..<6).map { ClipStandIn($0) }
        let ids = stands.map { ObjectIdentifier($0) }
        var rng = GateWalk(state: 0x0000_5B027)
        for _ in 0..<500 {
            let gate = ProviderPlaybackGate()
            var model = ClipModel()
            check(gate, model)
            for _ in 0..<48 {
                switch Int(rng.next() % 8) {
                case 0:
                    model.began(gate.begin())
                case 1:
                    let id = ids[Int(rng.next() % UInt64(ids.count))]
                    model.began(gate.begin(player: id), player: id)
                case 2:
                    let token = chooseToken(&rng, model)
                    gate.end(token, .finished)
                    model.resolved(token)
                case 3:
                    let token = chooseToken(&rng, model)
                    gate.cancel(token)
                    model.resolved(token)
                case 4:
                    let token = chooseToken(&rng, model)
                    gate.fail(token)
                    model.resolved(token)
                case 5:
                    let id = ids[Int(rng.next() % UInt64(ids.count))]
                    gate.endPlayer(id)
                    model.endedPlayer(id)
                case 6:
                    gate.reset()
                    model.reset()
                default:
                    let token = staleToken(&rng, model)
                    gate.end(token)
                    model.resolved(token)
                }
                check(gate, model)
            }
        }
    }

    private func check(_ gate: ProviderPlaybackGate, _ model: ClipModel) {
        #expect(gate.isOpen == (model.count == 0))
        #expect(gate.isPlaying == (model.count > 0))
        #expect(gate.active == model.count)
        #expect(ProviderSentencePump.canDequeue(queueEmpty: false, providerPlaying: gate.isPlaying) == gate.isOpen)
    }

    private func chooseToken(_ rng: inout GateWalk, _ model: ClipModel) -> Int {
        let live = model.active.sorted()
        if !live.isEmpty && rng.next() % 4 != 0 {
            return live[Int(rng.next() % UInt64(live.count))]
        }
        return staleToken(&rng, model)
    }

    private func staleToken(_ rng: inout GateWalk, _ model: ClipModel) -> Int {
        if !model.retired.isEmpty && rng.next() % 2 == 0 {
            return model.retired[Int(rng.next() % UInt64(model.retired.count))]
        }
        return Int(rng.next() % 5) - 2
    }
}

private final class ClipStandIn {
    let label: Int
    init(_ label: Int) { self.label = label }
}

private struct GateWalk {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Independent count of clips the test has not released. The gate is open exactly when this is empty.
private struct ClipModel {
    var active: Set<Int> = []
    var players: [ObjectIdentifier: Int] = [:]
    var retired: [Int] = []

    var count: Int { active.count }

    mutating func began(_ token: Int, player: ObjectIdentifier? = nil) {
        active.insert(token)
        if let player { players[player] = token }
    }

    mutating func resolved(_ token: Int) {
        guard active.remove(token) != nil else { return }
        retired.append(token)
        for id in players.filter({ $0.value == token }).map(\.key) {
            players[id] = nil
        }
    }

    mutating func endedPlayer(_ id: ObjectIdentifier) {
        guard let token = players.removeValue(forKey: id) else { return }
        resolved(token)
    }

    mutating func reset() {
        retired.append(contentsOf: active.sorted())
        active.removeAll()
        players.removeAll()
    }
}
