import Foundation

/// Colours taken from album art. The player, the like button, and the explicit badge read one result.
public struct MediaSongPalette: Equatable, Sendable {
    public var accent: ArtworkColor.RGB
    public var support: ArtworkColor.RGB
    public var card: ArtworkColor.RGB
    public var waveform: ArtworkColor.RGB

    public init(accent: ArtworkColor.RGB, support: ArtworkColor.RGB, card: ArtworkColor.RGB, waveform: ArtworkColor.RGB) {
        self.accent = accent
        self.support = support
        self.card = card
        self.waveform = waveform
    }

    /// A calm stand-in when the art has no usable colour.
    public static let neutral = MediaSongPalette(
        accent: ArtworkColor.RGB(red: 0.55, green: 0.62, blue: 0.72),
        support: ArtworkColor.RGB(red: 0.35, green: 0.40, blue: 0.48),
        card: ArtworkColor.RGB(red: 0.12, green: 0.13, blue: 0.16),
        waveform: ArtworkColor.RGB(red: 0.55, green: 0.62, blue: 0.72)
    )

    /// The like button's own colour when it does not follow the song.
    public static let heart = ArtworkColor.RGB(red: 0.93, green: 0.33, blue: 0.42)

    /// The explicit badge when it is not colour-matched.
    public static let neutralBadge = ArtworkColor.RGB(red: 0.93, green: 0.94, blue: 0.96)

    public func like(followsSong: Bool) -> ArtworkColor.RGB { followsSong ? accent : Self.heart }

    public func badge(matchColour: Bool) -> ArtworkColor.RGB { matchColour ? accent : Self.neutralBadge }

    /// `rgba` is 8-bit pixels, row after row. Clear, black, and white art stay neutral.
    public static func extract(rgba: [UInt8]) -> MediaSongPalette {
        var bins = Array(repeating: HueBin(), count: 12)
        var index = 0
        while index + 3 < rgba.count {
            let alpha = Double(rgba[index + 3]) / 255
            if alpha > 0.05 {
                let sample = ArtworkColor.RGB(
                    red: Double(rgba[index]) / 255,
                    green: Double(rgba[index + 1]) / 255,
                    blue: Double(rgba[index + 2]) / 255
                )
                let (hue, saturation, light) = hsl(sample)
                if light >= 0.08, light <= 0.92, saturation >= 0.15 {
                    let bin = min(max(Int(hue / 30), 0), 11)
                    let weight = saturation * alpha
                    bins[bin].weight += weight
                    bins[bin].red += sample.red * weight
                    bins[bin].green += sample.green * weight
                    bins[bin].blue += sample.blue * weight
                }
            }
            index += 4
        }
        let ranked = bins.enumerated().filter { $0.element.weight > 0 }.sorted { lhs, rhs in
            if lhs.element.weight != rhs.element.weight { return lhs.element.weight > rhs.element.weight }
            return lhs.offset < rhs.offset
        }
        guard let primary = ranked.first else { return .neutral }
        let accent = ArtworkColor.glow(average(primary.element))
        let support: ArtworkColor.RGB
        if let second = ranked.dropFirst().first(where: { hueDistance($0.offset, primary.offset) >= 2 }) {
            support = ArtworkColor.glow(average(second.element))
        } else {
            support = ArtworkColor.glow(rotate(accent, degrees: 140))
        }
        return MediaSongPalette(accent: accent, support: support, card: darkened(accent), waveform: accent)
    }

    private static func average(_ bin: HueBin) -> ArtworkColor.RGB {
        ArtworkColor.RGB(red: bin.red / bin.weight, green: bin.green / bin.weight, blue: bin.blue / bin.weight)
    }

    private static func hueDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let gap = abs(lhs - rhs)
        return min(gap, 12 - gap)
    }

    private static func darkened(_ accent: ArtworkColor.RGB) -> ArtworkColor.RGB {
        let glass = ArtworkColor.RGB(red: 0.10, green: 0.11, blue: 0.13)
        var card = mix(accent, glass, 0.18)
        var guardRail = 0
        while luminance(card) >= luminance(accent), luminance(card) > 0.02, guardRail < 6 {
            card = mix(card, glass, 0.55)
            guardRail += 1
        }
        return card
    }

    private static func mix(_ color: ArtworkColor.RGB, _ other: ArtworkColor.RGB, _ amount: Double) -> ArtworkColor.RGB {
        ArtworkColor.RGB(
            red: color.red * amount + other.red * (1 - amount),
            green: color.green * amount + other.green * (1 - amount),
            blue: color.blue * amount + other.blue * (1 - amount)
        )
    }

    private static func rotate(_ color: ArtworkColor.RGB, degrees: Double) -> ArtworkColor.RGB {
        let (hue, saturation, light) = hsl(color)
        return fromHSL(hue: (hue + degrees).truncatingRemainder(dividingBy: 360), saturation: max(saturation, 0.45), light: light)
    }

    private static func luminance(_ color: ArtworkColor.RGB) -> Double {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }

    private static func hsl(_ color: ArtworkColor.RGB) -> (Double, Double, Double) {
        let red = color.red, green = color.green, blue = color.blue
        let high = max(red, green, blue), low = min(red, green, blue)
        let light = (high + low) / 2
        let delta = high - low
        guard delta > 0.000_001 else { return (0, 0, light) }
        let saturation = delta / (1 - abs(2 * light - 1))
        let hue: Double
        if high == red { hue = (green - blue) / delta }
        else if high == green { hue = (blue - red) / delta + 2 }
        else { hue = (red - green) / delta + 4 }
        let degrees = hue * 60
        return (degrees < 0 ? degrees + 360 : degrees, saturation, light)
    }

    private static func fromHSL(hue: Double, saturation: Double, light: Double) -> ArtworkColor.RGB {
        let wrapped = hue < 0 ? hue + 360 : hue
        let c = (1 - abs(2 * light - 1)) * saturation
        let h = wrapped / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch Int(h) {
        case 0: (red, green, blue) = (c, x, 0)
        case 1: (red, green, blue) = (x, c, 0)
        case 2: (red, green, blue) = (0, c, x)
        case 3: (red, green, blue) = (0, x, c)
        case 4: (red, green, blue) = (x, 0, c)
        default: (red, green, blue) = (c, 0, x)
        }
        let match = light - c / 2
        return ArtworkColor.RGB(red: clamp(red + match), green: clamp(green + match), blue: clamp(blue + match))
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

private struct HueBin {
    var weight = 0.0
    var red = 0.0
    var green = 0.0
    var blue = 0.0
}
