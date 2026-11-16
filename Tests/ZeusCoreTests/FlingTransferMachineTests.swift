import Foundation
import Testing
@testable import ZeusCore

private let stack = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
private func sha(_ text: String) -> String { FlingCrypto.sha256Hex(Data(text.utf8)) }

@Suite("Fling send machine")
struct FlingSendMachineTests {
    private func items() -> [FlingSendItem] {
        [FlingSendItem(index: 0, name: "a.png", size: 5, kind: .file, uti: "public.png", url: nil),
         FlingSendItem(index: 1, name: "Link", size: 0, kind: .link, uti: nil, url: "https://example.com"),
         FlingSendItem(index: 2, name: "b.mov", size: 3, kind: .file, uti: nil, url: nil)]
    }
    private func machine() -> FlingSendMachine { FlingSendMachine(stackID: stack, items: items()) }
    private func hashed(_ m: inout FlingSendMachine) -> [FlingSendEffect] {
        var out = m.handle(.hashReady(index: 2, sha256: sha("c")))
        out += m.handle(.hashReady(index: 0, sha256: sha("a")))
        out += m.handle(.hashReady(index: 1, sha256: sha("l")))
        return out
    }

    /// REG-679: the offer goes out only after every hash is ready, with the hashes it was given.
    @Test func theOfferWaitsForEveryHash() throws {
        var m = machine()
        let start = m.handle(.start)
        #expect(start == [.computeHash(index: 0), .computeHash(index: 1), .computeHash(index: 2)])
        #expect(m.state == .hashing)
        let out1 = m.handle(.hashReady(index: 0, sha256: sha("a")))
        #expect(out1.isEmpty)
        let out2 = m.handle(.hashReady(index: 2, sha256: sha("c")))
        #expect(out2.isEmpty)
        #expect(m.state == .hashing)
        let last = m.handle(.hashReady(index: 1, sha256: sha("l")))
        #expect(m.state == .awaitingAccept)
        guard case .send(.offer(let offer))? = last.first else { Issue.record("no offer"); return }
        #expect(offer.stackID == stack)
        #expect(offer.items.map(\.sha256) == [sha("a"), sha("l"), sha("c")])
        #expect(offer.items[1].url == "https://example.com" && offer.items[1].kind == .link)
        #expect(offer.items[0].url == nil)
    }

    @Test func theNamesInAnOfferAreCleanedBeforeTheyLeave() {
        var m = FlingSendMachine(stackID: stack, items: [FlingSendItem(index: 0, name: "../evil.txt", size: 1, kind: .file, uti: nil, url: nil)])
        _ = m.handle(.start)
        let out = m.handle(.hashReady(index: 0, sha256: sha("x")))
        guard case .send(.offer(let offer))? = out.first else { Issue.record("no offer"); return }
        #expect(offer.items[0].name == "_evil.txt")
    }

    @Test func anAcceptStreamsTheFilesInOrderAndSkipsLinks() throws {
        var m = machine(); _ = m.handle(.start); _ = hashed(&m)
        let out3 = m.handle(.received(.accept(FlingStackRef(stackID: UUID()))))
        #expect(out3.isEmpty) // another stack
        let out4 = m.handle(.received(.accept(FlingStackRef(stackID: stack))))
        #expect(out4 == [.streamFile(index: 0)])
        #expect(m.state == .sending(index: 0, sent: 0))
        let out5 = m.handle(.progress(sent: 4))
        #expect(out5.isEmpty)
        #expect(m.state == .sending(index: 0, sent: 4))
        let out6 = m.handle(.fileSent(index: 0))
        #expect(out6 == [.send(.fileDone(FlingFileDone(index: 0))), .streamFile(index: 2)])
        #expect(m.state == .sending(index: 2, sent: 0))
        let out7 = m.handle(.fileSent(index: 2))
        #expect(out7 == [.send(.fileDone(FlingFileDone(index: 2)))])
        #expect(m.state == .finishing)
        let out8 = m.handle(.received(.itemResult(FlingItemResult(index: 0, ok: true))))
        #expect(out8.isEmpty)
        let out9 = m.handle(.received(.stackDone(FlingStackRef(stackID: stack))))
        #expect(out9 == [.close])
        #expect(m.state == .done)
    }

    @Test func anOfferOfOnlyLinksFinishesAtOnce() {
        var m = FlingSendMachine(stackID: stack, items: [FlingSendItem(index: 0, name: "Link", size: 0, kind: .link, uti: nil, url: "https://example.com")])
        _ = m.handle(.start); _ = m.handle(.hashReady(index: 0, sha256: sha("l")))
        let out10 = m.handle(.received(.accept(FlingStackRef(stackID: stack))))
        #expect(out10.isEmpty)
        #expect(m.state == .finishing)
    }

