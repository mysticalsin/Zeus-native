import Foundation

/// The closed notch's light language: short effects that run along the notch outline and its two
/// arms (the lit lines that leave the shoulders along the top edge of the screen).
/// Positions are fractions of one arm, 0 at the middle of the bottom lip, 1 at the arm tip.
public enum NotchLightKind: Equatable, Sendable {
    case copySweep
    case capsLock(Bool)
    case shiftCrest
    case battery(level: Double, charging: Bool)
    case landed(airDrop: Bool)
    case reminderPinned
    case eventRibbon
    case shortcut(ShortcutMotion)
    case entrance(HaloEntrance, NotchLightTint)
    case edgeWave(NotchLightTint)
    /// `previousLevel` is where the arm was before this change, so the render tweens continuously
    /// instead of restarting from zero on every key repeat (H2). `limitEcho` is a short pulse at
    /// the tip when the level is already at 0 or 1 and the same direction is pressed again (H3).
    case hudLevel(SystemHUDKind, value: Double, previousLevel: Double, muted: Bool, limitEcho: Bool = false)

    public var duration: TimeInterval {
        switch self {
        case .hudLevel: SystemHUDMath.holdAfterChange + SystemHUDMath.easeOut
        case .copySweep: 1.1
        case .capsLock(let on): on ? 1.0 : 0.6
        case .shiftCrest: 0.9
        case .battery: 3.2
        case .landed: 0.9
        case .reminderPinned, .eventRibbon: 1.6
        case .shortcut: 0.8
        case .entrance(let style, _): style.choreography.duration
        case .edgeWave: 1.6
        }
    }

    /// Applies the entrance-speed preference without changing other light cues.
    public func duration(speedPercent: Double) -> TimeInterval {
        guard case .entrance(let style, _) = self else { return duration }
        let finiteSpeed = speedPercent.isFinite ? speedPercent : 100
        let speed = min(max(finiteSpeed, 50), 200) / 100
        return max(duration / speed, style.choreography.minDuration)
    }
}

/// Named colours so the core stays UI free.
public enum NotchLightTint: String, Equatable, Sendable { case white, amber, mint, green, blue, cyan, purple, sky, ember, leaf }

/// Each shortcut's light mirrors what it does.
public enum ShortcutMotion: String, Equatable, Sendable {
    case sweep, breach, rewind, grow, circle, feed
    /// ⌘Q: the lit arms draw back into the notch and go out.
    case quit
}

public struct ShortcutPeek: Equatable, Sendable {
    public let key: String
    public let title: String
    public let symbol: String
    public let motion: ShortcutMotion

    /// The ⌘ shortcuts that get a peek. Copy is left to the clipboard sweep.
    public static func lookup(_ characters: String, shift: Bool) -> ShortcutPeek? {
        switch (characters.lowercased(), shift) {
        case ("x", false): .init(key: "⌘X", title: "Cut", symbol: "scissors", motion: .breach)
        case ("v", false): .init(key: "⌘V", title: "Paste", symbol: "doc.on.clipboard", motion: .sweep)
        case ("z", false): .init(key: "⌘Z", title: "Undo", symbol: "arrow.uturn.backward", motion: .rewind)
        case ("z", true): .init(key: "⇧⌘Z", title: "Redo", symbol: "arrow.uturn.forward", motion: .sweep)
        case ("s", false): .init(key: "⌘S", title: "Saved", symbol: "square.and.arrow.down", motion: .grow)
        case ("r", false): .init(key: "⌘R", title: "Reload", symbol: "arrow.clockwise", motion: .circle)
        case ("p", false): .init(key: "⌘P", title: "Print", symbol: "printer", motion: .feed)
        case ("a", false): .init(key: "⌘A", title: "Select all", symbol: "selection.pin.in.out", motion: .grow)
        case ("f", false): .init(key: "⌘F", title: "Find", symbol: "magnifyingglass", motion: .sweep)
        case ("t", false): .init(key: "⌘T", title: "New tab", symbol: "plus.square.on.square", motion: .grow)
        case ("w", false): .init(key: "⌘W", title: "Close", symbol: "xmark.square", motion: .breach)
        case ("n", false): .init(key: "⌘N", title: "New", symbol: "plus", motion: .grow)
        case ("q", false): .init(key: "⌘Q", title: "Quit", symbol: "power", motion: .quit)
        default: nil
        }
    }
}

/// One lit stretch of an arm: `from`...`to` in arm fractions, with an opacity.
public struct LightSegment: Equatable, Sendable {
    public var from: Double
    public var to: Double
    public var opacity: Double
    /// Which arms: -1 left only, 1 right only, 0 both.
    public var side: Int
    public init(from: Double, to: Double, opacity: Double, side: Int = 0) {
        self.from = max(0, min(1, from)); self.to = max(0, min(1, to)); self.opacity = max(0, min(1, opacity)); self.side = side
    }
}

public enum NotchLightMath {
    /// Settings > Appearance > Halo arm width, in points per side.
    public static func armLength(_ choice: String) -> Double {
        switch choice {
        case "Narrow": 76
        case "Wide": 220
        case "Extra wide": 440
        default: 130
        }
    }

