import Foundation
import Testing
@testable import ZeusCore

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
}

/// The handoff loop as it behaved before it became a state machine: check, then sleep, then one last check.
private func specTrace(attempts: Int, hits: [Bool]) -> (matched: Bool, sleeps: Int, observations: Int) {
    let turns = max(attempts, 1)
    var index = 0
    var sleeps = 0
    func read() -> Bool {
        let hit = index < hits.count ? hits[index] : false
        index += 1
        return hit
    }
    for _ in 0..<turns {
        if read() { return (true, sleeps, index) }
        sleeps += 1
    }
    return (read(), sleeps, index)
}

private func machineTrace(attempts: Int, hits: [Bool]) -> (matched: Bool, sleeps: Int, observations: Int) {
    var state = FrontmostHandoff.start(target: "wanted", attempts: attempts)
    var index = 0
    var sleeps = 0
    var guardSteps = 0
    while guardSteps < hits.count + attempts + 4 {
        guardSteps += 1
        switch state {
        case .matched:
            return (true, sleeps, index)
        case .unmatched:
            return (false, sleeps, index)
        case .checking, .finalLook:
            let hit = index < hits.count ? hits[index] : false
            index += 1
            let (next, effect) = FrontmostHandoff.reduce(state, hit ? .hit : .miss)
            state = next
            if effect == .sleep { sleeps += 1 }
        }
    }
    Issue.record("handoff did not reach a terminal state")
    return (false, sleeps, index)
}

@Suite("Dictation preview rules")
struct DictationPreviewRulesTests {
    @Test func returnEnterShiftAndEscape() {
        let modifiers = [(false, false), (true, false), (false, true), (true, true)]
        for (shift, command) in modifiers {
            let insert = shift && !command ? DictationPreviewKey.edit : DictationPreviewKey.insert
            #expect(DictationPreviewKey.action(keyCode: 36, shift: shift, command: command) == insert)
            #expect(DictationPreviewKey.action(keyCode: 76, shift: shift, command: command) == insert)
            #expect(DictationPreviewKey.action(keyCode: 53, shift: shift, command: command) == .cancel)
        }
        for code: UInt16 in [0, 35, 37, 52, 54, 75, 77, .max] {
            for (shift, command) in modifiers {
                #expect(DictationPreviewKey.action(keyCode: code, shift: shift, command: command) == .edit)
            }
        }
    }

    @Test func everyKeyOutsideReturnEnterAndEscapeEdits() {
        var offenders: [UInt16] = []
        var code: UInt32 = 0
        while code < 65536 {
            let key = UInt16(code)
            if key != 36, key != 76, key != 53 {
                for shift in [false, true] {
                    for command in [false, true] where DictationPreviewKey.action(keyCode: key, shift: shift, command: command) != .edit {
                        offenders.append(key)
                    }
                }
            }
            code += 1
        }
        #expect(offenders.isEmpty)
    }

    @Test func blankReviewInsertsNothingAndOtherTextKeepsItsWords() {
        for blank in ["", " ", "\n", "\t", " \n\t ", "\u{00A0}"] {
            #expect(DictationPreviewResult.finalText(blank) == nil)
        }
        #expect(DictationPreviewResult.finalText("a") == "a")
        #expect(DictationPreviewResult.finalText(" a ") == "a")
        #expect(DictationPreviewResult.finalText("a b") == "a b")
        #expect(DictationPreviewResult.finalText("  hello world \n") == "hello world")
    }

    @Test func randomReviewTextMatchesATrim() {
        var rng = SplitMix(state: 7)
        let alphabet: [Character] = ["a", "b", " ", "\n", "\t", "Z"]
        for _ in 0..<200 {
            let count = rng.int(12)
            let raw = String((0..<count).map { _ in alphabet[rng.int(alphabet.count)] })
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let expected: String? = trimmed.isEmpty ? nil : trimmed
            #expect(DictationPreviewResult.finalText(raw) == expected)
        }
    }

    @Test func handoffStatesMatchTheCheckThenSleepLoop() {
        #expect(FrontmostHandoff.start(target: nil, attempts: 5) == .unmatched)
        #expect(FrontmostHandoff.start(target: "wanted", attempts: 0) == .checking(remaining: 1))
        #expect(FrontmostHandoff.start(target: "wanted", attempts: -4) == .checking(remaining: 1))
        #expect(FrontmostHandoff.start(target: "wanted", attempts: 1) == .checking(remaining: 1))
        #expect(FrontmostHandoff.start(target: "wanted", attempts: 12) == .checking(remaining: 12))
        #expect(FrontmostHandoff.start(target: "wanted", attempts: .min) == .checking(remaining: 1))
        #expect(FrontmostHandoff.start(target: "wanted", attempts: .max) == .checking(remaining: .max))

        let checking = FrontmostHandoff.State.checking(remaining: 2)
        let (continued, slept) = FrontmostHandoff.reduce(checking, .miss)
        #expect(continued == .checking(remaining: 1))
        #expect(slept == .sleep)
        let (lastLoop, lastSleep) = FrontmostHandoff.reduce(.checking(remaining: 1), .miss)
        #expect(lastLoop == .finalLook)
        #expect(lastSleep == .sleep)
        let (hit, noSleep) = FrontmostHandoff.reduce(.checking(remaining: 1), .hit)
        #expect(hit == .matched && noSleep == nil)
        let (finalHit, _) = FrontmostHandoff.reduce(.finalLook, .hit)
        #expect(finalHit == .matched)
        let (finalMiss, finalEffect) = FrontmostHandoff.reduce(.finalLook, .miss)
        #expect(finalMiss == .unmatched && finalEffect == nil)
        #expect(FrontmostHandoff.reduce(.matched, .miss) == (.matched, nil))
        #expect(FrontmostHandoff.reduce(.unmatched, .hit) == (.unmatched, nil))
    }

    @Test func randomHandoffTracesFollowTheLoop() {
        var rng = SplitMix(state: 99)
        for _ in 0..<80 {
            let attempts = rng.int(9) - 2
            let hits = (0..<8).map { _ in rng.int(3) == 0 }
            #expect(machineTrace(attempts: attempts, hits: hits) == specTrace(attempts: attempts, hits: hits))
        }
    }

    @Test @MainActor func theWaitingFunctionPerformsTheMachine() async {
        var reads = 0
        var sleeps = 0
        let names = ["other", "other", "wanted"]
        let ok = await FrontmostHandoff.waitUntilFrontmost(target: "wanted", current: {
            defer { reads += 1 }
            return names[min(reads, names.count - 1)]
        }, attempts: 5, sleep: { sleeps += 1 })
        #expect(ok)
        #expect(reads == 3)
        #expect(sleeps == 2)

        var stuckReads = 0
        var stuckSleeps = 0
        let gaveUp = await FrontmostHandoff.waitUntilFrontmost(target: "wanted", current: {
            stuckReads += 1
            return "other"
        }, attempts: 3, sleep: { stuckSleeps += 1 })
        #expect(!gaveUp)
        #expect(stuckReads == 4)
        #expect(stuckSleeps == 3)

        var nilReads = 0
        let missing = await FrontmostHandoff.waitUntilFrontmost(target: nil, current: {
            nilReads += 1
            return "wanted"
        }, attempts: 4, sleep: { Issue.record("a missing target must not wait") })
        #expect(!missing)
        #expect(nilReads == 0)
    }
}
