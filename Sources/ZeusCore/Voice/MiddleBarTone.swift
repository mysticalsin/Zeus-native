import Foundation

/// The middle bar and the light that moves on it share this one colour.
/// Shades mix the Zeus purple accent with white or black only, so the hue stays put.
public enum MiddleBarTone {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }
    }

    /// The bar's own colour. Every animated shade uses this hue.
    public static let bar = RGB(hex: ZeusThemeTokens.zeusPurple)

    /// Seven lobe shades. One entry is `bar` itself.
    public static let shades: [RGB] = [
        mix(bar, white: 0.55),
        mix(bar, white: 0.28),
        bar,
        mix(bar, black: 0.18),
        mix(bar, white: 0.42),
        mix(bar, black: 0.32),
        mix(bar, white: 0.12),
    ]

    /// `white` lifts toward white. `black` darkens. Either one leaves the hue unchanged.
    public static func mix(_ color: RGB, white: Double = 0, black: Double = 0) -> RGB {
        let lift = min(1, max(0, white))
        let shade = min(1, max(0, black))
        func channel(_ value: Double) -> Double {
            let towardWhite = value + (1 - value) * lift
            return towardWhite * (1 - shade)
        }
        return RGB(red: channel(color.red), green: channel(color.green), blue: channel(color.blue))
    }

    /// Hue as turns around the wheel, 0...1. A grey sample (no chroma) is 0.
    public static func hueTurns(_ color: RGB) -> Double {
        let red = color.red, green = color.green, blue = color.blue
        let maxChannel = max(red, max(green, blue))
        let minChannel = min(red, min(green, blue))
        let delta = maxChannel - minChannel
        guard delta > 1e-8 else { return 0 }
        let sector: Double
        if maxChannel == red {
            var value = (green - blue) / delta
            if value < 0 { value += 6 }
            sector = value
        } else if maxChannel == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        return sector / 6
    }

    /// Shortest distance between two hues, 0...0.5.
    public static func hueDistance(_ first: RGB, _ second: RGB) -> Double {
        let delta = abs(hueTurns(first) - hueTurns(second))
        return min(delta, 1 - delta)
    }
}
