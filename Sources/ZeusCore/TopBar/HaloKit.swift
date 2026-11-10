import Foundation

// MARK: Halo style (one setting, one key)

/// The closed notch's halo styles. One setting (`halo.style`) holds the stable id; every picker shows `title`.
public enum HaloStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, pixelated, rayons, prisme, nimbus, lumiere, bioluminescent, aurora, storm, volumetric, off
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: "Classic halo"
        case .pixelated: "Pixelated"
        case .rayons: "Rayons"
        case .prisme: "Prisme"
        case .nimbus: "Nimbus"
        case .lumiere: "Lumiere"
        case .bioluminescent: "Bioluminescence"
        case .aurora: "Aurora"
        case .storm: "Storm"
        case .volumetric: "Volumetric light"
        case .off: "Off"
        }
    }

    /// Ids, current titles and every name an older build or the reference app's picker used.
    public static func resolve(_ raw: String?) -> HaloStyle {
        let key = (raw ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter(\.isLetter)
        switch key {
        case "pixelated", "pixelatedhalo": return .pixelated
        case "rayons", "wetrays": return .rayons
        case "prisme", "crystalprism": return .prisme
        case "nimbus", "realisticnimbus": return .nimbus
        case "lumiere": return .lumiere
        case "bioluminescence", "bioluminescent": return .bioluminescent
        case "aurora": return .aurora
        case "storm": return .storm
        case "volumetric", "volumetriclight": return .volumetric
        case "off": return .off
        default: return .classic
        }
    }

    /// How the style is drawn. The live notch, Settings and the welcome guide all pick their drawing from this.
    public enum Renderer: String, Sendable {
        case none, line, rays, prism, cloud, core, grid, depth, dots, aurora, storm
    }

    public var renderer: Renderer {
        switch self {
        case .off: .none
        case .classic: .line
        case .rayons: .rays
        case .prisme: .prism
        case .nimbus: .cloud
        case .lumiere: .core
        case .pixelated: .grid
        case .volumetric: .depth
        case .bioluminescent: .dots
        case .aurora: .aurora
        case .storm: .storm
        }
    }
}

/// Folds the two old keys (`topBar.halo`, which the notch read, and `halo.style`, which the picker wrote
/// and nothing read) into `halo.style`, stored as a stable id.
public enum HaloMigration {
    public static let legacyKey = "topBar.halo"
    public static let styleKey = "opt.halo.style"

    /// The old notch key wins: it is the one the user could see working.
    public static func unified(haloStyle: String?, legacyTopBar: String?) -> HaloStyle {
        if let legacy = legacyTopBar, !legacy.isEmpty { return HaloStyle.resolve(legacy) }
        return HaloStyle.resolve(haloStyle)
    }

    /// Rewrites the keys in `defaults`; returns the style when something changed.
    @discardableResult
    public static func run(defaults: UserDefaults) -> HaloStyle? {
        let legacy = defaults.string(forKey: legacyKey)
        let stored = defaults.string(forKey: styleKey)
        let storedIsID = stored.map { HaloStyle(rawValue: $0) != nil } ?? true
        guard legacy != nil || !storedIsID else { return nil }
        let style = unified(haloStyle: stored, legacyTopBar: legacy)
        defaults.set(style.rawValue, forKey: styleKey)
        defaults.removeObject(forKey: legacyKey)
        return style
    }
}

// MARK: Entrances