    @Test func aDeclineEndsItWithTheReason() {
        var m = machine(); _ = m.handle(.start); _ = hashed(&m)
        let out11 = m.handle(.received(.decline(FlingDecline(stackID: stack, reason: .diskFull))))
        #expect(out11 == [.close])
        #expect(m.state == .declined(.diskFull))
    }

    /// REG-679: cancel from any non-final state sends cancel and closes; a lost peer fails without resuming.
    @Test func cancelFromAnyStateSendsCancelAndALostPeerNeverResumes() {
        for steps in 0...3 {
            var m = machine(); _ = m.handle(.start)
            if steps >= 1 { _ = hashed(&m) }
            if steps >= 2 { _ = m.handle(.received(.accept(FlingStackRef(stackID: stack)))) }
            if steps >= 3 { _ = m.handle(.fileSent(index: 0)) }
            let out12 = m.handle(.userCancel)
            #expect(out12 == [.send(.cancel(FlingStackRef(stackID: stack))), .close], "step \(steps)")
            #expect(m.state == .cancelled)
            let out13 = m.handle(.userCancel)
            #expect(out13.isEmpty)
            let out14 = m.handle(.received(.accept(FlingStackRef(stackID: stack))))
            #expect(out14.isEmpty)
        }
        var lost = machine(); _ = lost.handle(.start); _ = hashed(&lost); _ = lost.handle(.received(.accept(FlingStackRef(stackID: stack))))
        let out15 = lost.handle(.connectionLost)
        #expect(out15 == [.close])
        #expect(lost.state == .failed(.peerLost))
        let out16 = lost.handle(.received(.accept(FlingStackRef(stackID: stack))))
        #expect(out16.isEmpty)
        let out17 = lost.handle(.fileSent(index: 0))
        #expect(out17.isEmpty)
        #expect(lost.state == .failed(.peerLost))
    }

    @Test func aMismatchOrAPeerCancelEndsIt() {
        var bad = machine(); _ = bad.handle(.start); _ = hashed(&bad); _ = bad.handle(.received(.accept(FlingStackRef(stackID: stack))))
        let out18 = bad.handle(.received(.itemResult(FlingItemResult(index: 0, ok: false))))
        #expect(out18 == [.close])
        #expect(bad.state == .failed(.hashMismatch))
        var gone = machine(); _ = gone.handle(.start); _ = hashed(&gone)
        let out19 = gone.handle(.received(.cancel(FlingStackRef(stackID: stack))))
        #expect(out19 == [.close])
        #expect(gone.state == .cancelled)
    }
}

