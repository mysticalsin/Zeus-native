import Foundation
#if os(macOS)
import AppKit
#endif

/// The lock card the probe draws while a lock part is up.
///
/// Fixed words, one button, and a ruler. The ruler ignores clicks. A key is a count with no code.
/// The window does not become key, and its sharing type is none. Nothing else is drawn.
public enum StepZeroLockPanel {
    public static let words = "Zeus probe"
    public static let button = "Press"
    public static let width = 360
    public static let height = 88
    public static let rulerTicks = Array(0...10)

    public enum Sharing: String, Sendable, Equatable {
        case none
    }

    public static let sharing = Sharing.none

    public enum Part: String, Sendable, Equatable, CaseIterable {
        case words
        case button
        case ruler
    }

    public static let drawn: [Part] = Part.allCases

    /// What reached the card. `key` has no code.
    public enum Input: Sendable, Equatable {
        case button
        case mouseDown
        case key
    }

    public struct Counts: Sendable, Equatable {
        public var buttonActions: Int
        public var mouseDowns: Int
        public var keyEvents: Int

        public init() {
            buttonActions = 0
            mouseDowns = 0
            keyEvents = 0
        }
    }

    /// The window facts the card is built from. The Mac window reads this value.
    public struct Style: Sendable, Equatable {
        public var canBecomeKey: Bool
        public var canBecomeMain: Bool
        public var acceptsFirstMouse: Bool
        public var ignoresMouseEvents: Bool
        public var hidesOnDeactivate: Bool
        public var isReleasedWhenClosed: Bool
        public var hasShadow: Bool
        public var registersDraggedTypes: Bool
        public var borderless: Bool
        public var nonactivating: Bool
        public var buffered: Bool
        public var deferCreation: Bool
        public var stationary: Bool
        public var ignoresCycle: Bool
        public var fullScreenAuxiliary: Bool
        public var joinsAllSpaces: Bool
        public var shieldingLevel: Bool

        public static let probe = Style(
            canBecomeKey: false,
            canBecomeMain: false,
            acceptsFirstMouse: true,
            ignoresMouseEvents: false,
            hidesOnDeactivate: false,
            isReleasedWhenClosed: false,
            hasShadow: false,
            registersDraggedTypes: false,
            borderless: true,
            nonactivating: true,
            buffered: true,
            deferCreation: false,
            stationary: true,
            ignoresCycle: true,
            fullScreenAuxiliary: true,
            joinsAllSpaces: false,
            shieldingLevel: true
        )
    }

    /// A click on the ruler is not an input. The words are a mouse-down, not a button.
    public static func input(at part: Part) -> Input? {
        switch part {
        case .button:
            return .button
        case .words:
            return .mouseDown
        case .ruler:
            return nil
        }
    }

    public static func record(_ input: Input, into counts: inout Counts) {
        switch input {
        case .button:
            counts.buttonActions += 1
        case .mouseDown:
            counts.mouseDowns += 1
        case .key:
            counts.keyEvents += 1
        }
    }

    /// Records a part that produces an input. The ruler returns false and changes nothing.
    @discardableResult
    public static func accept(_ part: Part, into counts: inout Counts) -> Bool {
        guard let input = input(at: part) else { return false }
        record(input, into: &counts)
        return true
    }
}

#if os(macOS)
/// Borderless, non-activating panel at the shielding level. It cannot become key or main.
public final class StepZeroLockPanelWindow: NSPanel {
    public var onPress: (() -> Void)?

    public static func make() -> StepZeroLockPanelWindow {
        let style = StepZeroLockPanel.Style.probe
        var mask: NSWindow.StyleMask = []
        if style.borderless { mask.insert(.borderless) }
        if style.nonactivating { mask.insert(.nonactivatingPanel) }
        let frame = NSRect(x: 0, y: 0, width: StepZeroLockPanel.width, height: StepZeroLockPanel.height)
        let panel = StepZeroLockPanelWindow(
            contentRect: frame,
            styleMask: mask,
            backing: style.buffered ? .buffered : .retained,
            defer: style.deferCreation
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = style.hasShadow
        panel.hidesOnDeactivate = style.hidesOnDeactivate
        panel.isReleasedWhenClosed = style.isReleasedWhenClosed
        panel.ignoresMouseEvents = style.ignoresMouseEvents
        if style.shieldingLevel {
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        }
        var behavior: NSWindow.CollectionBehavior = []
        if style.stationary { behavior.insert(.stationary) }
        if style.ignoresCycle { behavior.insert(.ignoresCycle) }
        if style.fullScreenAuxiliary { behavior.insert(.fullScreenAuxiliary) }
        if style.joinsAllSpaces { behavior.insert(.canJoinAllSpaces) }
        panel.collectionBehavior = behavior
        if StepZeroLockPanel.sharing == .none {
            panel.sharingType = .none
        }
        let card = StepZeroLockCardView(frame: NSRect(origin: .zero, size: frame.size))
        card.onPress = { [weak panel] in panel?.onPress?() }
        panel.contentView = card
        return panel
    }

    public override var canBecomeKey: Bool { StepZeroLockPanel.Style.probe.canBecomeKey }
    public override var canBecomeMain: Bool { StepZeroLockPanel.Style.probe.canBecomeMain }
}

private final class StepZeroLockCardView: NSView {
    var onPress: (() -> Void)?
    private let press = StepZeroPressControl()
    private let ruler = StepZeroRulerStrip()

    override init(frame: NSRect) {
        super.init(frame: frame)
        press.title = StepZeroLockPanel.button
        press.bezelStyle = .rounded
        press.setButtonType(.momentaryPushIn)
        press.refusesFirstResponder = true
        press.target = self
        press.action = #selector(pressed)
        press.frame = NSRect(x: 16, y: 40, width: 80, height: 28)
        ruler.frame = NSRect(x: 0, y: frame.height - 16, width: frame.width, height: 16)
        addSubview(press)
        addSubview(ruler)
    }

    required init?(coder: NSCoder) { return nil }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        StepZeroLockPanel.Style.probe.acceptsFirstMouse
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        let line = StepZeroLockPanel.words as NSString
        line.draw(at: NSPoint(x: 16, y: 12), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
    }

    @objc private func pressed() { onPress?() }
}

private final class StepZeroPressControl: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        StepZeroLockPanel.Style.probe.acceptsFirstMouse
    }
}

/// Numbered ticks. A click here is not delivered to the strip or the button under it.
private final class StepZeroRulerStrip: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard StepZeroLockPanel.rulerTicks.count > 1 else { return }
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath()
        let step = bounds.width / CGFloat(StepZeroLockPanel.rulerTicks.count - 1)
        for (index, _) in StepZeroLockPanel.rulerTicks.enumerated() {
            let x = CGFloat(index) * step
            path.move(to: NSPoint(x: x, y: bounds.minY))
            path.line(to: NSPoint(x: x, y: bounds.maxY))
            let label = "\(index)" as NSString
            label.draw(at: NSPoint(x: x + 1, y: 0), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.white,
            ])
        }
        path.lineWidth = 1
        path.stroke()
    }
}
#endif
