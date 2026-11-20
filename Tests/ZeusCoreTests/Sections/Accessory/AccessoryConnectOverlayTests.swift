import Foundation
import Testing
import ZeusCore

@Suite("Accessory connect overlay")
struct AccessoryConnectOverlayTests {
    @Test func theOverlayStartsClosedAndIgnoresConnects() {
        var machine = AccessoryConnectOverlayMachine()
        #expect(machine.phase == .closed)
        #expect(machine.gate == .closed)
        #expect(machine.handle(.connected(AccessoryConnectInput.preview)).isEmpty)
        #expect(machine.phase == .closed)
        #expect(machine.handle(.appearFinished).isEmpty)
        #expect(machine.handle(.dismiss).isEmpty)
        #expect(machine.handle(.dismissFinished).isEmpty)
        #expect(machine.handle(.disconnected).isEmpty)
        #expect(machine.phase == .closed)
    }

    @Test func bothGatesMustBeOpenBeforeAConnectPresents() {
        let flags = [false, true]
        for enabled in flags {
            for style in AccessoryOverlayStyle.allCases {
                for motion in flags {
                    let gate = AccessoryOverlayGate(connectEnabled: enabled, style: style, reduceMotion: motion)
                    var machine = AccessoryConnectOverlayMachine(gate: gate)
                    #expect(machine.gate.admits == (enabled && style != .off))
                    #expect(machine.gate.duration == (motion ? 0 : MotionTokens.crossfadeDuration))
                    #expect(machine.gate.duration >= 0)
                    if machine.gate.admits {
                        #expect(machine.phase == .armed)
                    } else {
                        #expect(machine.phase == .closed)
                    }
                    let effects = machine.handle(.connected(AccessoryConnectInput.preview))
                    if !machine.gate.admits {
                        #expect(effects.isEmpty)
                        #expect(machine.phase == .closed)
                    } else if motion {
                        #expect(effects == [.showNow])
                        #expect(machine.phase.content?.duration == 0)
                        if case .visible(let content) = machine.phase {
                            #expect(content.style == style)
                        } else {
                            Issue.record("reduce motion should show at once")
                        }
                    } else {
                        #expect(effects == [.animateIn(MotionTokens.crossfadeDuration)])
                        if case .appearing(let content) = machine.phase {
                            #expect(content.style == style)
                            #expect(content.duration == MotionTokens.crossfadeDuration)
                        } else {
                            Issue.record("motion should appear first")
                        }
                    }
                }
            }
        }
    }

    @Test func unknownChargeIsNeverShownAsZero() {
        let unknown = AccessoryChargeReading(left: 0, right: 50, caseCharge: nil, known: false)
        #expect(unknown.display.summary == "Unknown")
        #expect(unknown.display.left == "Unknown")
        #expect(!unknown.display.summary.contains("0"))
        #expect(!unknown.display.summary.contains("%"))

        let zero = AccessoryChargeReading(left: 0, right: nil, caseCharge: 100, known: true)
        #expect(zero.display.left == "0%")
        #expect(zero.display.right == "Unknown")
        #expect(zero.display.caseText == "100%")
        #expect(zero.display.summary == "Left 0%, Case 100%")

        let outside = AccessoryChargeReading(left: -1, right: 101, caseCharge: 40, known: true)
        #expect(outside.display.left == "Unknown")
        #expect(outside.display.right == "Unknown")
        #expect(outside.display.caseText == "40%")
        #expect(outside.display.summary == "Case 40%")

        let blank = AccessoryChargeReading(left: nil, right: nil, caseCharge: nil, known: true)
        #expect(blank.display.summary == "Unknown")
    }

