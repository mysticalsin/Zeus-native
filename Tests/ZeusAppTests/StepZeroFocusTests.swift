import Foundation
import Testing
@testable import Zeus

@Suite("Step zero focus")
struct StepZeroFocusTests {
    @Test func aNameDoesNotSurviveAndAMissingKeyIsANo() {
        let token = "ZephyrMint"
        let people = "AllowedCircle"
        let body = """
        {"\(FocusSection.liveRecordsKey)":[{"modeId":"m1","name":"\(token)","symbol":"moon.fill","people":"\(people)"}]}
        """
        let decoded = FocusSection.decode(Data(body.utf8))
        guard case .live(let facts) = decoded else {
            Issue.record("expected a live fact")
            return
        }
        #expect(facts.count == 1)
        #expect(facts[0] == FocusSection.Fact(hasModeId: true, hasName: true, hasSymbol: true))
        #expect(kept(decoded).contains(token) == false)
        #expect(kept(decoded).contains(people) == false)

        let missing = FocusSection.decode(Data("{\"\(FocusSection.liveRecordsKey)\":[{}]}".utf8))
        #expect(missing == .live([FocusSection.Fact(hasModeId: false, hasName: false, hasSymbol: false)]))

        let number = FocusSection.decode(
            Data("{\"\(FocusSection.liveRecordsKey)\":[{\"modeId\":\"m\",\"name\":12,\"symbol\":\"\"}]}".utf8)
        )
        #expect(number == .live([FocusSection.Fact(hasModeId: true, hasName: false, hasSymbol: false)]))

        let absent = FocusSection.decode(Data("{\"other\":true}".utf8))
        #expect(absent == .off)
        #expect(FocusSection.decode(Data("{\"\(FocusSection.liveRecordsKey)\":null}".utf8)) == .off)
        #expect(FocusSection.decode(Data("{\"\(FocusSection.liveRecordsKey)\":[]}".utf8)) == .off)
        #expect(FocusSection.decode(Data("[]".utf8)) == .malformed)
        #expect(FocusSection.decode(Data("{".utf8)) == .malformed)
        #expect(
            FocusSection.decode(Data("{\"\(FocusSection.liveRecordsKey)\":\"nope\"}".utf8)) == .malformed
        )

