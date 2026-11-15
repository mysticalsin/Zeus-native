import Foundation

/// What a keyboard picture says about one shortcut, as plain facts. A pure function of a `ShortcutState` and a
/// `Shortcut`: the voice key machine and the pointing gesture read the same facts, so one rule decides what is a clean
/// press, a release and a larger chord. The facts come from `flagModifiers`, so only a flags event says which
/// modifiers are down.
public struct KeyFacts: Equatable, Sendable {
    /// Every modifier of the key is down. A sided key needs its own physical key, a keyed key needs its key code.
    public let ownDown: Bool
    /// The modifiers down that are not the key's. Fn is left out for a keyed key that does not ask for it, because
    /// a laptop function key carries it by itself.
    public let foreignModifiers: ShortcutModifiers
    /// The other physical key of a sided modifier is down (Left Command beside a Right Command key).
    public let otherSideDown: Bool
    /// A modifier-only key: an ordinary key is down, or one joined the chord. A keyed key: an ordinary key other
    /// than its own is down.
    public let foreignKey: Bool
    /// No modifier and no ordinary key is down.
    public let allUp: Bool

    /// The chord key the caller allows beside a modifier-only key is down.
    public let chordDown: Bool

    public var foreignModifier: Bool { !foreignModifiers.isEmpty || otherSideDown }

    public init(of state: ShortcutState, key: Shortcut, chord: UInt16? = nil) {
        let mods = state.flagModifiers
        let own = key.modifiers
        var down = key.isValid && mods.isSuperset(of: own)
        var foreign = mods.subtracting(own)
        var other = false
        if let code = key.keyCode {
            down = down && state.keysDown.contains(code)
            if !own.contains(.function) { foreign.remove(.function) }
            foreignKey = !state.keysDown.subtracting([code]).isEmpty
            chordDown = false
        } else {
            // The chord key the caller allows is not foreign; any other key, down now or earlier, is.
            let allowed: Set<UInt16> = chord.map { [$0] } ?? []
            foreignKey = !state.keysDown.subtracting(allowed).isEmpty || !state.spoilers.subtracting(allowed).isEmpty
            chordDown = chord.map { state.keysDown.contains($0) } ?? false
            if key.side != .any, let entry = ShortcutModifiers.keyCodes.first(where: { $0.0 == own }) {
                let mine = key.side == .right ? entry.right : entry.left
                let theirs = key.side == .right ? entry.left : entry.right
                down = down && state.deviceKeys.contains(mine)
                other = mine != theirs && state.deviceKeys.contains(theirs)
            }
        }
        ownDown = down
        foreignModifiers = foreign
        otherSideDown = other
        allUp = mods.isEmpty && state.keysDown.isEmpty
    }
}
