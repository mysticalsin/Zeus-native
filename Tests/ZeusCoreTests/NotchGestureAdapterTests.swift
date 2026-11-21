import Foundation
import Testing
@testable import ZeusCore

@Suite("Notch pointer samples")
struct NotchGestureAdapterTests {
    private typealias Adapter = NotchGestureAdapter<NotchPointerSample>
    private let start = Date(timeIntervalSince1970: 5_000)

    private func kinds(_ effects: [Adapter.Effect]) -> [NotchPointerSample.Kind] {
        effects.compactMap { if case .emit(let sample) = $0 { sample.kind } else { nil } }
    }

    @Test func syntheticTimingsEmitDownHoldUpSettleAndRightSwipe() {
        var adapter = Adapter()
        let down = adapter.reduce(.down(at: start, x: 0, y: 0, clickCount: 1))
        #expect(kinds(down) == [.down(clickCount: 1)])
        #expect(down.contains(.arm(at: start.addingTimeInterval(Adapter.holdAfter))))

        let early = adapter.reduce(.tick(at: start.addingTimeInterval(0.25)))
        #expect(kinds(early).isEmpty)
        #expect(early == [.arm(at: start.addingTimeInterval(Adapter.holdAfter))])

        let held = adapter.reduce(.tick(at: start.addingTimeInterval(Adapter.holdAfter)))
        #expect(kinds(held) == [.hold(elapsed: Adapter.holdAfter)])
        #expect(adapter.reduce(.tick(at: start.addingTimeInterval(0.8))).isEmpty)

        let up = adapter.reduce(.up(at: start.addingTimeInterval(0.8), x: 1, y: 0, clickCount: 1))
        #expect(kinds(up) == [.up(clickCount: 1)])
        #expect(adapter.phase == .idle)

        var click = Adapter()
        _ = click.reduce(.down(at: start, x: 10, y: 10, clickCount: 1))
        let upAt = start.addingTimeInterval(0.1)
        let released = click.reduce(.up(at: upAt, x: 12, y: 11, clickCount: 1))
        #expect(kinds(released) == [.up(clickCount: 1)])
        let soon = click.reduce(.tick(at: upAt.addingTimeInterval(0.2)))
        #expect(kinds(soon).isEmpty)
        let settled = click.reduce(.tick(at: upAt.addingTimeInterval(Adapter.settleAfter)))
        if case .settle(let elapsed) = kinds(settled).first {
            #expect(elapsed >= Adapter.settleAfter && elapsed < Adapter.settleAfter + 0.000_001)
        } else {
            Issue.record("settle did not fire")
        }
        #expect(click.phase == .idle)

        var swipe = Adapter()
        _ = swipe.reduce(.down(at: start, x: 0, y: 0, clickCount: 1))
        let across = swipe.reduce(.move(at: start.addingTimeInterval(0.05), x: Adapter.swipeDistance, y: 4))
        #expect(kinds(across) == [.swipeRight(distance: Adapter.swipeDistance)])
        #expect(swipe.reduce(.move(at: start.addingTimeInterval(0.08), x: 80, y: 4)).isEmpty)
        let ended = swipe.reduce(.up(at: start.addingTimeInterval(0.1), x: 80, y: 4, clickCount: 1))
        #expect(kinds(ended) == [.up(clickCount: 1)])
        #expect(swipe.phase == .idle)
    }

    @Test func aSecondClickBeforeSettleStartsAgainAndADragPastTheSlopDoesNotSettle() {
        var adapter = Adapter()
        _ = adapter.reduce(.down(at: start, x: 0, y: 0, clickCount: 1))
        _ = adapter.reduce(.up(at: start.addingTimeInterval(0.05), x: 0, y: 0, clickCount: 1))
        let again = adapter.reduce(.down(at: start.addingTimeInterval(0.2), x: 0, y: 0, clickCount: 2))
        #expect(kinds(again) == [.down(clickCount: 2)])
        let oldSettle = adapter.reduce(.tick(at: start.addingTimeInterval(0.05 + Adapter.settleAfter)))
        #expect(kinds(oldSettle).isEmpty)
        if case .pressed = adapter.phase {} else { Issue.record("the second press is still down") }

        var dragged = Adapter()
        _ = dragged.reduce(.down(at: start, x: 0, y: 0, clickCount: 1))
        #expect(dragged.reduce(.move(at: start.addingTimeInterval(0.02), x: -40, y: 0)).isEmpty)
        #expect(dragged.reduce(.tick(at: start.addingTimeInterval(Adapter.holdAfter))).isEmpty)
        let up = dragged.reduce(.up(at: start.addingTimeInterval(0.6), x: -40, y: 0, clickCount: 1))
        #expect(kinds(up) == [.up(clickCount: 1)])
        #expect(dragged.phase == .idle)
    }

    @Test func cancelDropsAPressThatIsStillWaiting() {
        var adapter = Adapter()
        _ = adapter.reduce(.down(at: start, x: 0, y: 0, clickCount: 1))
        #expect(adapter.reduce(.cancel) == [.disarm])
        #expect(adapter.phase == .idle)
        #expect(adapter.reduce(.tick(at: start.addingTimeInterval(1))).isEmpty)
    }
}
