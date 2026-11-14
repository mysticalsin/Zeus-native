import Foundation
import Testing
@testable import ZeusCore

private let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
private let keyJ: UInt16 = 38, keyT: UInt16 = 17, keyP: UInt16 = 35, keyR: UInt16 = 15, keyK: UInt16 = 40, keyZ: UInt16 = 6
private let openBracket: UInt16 = 33

private let live = TileKeyGate(enabled: true)

private func press(_ code: UInt16, _ modifiers: ShortcutModifiers, repeating: Bool = false, own: Bool = false) -> TileKeyEvent {
    TileKeyEvent(phase: .down, keyCode: code, modifiers: modifiers, isRepeat: repeating, isOwnInput: own)
}

private func release(_ code: UInt16, _ modifiers: ShortcutModifiers = [], own: Bool = false) -> TileKeyEvent {
    TileKeyEvent(phase: .up, keyCode: code, modifiers: modifiers, isRepeat: false, isOwnInput: own)
}

@Suite struct TileChordMatcherTests {
    private let base: ShortcutModifiers = [.control, .option]
    private let map = TileKeymap.defaults(base: .controlOption)

    // MARK: What gets consumed

    @Test func everyDefaultChordIsConsumedWithItsActionForEveryBase() {
        for modifierBase in TileModifierBase.allCases {
            let keymap = TileKeymap.defaults(base: modifierBase)
            #expect(!keymap.bindings.isEmpty)
            for binding in keymap.bindings {
                var matcher = TileKeyMatcher()
                let decision = matcher.decide(press(binding.shortcut.keyCode!, binding.shortcut.modifiers), keymap: keymap, gate: live)
                #expect(decision == .consume(binding.action))
            }
        }
    }

    @Test func aKeyThatIsNotBoundPassesThrough() {
        var matcher = TileKeyMatcher()
        // A bare letter, the base with an unbound letter, and a bare arrow.
        #expect(matcher.decide(press(keyJ, []), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(press(keyZ, base), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(press(left, []), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(press(left, [.shift]), keymap: map, gate: live) == .passThrough)
    }

    @Test func onlyTheExactModifierSetMatches() {
        var matcher = TileKeyMatcher()
        // Missing one modifier of the base.
        #expect(matcher.decide(press(left, [.control]), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(press(left, [.option]), keymap: map, gate: live) == .passThrough)
        // One modifier too many: Command added to Control-Option.
        #expect(matcher.decide(press(left, [.control, .option, .command]), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(press(keyJ, [.control, .option, .command]), keymap: map, gate: live) == .passThrough)
        // Shift on a chord that has no shifted bind.
        #expect(matcher.decide(press(keyJ, [.control, .option, .shift]), keymap: map, gate: live) == .passThrough)
        // The same keys with the exact set are consumed.
        #expect(matcher.decide(press(left, base), keymap: map, gate: live) == .consume(.focus(.left)))
        #expect(matcher.decide(press(left, base.union(.shift)), keymap: map, gate: live) == .consume(.swap(.left)))
    }