        var trace = atWatch()
        _ = trace.step(.pressStart)
        #expect(trace.step(.record(Data(body.utf8))).isEmpty)
        #expect(trace.state.facts == [FocusSection.Fact(hasModeId: true, hasName: true, hasSymbol: true)])
        #expect(kept(trace.state).contains(token) == false)
        #expect(kept(trace.state).contains(people) == false)
    }

    @Test func historyIsIgnoredAndBytesOverTheCapAreRefused() {
        #expect(FocusSection.maxBytes == 4 * 1024 * 1024)
        #expect(FocusSection.maxRecords == 64)

        let hidden = "HiddenMint"
        let history = """
        {"history":[{"name":"\(hidden)","modeId":"old","symbol":"secret.fill"}],"note":"\(hidden)"}
        """
        let ignored = FocusSection.decode(Data(history.utf8))
        #expect(ignored == .off)
        #expect(kept(ignored).contains(hidden) == false)

        let over = FocusSection.decode(Data(count: FocusSection.maxBytes + 1))
        #expect(over == .tooLarge)
        let atCap = FocusSection.decode(Data(count: FocusSection.maxBytes))
        #expect(atCap == .malformed)

        var rows = Array(repeating: "{}", count: 64)
        rows.append("{\"name\":\"ExtraMint\",\"modeId\":\"z\",\"symbol\":\"a.b\"}")
        let many = "{\"\(FocusSection.liveRecordsKey)\":[\(rows.joined(separator: ","))]}"
        let capped = FocusSection.decode(Data(many.utf8))
        guard case .live(let facts) = capped else {
            Issue.record("expected 64 live facts")
            return
        }
        #expect(facts.count == 64)
        #expect(facts.allSatisfy { $0 == FocusSection.Fact(hasModeId: false, hasName: false, hasSymbol: false) })
        #expect(kept(capped).contains("ExtraMint") == false)

        var trace = atWatch()
        #expect(trace.step(.record(Data(history.utf8))).isEmpty)
        #expect(trace.state.decode == .off)
        #expect(trace.state.facts.isEmpty)
        #expect(kept(trace.state).contains(hidden) == false)
        #expect(trace.step(.record(Data(count: FocusSection.maxBytes + 1))).isEmpty)
        #expect(trace.state.decode == .tooLarge)
        #expect(trace.state.facts.isEmpty)
    }

    @Test func aGrantThatStartsOnEndsOn() {
        let on = FocusSection.script(starting: .on)
        #expect(on.first == .files)
        #expect(on.last == .flipOn)
        #expect(on.firstIndex(of: .flipOff)! < on.firstIndex(of: .errno)!)
        #expect(on.firstIndex(of: .errno)! < on.firstIndex(of: .prompt)!)
        #expect(on.firstIndex(of: .prompt)! < on.firstIndex(of: .flipOn)!)

        let trace = finish(.on)
        #expect(trace.state.phase == .done)
        #expect(trace.state.grantAtStart == .on)
        #expect(trace.state.endedGrant == .on)
        #expect(trace.state.grantLive == true)
        #expect(trace.state.assertionsExist == true)
        #expect(trace.state.configurationsExist == false)
        #expect(trace.state.modes == 2)
        #expect(trace.state.withName == 2)
        #expect(trace.state.withSymbol == 1)
        #expect(trace.state.symbolsResolve == 1)
        #expect(trace.state.write == .inPlace)
        #expect(trace.state.schedule == .notTried)
        #expect(trace.state.phone == .no)
        #expect(trace.state.recordWhileNoFocus == false)
        #expect(trace.state.childCanRead == .yes)
        #expect(trace.state.errno == .missing)
        #expect(trace.state.promptSeen == true)
        #expect(trace.state.listed == false)

        let grant = trace.effects.firstIndex(of: .readGrant)
        let files = trace.effects.firstIndex(of: .readStore(.assertions))
        let watch = trace.effects.firstIndex(of: .armFileSource)
        let stop = trace.effects.firstIndex(of: .stopWatch)
        let tool = trace.effects.firstIndex(of: .runTool)
        let off = trace.effects.firstIndex(of: .setGrant(.off))
        let errno = trace.effects.firstIndex(of: .readErrno)
        let prompt = trace.effects.firstIndex(of: .askPrompt)
        let back = trace.effects.lastIndex(of: .setGrant(.on))
        #expect(grant != nil && files != nil && watch != nil && stop != nil && tool != nil)
        #expect(off != nil && errno != nil && prompt != nil && back != nil)
        #expect(grant! < files!)
        #expect(files! < watch!)
        #expect(watch! < stop!)
        #expect(stop! < tool!)
        #expect(tool! < off!)
        #expect(off! < errno!)
        #expect(errno! < prompt!)
        #expect(prompt! < back!)
    }

    @Test func aGrantThatStartsOffEndsOffAndReadsTheErrorFirst() {
        let off = FocusSection.script(starting: .off)
        #expect(off.first == .errno)
        #expect(off.last == .flipOff)
        #expect(off.firstIndex(of: .errno)! < off.firstIndex(of: .flipOn)!)
        #expect(off.firstIndex(of: .flipOn)! < off.firstIndex(of: .tool)!)
        #expect(off.firstIndex(of: .tool)! < off.firstIndex(of: .flipOff)!)

        let trace = finish(.off)
        #expect(trace.state.phase == .done)
        #expect(trace.state.grantAtStart == .off)
        #expect(trace.state.endedGrant == .off)
        #expect(trace.state.errno == .missing)
        #expect(trace.state.childCanRead == .yes)

        let errno = trace.effects.firstIndex(of: .readErrno)
        let prompt = trace.effects.firstIndex(of: .askPrompt)
        let on = trace.effects.firstIndex(of: .setGrant(.on))
        let tool = trace.effects.firstIndex(of: .runTool)
        let back = trace.effects.lastIndex(of: .setGrant(.off))
        #expect(errno != nil && prompt != nil && on != nil && tool != nil && back != nil)
        #expect(errno! < prompt!)
        #expect(prompt! < on!)
        #expect(on! < tool!)
        #expect(tool! < back!)
    }

    @Test func anInPlaceRewriteIsSeenByTheFileSourceOnly() {
        var early = atWatch()
        #expect(early.step(.fileRewritten).isEmpty)
        #expect(early.state.changeSeen == false)
        #expect(early.step(.folderEvent).isEmpty)
        #expect(early.state.seenBy == nil)

        var trace = atWatch()
        #expect(trace.step(.pressStart).isEmpty)
        #expect(trace.step(.folderEvent).isEmpty)
        #expect(trace.state.changeSeen == false)
        #expect(trace.state.reopened == false)
        #expect(trace.step(.fileRewritten).isEmpty)
        #expect(trace.state.changeSeen == true)
        #expect(trace.state.seenBy == .fileEvent)
        #expect(trace.state.reopened == false)
        #expect(trace.effects.contains(.reopenFileSource) == false)
        #expect(trace.step(.fileReplaced).isEmpty)
        #expect(trace.state.seenBy == .fileEvent)
        #expect(trace.step(.stampChanged).isEmpty)
        #expect(trace.state.seenBy == .fileEvent)
    }

    @Test func aReplacedFileReopensTheSource() {
        var trace = atWatch()
        _ = trace.step(.pressStart)
        #expect(trace.step(.fileReplaced) == [.reopenFileSource])
        #expect(trace.state.seenBy == .fileEvent)
        #expect(trace.state.reopened == true)
        #expect(trace.state.changeSeen == true)
        #expect(trace.effects.filter { $0 == .reopenFileSource }.count == 1)
        #expect(trace.step(.fileReplaced).isEmpty)
        #expect(trace.effects.filter { $0 == .reopenFileSource }.count == 1)

        var fromFolder = atWatch()
        _ = fromFolder.step(.sources(file: false, folder: true))
        _ = fromFolder.step(.pressStart)
        #expect(fromFolder.step(.fileRewritten).isEmpty)
        #expect(fromFolder.state.changeSeen == false)
        #expect(fromFolder.step(.fileReplaced) == [.reopenFileSource])
        #expect(fromFolder.state.seenBy == .folderEvent)
        #expect(fromFolder.state.reopened == true)
    }

    @Test func bothSourcesDisabledStillSeeTheQuarterSecondCheck() {
        #expect(FocusSection.pollMilliseconds == 250)

        var trace = atWatch()
        #expect(trace.step(.sources(file: false, folder: false)).isEmpty)
        #expect(trace.step(.pressStart).isEmpty)
        #expect(trace.step(.fileRewritten).isEmpty)
        #expect(trace.step(.fileReplaced).isEmpty)
        #expect(trace.step(.folderEvent).isEmpty)
        #expect(trace.state.changeSeen == false)
        #expect(trace.effects.contains(.reopenFileSource) == false)
        #expect(trace.step(.waited(milliseconds: 249)).isEmpty)
        #expect(trace.step(.stampChanged).isEmpty)
        #expect(trace.state.seenBy == nil)
        #expect(trace.step(.waited(milliseconds: 1)).isEmpty)
        #expect(trace.state.clockMs == 250)
        #expect(trace.step(.stampChanged).isEmpty)
        #expect(trace.state.changeSeen == true)
        #expect(trace.state.seenBy == .poll)
        #expect(trace.state.changedWithin == .w2s)
        #expect(trace.step(.waited(milliseconds: 0)).isEmpty)
        #expect(trace.step(.waited(milliseconds: -5)).isEmpty)
        #expect(trace.state.clockMs == 250)
    }

    @Test func theWindowIsCountedFromThePress() {
        #expect(FocusSection.changeWindow(milliseconds: 0) == .w2s)
        #expect(FocusSection.changeWindow(milliseconds: 2_000) == .w2s)
        #expect(FocusSection.changeWindow(milliseconds: 2_001) == .w10s)
        #expect(FocusSection.changeWindow(milliseconds: 10_000) == .w10s)
        #expect(FocusSection.changeWindow(milliseconds: 10_001) == .w30s)
        #expect(FocusSection.changeWindow(milliseconds: 30_000) == .w30s)
        #expect(FocusSection.changeWindow(milliseconds: 30_001) == .none)
        #expect(FocusSection.writeShape(before: 8, after: 8) == .inPlace)
        #expect(FocusSection.writeShape(before: 8, after: 9) == .replaced)
        #expect(FocusSection.writeShape(before: nil, after: 9) == .unknown)
        #expect(FocusSection.writeShape(before: 8, after: nil) == .unknown)

        #expect(window(after: 0) == .w2s)
        #expect(window(after: 2_000) == .w2s)
        #expect(window(after: 2_001) == .w10s)
        #expect(window(after: 10_000) == .w10s)
        #expect(window(after: 10_001) == .w30s)
        #expect(window(after: 30_000) == .w30s)
        #expect(window(after: 30_001) == FocusSection.ChangeWindow.none)
    }

    @Test func theToolReadsTheExitAndTimesOutAtFiveSeconds() {
        #expect(FocusSection.toolLimitMilliseconds == 5_000)
        #expect(FocusSection.childRead(exit: 0) == .yes)
        #expect(FocusSection.childRead(exit: 1) == .no)
        #expect(FocusSection.childRead(exit: 2) == .no)

        var gate = untilGate(.tool, grant: .on)
        #expect(gate.state.phase == .gate)
        #expect(gate.effects.contains(.runTool) == false)
        #expect(gate.effects.contains(.readSelf) == false)
        #expect(gate.step(.tool(exit: 0)).isEmpty)
        #expect(gate.state.childCanRead == nil)
        #expect(gate.step(.continueAsked) == [.readSelf])
        #expect(gate.step(.tool(exit: 0)).isEmpty)
        #expect(gate.step(.selfCanRead(false)) == [.runTool])
        #expect(gate.state.selfCanRead == false)
        #expect(gate.step(.tool(exit: 7)) == [])
        #expect(gate.state.childCanRead == .no)
        #expect(gate.step(.tool(exit: 0)).isEmpty)
        #expect(gate.state.childCanRead == .no)

        var quiet = untilGate(.tool, grant: .on)
        _ = quiet.step(.continueAsked)
        #expect(quiet.step(.selfCanRead(true)) == [.runTool])
        #expect(quiet.step(.waited(milliseconds: 4_999)).isEmpty)
        #expect(quiet.state.phase == .awaitTool)
        #expect(quiet.state.childCanRead == nil)
        #expect(quiet.step(.waited(milliseconds: 1)).isEmpty)
        #expect(quiet.state.childCanRead == .timedOut)
        #expect(quiet.step(.tool(exit: 0)).isEmpty)
        #expect(quiet.state.childCanRead == .timedOut)
        #expect(quiet.effects.filter { $0 == .runTool }.count == 1)

        var yes = untilGate(.tool, grant: .on)
        _ = yes.step(.continueAsked)
        _ = yes.step(.selfCanRead(true))
        #expect(yes.step(.tool(exit: 0)).isEmpty)
        #expect(yes.state.childCanRead == .yes)
    }

    @Test func aFlipThatNeverLandsLeavesTheGrantWhereItStarted() {
        #expect(FocusSection.grantWatchMilliseconds == 30_000)

        var on = untilGate(.flipOff, grant: .on)
        #expect(on.step(.continueAsked) == [.setGrant(.off)])
        #expect(on.step(.waited(milliseconds: 29_999)).isEmpty)
        #expect(on.state.phase == .awaitFlip)
        #expect(on.state.grantNow == .on)
        #expect(on.step(.waited(milliseconds: 1)).isEmpty)
        #expect(on.state.grantLive == false)
        #expect(on.state.grantNow == .on)
        #expect(on.state.phase == .done)
        #expect(on.state.endedGrant == .on)
        #expect(on.effects.contains(.readErrno) == false)
        #expect(on.effects.contains(.askPrompt) == false)
        #expect(on.effects.contains(.setGrant(.on)) == false)
        #expect(on.step(.grantFlipped(.off)).isEmpty)
        #expect(on.state.endedGrant == .on)

        var off = Trace()
        _ = off.step(.begin)
        _ = off.step(.grant(.off))
        _ = off.step(.continueAsked)
        _ = off.step(.errno(.denied))
        _ = off.step(.continueAsked)
        _ = off.step(.prompt(seen: false, listed: true))
        #expect(off.step(.continueAsked) == [.setGrant(.on)])
        #expect(off.state.errno == .denied)
        #expect(off.state.promptSeen == false)
        #expect(off.state.listed == true)
        #expect(off.step(.waited(milliseconds: 30_000)).isEmpty)
        #expect(off.state.grantLive == false)
        #expect(off.state.grantNow == .off)
        #expect(off.step(.grantFlipped(.on)).isEmpty)
        let done = finishRest(&off)
        #expect(done.state.phase == .done)
        #expect(done.state.endedGrant == .off)
        #expect(done.state.childCanRead == .noGrant)
        #expect(done.effects.contains(.runTool) == false)
        #expect(done.effects.contains(.readSelf) == false)
        #expect(done.effects.contains(.setGrant(.off)) == false)
    }
}