    @Test func aBlankConnectIsIgnoredAndListeningModeHidesWhenAbsent() {
        let blankID = AccessoryConnectInput(
            id: " ",
            name: "Buds",
            connected: true,
            charge: AccessoryChargeReading(left: 10, right: 10, caseCharge: 10, known: true),
            listeningMode: "Indoor"
        )
        #expect(blankID.sanitized == nil)
        let disconnected = AccessoryConnectInput.preview
        var notConnected = disconnected
        notConnected.connected = false
        #expect(notConnected.sanitized == nil)

        let unnamed = AccessoryConnectInput(
            id: "a",
            name: " \n ",
            connected: true,
            charge: AccessoryChargeReading(left: 0, right: 1, caseCharge: 2, known: false),
            listeningMode: "  "
        )
        let clean = unnamed.sanitized
        #expect(clean?.name == "Earbuds")
        #expect(clean?.listeningMode == nil)
        #expect(clean?.charge.known == false)
        #expect(clean?.charge.left == nil)

        var machine = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .split, reduceMotion: true
        ))
        #expect(machine.handle(.connected(blankID)).isEmpty)
        #expect(machine.phase == .armed)
        _ = machine.handle(.connected(unnamed))
        let content = machine.phase.content
        #expect(content?.showsListeningMode == false)
        #expect(content?.title == "Earbuds")
        #expect(content?.accessibilityLabel.contains("Unknown") == true)
        #expect(content?.style == .split)
        #expect(content?.lines == ["Left Unknown", "Right Unknown", "Case Unknown"])
    }

    @Test func theLifecycleIsAppearShowDismissAndADismissStaysDownUntilReconnect() {
        var machine = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .compact, reduceMotion: false
        ))
        let first = AccessoryConnectInput.preview
        #expect(machine.handle(.connected(first)) == [.animateIn(MotionTokens.crossfadeDuration)])
        #expect(machine.handle(.appearFinished).isEmpty)
        guard case .visible(let shown) = machine.phase else {
            Issue.record("expected visible")
            return
        }
        #expect(shown.showsListeningMode == false)
        #expect(shown.style == .compact)
        #expect(machine.handle(.appearFinished).isEmpty)
        #expect(machine.handle(.dismissFinished).isEmpty)
        #expect(machine.phase.content?.title == first.name)

        #expect(machine.handle(.dismiss) == [.animateOut(MotionTokens.crossfadeDuration)])
        guard case .dismissing = machine.phase else {
            Issue.record("expected dismissing")
            return
        }
        #expect(machine.handle(.dismiss).isEmpty)
        #expect(machine.handle(.dismissFinished).isEmpty)
        #expect(machine.phase == .armed)
        #expect(machine.handle(.connected(first)).isEmpty)
        #expect(machine.phase == .armed)

        #expect(machine.handle(.disconnected).isEmpty)
        #expect(machine.handle(.connected(first)) == [.animateIn(MotionTokens.crossfadeDuration)])
        #expect(machine.phase.content != nil)
    }

    @Test func reduceMotionSkipsTheTransitionAndAClosedGateDropsTheOverlay() {
        var machine = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .compact, reduceMotion: true
        ))
        #expect(machine.handle(.connected(AccessoryConnectInput.preview)) == [.showNow])
        #expect(machine.handle(.disconnected) == [.hideNow])
        #expect(machine.phase == .armed)

        _ = machine.handle(.connected(AccessoryConnectInput.preview))
        let closed = AccessoryOverlayGate(connectEnabled: false, style: .compact, reduceMotion: true)
        #expect(machine.handle(.gate(closed)) == [.hideNow])
        #expect(machine.phase == .closed)

        var animated = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .split, reduceMotion: false
        ))
        _ = animated.handle(.connected(AccessoryConnectInput.preview))
        _ = animated.handle(.appearFinished)
        let shutting = AccessoryOverlayGate(connectEnabled: true, style: .off, reduceMotion: false)
        #expect(animated.handle(.gate(shutting)) == [.animateOut(MotionTokens.crossfadeDuration)])
        guard case .dismissing(let content) = animated.phase else {
            Issue.record("expected dismissing")
            return
        }
        #expect(content.style == .split)
        #expect(animated.handle(.dismissFinished).isEmpty)
        #expect(animated.phase == .closed)
    }

    @Test func aNewDeviceReplacesASuppressedOneAndAConnectDuringDismissWaits() {
        var machine = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .compact, reduceMotion: true
        ))
        let first = AccessoryConnectInput.preview
        var second = first
        second.id = "other"
        second.name = "Hall"
        _ = machine.handle(.connected(first))
        _ = machine.handle(.dismiss)
        #expect(machine.phase == .armed)
        #expect(machine.handle(.connected(second)) == [.showNow])
        #expect(machine.phase.content?.title == "Hall")

        var waiting = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .compact, reduceMotion: false
        ))
        _ = waiting.handle(.connected(first))
        _ = waiting.handle(.appearFinished)
        _ = waiting.handle(.disconnected)
        guard case .dismissing = waiting.phase else {
            Issue.record("disconnect should dismiss")
            return
        }
        #expect(waiting.handle(.connected(second)).isEmpty)
        #expect(waiting.handle(.dismissFinished) == [.animateIn(MotionTokens.crossfadeDuration)])
        #expect(waiting.phase.content?.input.id == "other")
    }

    @Test func aUserDismissDoesNotReturnWhenTheSameDeviceIsStillThere() {
        var machine = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .split, reduceMotion: false
        ))
        _ = machine.handle(.connected(AccessoryConnectInput.preview))
        _ = machine.handle(.dismiss)
        #expect(machine.handle(.dismissFinished).isEmpty)
        #expect(machine.phase == .armed)
        #expect(machine.suppressedID == AccessoryConnectInput.preview.id)
    }

    @Test func reduceMotionMidTransitionJumpsToTheSettledPhase() {
        var appearing = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .compact, reduceMotion: false
        ))
        _ = appearing.handle(.connected(AccessoryConnectInput.preview))
        let settled = AccessoryOverlayGate(connectEnabled: true, style: .compact, reduceMotion: true)
        #expect(appearing.handle(.gate(settled)) == [.showNow])
        guard case .visible(let content) = appearing.phase else {
            Issue.record("expected visible")
            return
        }
        #expect(content.duration == 0)

        var dismissing = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
            connectEnabled: true, style: .compact, reduceMotion: false
        ))
        _ = dismissing.handle(.connected(AccessoryConnectInput.preview))
        _ = dismissing.handle(.appearFinished)
        _ = dismissing.handle(.dismiss)
        #expect(dismissing.handle(.gate(settled)) == [.hideNow])
        #expect(dismissing.phase == .armed)
    }

    @Test func closedGatesNeverPresentAcrossRandomSequences() {
        var rng = AccessorySplitMix(seed: 0xA11CE)
        for _ in 0..<240 {
            var machine = AccessoryConnectOverlayMachine()
            let steps = Int(rng.next() % 18) + 1
            for _ in 0..<steps {
                let event = rng.closedOverlayEvent()
                let effects = machine.handle(event)
                #expect(machine.phase == .closed)
                #expect(machine.gate.admits == false)
                #expect(effects.isEmpty)
                #expect(machine.phase.content == nil)
            }
        }
    }

    @Test func presentedContentKeepsARealStyleAndANonNegativeDuration() {
        var rng = AccessorySplitMix(seed: 0x0C0_FFEE)
        for _ in 0..<120 {
            let style: AccessoryOverlayStyle = rng.next() % 2 == 0 ? .compact : .split
            let motion = rng.next() % 2 == 0
            var machine = AccessoryConnectOverlayMachine(gate: AccessoryOverlayGate(
                connectEnabled: true, style: style, reduceMotion: motion
            ))
            _ = machine.handle(.connected(rng.connectInput()))
            if let content = machine.phase.content {
                #expect(content.style != .off)
                #expect(content.duration == (motion ? 0 : MotionTokens.crossfadeDuration))
                #expect(content.duration >= 0)
                #expect(!content.accessibilityLabel.isEmpty)
                #expect(!content.title.isEmpty)
            } else {
                Issue.record("an open gate should present")
            }
            _ = machine.handle(.disconnected)
            #expect(machine.phase == .armed || machine.phase.content != nil)
        }
    }
}

struct AccessorySplitMix: Sendable {
    var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func closedOverlayEvent() -> AccessoryConnectOverlayEvent {
        switch next() % 6 {
        case 0:
            let style: AccessoryOverlayStyle = next() % 2 == 0 ? .off : .compact
            let enabled = style == .off && next() % 2 == 0
            return .gate(AccessoryOverlayGate(connectEnabled: enabled, style: enabled ? .off : style, reduceMotion: next() % 2 == 0))
        case 1:
            return .connected(connectInput())
        case 2:
            return .disconnected
        case 3:
            return .appearFinished
        case 4:
            return .dismiss
        default:
            return .dismissFinished
        }
    }

    mutating func connectInput() -> AccessoryConnectInput {
        let known = next() % 2 == 0
        return AccessoryConnectInput(
            id: "id-\(next() % 5)",
            name: next() % 4 == 0 ? " " : "Buds \(next() % 3)",
            connected: true,
            charge: AccessoryChargeReading(
                left: Int(next() % 120) - 5,
                right: Int(next() % 120) - 5,
                caseCharge: Int(next() % 120) - 5,
                known: known
            ),
            listeningMode: next() % 3 == 0 ? "Indoor" : " "
        )
    }
}