    @Test func theFnFlagThatMacOSAddsToArrowsStillMatches() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(left, base.union(.function)), keymap: map, gate: live) == .consume(.focus(.left)))
        #expect(matcher.decide(press(up, base.union([.shift, .function])), keymap: map, gate: live) == .consume(.swap(.up)))
        // An unbound key stays unbound with the flag added.
        #expect(matcher.decide(press(keyZ, base.union(.function)), keymap: map, gate: live) == .passThrough)
    }

    @Test func everyKeyCodeAndModifierSetAgreesWithTheKeymapLookup() {
        // The tap may consume only what the keymap binds: exhaustive over key codes and modifier subsets.
        var consumed = 0
        for code in UInt16(0)..<128 {
            for raw in UInt8(0)..<32 {
                let modifiers = ShortcutModifiers(rawValue: raw)
                var matcher = TileKeyMatcher()
                let decision = matcher.decide(press(code, modifiers), keymap: map, gate: live)
                let expected = map.action(for: Shortcut(keyCode: code, modifiers: modifiers))
                if let expected {
                    consumed += 1
                    #expect(decision == .consume(expected), "code \(code) modifiers \(raw)")
                } else {
                    #expect(decision == .passThrough, "code \(code) modifiers \(raw)")
                }
            }
        }
        // Each bound chord also matches with the fn flag added, so there are more hits than bindings.
        #expect(consumed > map.bindings.count)
    }

    @Test func anEmptyKeymapPassesEverythingThrough() {
        var matcher = TileKeyMatcher()
        let empty = TileKeymap()
        #expect(matcher.decide(press(left, base), keymap: empty, gate: live) == .passThrough)
        #expect(matcher.decide(press(keyJ, base), keymap: empty, gate: live) == .passThrough)
        #expect(matcher.decide(release(left), keymap: empty, gate: live) == .passThrough)
    }

    // MARK: Yielding

    @Test func nothingIsConsumedWhileTilingIsOff() {
        let off = TileKeyGate(enabled: false)
        for binding in map.bindings {
            var matcher = TileKeyMatcher()
            #expect(matcher.decide(press(binding.shortcut.keyCode!, binding.shortcut.modifiers), keymap: map, gate: off) == .passThrough)
        }
    }

    @Test func nothingIsConsumedWhileASecureFieldIsActive() {
        let secure = TileKeyGate(enabled: true, secureInput: true)
        for binding in map.bindings {
            var matcher = TileKeyMatcher()
            #expect(matcher.decide(press(binding.shortcut.keyCode!, binding.shortcut.modifiers), keymap: map, gate: secure) == .passThrough)
        }
    }

    @Test func whilePausedOnlyTheResumeChordIsConsumed() {
        let paused = TileKeyGate(enabled: true, paused: true)
        for binding in map.bindings {
            var matcher = TileKeyMatcher()
            let decision = matcher.decide(press(binding.shortcut.keyCode!, binding.shortcut.modifiers), keymap: map, gate: paused)
            if binding.action == .togglePause {
                #expect(decision == .consume(.togglePause))
            } else {
                #expect(decision == .passThrough, "\(binding.action.id)")
            }
        }
    }

    @Test func zeusOwnSyntheticInputAlwaysPassesThrough() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(left, base, own: true), keymap: map, gate: live) == .passThrough)
        // It leaves nothing behind: the matching key-up passes through too.
        #expect(matcher.decide(release(left, own: true), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .passThrough)
    }

    // MARK: Key-up pairing

    @Test func theKeyUpOfAConsumedKeyDownIsConsumedOnce() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(keyJ, base), keymap: map, gate: live) == .consume(.flipSplit))
        #expect(matcher.decide(release(keyJ), keymap: map, gate: live) == .consume(nil))
        // Only once: the next key-up of that key was not ours.
        #expect(matcher.decide(release(keyJ), keymap: map, gate: live) == .passThrough)
    }

    @Test func aKeyUpWithNoConsumedKeyDownPassesThrough() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(release(keyJ), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(release(left, base), keymap: map, gate: live) == .passThrough)
    }

    @Test func theKeyUpIsStillConsumedAfterTilingWasTurnedOffMidPress() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(keyT, base), keymap: map, gate: live) == .consume(.toggleFloat))
        #expect(matcher.decide(release(keyT), keymap: map, gate: TileKeyGate(enabled: false)) == .consume(nil))
        // Modifiers released first: the key-up still pairs with its key-down.
        #expect(matcher.decide(press(keyR, base), keymap: map, gate: live) == .consume(.retile))
        #expect(matcher.decide(release(keyR, []), keymap: map, gate: live) == .consume(nil))
    }

    @Test func twoChordsHeldAtOnceEachPairTheirOwnKeyUp() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(left, base), keymap: map, gate: live) == .consume(.focus(.left)))
        #expect(matcher.decide(press(right, base), keymap: map, gate: live) == .consume(.focus(.right)))
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .consume(nil))
        #expect(matcher.decide(release(right), keymap: map, gate: live) == .consume(nil))
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .passThrough)
    }

    @Test func aStaleConsumedKeyNeverSwallowsLaterTyping() {
        var matcher = TileKeyMatcher()
        // The key-up of a consumed press never arrives (the tap was off for a moment).
        #expect(matcher.decide(press(keyJ, base), keymap: map, gate: live) == .consume(.flipSplit))
        // The next plain press of that key is not a chord: it and its key-up belong to the app.
        #expect(matcher.decide(press(keyJ, []), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(release(keyJ), keymap: map, gate: live) == .passThrough)
    }

    @Test func resetForgetsEveryConsumedKey() {
        var matcher = TileKeyMatcher()
        _ = matcher.decide(press(keyJ, base), keymap: map, gate: live)
        _ = matcher.decide(press(left, base), keymap: map, gate: live)
        matcher.reset()
        #expect(matcher.decide(release(keyJ), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .passThrough)
    }

    // MARK: Autorepeat

    @Test func focusAndNudgeRepeatWhileHeld() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(left, base), keymap: map, gate: live) == .consume(.focus(.left)))
        #expect(matcher.decide(press(left, base, repeating: true), keymap: map, gate: live) == .consume(.focus(.left)))
        #expect(matcher.decide(press(left, base, repeating: true), keymap: map, gate: live) == .consume(.focus(.left)))
        let shifted = base.union(.shift)
        #expect(matcher.decide(press(openBracket, shifted), keymap: map, gate: live) == .consume(.nudge(.left)))
        #expect(matcher.decide(press(openBracket, shifted, repeating: true), keymap: map, gate: live) == .consume(.nudge(.left)))
    }

    @Test func everyOtherActionIgnoresAutorepeatButStillSwallowsIt() {
        let others: [(UInt16, ShortcutModifiers, TileAction)] = [
            (left, base.union(.shift), .swap(.left)), (right, base.union(.shift), .swap(.right)),
            (up, base.union(.shift), .swap(.up)), (down, base.union(.shift), .swap(.down)),
            (keyJ, base, .flipSplit), (keyT, base, .toggleFloat), (keyP, base, .togglePause),
            (keyR, base, .retile), (keyK, base, .showKeys),
        ]
        for (code, modifiers, action) in others {
            var matcher = TileKeyMatcher()
            #expect(matcher.decide(press(code, modifiers), keymap: map, gate: live) == .consume(action))
            #expect(matcher.decide(press(code, modifiers, repeating: true), keymap: map, gate: live) == .consume(nil), "\(action.id)")
            #expect(matcher.decide(press(code, modifiers, repeating: true), keymap: map, gate: live) == .consume(nil), "\(action.id)")
        }
    }

    @Test func onlyFocusAndNudgeAreMarkedRepeatable() {
        let repeatable = TileAction.all.filter(\.repeatsWhileHeld)
        #expect(Set(repeatable) == Set(TileDirection.allCases.map { TileAction.focus($0) } + TileDirection.allCases.map { TileAction.nudge($0) }))
    }

    @Test func aRepeatThatDidNotStartAsAConsumedPressPassesThrough() {
        var matcher = TileKeyMatcher()
        // A plain Left press passed through, then the modifiers joined: the repeats are not a new chord.
        #expect(matcher.decide(press(left, []), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(press(left, base, repeating: true), keymap: map, gate: live) == .passThrough)
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .passThrough)
    }

    @Test func repeatsOfAConsumedPressStaySwallowedAfterAModifierIsReleased() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(left, base), keymap: map, gate: live) == .consume(.focus(.left)))
        // Option let go while Left is still held: the repeat is no longer the chord, and it must not leak as Control-Left.
        #expect(matcher.decide(press(left, [.control], repeating: true), keymap: map, gate: live) == .consume(nil))
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .consume(nil))
        #expect(matcher.decide(release(left), keymap: map, gate: live) == .passThrough)
    }

    @Test func repeatsOfAConsumedPressStaySwallowedWhenTilingTurnsOffMidPress() {
        var matcher = TileKeyMatcher()
        #expect(matcher.decide(press(left, base), keymap: map, gate: live) == .consume(.focus(.left)))
        let off = TileKeyGate(enabled: false)
        #expect(matcher.decide(press(left, base, repeating: true), keymap: map, gate: off) == .consume(nil))
        // A fresh press while off is not touched.
        #expect(matcher.decide(release(left), keymap: map, gate: off) == .consume(nil))
        #expect(matcher.decide(press(left, base), keymap: map, gate: off) == .passThrough)
    }
}

