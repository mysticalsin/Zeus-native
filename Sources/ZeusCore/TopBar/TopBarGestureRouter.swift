import Foundation

public enum PlayerWeatherFace: Equatable, Sendable {
    case player
    case weather
}

public enum TopBarGestureSurface: Equatable, Sendable {
    case player
    case weather
    case other
}

public enum TopBarGestureRoute: Equatable, Sendable {
    case holdMenu
    case click
    case doubleClick
    case tripleClick
    case rightSwipe
    case showPlayer
    case showWeather
}

public struct TopBarPointerSample: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case down(clickCount: Int)
        case move(distance: Double)
        case up(clickCount: Int)
        case hold(elapsed: Double)
        case settle(elapsed: Double)
        case swipeRight(distance: Double)
        case trackpad(deltaX: Double, deltaY: Double, ended: Bool)
        case cancel
    }

    public var kind: Kind

    public init(_ kind: Kind) { self.kind = kind }
}

/// One route per gesture. Hold, click, double click, triple click, and right-swipe stay distinct from the
/// trackpad move between the player and the weather.
public struct TopBarGestureRouter: Equatable, Sendable {
    public static let holdSeconds = 0.5
    public static let clickSlop = 6.0
    public static let multiClickWindow = 0.35
    public static let trackpadThreshold = 36.0
    public static let axisRatio = 1.5

    public private(set) var face: PlayerWeatherFace
    public private(set) var surface: TopBarGestureSurface

    private enum Phase: Equatable, Sendable {
        case idle
        case pressed(clickCount: Int, distance: Double, held: Bool)
        case pending(clickCount: Int)
        case trackpad(deltaX: Double, deltaY: Double)
        case consumed
    }

    private var phase: Phase = .idle

    public init(face: PlayerWeatherFace = .player, surface: TopBarGestureSurface = .player) {
        self.face = face
        self.surface = surface
    }

    public mutating func receive(_ sample: TopBarPointerSample) -> TopBarGestureRoute? {
        switch (phase, sample.kind) {
        case (.consumed, .up), (.consumed, .cancel):
            phase = .idle
            return nil
        case (.consumed, _):
            return nil
        case (_, .cancel):
            phase = .idle
            return nil
        case (_, .swipeRight):
            phase = .consumed
            return .rightSwipe
        case (.idle, .down(let count)), (.pending, .down(let count)):
            phase = .pressed(clickCount: max(count, 1), distance: 0, held: false)
            return nil
        case (.pressed(let count, let distance, let held), .move(let moved)):
            phase = .pressed(clickCount: count, distance: max(distance, moved), held: held)
            return nil
        case (.pressed(let count, let distance, let held), .hold(let elapsed)):
            if held || distance > Self.clickSlop || elapsed < Self.holdSeconds { return nil }
            phase = .pressed(clickCount: count, distance: distance, held: true)
            return .holdMenu
        case (.pressed(let count, let distance, let held), .up(let upCount)):
            if held || distance > Self.clickSlop {
                phase = .idle
                return nil
            }
            phase = .pending(clickCount: max(count, upCount, 1))
            return nil
        case (.pending(let count), .settle(let elapsed)):
            guard elapsed >= Self.multiClickWindow else { return nil }
            phase = .idle
            return Self.route(forClickCount: count)
        case let (.idle, .trackpad(dx, dy, ended)),
             let (.pressed, .trackpad(dx, dy, ended)),
             let (.pending, .trackpad(dx, dy, ended)):
            if ended {
                phase = .idle
                return finishTrackpad(dx, dy)
            }
            phase = .trackpad(deltaX: dx, deltaY: dy)
            return nil
        case let (.trackpad(accX, accY), .trackpad(dx, dy, ended)):
            let totalX = accX + dx
            let totalY = accY + dy
            if ended {
                phase = .idle
                return finishTrackpad(totalX, totalY)
            }
            phase = .trackpad(deltaX: totalX, deltaY: totalY)
            return nil
        default:
            return nil
        }
    }

    /// VoiceOver and the keyboard use the same face change as a finished trackpad swipe.
    public mutating func accessibilityActivate() -> TopBarGestureRoute? {
        guard surface == .player || surface == .weather else { return nil }
        phase = .idle
        return switchFace(towardWeather: face == .player)
    }

    private static func route(forClickCount count: Int) -> TopBarGestureRoute {
        switch count {
        case 2: .doubleClick
        case 3...: .tripleClick
        default: .click
        }
    }

    private mutating func finishTrackpad(_ dx: Double, _ dy: Double) -> TopBarGestureRoute? {
        let horizontal = abs(dx) >= Self.trackpadThreshold && abs(dx) >= abs(dy) * Self.axisRatio
        guard horizontal, surface == .player || surface == .weather else { return nil }
        if dx < 0, face == .player { return switchFace(towardWeather: true) }
        if dx > 0, face == .weather { return switchFace(towardWeather: false) }
        return nil
    }

    private mutating func switchFace(towardWeather: Bool) -> TopBarGestureRoute {
        if towardWeather {
            face = .weather
            if surface != .other { surface = .weather }
            return .showWeather
        }
        face = .player
        if surface != .other { surface = .player }
        return .showPlayer
    }
}

public enum PlayerWeatherTransition {
    public static func duration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : MotionTokens.crossfadeDuration
    }
}
