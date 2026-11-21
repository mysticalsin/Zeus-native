import Foundation
import Testing
@testable import ZeusCore

/// S08-02: a notch click opens after the pointer has settled for 0.35 s. The clock is passed in.
@Suite struct NotchClickSettleTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func mouseDownWaitsAndDoesNotOpen() {
        var settle = NotchClickSettle()
        let down = settle.pointerDown(at: now, point: NotchClickPoint(x: 10, y: 20))
        #expect(down == .wait(until: now.addingTimeInterval(NotchClickSettle.delay)))
        #expect(NotchClickSettle.delay == 0.35)
        let early = settle.tick(at: now.addingTimeInterval(0.349), point: NotchClickPoint(x: 10, y: 20))
        #expect(early == .wait(until: now.addingTimeInterval(0.35)))
        let opened = settle.tick(at: now.addingTimeInterval(0.35), point: NotchClickPoint(x: 12, y: 22))
        #expect(opened == .open)
        #expect(settle.tick(at: now.addingTimeInterval(0.5), point: NotchClickPoint(x: 12, y: 22)) == .ignore)
    }

    @Test func aPointerThatLeavesDoesNotOpen() {
        var settle = NotchClickSettle()
        _ = settle.pointerDown(at: now, point: NotchClickPoint(x: 0, y: 0))
        #expect(settle.tick(at: now.addingTimeInterval(0.35), point: NotchClickPoint(x: 40, y: 0)) == .ignore)
    }

    @Test func aPointExactlyOnTheSlopStillOpens() {
        var onTheEdge = NotchClickSettle()
        _ = onTheEdge.pointerDown(at: now, point: NotchClickPoint(x: 0, y: 0))
        let edge = onTheEdge.tick(
            at: now.addingTimeInterval(NotchClickSettle.delay),
            point: NotchClickPoint(x: NotchClickSettle.slop, y: 0))
        #expect(edge == .open)
        var past = NotchClickSettle()
        _ = past.pointerDown(at: now, point: NotchClickPoint(x: 0, y: 0))
        let outside = past.tick(
            at: now.addingTimeInterval(NotchClickSettle.delay),
            point: NotchClickPoint(x: NotchClickSettle.slop + 0.01, y: 0))
        #expect(outside == .ignore)
    }

    /// Mouse-down must arm the wait. Opening before that sleep is the failure.
    @Test func openOnClickDoesNotFinishBeforeTheWait() throws {
        let source = try repoSource("Sources/Zeus/Notch/NotchController.swift")
        let open = source.components(separatedBy: "private func openOnClick()").dropFirst().first ?? ""
        let openBody = open.components(separatedBy: "private func armClickSettle").first ?? open
        #expect(!openBody.contains("finishSettledClick"))
        let arm = source.components(separatedBy: "private func armClickSettle").dropFirst().first ?? ""
        let armBody = arm.components(separatedBy: "private func finishSettledClick").first ?? arm
        let sleep = armBody.range(of: "Task.sleep")
        let finish = armBody.range(of: "finishSettledClick")
        #expect(sleep != nil)
        #expect(finish != nil)
        if let sleep, let finish {
            #expect(sleep.lowerBound < finish.lowerBound)
        }
    }

    @Test func openOnClickUsesTheSettleClock() throws {
        let source = try repoSource("Sources/Zeus/Notch/NotchController.swift")
        #expect(source.contains("NotchClickSettle"))
        #expect(source.contains("private func openOnClick()"))
        let voice = try repoSource("Sources/ZeusCore/VoiceKey.swift")
        #expect(voice.contains("yieldsTo"))
        #expect(voice.contains("pointing"))
        #expect(voice.contains("dictation"))
        #expect(voice.contains("polyglot"))
        #expect(voice.contains("voiceOverOn"))
    }

    private func repoSource(_ relative: String) throws -> String {
        if let root = ProcessInfo.processInfo.environment["ZEUS_REPO"], !root.isEmpty {
            return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(relative), encoding: .utf8)
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        Issue.record("Missing \(relative)")
        return ""
    }
}
