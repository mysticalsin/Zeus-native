import Foundation

/// What the Tiling section says about itself. One word and one symbol for each state, so the state is never
/// carried by colour alone. Pure: the app feeds it four facts and shows the answer.
public enum TilingPhase: Equatable, Sendable {
    /// The switch is off. Nothing exists: no key tap, no observer, no timer, no window.
    case off
    /// The switch is on but Accessibility is not allowed, so no window can be read or moved.
    case needsAccessibility
    /// Accessibility is on but the system keeps turning the key tap off, so tiling stopped itself.
    case keysUnavailable
    /// Arranging is stopped for now. Windows stay where they are.
    case paused
    case running

    /// The switch decides first, then Accessibility, then the keys, then the pause.
    public init(enabled: Bool, accessibilityOn: Bool, keysUnavailable: Bool, paused: Bool) {
        if !enabled { self = .off }
        else if !accessibilityOn { self = .needsAccessibility }
        else if keysUnavailable { self = .keysUnavailable }
        else if paused { self = .paused }
        else { self = .running }
    }

    public var isActive: Bool { self == .running }

    public var word: String {
        switch self {
        case .off: "Off"
        case .needsAccessibility: "Needs Accessibility"
        case .keysUnavailable: "Keys unavailable"
        case .paused: "Paused"
        case .running: "On"
        }
    }

    /// An SF Symbol name; each state has its own shape.
    public var symbol: String {
        switch self {
        case .off: "power"
        case .needsAccessibility: "lock.fill"
        case .keysUnavailable: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        case .running: "checkmark.circle.fill"
        }
    }

    /// One plain line under the word.
    public var detail: String {
        switch self {
        case .off: "Turn it on to arrange your windows from the keyboard."
        case .needsAccessibility: "Allow Accessibility so Zeus can move windows."
        case .keysUnavailable: "Zeus could not read the tiling keys. Turn tiling off and on to try again."
        case .paused: "Windows stay where they are."
        case .running: "Hold the keys and tap an arrow."
        }
    }
}

/// A counter that makes earlier work stale. Work remembers the number it was queued under and checks it
/// before it touches anything; a display, Space or sleep change advances the number, so work queued before
/// the change does nothing when it finally runs.
public struct TileGeneration: Equatable, Sendable {
    public private(set) var value = 0

    public init() {}

    /// Makes every earlier token stale and returns the new one.
    public mutating func advance() -> Int {
        value += 1
        return value
    }

    public func isCurrent(_ token: Int) -> Bool { token == value }
}

extension TileModifierBase {
    /// The words the "Tiling keys" settings row stores and shows. `init(label:)` reads them back.
    public var label: String {
        switch self {
        case .controlOption: "Control-Option"
        case .optionCommand: "Option-Command"
        case .controlOptionCommand: "Control-Option-Command"
        }
    }

    /// The same pair as modifier glyphs, for a short key list.
    public var glyphs: String { Shortcut(modifiers: modifiers).symbol }
}
