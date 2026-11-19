import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing stale target")
struct PointingStaleTargetTests {
    private func fresh() -> PointingStaleTarget { PointingStaleTarget(x: 100, y: 200, width: 80, height: 30) }
    private func isAsk(_ action: PointingStaleTarget.Action) -> Bool { if case .ask = action { true } else { false } }

    @Test func driftWithinTwoPointsIsStillFresh() {
        var target = fresh()
        let action = target.send(.observed(x: 101.5, y: 201, width: 80, height: 30))
        #expect(action == .none)
        #expect(target.isFresh)
    }

    @Test func driftBeyondTwoPointsHidesTheMarkAndReResolves() {
        var target = fresh()
        let action = target.send(.observed(x: 108, y: 200, width: 80, height: 30))
        #expect(action == .hideAndReResolve)
        #expect(target.phase == .resolving)
        let shown = target.send(.resolved(x: 108, y: 200, width: 80, height: 30))
        #expect(shown == .showMark)
        #expect(target.isFresh)
        #expect(target.frame.x == 108)
    }

    @Test func aMoveNotificationAloneIsEnough() {
        var target = fresh()
        #expect(target.send(.moved) == .hideAndReResolve)
        var resized = fresh()
        #expect(resized.send(.resized) == .hideAndReResolve)
        var changed = fresh()
        #expect(changed.send(.valueChanged) == .hideAndReResolve)
    }

    @Test func aFailedReResolveAsksInsteadOfGuessing() {
        var target = fresh()
        _ = target.send(.moved)
        let action = target.send(.resolveFailed)
        #expect(isAsk(action))
        #expect(target.phase == .gone)
    }

    @Test func aDestroyedTargetAsksAndStaysGone() {
        var target = fresh()
        #expect(isAsk(target.send(.destroyed)))
        #expect(target.phase == .gone)
        #expect(target.send(.moved) == .none)
        #expect(target.send(.resolved(x: 0, y: 0, width: 1, height: 1)) == .none)
    }

    @Test func eventsWhileResolvingDoNotRestartTheLookup() {
        var target = fresh()
        _ = target.send(.moved)
        #expect(target.send(.resized) == .none)
        #expect(target.phase == .resolving)
    }

    @Test func nonFiniteReadsCountAsStale() {
        var target = fresh()
        #expect(target.send(.observed(x: .nan, y: 0, width: 1, height: 1)) == .hideAndReResolve)
    }

    @Test func aResizeBeyondToleranceIsReportedAsResizedDrift() {
        var target = fresh()
        #expect(target.send(.observed(x: 100, y: 200, width: 120, height: 30)) == .hideAndReResolve)
    }

    @Test func mapsAccessibilityNotificationNames() {
        #expect(PointingStaleTarget.Event(axNotification: "AXMoved") == .moved)
        #expect(PointingStaleTarget.Event(axNotification: "AXWindowResized") == .resized)
        #expect(PointingStaleTarget.Event(axNotification: "AXUIElementDestroyed") == .destroyed)
        #expect(PointingStaleTarget.Event(axNotification: "AXValueChanged") == .valueChanged)
        #expect(PointingStaleTarget.Event(axNotification: "AXFocusedUIElementChanged") == nil)
        #expect(PointingStaleTarget.Event.observedNotifications.allSatisfy { PointingStaleTarget.Event(axNotification: $0) != nil })
    }
}
