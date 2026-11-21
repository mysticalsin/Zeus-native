import Foundation

/// Forwards every notch sample into the weather gesture router.
///
/// The adapter's right swipe keeps its distance. A trackpad sample stays a trackpad sample, so a
/// drag and a trackpad swipe stay different routes. The clock is the date on each event.
public struct NotchWeatherGestureLink: Equatable, Sendable {
    public struct Outcome: Equatable, Sendable {
        public var routes: [TopBarGestureRoute]
        public var samples: [TopBarPointerSample]
        /// Ask for a `.tick` at this date. Nil when this step did not arm one.
        public var arm: Date?
        public var disarm: Bool

        public init(routes: [TopBarGestureRoute], samples: [TopBarPointerSample], arm: Date?, disarm: Bool) {
            self.routes = routes
            self.samples = samples
            self.arm = arm
            self.disarm = disarm
        }
    }

    public private(set) var router: TopBarGestureRouter
    private var adapter = NotchGestureAdapter<NotchPointerSample>()

    public init(face: PlayerWeatherFace = .player, surface: TopBarGestureSurface = .player) {
        router = TopBarGestureRouter(face: face, surface: surface)
    }

    public mutating func receive(_ event: NotchGestureAdapter<NotchPointerSample>.Event) -> Outcome {
        let effects = adapter.reduce(event)
        var samples: [TopBarPointerSample] = []
        var routes: [TopBarGestureRoute] = []
        if case .move = event, case .pressed(let press) = adapter.phase {
            let moved = TopBarPointerSample(.move(distance: press.distance))
            samples.append(moved)
            if let route = router.receive(moved) { routes.append(route) }
        }
        var arm: Date?
        var disarm = false
        for effect in effects {
            switch effect {
            case .emit(let sample):
                let translated = Self.translate(sample)
                samples.append(translated)
                if let route = router.receive(translated) { routes.append(route) }
            case .arm(let at):
                arm = at
                disarm = false
            case .disarm:
                arm = nil
                disarm = true
            }
        }
        return Outcome(routes: routes, samples: samples, arm: arm, disarm: disarm)
    }

    /// A trackpad swipe between the player and the weather. It is not a pointer drag.
    public mutating func trackpad(deltaX: Double, deltaY: Double, ended: Bool) -> Outcome {
        let sample = TopBarPointerSample(.trackpad(deltaX: deltaX, deltaY: deltaY, ended: ended))
        let route = router.receive(sample)
        return Outcome(routes: route.map { [$0] } ?? [], samples: [sample], arm: nil, disarm: false)
    }

    /// One router sample for one adapter sample. Every kind is kept.
    public static func translate(_ sample: NotchPointerSample) -> TopBarPointerSample {
        switch sample.kind {
        case .down(let count):
            return TopBarPointerSample(.down(clickCount: count))
        case .up(let count):
            return TopBarPointerSample(.up(clickCount: count))
        case .hold(let elapsed):
            return TopBarPointerSample(.hold(elapsed: elapsed))
        case .settle(let elapsed):
            return TopBarPointerSample(.settle(elapsed: elapsed))
        case .swipeRight(let distance):
            return TopBarPointerSample(.swipeRight(distance: distance))
        }
    }
}