    /// Fraction of one arm taken by the notch itself (bottom lip plus side), the rest is the arm.
    public static func shoulderFraction(notchHalfWidth: Double, notchHeight: Double, arm: Double) -> Double {
        let body = notchHalfWidth + notchHeight
        return body / max(body + arm, 1)
    }

    public static func ease(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }
    public static func fadeOut(_ p: Double, from start: Double = 0.7) -> Double { p < start ? 1 : max(0, 1 - (p - start) / (1 - start)) }

    /// A crest of half width `w` centred at `c`.
    public static func crest(_ c: Double, _ w: Double, _ o: Double, side: Int = 0) -> LightSegment { .init(from: c - w, to: c + w, opacity: o, side: side) }

    /// The lit segments of an effect at progress `p` (0...1). `shoulder` is the shoulder fraction.
    public static func segments(_ kind: NotchLightKind, progress p: Double, shoulder s: Double) -> [LightSegment] {
        let p = max(0, min(1, p))
        switch kind {
        case .copySweep:
            // Two passes left tip to right tip; the second fainter.
            let pass = p < 0.5 ? p * 2 : (p - 0.5) * 2
            let o = p < 0.5 ? 1 : 0.6
            let across = ease(pass)
            return across < 0.5
                ? [crest(1 - across * 2, 0.12, o, side: -1)]
                : [crest(across * 2 - 1, 0.12, o, side: 1)]
        case .capsLock(let on):
            let pulses = on ? 2.0 : 1.0
            let o = max(0, sin(p * pulses * .pi)) * (on ? 1 : 0.5)
            return [.init(from: 0, to: 1, opacity: o)]
        case .shiftCrest:
            return [crest(ease(p), 0.12, fadeOut(p))]
        case .battery(let level, let charging):
            let fill = LightSegment(from: 0, to: level, opacity: (p < 0.15 ? p / 0.15 : 1) * fadeOut(p, from: 0.8) * 0.85)
            guard charging else { return [fill] }
            let climb = (p * 3).truncatingRemainder(dividingBy: 1) * level
            return [fill, crest(climb, 0.06, fadeOut(p, from: 0.8))]
        case .landed:
            // Burst on the shoulders.
            return [crest(s, 0.04 + 0.16 * ease(p), 1 - ease(p))]
        case .reminderPinned:
            // Two crests rise from the bottom lip to the shoulders, settle, then breathe.
            if p < 0.55 { return [crest(s * ease(p / 0.55), 0.07, 1)] }
            let breath = 0.6 + 0.4 * sin((p - 0.55) / 0.45 * .pi)
            return [crest(s, 0.07, breath * fadeOut(p, from: 0.85))]
        case .eventRibbon:
            // A crest sweeps the bottom lip left to right, then a marker settles in the middle.
            let lip = s * 0.55
            if p < 0.6 {
                let q = ease(p / 0.6)
                return q < 0.5 ? [crest(lip * (1 - q * 2), 0.08, 1, side: -1)] : [crest(lip * (q * 2 - 1), 0.08, 1, side: 1)]
            }
            return [.init(from: 0, to: 0.035, opacity: fadeOut(p, from: 0.8))]
        case .shortcut(let motion):
            switch motion {
            case .sweep: return [crest(ease(p), 0.14, fadeOut(p))]
            case .breach: return [.init(from: ease(p) * 0.6, to: ease(p) * 0.6 + 0.25, opacity: fadeOut(p))]
            case .rewind: return [crest(1 - ease(p), 0.14, fadeOut(p))]
            case .grow:
                if p < 0.6 { return [.init(from: 0, to: ease(p / 0.6), opacity: 0.8)] }
                return [.init(from: 0, to: 1, opacity: (p < 0.75 ? 1 : 1 - (p - 0.75) / 0.25))]
            case .circle:
                // Out the left arm and back along the right: one full turn.
                return p < 0.5 ? [crest(ease(p * 2), 0.1, 1, side: -1)] : [crest(1 - ease((p - 0.5) * 2), 0.1, 1, side: 1)]
            case .feed: return [crest(1 - ease(p) * (1 - s), 0.08, fadeOut(p))]
            // Both arms fully lit, then pulled back into the notch while fading.
            case .quit: return [.init(from: 0, to: max(0.02, 1 - ease(p)), opacity: fadeOut(p, from: 0.35))]
            }
        case .entrance(let style, _):
            return entranceFrame(style, progress: p, shoulder: s).flat
        case .edgeWave:
            return []
        case .hudLevel(_, let value, let previousLevel, let muted, let limitEcho):
            let target = muted ? 0.06 : max(0.02, value)
            let start = muted ? 0.06 : max(0.02, previousLevel)
            // Springs from where the arm already was, not from zero, so repeated key presses
            // continue the same light instead of restarting it (H2); this also makes a lower
            // value visibly retract rather than regrow from nothing (H3).
            let spring = ease(min(1, p / 0.12))
            let current = start + (target - start) * spring
            let hold = p < 0.85 ? 1 : fadeOut(p, from: 0.85)
            let pulse = muted ? (0.45 + 0.55 * max(0, sin(p * 5 * .pi))) : 1
            var segs = [LightSegment(from: 0, to: current, opacity: hold * pulse * 0.92)]
            if limitEcho, p < 0.18 {
                // One soft pulse right at the tip when 0 or 1 is hit again in the same direction.
                let echo = 1 - ease(min(1, p / 0.18))
                segs.append(.init(from: max(0, target - 0.035), to: target, opacity: echo))
            }
            return segs
        }
    }

