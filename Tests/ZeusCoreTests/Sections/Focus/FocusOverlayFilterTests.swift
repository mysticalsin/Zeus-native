import Testing
@testable import ZeusCore

@Suite struct FocusOverlayFilterTests {
    @Test func theFilterTableHasOneRowForEveryKind() {
        let kinds = FocusOverlayFilter.table.map(\.kind)
        #expect(kinds == FocusOverlayKind.allCases)
        #expect(Set(kinds).count == FocusOverlayKind.allCases.count)
    }

    @Test func theFilterAllowsOnlyTheTransitionAndTheTimerWhileAFocusIsOn() {
        let allowed = Set(FocusOverlayFilter.table.filter(\.allowed).map(\.kind))
        #expect(allowed == [.transition, .timer])
        let named = FocusOverlayFilter.table.filter(\.showsName).map(\.kind)
        #expect(named == [.notchCue])
    }

    @Test func everyFocusAndSwitchPairFollowsTheRuleTable() {
        let activities: [FocusActivity] = [.unknown, .off, .on(name: nil), .on(name: "Deep Work")]
        for kind in FocusOverlayKind.allCases {
            for filterEnabled in [false, true] {
                for armed in [false, true] {
                    for activity in activities {
                        let first = FocusOverlayFilter.decide(
                            kind: kind, focus: activity, filterEnabled: filterEnabled, transitionArmed: armed
                        )
                        let again = FocusOverlayFilter.decide(
                            kind: kind, focus: activity, filterEnabled: filterEnabled, transitionArmed: armed
                        )
                        #expect(first == again)
                        #expect(first == expectedDecision(kind: kind, focus: activity, filterEnabled: filterEnabled, transitionArmed: armed))
                    }
                }
            }
        }
    }

    @Test func anUnknownFocusDoesNotBlockOrAllowAnOverlay() {
        for kind in FocusOverlayKind.allCases {
            let decision = FocusOverlayFilter.decide(kind: kind, focus: .unknown, filterEnabled: false, transitionArmed: true)
            #expect(decision == .unavailable)
        }
    }

    private func expectedDecision(
        kind: FocusOverlayKind, focus: FocusActivity, filterEnabled: Bool, transitionArmed: Bool
    ) -> FocusOverlayDecision {
        switch focus {
        case .unknown:
            return .unavailable
        case .off:
            return .unfiltered
        case .on:
            if !filterEnabled {
                return kind == .transition && transitionArmed ? .allowed : .blocked
            }
            let allowed = FocusOverlayFilter.table.first { $0.kind == kind }?.allowed ?? false
            return allowed ? .allowed : .blocked
        }
    }
}
