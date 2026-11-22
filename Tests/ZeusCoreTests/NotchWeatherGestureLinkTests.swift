import Foundation
import Testing
@testable import ZeusCore

@Suite("Notch routes reach the weather gesture router")
struct NotchWeatherGestureLinkTests {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test func everyAdapterSampleKeepsItsKind() {
        #expect(NotchWeatherGestureLink.translate(.down(clickCount: 2)) == TopBarPointerSample(.down(clickCount: 2)))
        #expect(NotchWeatherGestureLink.translate(.up(clickCount: 2)) == TopBarPointerSample(.up(clickCount: 2)))
        #expect(NotchWeatherGestureLink.translate(.hold(elapsed: 0.5)) == TopBarPointerSample(.hold(elapsed: 0.5)))
        #expect(NotchWeatherGestureLink.translate(.settle(elapsed: 0.35)) == TopBarPointerSample(.settle(elapsed: 0.35)))
        #expect(NotchWeatherGestureLink.translate(.swipeRight(distance: 36)) == TopBarPointerSample(.swipeRight(distance: 36)))
    }

    @Test func theSettleThresholdIsTheFinding() {
        #expect(NotchGestureAdapter<NotchPointerSample>.settleAfter == 0.35)
    }

    @Test func aClickOpensOnlyAfterThePointerSettles() {
        var link = NotchWeatherGestureLink()
        let down = link.receive(.down(at: start, x: 10, y: 20, clickCount: 1))
        #expect(down.routes.isEmpty)
        let upAt = start.addingTimeInterval(0.1)
        let up = link.receive(.up(at: upAt, x: 10, y: 20, clickCount: 1))
        #expect(up.routes.isEmpty)
        #expect(up.arm == upAt.addingTimeInterval(0.35))
        let early = link.receive(.tick(at: upAt.addingTimeInterval(0.35 - 0.001)))
        #expect(early.routes.isEmpty)
        let settled = link.receive(.tick(at: upAt.addingTimeInterval(0.35)))
        #expect(settled.routes == [.click])
        let kinds = down.samples + up.samples + settled.samples
        #expect(kinds.contains(TopBarPointerSample(.down(clickCount: 1))))
        #expect(kinds.contains(TopBarPointerSample(.up(clickCount: 1))))
        let settle = kinds.compactMap { sample -> Double? in
            if case .settle(let elapsed) = sample.kind { return elapsed }
            return nil
        }
        #expect(settle.count == 1)
        #expect(abs((settle.first ?? 0) - 0.35) < 0.001)
    }

    @Test func aDoubleClickIsItsOwnRoute() {
        var link = NotchWeatherGestureLink()
        _ = link.receive(.down(at: start, x: 0, y: 0, clickCount: 1))
        _ = link.receive(.up(at: start.addingTimeInterval(0.05), x: 0, y: 0, clickCount: 1))
        _ = link.receive(.down(at: start.addingTimeInterval(0.1), x: 0, y: 0, clickCount: 2))
        let upAt = start.addingTimeInterval(0.15)
        _ = link.receive(.up(at: upAt, x: 0, y: 0, clickCount: 2))
        let settled = link.receive(.tick(at: upAt.addingTimeInterval(0.35)))
        #expect(settled.routes == [.doubleClick])
    }

    @Test func aTripleClickIsItsOwnRoute() {
        var link = NotchWeatherGestureLink()
        _ = link.receive(.down(at: start, x: 0, y: 0, clickCount: 1))
        _ = link.receive(.up(at: start.addingTimeInterval(0.04), x: 0, y: 0, clickCount: 1))
        _ = link.receive(.down(at: start.addingTimeInterval(0.08), x: 0, y: 0, clickCount: 3))
        let upAt = start.addingTimeInterval(0.12)
        _ = link.receive(.up(at: upAt, x: 0, y: 0, clickCount: 3))
        let settled = link.receive(.tick(at: upAt.addingTimeInterval(0.35)))
        #expect(settled.routes == [.tripleClick])
    }

    @Test func aHoldOpensTheMenuAndNotTheClick() {
        var link = NotchWeatherGestureLink()
        let down = link.receive(.down(at: start, x: 0, y: 0, clickCount: 1))
        #expect(down.routes.isEmpty)
        #expect(down.arm == start.addingTimeInterval(0.5))
        let held = link.receive(.tick(at: start.addingTimeInterval(0.5)))
        #expect(held.routes == [.holdMenu])
    }

    @Test func aRightDragIsARightSwipeAndKeepsItsDistance() {
        var link = NotchWeatherGestureLink()
        _ = link.receive(.down(at: start, x: 0, y: 0, clickCount: 1))
        let dragged = link.receive(.move(at: start.addingTimeInterval(0.05), x: 36, y: 0))
        #expect(dragged.routes == [.rightSwipe])
        #expect(dragged.samples.contains(TopBarPointerSample(.swipeRight(distance: 36))))
        #expect(!dragged.routes.contains(.showWeather))
        #expect(!dragged.routes.contains(.showPlayer))
    }

    @Test func aTrackpadSwipeChangesFaceAndIsNotARightSwipe() {
        var player = NotchWeatherGestureLink()
        let toWeather = player.trackpad(deltaX: -40, deltaY: 0, ended: true)
        #expect(toWeather.routes == [.showWeather])
        let rightward = player.trackpad(deltaX: 40, deltaY: 0, ended: true)
        #expect(rightward.routes == [.showPlayer])
        #expect(!rightward.routes.contains(.rightSwipe))

        var fresh = NotchWeatherGestureLink()
        let notADrag = fresh.trackpad(deltaX: 40, deltaY: 0, ended: true)
        #expect(notADrag.routes.isEmpty)
    }
}
