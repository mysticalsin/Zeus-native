import Foundation

/// How long the music wings stay up after a pause, and which pause label is a real choice.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum MusicWingsHoldBox {
    /// Spaces and line breaks, named as scalars. U+200B is not a member. Linux
    /// `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so a label is not asked of that set.
    public static let blankScalars: Set<Unicode.Scalar> = [
        "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}",
        "\u{0020}",
        "\u{0085}",
        "\u{00A0}",
        "\u{1680}",
        "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}",
        "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
        "\u{2028}", "\u{2029}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]

    /// Leading and trailing members of `blankScalars` only. A zero-width space stays.
    public static func trimmedLabel(_ label: String) -> String {
        let scalars = label.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, blankScalars.contains(scalars[start]) {
            start = scalars.index(after: start)
        }
        while end > start {
            let previous = scalars.index(before: end)
            if blankScalars.contains(scalars[previous]) {
                end = previous
            } else {
                break
            }
        }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// An unknown label, including one that still holds U+200B, is at once.
    public static func collapse(label: String) -> PauseCollapse {
        switch trimmedLabel(label) {
        case "At once": return .atOnce
        case "After 10 s": return .after(10)
        case "After 1 min": return .after(60)
        case "Never": return .never
        default: return .atOnce
        }
    }

    /// A delay that is not a positive finite number is at once.
    public static func collapse(delay: TimeInterval) -> PauseCollapse {
        if delay.isFinite, delay > 0 {
            return .after(delay)
        }
        return .atOnce
    }

    public static func showsWings(_ state: MusicWingsHold.State) -> Bool {
        switch state {
        case .playing, .held: true
        case .hidden: false
        }
    }

    public static func isPaused(_ state: MusicWingsHold.State) -> Bool {
        if case .held = state { return true }
        return false
    }

    /// `wingsOnScreen` is read only on the edge from playing to paused. A second pause keeps `since`.
    /// A time before that pause collapses the hold. An early deadline asks for the same wake again.
    public static func reduce(
        _ state: MusicWingsHold.State,
        _ event: MusicWingsHold.Event,
        policy: PauseCollapse
    ) -> (MusicWingsHold.State, [MusicWingsHold.Effect]) {
        switch event {
        case .wingsSwitchedOff:
            if case .held = state { return (.hidden, [.cancelWake]) }
            return (.hidden, [])
        case .policy(let next, let now):
            guard case .held(let since, _) = state else { return (state, []) }
            return retimed(since: since, now: now, policy: next)
        case .deadline(let now):
            guard case .held(let since, let until) = state else { return (state, []) }
            if now < since { return (.hidden, [.cancelWake]) }
            guard let until else { return (state, []) }
            if now < until { return (state, [.wake(at: until)]) }
            return (.hidden, [.cancelWake])
        case .playback(let playback, let wingsOnScreen, let now):
            switch (state, playback) {
            case (_, .playing):
                if case .held = state { return (.playing, [.cancelWake]) }
                return (.playing, [])
            case (.playing, .paused):
                guard wingsOnScreen else { return (.hidden, []) }
                return begin(at: now, policy: policy)
            case (.playing, .none):
                return (.hidden, [])
            case (.held(let since, let until), .paused):
                if now < since { return (.hidden, [.cancelWake]) }
                return (.held(since: since, until: until), [])
            case (.held, .none):
                return (.hidden, [.cancelWake])
            case (.hidden, _):
                return (.hidden, [])
            }
        }
    }

    private static func begin(at now: Date, policy: PauseCollapse) -> (MusicWingsHold.State, [MusicWingsHold.Effect]) {
        switch normalized(policy) {
        case .atOnce:
            return (.hidden, [])
        case .never:
            return (.held(since: now, until: nil), [])
        case .after(let seconds):
            let until = now.addingTimeInterval(seconds)
            return (.held(since: now, until: until), [.wake(at: until)])
        }
    }

    private static func retimed(since: Date, now: Date, policy: PauseCollapse) -> (MusicWingsHold.State, [MusicWingsHold.Effect]) {
        if now < since { return (.hidden, [.cancelWake]) }
        switch normalized(policy) {
        case .atOnce:
            return (.hidden, [.cancelWake])
        case .never:
            return (.held(since: since, until: nil), [.cancelWake])
        case .after(let seconds):
            let until = since.addingTimeInterval(seconds)
            if now >= until { return (.hidden, [.cancelWake]) }
            return (.held(since: since, until: until), [.cancelWake, .wake(at: until)])
        }
    }

    private static func normalized(_ policy: PauseCollapse) -> PauseCollapse {
        if case .after(let seconds) = policy, !(seconds.isFinite && seconds > 0) {
            return .atOnce
        }
        return policy
    }
}