public enum HaloEntrance: String, CaseIterable, Identifiable, Sendable {
    case sweep, trace, blast, whiteFlash, hueSlide, hybrid, deflagration, shockwave, supernova, strobe, bigBang, ondulation, shimmer
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sweep: "Sweep"
        case .trace: "Trace (sleek)"
        case .blast: "Blast"
        case .whiteFlash: "White flash"
        case .hueSlide: "Hue slide"
        case .hybrid: "Hybrid"
        case .deflagration: "Deflagration"
        case .shockwave: "Shockwave"
        case .supernova: "Supernova"
        case .strobe: "Strobe"
        case .bigBang: "Big Bang"
        case .ondulation: "Ondulation"
        case .shimmer: "Shimmer"
        }
    }

    /// Ids, titles, and the raw values older builds saved ("Trace", "Big bang", "White flash"). Unknown means Sweep.
    public static func resolve(_ raw: String?) -> HaloEntrance {
        var text = raw ?? ""
        if let open = text.firstIndex(of: "(") { text = String(text[..<open]) }
        let key = text.lowercased().filter(\.isLetter)
        switch key {
        case "trace": return .trace
        case "blast": return .blast
        case "whiteflash": return .whiteFlash
        case "hueslide": return .hueSlide
        case "hybrid": return .hybrid
        case "deflagration": return .deflagration
        case "shockwave": return .shockwave
        case "supernova": return .supernova
        case "strobe": return .strobe
        case "bigbang": return .bigBang
        case "ondulation": return .ondulation
        case "shimmer": return .shimmer
        default: return .sweep
        }
    }

    public var choreography: EntranceChoreography { EntranceChoreography.make(self) }
}

/// What one entrance does: its shape of light and the numbers that drive it.
public struct EntranceChoreography: Equatable, Sendable {
    public enum Shape: String, Sendable { case sweep, ondulation, shimmer, trace, hueSlide, flash, hybrid, deflagration, shockwave, supernova, strobe, bigBang, blast }
    public let shape: Shape
    /// Seconds at 100 % speed; always within 0.4 ... 1.2.
    public let duration: TimeInterval
    /// Shortest length the speed setting may squeeze it to. Strobe never flashes faster than 3 Hz.
    public let minDuration: TimeInterval
    public let crests: Int
    public let pulses: Int
    /// Turns of hue the colour travels (0 for entrances that keep their tint).
    public let hueTravel: Double
    public let whitePeak: Double
    public let bloomPeak: Double
    public let widthPeak: Double

    /// One line that differs for every entrance; the tests hold each pair apart.
    public var signature: String {
        "\(shape.rawValue)|\(duration)|\(crests)|\(pulses)|\(hueTravel)|\(whitePeak)|\(bloomPeak)|\(widthPeak)"
    }

    /// Flashes per second at the base speed.
    public var flashRate: Double { pulses > 0 ? Double(pulses) / duration : 0 }

    static func make(_ e: HaloEntrance) -> EntranceChoreography {
        func c(_ shape: Shape, _ d: Double, crests: Int = 1, pulses: Int = 0, hue: Double = 0, white: Double = 0, bloom: Double = 1, width: Double = 1, min: Double? = nil) -> EntranceChoreography {
            .init(shape: shape, duration: d, minDuration: min ?? d / 2, crests: crests, pulses: pulses, hueTravel: hue, whitePeak: white, bloomPeak: bloom, widthPeak: width)
        }
        switch e {
        case .sweep: return c(.sweep, 0.8)
        case .ondulation: return c(.ondulation, 1.1, crests: 3, bloom: 1.2)
        case .shimmer: return c(.shimmer, 1.0, crests: 7, bloom: 1.3)
        case .trace: return c(.trace, 0.7, crests: 5, white: 0.6, bloom: 1.4)
        case .hueSlide: return c(.hueSlide, 1.2, hue: 0.6)
        case .whiteFlash: return c(.flash, 0.4, white: 1, bloom: 2.8, width: 1.6)
        case .hybrid: return c(.hybrid, 0.9, crests: 2, white: 1, bloom: 1.6)
        case .deflagration: return c(.deflagration, 0.7, bloom: 2.2, width: 1.8)
        case .shockwave: return c(.shockwave, 0.6, crests: 2, bloom: 2.0)
        case .supernova: return c(.supernova, 1.1, white: 0.8, bloom: 3.5, width: 2.2)
        case .strobe: return c(.strobe, 1.1, pulses: 3, white: 0.4, bloom: 1.5, min: 3.0 / 3.0)
        case .bigBang: return c(.bigBang, 1.2, crests: 2, white: 1, bloom: 3.0, width: 1.5)
        case .blast: return c(.blast, 0.5, bloom: 2.2, width: 1.8)
        }
    }
}