@Suite struct TileTapHealthTests {
    @Test func theFirstDisablesAreReEnabledAndARunOfThemGivesUp() {
        var health = TileTapHealth(maxDisables: 3, within: 10)
        #expect(health.recordDisable(at: 100) == .reenable)
        #expect(health.recordDisable(at: 101) == .reenable)
        #expect(health.recordDisable(at: 102) == .giveUp)
    }

    @Test func disablesFarApartNeverAddUp() {
        var health = TileTapHealth(maxDisables: 3, within: 10)
        for index in 0..<20 {
            #expect(health.recordDisable(at: Double(index) * 11) == .reenable)
        }
    }

    @Test func onlyDisablesInsideTheWindowCount() {
        var health = TileTapHealth(maxDisables: 3, within: 10)
        #expect(health.recordDisable(at: 0) == .reenable)
        #expect(health.recordDisable(at: 5) == .reenable)
        // The first one has aged out by now, so this is the second inside the window.
        #expect(health.recordDisable(at: 12) == .reenable)
        #expect(health.recordDisable(at: 13) == .giveUp)
    }

    @Test func onceGivenUpItStaysGivenUpUntilReset() {
        var health = TileTapHealth(maxDisables: 2, within: 10)
        #expect(health.recordDisable(at: 0) == .reenable)
        #expect(health.recordDisable(at: 1) == .giveUp)
        #expect(health.recordDisable(at: 500) == .giveUp)
        health.reset()
        #expect(health.recordDisable(at: 501) == .reenable)
    }

    @Test func theDefaultsAreThreeInTenSeconds() {
        var health = TileTapHealth()
        #expect(health.recordDisable(at: 0) == .reenable)
        #expect(health.recordDisable(at: 1) == .reenable)
        #expect(health.recordDisable(at: 2) == .giveUp)
    }

    @Test func aLimitBelowOneStillAllowsOneReEnable() {
        var health = TileTapHealth(maxDisables: 0, within: 10)
        // A limit is raised to at least two, so a single stray disable never gives up.
        #expect(health.recordDisable(at: 0) == .reenable)
    }
}