    /// The timer gauge: the outline pulls back toward the notch as the session runs down.
    public static func timerGauge(remainingFraction: Double) -> LightSegment {
        .init(from: 0, to: max(0.02, remainingFraction), opacity: 0.8)
    }

    /// Crests climbing from the arm tips toward the notch while files are dragged.
    public static func dragCrests(time t: Double, shoulder s: Double) -> [LightSegment] {
        let a = (t / 1.1).truncatingRemainder(dividingBy: 1)
        let b = (a + 0.5).truncatingRemainder(dividingBy: 1)
        return [a, b].map { crest(1 - $0 * (1 - s), 0.07, 0.4 + 0.6 * $0) }
    }

    /// The soft wave that runs across the closed notch while music plays.
    public static func musicWave(time t: Double) -> LightSegment {
        crest((t / 3.2).truncatingRemainder(dividingBy: 1), 0.18, 0.45)
    }

    /// The same wave driven by the real sound level (0...1): louder is longer and brighter, silence
    /// leaves a thin faint trace.
    public static func musicWave(time t: Double, level: Double) -> LightSegment {
        let l = max(0, min(1, level))
        return crest((t / 3.2).truncatingRemainder(dividingBy: 1), 0.06 + 0.16 * l, 0.18 + 0.72 * l)
    }
}

/// Shift on its own, held for half a second, shows a peek; any other key cancels it. H10: the
/// peek holds at the arm tips until Shift is released (`release()`), instead of a fixed-duration
/// light that fades regardless of whether the key is still down.
public struct ShiftPeekGate: Sendable {
    public private(set) var downAt: Date?
    public private(set) var cancelled = false
    public private(set) var revealed = false
    public init() {}
    public mutating func shift(down: Bool, at now: Date) { if down { downAt = now; cancelled = false } else { downAt = nil } }
    public mutating func otherKey() { cancelled = true }
    /// True once, when Shift has been held alone for `hold` seconds.
    public mutating func fire(at now: Date, hold: TimeInterval = 0.5) -> Bool {
        guard let downAt, !cancelled, !revealed, now.timeIntervalSince(downAt) >= hold else { return false }
        revealed = true
        return true
    }
    /// Shift released: true when a peek was showing, so the caller starts its 250 ms fade now.
    public mutating func release() -> Bool {
        defer { revealed = false; downAt = nil }
        return revealed
    }
}

/// Hold-Tab (Zeus's own addition, styled like Glance's Shift peek, H9): Tab held alone for 0.4 s,
/// with no modifiers, reveals the tab strip; it holds until release. Any other key, or Tab
/// repeating into a text field (also reported via `otherKey()`), cancels it. Tab itself is never
/// consumed by this gate -- the caller still forwards the keystroke.
public struct TabHoldGate: Sendable {
    public private(set) var downAt: Date?
    public private(set) var cancelled = false
    public private(set) var revealed = false
    public init() {}

    /// `modifiersHeld`: any modifier key down alongside Tab. That shape is ignored entirely (it's
    /// someone's normal Tab-navigation or a shortcut, not a hold).
    public mutating func tabDown(at now: Date, modifiersHeld: Bool) {
        guard !modifiersHeld else { return }
        downAt = now
        cancelled = false
    }

    public mutating func otherKey() {
        cancelled = true
        revealed = false
    }

    /// True once, when Tab has been held alone for `threshold` seconds.
    public mutating func fire(at now: Date, threshold: TimeInterval = 0.4) -> Bool {
        guard let downAt, !cancelled, !revealed, now.timeIntervalSince(downAt) >= threshold else { return false }
        revealed = true
        return true
    }

    /// Tab released: true when the hold had revealed the strip, so the caller starts its 250 ms
    /// fade now (releasing before the threshold fires nothing to fade).
    public mutating func tabUp() -> Bool {
        defer { downAt = nil; cancelled = false; revealed = false }
        return revealed
    }
}

/// "Rain in X min" once per shower, then silent for three hours.
public struct RainAlertGate: Sendable {
    public private(set) var lastAlert = Date.distantPast
    public init() {}
    public mutating func minutesUntilRain(_ weather: WeatherSnapshot, now: Date = Date()) -> Int? {
        guard now.timeIntervalSince(lastAlert) > 3 * 3600 else { return nil }
        switch weather.sky { case .rain, .drizzle, .storm: return nil; default: break }
        guard let hour = weather.rainSoon(after: now) else { return nil }
        let minutes = Int(hour.time.timeIntervalSince(now) / 60)
        guard minutes <= 90 else { return nil }
        lastAlert = now
        return max(minutes, 1)
    }
}
