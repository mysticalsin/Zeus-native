import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The Carbon hot keys let go while a recorder listens (docs/ULTRON-CHORD-PLAN.md). Two recorders, or one that begins again,
/// must not give them back while another still listens, and a recorder that the app leaves must stop listening.
@Suite("Shortcut recorder pauses the global hot keys", .serialized) @MainActor
struct ShortcutRecorderModelTests {
    private func watching(_ test: (() -> [Bool]) -> Void) {
        let saved = ShortcutRecorderModel.pauseGlobalHotkeys
        defer { ShortcutRecorderModel.pauseGlobalHotkeys = saved }
        var calls: [Bool] = []
        ShortcutRecorderModel.pauseGlobalHotkeys = { calls.append($0) }
        test { calls }
    }

    @Test func twoRecordersKeepTheKeysPausedUntilTheLastOneStops() {
        watching { calls in
            let first = ShortcutRecorderModel(), second = ShortcutRecorderModel()
            first.begin { _ in }
            second.begin { _ in }
            first.end()
            #expect(calls() == [true], "the second recorder still listens: \(calls())")
            second.end()
            #expect(calls() == [true, false], "\(calls())")
            second.end()
            #expect(calls() == [true, false], "ending twice gives nothing back twice: \(calls())")
        }
    }

    @Test func aRecorderThatBeginsAgainDoesNotLetGoOfThePause() {
        watching { calls in
            let model = ShortcutRecorderModel()
            model.begin { _ in }
            model.begin { _ in }
            #expect(calls() == [true], "no gap in the pause: \(calls())")
            model.end()
            #expect(calls() == [true, false], "\(calls())")
        }
    }

    @Test func leavingTheAppEndsTheRecordingAndGivesTheKeysBack() {
        watching { calls in
            let model = ShortcutRecorderModel()
            model.begin { _ in }
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
            #expect(!model.recording && calls() == [true, false], "a local monitor hears nothing once another app is in front: \(calls())")
        }
    }
}