private struct Trace {
    var state = FocusSection.fresh()
    var effects: [FocusSection.Effect] = []

    mutating func step(_ event: FocusSection.Event) -> [FocusSection.Effect] {
        let (next, out) = FocusSection.reduce(state, event)
        state = next
        effects.append(contentsOf: out)
        return out
    }
}

private func kept(_ value: Any) -> String {
    var found: [String] = []
    func walk(_ value: Any) {
        if let text = value as? String {
            found.append(text)
            return
        }
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            walk(child.value)
        }
    }
    walk(value)
    return found.joined(separator: "\n") + "\n" + String(reflecting: value)
}

private func atWatch() -> Trace {
    var trace = Trace()
    _ = trace.step(.begin)
    _ = trace.step(.grant(.on))
    _ = trace.step(.continueAsked)
    _ = trace.step(.files(assertions: true, configurations: true))
    _ = trace.step(.continueAsked)
    return trace
}

private func window(after milliseconds: Int) -> FocusSection.ChangeWindow? {
    var trace = atWatch()
    _ = trace.step(.pressStart)
    if milliseconds > 0 {
        _ = trace.step(.waited(milliseconds: milliseconds))
    }
    _ = trace.step(.fileRewritten)
    return trace.state.changedWithin
}

private func untilGate(_ wanted: FocusSection.Step, grant: FocusSection.Grant) -> Trace {
    var trace = Trace()
    _ = trace.step(.begin)
    _ = trace.step(.grant(grant))
    for _ in 0..<40 {
        if trace.state.phase == .gate, trace.state.cursor < trace.state.script.count,
           trace.state.script[trace.state.cursor] == wanted {
            return trace
        }
        let before = trace.state
        advance(&trace)
        if trace.state == before { break }
    }
    return trace
}

