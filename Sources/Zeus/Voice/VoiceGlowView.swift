import Observation
import SwiftUI
import ZeusCore

/// The voice glow's two settings, shared by the Dictation page and the recorder pill so a change
/// shows at once. Persists to the same UserDefaults keys as before.
@MainActor
@Observable
final class VoiceGlowSettings {
    static let shared = VoiceGlowSettings()
    static let enabledKey = "dictation.voiceGlow.enabled"
    static let variantKey = "dictation.voiceGlow.variant"

    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    var variant: VoiceGlowVariant { didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey) } }

    private init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        variant = VoiceGlowVariant.resolve(UserDefaults.standard.string(forKey: Self.variantKey))
    }
}

extension Color {
    init(voiceGlow rgb: VoiceGlowRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Carries a `VoiceGlowModel` from frame to frame. A view value is rebuilt whenever its parent
/// updates, so the smoothed envelope and the beam clock live here (this toolchain has no
/// `@State`). Stepped once per timeline tick; the lock only guards the rare overlap between ticks.
final class VoiceGlowDriver: @unchecked Sendable {
    /// For a single glow without its own driver.
    static let shared = VoiceGlowDriver()
    /// The recorder pill's glow.
    static let pill = VoiceGlowDriver(geometry: .pill)

    private let lock = NSLock()
    private var model: VoiceGlowModel
    private var last: Date?

    init(geometry: VoiceGlowGeometry = .default) {
        model = VoiceGlowModel(geometry: geometry)
    }

    func advance(now: Date, level: Double, processing: Bool, reduceMotion: Bool, geometry: VoiceGlowGeometry) -> VoiceGlowModel {
        lock.lock()
        defer { lock.unlock() }
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        model.geometry = geometry
        model.step(level: level, processing: processing, dt: dt, reduceMotion: reduceMotion)
        return model
    }
}

/// A sound reactive glow along the bottom edge of the wrapped view: soft coloured lobes rise and
/// bloom with the voice; while `processing` they gather into a narrow beam that sweeps along the
/// edge. Clipped to the view's rounded shape. Drawn at up to 30 fps, paused while `active` is false,
/// and a still, low glow under Reduce Motion. Decorative: hidden from accessibility.
struct VoiceGlow: ViewModifier {
    enum Layer { case behind, over }

    let level: @MainActor () -> Double
    let processing: Bool
    let preset: VoiceGlowGeometry
    let variant: VoiceGlowVariant
    let customColors: [Color]
    let strength: Double
    let cornerRadius: CGFloat
    let active: Bool
    let layer: Layer
    let driver: VoiceGlowDriver

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(level: @escaping @MainActor () -> Double, processing: Bool, preset: VoiceGlowGeometry = .default,
         variant: VoiceGlowVariant = .colorful, customColors: [Color] = [], strength: Double = 1,
         cornerRadius: CGFloat = 16, active: Bool = true, layer: Layer = .behind, driver: VoiceGlowDriver = .shared) {
        self.level = level
        self.processing = processing
        self.preset = preset
        self.variant = variant
        self.customColors = customColors
        self.strength = strength
        self.cornerRadius = cornerRadius
        self.active = active
        self.layer = layer
        self.driver = driver
    }

    func body(content: Content) -> some View {
        switch layer {
        case .behind: content.background { glow }
        case .over: content.overlay { glow }
        }
    }

    private var colors: [Color] {
        customColors.isEmpty
            ? variant.palette.map { Color(voiceGlow: $0) }
            : Array(customColors.prefix(VoiceGlowVariant.maxColors))
    }

    private var glow: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { timeline in
            let sampled = MainActor.assumeIsolated { level() }
            let model = driver.advance(now: timeline.date, level: sampled, processing: processing,
                                       reduceMotion: reduceMotion, geometry: preset)
            VoiceGlowCanvas(model: model, colors: colors, strength: VoiceGlowModel.clampStrength(strength))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func voiceGlow(level: @escaping @MainActor () -> Double, processing: Bool, preset: VoiceGlowGeometry = .default,
                   variant: VoiceGlowVariant = .colorful, customColors: [Color] = [], strength: Double = 1,
                   cornerRadius: CGFloat = 16, active: Bool = true, layer: VoiceGlow.Layer = .behind,
                   driver: VoiceGlowDriver = .shared) -> some View {
        modifier(VoiceGlow(level: level, processing: processing, preset: preset, variant: variant, customColors: customColors,
                           strength: strength, cornerRadius: cornerRadius, active: active, layer: layer, driver: driver))
    }
}

/// Paints the lobes as soft radial gradients, then blurs the lot. The canvas is made larger than
/// the view (negative padding) so the blur doesn't fade the glow where it meets the bottom edge.
private struct VoiceGlowCanvas: View {
    let model: VoiceGlowModel
    let colors: [Color]
    let strength: Double

    var body: some View {
        let blur = CGFloat(max(0, model.geometry.blur))
        let inset = blur * 2
        Canvas { context, size in
            Self.paint(into: &context, size: size, inset: inset, model: model, colors: colors, strength: strength)
        }
        .padding(EdgeInsets(top: 0, leading: -inset, bottom: -inset, trailing: -inset))
        .blur(radius: blur)
    }

    private nonisolated static func paint(into context: inout GraphicsContext, size: CGSize, inset: CGFloat,
                              model: VoiceGlowModel, colors: [Color], strength: Double) {
        guard !colors.isEmpty, strength > 0 else { return }
        let width = max(1, size.width - inset * 2)
        let baseline = size.height - inset
        let reach = CGFloat(max(1, model.geometry.reach))
        context.blendMode = .plusLighter
        for lobe in model.lobes(paletteCount: colors.count) {
            let radiusX = CGFloat(lobe.halfWidth) * width
            let radiusY = CGFloat(lobe.height) * reach
            guard radiusX > 0.5, radiusY > 0.5 else { continue }
            let color = colors[lobe.colorIndex % colors.count]
            let gradient = Gradient(stops: [
                .init(color: color.opacity(0.85 * strength), location: 0),
                .init(color: color.opacity(0.4 * strength), location: 0.45),
                .init(color: color.opacity(0), location: 1),
            ])
            var layer = context
            layer.translateBy(x: inset + CGFloat(lobe.center) * width, y: baseline)
            layer.scaleBy(x: radiusX, y: radiusY)
            layer.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                       with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
        }
    }
}