/// One drawable layer of an entrance frame: segments plus how white, thick and bloomy to draw them.
public struct EntranceLayer: Equatable, Sendable {
    public var segments: [LightSegment]
    public var white: Double
    public var width: Double
    public var bloom: Double
    public init(_ segments: [LightSegment], white: Double = 0, width: Double = 1, bloom: Double = 1) {
        self.segments = segments; self.white = white; self.width = width; self.bloom = bloom
    }
}

public struct EntranceFrame: Equatable, Sendable {
    public var layers: [EntranceLayer]
    /// Turns the tint's hue has travelled at this moment.
    public var hueShift: Double
    public var flat: [LightSegment] { layers.flatMap(\.segments) }
}

extension NotchLightMath {
    private static func frac(_ x: Double) -> Double { x - x.rounded(.down) }
    private static func bump(_ p: Double) -> Double { sin(max(0, min(1, p)) * .pi) }

    /// The entrance's light at progress `p` (0...1): its own choreography, not a shared fade.
    public static func entranceFrame(_ style: HaloEntrance, progress p: Double, shoulder s: Double) -> EntranceFrame {
        let p = max(0, min(1, p))
        let ch = style.choreography
        let e = ease(p)
        switch ch.shape {
        case .sweep:
            return .init(layers: [.init([.init(from: 0, to: e, opacity: fadeOut(p, from: 0.6))])], hueShift: 0)
        case .ondulation:
            let env = pow(bump(p), 0.7)
            var segs: [LightSegment] = [.init(from: 0, to: 1, opacity: 0.16 * env)]
            for k in 0..<ch.crests {
                let center = e * 1.3 - Double(k) * 0.22
                guard center > -0.07, center < 1.07 else { continue }
                segs.append(crest(center, 0.07, env * (1 - Double(k) * 0.2)))
            }
            return .init(layers: [.init(segs, bloom: ch.bloomPeak)], hueShift: 0)
        case .shimmer:
            let env = bump(p)
            var segs: [LightSegment] = [.init(from: 0, to: e, opacity: 0.22 * env)]
            for k in 0..<ch.crests {
                let wave = max(0, sin(2 * .pi * (p * 2.2 + Double(k) * 0.37)))
                segs.append(crest((Double(k) + 0.5) / Double(ch.crests), 0.035, env * wave * wave, side: [-1, 1, 0][k % 3]))
            }
            return .init(layers: [.init(segs, bloom: ch.bloomPeak)], hueShift: 0)
        case .trace:
            let head = 1 - e
            let fade = fadeOut(p, from: 0.8)
            var tail: [LightSegment] = []
            for k in 1...4 { tail.append(.init(from: head, to: min(1, head + Double(k) * 0.06), opacity: 0.35 * fade / Double(k))) }
            return .init(layers: [.init(tail), .init([crest(head, 0.045, fade)], white: ch.whitePeak, bloom: ch.bloomPeak)], hueShift: 0)
        case .hueSlide:
            let reach = ease(min(1, p * 1.6))
            return .init(layers: [.init([.init(from: 0, to: reach, opacity: fadeOut(p, from: 0.75))])], hueShift: e * ch.hueTravel)
        case .flash:
            let fall = 1 - e
            return .init(layers: [.init([.init(from: 0, to: 1, opacity: max(0, 1 - e * 0.85))], white: ch.whitePeak * fall, width: 1 + (ch.widthPeak - 1) * fall, bloom: 1 + (ch.bloomPeak - 1) * fall)], hueShift: 0)
        case .hybrid:
            let fade = fadeOut(p, from: 0.7)
            return .init(layers: [.init([.init(from: 0, to: e, opacity: 0.65 * fade)]),
                                  .init([crest(e, 0.07, fade)], white: ch.whitePeak, bloom: ch.bloomPeak)], hueShift: 0)
        case .deflagration:
            let spread = 0.04 + 0.5 * e
            let flicker = 0.8 + 0.2 * sin(p * 60)
            return .init(layers: [.init([.init(from: s - spread, to: s + spread, opacity: max(0, 1 - pow(e, 1.5)) * flicker)],
                                         width: 1 + (ch.widthPeak - 1) * (1 - p), bloom: 1 + (ch.bloomPeak - 1) * (1 - p))], hueShift: 0)
        case .shockwave:
            let front = e * 1.12
            let fade = fadeOut(p, from: 0.5)
            return .init(layers: [.init([crest(front, 0.025, fade)], bloom: ch.bloomPeak),
                                  .init([crest(front - 0.12, 0.02, 0.5 * fade)])], hueShift: 0)
        case .supernova:
            let swell = bump(min(1, p * 1.15))
            return .init(layers: [.init([.init(from: 0, to: 1, opacity: fadeOut(p, from: 0.65) * (0.5 + 0.5 * swell))],
                                        white: ch.whitePeak * swell * swell, width: 1 + (ch.widthPeak - 1) * swell, bloom: 1 + (ch.bloomPeak - 1) * swell)], hueShift: 0)
        case .strobe:
            // Three flashes, each lasting half of its third of the run, with soft edges.
            let cell = frac(p * Double(ch.pulses)), on = p >= 1 ? 0 : ramp3(cell, 0.0, 0.12) * (1 - ramp3(cell, 0.4, 0.5))
            return .init(layers: [.init([.init(from: 0, to: 1, opacity: on)], white: ch.whitePeak * on, bloom: ch.bloomPeak)], hueShift: 0)
        case .bigBang:
            let core = max(0, 1 - p / 0.25)
            let reach = ease(max(0, (p - 0.08) / 0.92))
            return .init(layers: [.init([.init(from: 0, to: 0.05, opacity: core)], white: ch.whitePeak, width: ch.widthPeak, bloom: ch.bloomPeak),
                                  .init([.init(from: 0, to: reach, opacity: max(0, 1 - reach) * 0.8)], white: 0.5 * (1 - p)),
                                  .init([crest(reach, 0.05, max(0, 1 - reach))], bloom: 2.2)], hueShift: 0)
        case .blast:
            return .init(layers: [.init([.init(from: 0, to: 1, opacity: 1 - e)], width: 1 + (ch.widthPeak - 1) * (1 - e), bloom: ch.bloomPeak - (ch.bloomPeak - 1) * e)], hueShift: 0)
        }
    }