private func finish(_ grant: FocusSection.Grant) -> Trace {
    var trace = Trace()
    _ = trace.step(.begin)
    _ = trace.step(.grant(grant))
    return finishRest(&trace)
}

private func finishRest(_ trace: inout Trace) -> Trace {
    for _ in 0..<40 {
        if trace.state.phase == .done { break }
        let before = trace.state
        advance(&trace)
        if trace.state == before { break }
    }
    return trace
}

private func advance(_ trace: inout Trace) {
    switch trace.state.phase {
    case .gate:
        _ = trace.step(.continueAsked)
    case .awaitFiles:
        _ = trace.step(.files(assertions: true, configurations: false))
    case .watching:
        _ = trace.step(.withinSecond(true))
    case .awaitCounts:
        _ = trace.step(.counts(modes: 2, withName: 2, withSymbol: 1, symbolsResolve: 1))
    case .awaitInodes:
        _ = trace.step(.inodes(before: 4, after: 4))
    case .awaitSchedule:
        _ = trace.step(.schedule(.notTried))
    case .awaitPhone:
        _ = trace.step(.phone(.no))
    case .awaitMirror:
        _ = trace.step(.mirror(recordWhileNoFocus: false, carriesModeId: false))
    case .awaitSelf:
        _ = trace.step(.selfCanRead(true))
    case .awaitTool:
        _ = trace.step(.tool(exit: 0))
    case .awaitFlip:
        let grant: FocusSection.Grant = trace.state.script[trace.state.cursor] == .flipOn ? .on : .off
        _ = trace.step(.grantFlipped(grant))
    case .awaitErrno:
        _ = trace.step(.errno(.missing))
    case .awaitPrompt:
        _ = trace.step(.prompt(seen: true, listed: false))
    case .idle, .awaitGrant, .done:
        break
    }
}