@Suite("Fling receive machine")
struct FlingReceiveMachineTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private let gib: Int64 = 1024 * 1024 * 1024

    private func offer(_ names: [String] = ["a.png", "Link", "b.mov"], sizes: [Int64] = [5, 0, 3]) -> FlingOffer {
        FlingOffer(stackID: stack, items: [
            FlingOfferItem(index: 0, name: names[0], size: sizes[0], kind: .file, uti: nil, sha256: sha("a"), url: nil),
            FlingOfferItem(index: 1, name: names[1], size: 0, kind: .link, uti: nil, sha256: sha("https://example.com"), url: "https://example.com"),
            FlingOfferItem(index: 2, name: names[2], size: sizes[2], kind: .file, uti: nil, sha256: sha("c"), url: nil),
        ])
    }
    private func context(paired: Bool = true, auto: Bool = true, replay: Bool = false, free: Int64 = 100 * 1024 * 1024 * 1024) -> FlingReceiveContext {
        FlingReceiveContext(peerID: "idA", peerName: "Tony's Mac", paired: paired, autoAccept: auto, freeBytes: free, isReplay: replay)
    }
    private func accepted() -> FlingReceiveMachine {
        var m = FlingReceiveMachine(context: context())
        _ = m.handle(.received(.offer(offer()), now: t0))
        return m
    }
    private func chunk(_ i: UInt32, _ n: Int) -> FlingReceiveEvent { .received(.chunk(FlingChunk(index: i, bytes: Data(count: n))), now: t0) }
    private func declines(_ effects: [FlingReceiveEffect]) -> [FlingDeclineReason] {
        effects.compactMap { if case .send(.decline(let d)) = $0 { return d.reason } else { return nil } }
    }

    @Test func aPairedPeerWithAutoAcceptIsAcceptedAtOnce() {
        var m = FlingReceiveMachine(context: context())
        let out = m.handle(.received(.offer(offer()), now: t0))
        #expect(out == [.makeTemp(stackID: stack), .send(.accept(FlingStackRef(stackID: stack)))])
        #expect(m.state == .receiving(index: 0, got: 0))
    }

    @Test func theWholeStackLandsFileByFileAndTheLinkIsAnItemToo() {
        var m = accepted()
        let out20 = m.handle(chunk(0, 5))
        #expect(out20 == [.write(index: 0, data: Data(count: 5))])
        #expect(m.state == .receiving(index: 0, got: 5))
        let out21 = m.handle(.received(.fileDone(FlingFileDone(index: 0)), now: t0))
        #expect(out21 == [.verify(index: 0)])
        #expect(m.state == .verifying(index: 0))
        let out22 = m.handle(.hashComputed(index: 0, sha256: sha("a")))
        #expect(out22 == [.commit(index: 0)])
        #expect(m.state == .committing(index: 0))
        // The commit of file 0 moves on to the link, which has no bytes.
        let out23 = m.handle(.committed(index: 0))
        #expect(out23 == [.addToShelf(index: 0), .send(.itemResult(FlingItemResult(index: 0, ok: true))), .commitLink(index: 1, url: "https://example.com")])
        #expect(m.state == .committing(index: 1))
        let out24 = m.handle(.committed(index: 1))
        #expect(out24 == [.addToShelf(index: 1), .send(.itemResult(FlingItemResult(index: 1, ok: true)))])
        #expect(m.state == .receiving(index: 2, got: 0))
        _ = m.handle(chunk(2, 3)); _ = m.handle(.received(.fileDone(FlingFileDone(index: 2)), now: t0))
        _ = m.handle(.hashComputed(index: 2, sha256: sha("c")))
        let end = m.handle(.committed(index: 2))
        #expect(end == [.addToShelf(index: 2), .send(.itemResult(FlingItemResult(index: 2, ok: true))), .send(.stackDone(FlingStackRef(stackID: stack))), .close])
        #expect(m.state == .done)
        #expect(!end.contains(.deleteTemp))
    }

    /// REG-669: bytes beyond the declared size fail the transfer.
    @Test func bytesBeyondTheDeclaredSizeFailTheTransfer() {
        var m = accepted()
        _ = m.handle(chunk(0, 5))
        let out = m.handle(chunk(0, 1))
        #expect(m.state == .failed(.overSize))
        #expect(out.contains(.deleteTemp) && out.contains(.close))
        #expect(declines(out) == [.overSize])
        #expect(!out.contains { if case .write = $0 { return true } else { return false } })
    }

    @Test func aFileDoneThatIsShortFailsAndAChunkForTheWrongItemIsMalformed() {
        var short = accepted(); _ = short.handle(chunk(0, 2))
        let out = short.handle(.received(.fileDone(FlingFileDone(index: 0)), now: t0))
        #expect(short.state == .failed(.hashMismatch) && out.contains(.deleteTemp))
        var wrong = accepted()
        let w = wrong.handle(chunk(2, 1))
        #expect(wrong.state == .failed(.malformed) && w.contains(.deleteTemp))
        var link = accepted()
        _ = link.handle(chunk(7, 1))
        #expect(link.state == .failed(.malformed))
    }

    /// REG-670: a hash that does not match deletes the temp file, tells the sender, and commits nothing.
    @Test func aHashMismatchDeletesTheTempFileAndTellsTheSender() {
        var m = accepted()
        _ = m.handle(chunk(0, 5)); _ = m.handle(.received(.fileDone(FlingFileDone(index: 0)), now: t0))
        let out = m.handle(.hashComputed(index: 0, sha256: sha("tampered")))
        #expect(m.state == .failed(.hashMismatch))
        #expect(out.contains(.deleteTemp))
        #expect(out.contains(.send(.itemResult(FlingItemResult(index: 0, ok: false)))))
        #expect(!out.contains(.commit(index: 0)) && !out.contains(.addToShelf(index: 0)))
    }

    @Test func aLinkWhoseHashDoesNotMatchItsAddressIsNotKept() {
        var o = offer(); o.items[1].sha256 = sha("https://elsewhere.example")
        var m = FlingReceiveMachine(context: context())
        _ = m.handle(.received(.offer(o), now: t0))
        _ = m.handle(chunk(0, 5)); _ = m.handle(.received(.fileDone(FlingFileDone(index: 0)), now: t0))
        _ = m.handle(.hashComputed(index: 0, sha256: sha("a")))
        let out = m.handle(.committed(index: 0))
        #expect(m.state == .failed(.hashMismatch))
        #expect(!out.contains(.commitLink(index: 1, url: "https://example.com")))
        #expect(out.contains(.deleteTemp))
    }

    /// REG-671: every end state except done deletes the partial folder.
    @Test func everyEndStateExceptDoneDeletesTheTempFolder() {
        func ends(_ build: () -> (FlingReceiveMachine, [FlingReceiveEffect])) -> (FlingReceiveState, [FlingReceiveEffect]) { let (m, e) = build(); return (m.state, e) }
        var results: [(String, FlingReceiveState, [FlingReceiveEffect])] = []
        do { var m = accepted(); let e = m.handle(.userCancel); results.append(("userCancel", m.state, e)) }
        do { var m = accepted(); let e = m.handle(.received(.cancel(FlingStackRef(stackID: stack)), now: t0)); results.append(("peerCancel", m.state, e)) }
        do { var m = accepted(); let e = m.handle(.connectionLost); results.append(("lost", m.state, e)) }
        do { var m = FlingReceiveMachine(context: context(auto: false)); _ = m.handle(.received(.offer(offer()), now: t0)); let e = m.handle(.userDecline); results.append(("decline", m.state, e)) }
        do { var m = FlingReceiveMachine(context: context(auto: false)); _ = m.handle(.received(.offer(offer()), now: t0)); let e = m.handle(.tick(now: t0.addingTimeInterval(60))); results.append(("timeout", m.state, e)) }
        do { var m = FlingReceiveMachine(context: context(replay: true)); let e = m.handle(.received(.offer(offer()), now: t0)); results.append(("replay", m.state, e)) }
        do { var m = accepted(); _ = m.handle(chunk(0, 5)); _ = m.handle(.received(.fileDone(FlingFileDone(index: 0)), now: t0)); _ = m.handle(.hashComputed(index: 0, sha256: sha("a"))); let e = m.handle(.commitFailed(index: 0)); results.append(("commitFailed", m.state, e)) }
        for (name, state, effects) in results {
            #expect(effects.contains(.deleteTemp), "\(name)")
            #expect(effects.contains(.close), "\(name)")
            #expect(state != .done, "\(name)")
        }
    }

    /// REG-674: an offer that breaks a rule is declined with its reason before anyone is asked.
    @Test func aBadOfferIsDeclinedBeforeAnyPrompt() {
        let cases: [(FlingOffer, FlingReceiveFailure, FlingDeclineReason)] = [
            (offer(["../evil.txt", "Link", "b"]), .badName, .badName),
            (FlingOffer(stackID: stack, items: []), .tooMany, .tooMany),
            (offer(sizes: [200 * 1024 * 1024 * 1024, 0, 3]), .diskFull, .diskFull),
        ]
        for (o, failure, reason) in cases {
            var m = FlingReceiveMachine(context: context(auto: false))
            let out = m.handle(.received(.offer(o), now: t0))
            #expect(m.state == .failed(failure))
            #expect(declines(out) == [reason])
            #expect(!out.contains { if case .prompt = $0 { return true } else { return false } })
            #expect(out.contains(.deleteTemp))
        }
        var unpaired = FlingReceiveMachine(context: context(paired: false))
        let out = unpaired.handle(.received(.offer(offer()), now: t0))
        #expect(unpaired.state == .failed(.notPaired) && declines(out) == [.notPaired])
    }

    /// REG-672: a repeat of a stack id is declined as a replay.
    @Test func aReplayedStackIsDeclined() {
        var m = FlingReceiveMachine(context: context(replay: true))
        let out = m.handle(.received(.offer(offer()), now: t0))
        #expect(m.state == .failed(.replay) && declines(out) == [.replay])
    }

    @Test func aPromptWaitsSixtySecondsThenCountsAsADecline() {
        var m = FlingReceiveMachine(context: context(auto: false))
        let out = m.handle(.received(.offer(offer()), now: t0))
        #expect(out == [.prompt(peerName: "Tony's Mac", itemCount: 3, totalBytes: 8, stackID: stack)])
        #expect(m.state == .prompting(deadline: t0.addingTimeInterval(60)))
        let out25 = m.handle(.tick(now: t0.addingTimeInterval(59)))
        #expect(out25.isEmpty)
        let late = m.handle(.tick(now: t0.addingTimeInterval(60)))
        #expect(m.state == .declined(.timeout))
        #expect(declines(late) == [.timeout] && late.contains(.hidePrompt))

        var yes = FlingReceiveMachine(context: context(auto: false))
        _ = yes.handle(.received(.offer(offer()), now: t0))
        let out26 = yes.handle(.userAccept)
        #expect(out26 == [.makeTemp(stackID: stack), .send(.accept(FlingStackRef(stackID: stack))), .hidePrompt])
        #expect(yes.state == .receiving(index: 0, got: 0))

        var no = FlingReceiveMachine(context: context(auto: false))
        _ = no.handle(.received(.offer(offer()), now: t0))
        let d = no.handle(.userDecline)
        #expect(no.state == .declined(.declined) && declines(d) == [.declined])
    }

    @Test func aFinishedMachineIgnoresLateEvents() {
        var m = accepted(); _ = m.handle(.userCancel)
        let out27 = m.handle(chunk(0, 1))
        let out28 = m.handle(.userAccept)
        #expect(out27.isEmpty && out28.isEmpty)
        #expect(m.state == .cancelled)
    }
}
