import Foundation

/// The stored Settings choice `general.windowTheme` (`opt.general.windowTheme`).
/// Light and Dark are fixed. System, a missing value, or any other string follows the Mac appearance.
public enum WindowGlassPalette: Sendable {
    public static let storageKey = "opt.general.windowTheme"

    public enum Resolved: String, Sendable {
        case light
        case dark
    }

    public struct RGB: Sendable, Equatable {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8

        public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// The Settings window, panel, cards, and the text on them.
    public struct Tokens: Sendable, Equatable {
        public var window: RGB
        public var panel: RGB
        public var panelStroke: RGB
        public var card: RGB
        public var cardStroke: RGB
        public var separator: RGB
        public var text: RGB
        public var secondary: RGB
        public var selectedFill: RGB
        public var selectedText: RGB
        public var buttonFill: RGB
        public var buttonStroke: RGB
        public var controlFill: RGB
        public var controlStroke: RGB
        public var controlText: RGB
        public var toggleOff: RGB
        public var knob: RGB

        public init(window: RGB, panel: RGB, panelStroke: RGB, card: RGB, cardStroke: RGB, separator: RGB,
                    text: RGB, secondary: RGB, selectedFill: RGB, selectedText: RGB, buttonFill: RGB, buttonStroke: RGB,
                    controlFill: RGB, controlStroke: RGB, controlText: RGB, toggleOff: RGB, knob: RGB) {
            self.window = window
            self.panel = panel
            self.panelStroke = panelStroke
            self.card = card
            self.cardStroke = cardStroke
            self.separator = separator
            self.text = text
            self.secondary = secondary
            self.selectedFill = selectedFill
            self.selectedText = selectedText
            self.buttonFill = buttonFill
            self.buttonStroke = buttonStroke
            self.controlFill = controlFill
            self.controlStroke = controlStroke
            self.controlText = controlText
            self.toggleOff = toggleOff
            self.knob = knob
        }
    }

    /// The dark glass Settings already draws.
    public static let dark = Tokens(
        window: RGB(20, 22, 27),
        panel: RGB(31, 32, 37),
        panelStroke: RGB(53, 54, 59),
        card: RGB(35, 37, 44),
        cardStroke: RGB(61, 63, 69),
        separator: RGB(55, 57, 63),
        text: RGB(241, 243, 248),
        secondary: RGB(173, 181, 195),
        selectedFill: RGB(38, 56, 86),
        selectedText: RGB(128, 178, 249),
        buttonFill: RGB(20, 22, 27),
        buttonStroke: RGB(48, 50, 54),
        controlFill: RGB(54, 57, 66),
        controlStroke: RGB(104, 109, 122),
        controlText: RGB(232, 235, 242),
        toggleOff: RGB(89, 91, 97),
        knob: RGB(230, 231, 232))

    /// Light glass for the same surfaces. Text on window, panel, and card clears 4.5:1.
    /// The control rim on a card clears 3:1.
    public static let light = Tokens(
        window: RGB(244, 245, 248),
        panel: RGB(255, 255, 255),
        panelStroke: RGB(196, 200, 210),
        card: RGB(255, 255, 255),
        cardStroke: RGB(176, 182, 194),
        separator: RGB(210, 214, 222),
        text: RGB(22, 24, 30),
        secondary: RGB(70, 76, 88),
        selectedFill: RGB(214, 228, 248),
        selectedText: RGB(16, 58, 140),
        buttonFill: RGB(244, 245, 248),
        buttonStroke: RGB(160, 168, 184),
        controlFill: RGB(232, 235, 242),
        controlStroke: RGB(80, 88, 104),
        controlText: RGB(22, 24, 30),
        toggleOff: RGB(168, 174, 186),
        knob: RGB(255, 255, 255))

    public static func resolve(stored: String?, systemIsLight: Bool) -> Resolved {
        switch stored {
        case "Light": .light
        case "Dark": .dark
        default: systemIsLight ? .light : .dark
        }
    }

    public static func tokens(_ resolved: Resolved) -> Tokens {
        resolved == .light ? light : dark
    }

    /// WCAG contrast ratio. 1 is the same colour. Black on white is 21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let lighter = max(luminance(a), luminance(b))
        let darker = min(luminance(a), luminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ rgb: RGB) -> Double {
        func channel(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            if value <= 0.04045 { return value / 12.92 }
            return pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }
}