    /// 0 below `a`, 1 above `b`.
    private static func ramp3(_ x: Double, _ a: Double, _ b: Double) -> Double { ease((x - a) / max(b - a, 1e-6)) }
}

// MARK: Wallpaper-aware colour

/// "Match the halo colour to the wallpaper": a bright wallpaper washes a coloured glow out, so the
/// colour is blended toward white as the wallpaper under the notch gets lighter.
public enum WallpaperBlend {
    /// Perceived brightness 0...1 from gamma-encoded sRGB components.
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// 0 on dark and mid wallpapers, rising smoothly to 0.8 on very light ones.
    public static func whiteAmount(luminance: Double) -> Double {
        let x = max(0, min(1, (luminance - 0.55) / 0.3))
        return x * x * (3 - 2 * x) * 0.8
    }

    public static func blend(red: Double, green: Double, blue: Double, luminance: Double) -> (red: Double, green: Double, blue: Double) {
        let a = whiteAmount(luminance: luminance)
        return (red + (1 - red) * a, green + (1 - green) * a, blue + (1 - blue) * a)
    }
}

// MARK: Screen-edge wave

public enum EdgeWaveMath {
    /// Two fronts leave the top centre and run round the screen edge in both directions, meeting at the
    /// bottom centre. Positions are 0 (top centre) ... 1 (bottom centre) along one half of the perimeter.
    public static func fronts(progress p: Double) -> (head: Double, tail: Double, opacity: Double) {
        let p = max(0, min(1, p))
        let head = NotchLightMath.ease(p)
        let tail = NotchLightMath.ease(max(0, p - 0.22) / 0.78)
        let opacity = min(1, p / 0.08) * NotchLightMath.fadeOut(p, from: 0.6)
        return (head, tail, opacity)
    }
}
