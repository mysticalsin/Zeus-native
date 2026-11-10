import AppKit
import CoreText
import SwiftUI
import ZeusCore

// The welcome guide's look, measured on Glance 0.3.1's live onboarding window (960 x 760 pt,
// screencapture -l, pt = px / 2; glance-clone-proof/laneb/parity/g-ob*.png). Our own drawing:
// the Zeus bolt and mascot replace Glance's logo and character.

enum OB {
    // MARK: Window
    static let size = CGSize(width: 960, height: 760)

    // MARK: Colour (dark; the light set follows "Window appearance")
    struct Palette {
        let canvas: Color, watermark: Color, text: Color, secondary: Color, hairline: Color
        let dotOff: Color, fieldFill: Color, fieldStroke: Color, track: Color, popup: Color
        let tile: Color, tileStroke: Color
    }

    static let dark = Palette(
        canvas: Color(rgb: 20, 22, 27), watermark: Color(rgb: 24, 27, 32), text: Color(rgb: 241, 243, 248),
        secondary: Color(rgb: 173, 181, 195), hairline: Color(rgb: 48, 50, 54), dotOff: Color(rgb: 48, 50, 54),
        fieldFill: Color(rgb: 35, 37, 44), fieldStroke: Color(rgb: 61, 63, 69), track: Color(rgb: 38, 40, 45),
        popup: Color(rgb: 66, 68, 73), tile: Color(rgb: 38, 56, 86), tileStroke: Color(rgb: 61, 63, 69))

    static let light = Palette(
        canvas: Color(rgb: 244, 245, 248), watermark: Color(rgb: 236, 238, 243), text: Color(rgb: 22, 24, 30),
        secondary: Color(rgb: 96, 102, 114), hairline: Color(rgb: 222, 224, 229), dotOff: Color(rgb: 214, 217, 223),
        fieldFill: Color.white, fieldStroke: Color(rgb: 212, 215, 222), track: Color(rgb: 228, 230, 235),
        popup: Color(rgb: 226, 228, 233), tile: Color(rgb: 222, 233, 252), tileStroke: Color(rgb: 212, 215, 222))

    static let blue = Color(rgb: 41, 98, 210)
    static let blueLight = Color(rgb: 128, 178, 249)
    static let blueText = Color(rgb: 121, 169, 237)
    static let toggleOn = Color(rgb: 61, 126, 246)
    static let allowed = Color(rgb: 136, 219, 161)

    // MARK: Layout (window coordinates, top-left origin)
    /// Shared left edge for the brand mark and every step heading (QA19 alignment).
    static let leadingEdge: CGFloat = OnboardingChromeLayout.leadingEdge
    static let contentX: CGFloat = leadingEdge
    static let columnWidth: CGFloat = 420 // 48 to 468
    static let visualCenterX: CGFloat = 782
    static let dotsY: CGFloat = 112
    static let footerButtonTop: CGFloat = 694
    static let footerRight: CGFloat = 32 // 960 - 928
    /// Steps sit centred on this line (Glance: 401.5 to 408 across steps).
    static let contentMidY: CGFloat = 404
    /// Shared title top for onboarding steps (QA7: one baseline across welcome through sounds).
    static let headingTopY: CGFloat = OnboardingChromeLayout.headingTopY

    // MARK: Type
    // Glance sets titles and its wordmark in Plus Jakarta Sans and everything else in Poppins
    // (both OFL; it names Poppins-Regular, -Medium and -SemiBold). Zeus bundles Jakarta; Poppins
    // is used when its upstream TTFs are in Sources/Zeus/Fonts, otherwise Jakarta stands in at
    // the size that matches Poppins' measured line widths (x 0.88).
    /// Plus Jakarta Sans (titles, wordmark).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { Glass.font(size, weight) }
    /// Poppins at Glance's size, or the Jakarta stand-in.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = PoppinsFont.name(weight) { return .custom(name, size: size) }
        return Glass.font(size * 0.88, weight)
    }
    static var title: Font { display(34) }
    static var subtitle: Font { font(16) }
    static var rowTitle: Font { font(14.5, .semibold) }
    static var rowText: Font { font(13.5) }
    static var button: Font { font(15.5, .semibold) }
    static var footer: Font { font(15.5, .medium) }
    static var progress: Font { font(12, .medium) }
    static let titleTracking: CGFloat = -1.5
}

/// Registers Poppins from the bundle's Fonts folder when it is there (process scope only).
enum PoppinsFont {
    nonisolated(unsafe) private static var available: Bool?

    static func name(_ weight: Font.Weight) -> String? {
        if available == nil {
            var found = false
            for face in ["Regular", "Medium", "SemiBold"] {
                if let url = ZeusResources.bundle?.url(forResource: "Poppins-\(face)", withExtension: "ttf", subdirectory: "Fonts") {
                    found = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) || found
                }
            }
            available = found || NSFont(name: "Poppins-Regular", size: 12) != nil
        }
        guard available == true else { return nil }
        switch weight {
        case .semibold, .bold, .heavy, .black: return "Poppins-SemiBold"
        case .medium: return "Poppins-Medium"
        default: return "Poppins-Regular"
        }
    }
}

extension Color {
    init(rgb r: Int, _ g: Int, _ b: Int) {
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = OB.dark }

extension EnvironmentValues {
    var ob: OB.Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: Chrome

/// The faint outline mark behind every step: Zeus's bolt, drawn huge in a thick stroke, where
/// Glance draws its own logo.
struct OnboardingWatermark: View {
    /// Parallax: the mark drifts a little against the direction of travel as the steps advance.
    var shift: CGFloat = 0
    @Environment(\.ob) private var ob
    var body: some View {
        Canvas { context, size in
            var bolt = Path()
            // A rounded Z-bolt spanning the window, like Glance's oversized mark.
            bolt.move(to: CGPoint(x: 150, y: 70))
            bolt.addCurve(to: CGPoint(x: 820, y: 90), control1: CGPoint(x: 420, y: -40), control2: CGPoint(x: 640, y: 40))
            bolt.addCurve(to: CGPoint(x: 900, y: 230), control1: CGPoint(x: 900, y: 110), control2: CGPoint(x: 940, y: 180))
            bolt.addLine(to: CGPoint(x: 330, y: 560))
            bolt.addCurve(to: CGPoint(x: 360, y: 650), control1: CGPoint(x: 280, y: 590), control2: CGPoint(x: 300, y: 650))
            bolt.addLine(to: CGPoint(x: 900, y: 640))
            bolt.addCurve(to: CGPoint(x: 1010, y: 760), control1: CGPoint(x: 960, y: 650), control2: CGPoint(x: 1010, y: 700))
            var spark = Path()
            spark.move(to: CGPoint(x: 610, y: 260))
            spark.addCurve(to: CGPoint(x: 470, y: 470), control1: CGPoint(x: 520, y: 330), control2: CGPoint(x: 470, y: 400))
            spark.addCurve(to: CGPoint(x: 640, y: 560), control1: CGPoint(x: 470, y: 540), control2: CGPoint(x: 560, y: 580))
            let style = StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round)
            context.stroke(bolt, with: .color(ob.watermark), style: style)
            context.stroke(spark, with: .color(ob.watermark), style: style)
            _ = size
        }
        .offset(x: shift)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where the mascot sits on each step (window coordinates).
enum OnboardingLayout {
    struct Slot: Equatable { let center: CGPoint; let side: CGFloat; let isHero: Bool }

    static let heroSide: CGFloat = 112
    static let welcomeHeroSide: CGFloat = 240
    static let companionSide: CGFloat = 62

    static func mascotSlot(for step: OnboardingStep) -> Slot {
        switch step {
        case .welcome:
            // Centred in the hero panel, a little under the notch drawn at its top.
            let frame = OnboardingChromeLayout.welcomePreviewFrame()
            return Slot(center: CGPoint(x: frame.midX, y: frame.midY + 10), side: welcomeHeroSide, isHero: true)
        case .sounds:
            // In the upper part of the preview tile, above its waveform.
            let block = OnboardingChromeLayout.rowsBlock(count: 5, pitch: 62)
            return Slot(center: CGPoint(x: OB.visualCenterX, y: block.top + block.height * 0.36), side: heroSide, isHero: true)
        default: return Slot(center: CGPoint(x: 884, y: 620), side: companionSide, isHero: false)
        }
    }

    /// Size of the film card a step shows, if any (the intro is wide, the learn films are 260 pt).
    static func filmCard(for step: OnboardingStep) -> CGSize? {
        guard let film = step.films.first else { return nil }
        let width: CGFloat = film == .intro ? 420 : 260
        return CGSize(width: width, height: width * film.size.height / film.size.width)
    }
}

/// The light that crosses the window when a step advances: a soft diagonal band, brightest mid-way.
/// Animatable, so every frame of the move gets its own progress.
struct SweepBand: View, Animatable {
    var progress: Double
    var direction: Int
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let travel = direction >= 0 ? progress : 1 - progress
            LinearGradient(colors: [.clear, .white.opacity(0.16), .white.opacity(0.05), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 300, height: proxy.size.height * 1.4)
                .rotationEffect(.degrees(14))
                .blendMode(.plusLighter)
                .position(x: -200 + (width + 400) * travel, y: proxy.size.height / 2)
                .opacity(progress <= 0 || progress >= 1 ? 0 : sin(progress * .pi))
        }
        .clipped()
    }
}

/// Logo tile (21 pt) and the Zeus wordmark, top left (Glance: tile 34.5, 69.5; wordmark x 66.5).
struct OnboardingBrand: View {
    @Environment(\.ob) private var ob
    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [OB.blue, OB.blueLight.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
                .overlay {
                    BoltShape().fill(.white).padding(5)
                }
            Text("Zeus").font(OB.display(25, .heavy)).tracking(-1.2).foregroundStyle(ob.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeus")
    }
}

/// A small, readable progress landmark; a permission step remains optional and can be set up later.
struct OnboardingProgress: View {
    let step: OnboardingStep
    @Environment(\.ob) private var ob

    var body: some View {
        VStack(spacing: 8) {
            StepDashes(current: step.rawValue, count: OnboardingStep.allCases.count)
                .accessibilityHidden(true)
            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count) · \(step.title)")
                .font(OB.progress).monospacedDigit().foregroundStyle(ob.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityIdentifier("onboarding.progress")
        .accessibilityValue("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count). \(step.title)")
    }
}

/// 9.5 x 3 pt dashes, 5 pt apart; done and current are lit. The lit colour wipes in from the left and the
/// current dash stretches, on the same spring as the step change.
struct StepDashes: View {
    let current: Int
    let count: Int
    @Environment(\.ob) private var ob
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onboardingReduceMotion) private var motionOverride
    private var reduceMotion: Bool { OnboardingMotionPolicy.reduced(system: systemReduceMotion, override: motionOverride) }
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                let lit = index <= current
                ZStack(alignment: .leading) {
                    Capsule().fill(ob.dotOff)
                    if reduceMotion {
                        Capsule().fill(lit ? OB.blueLight : ob.dotOff)
                    } else {
                        Capsule().fill(OB.blueLight).scaleEffect(x: lit ? 1 : 0.001, y: 1, anchor: .leading)
                    }
                }
                .frame(width: index == current && !reduceMotion ? 20 : 9.5, height: 3)
            }
        }
        .animation(reduceMotion ? nil : OnboardingTransition.animation(reduceMotion: false), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: Buttons

private struct OBButtonFeedback: ViewModifier {
    let pressed: Bool
    var scales = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onboardingReduceMotion) private var motionOverride
    private var reduceMotion: Bool { OnboardingMotionPolicy.reduced(system: systemReduceMotion, override: motionOverride) }
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed && scales && isEnabled && !reduceMotion ? Motion.pressedScale : 1)
            .animation(Motion.feedback(reduceMotion: reduceMotion), value: pressed)
    }
}

/// The blue footer pill (Continue 117.5 x 44, Start 87 x 45, Finish 93.5 x 44, radius 12).
struct OBPrimaryButtonStyle: ButtonStyle {
    var width: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OB.button)
            .foregroundStyle(.white)
            .frame(width: width, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OB.blue.opacity(configuration.isPressed ? 0.82 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .modifier(OBButtonFeedback(pressed: configuration.isPressed))
    }
}

/// Small blue action (Connect 80 x 35).
struct OBBlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OB.font(14.5, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 35)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(OB.blue.opacity(configuration.isPressed ? 0.82 : 1)))
            .modifier(OBButtonFeedback(pressed: configuration.isPressed))
    }
}

/// Outline action: Check again (105 x 35), Allow (68 x 30), Download.
struct OBOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    var filled = true
    @Environment(\.ob) private var ob
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OB.font(14.5, .bold))
            .foregroundStyle(ob.text)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(filled ? ob.fieldFill : Color.clear).opacity(configuration.isPressed ? 0.7 : 1))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(filled ? ob.fieldStroke : ob.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(OBButtonFeedback(pressed: configuration.isPressed))
    }
}

/// Plain text footer buttons (Back with a chevron, Set up later).
struct OBTextButtonStyle: ButtonStyle {
    @Environment(\.ob) private var ob
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OB.footer)
            .foregroundStyle(ob.secondary.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
            .modifier(OBButtonFeedback(pressed: configuration.isPressed, scales: false))
    }
}

// MARK: Rows

/// One feature row: icon column, title + explanation, and the trailing Allow / Allowed.
struct OBRow<Trailing: View>: View {
    let symbol: String?
    let title: String
    let text: String
    var textWidth: CGFloat? = nil
    @ViewBuilder let trailing: Trailing
    @Environment(\.ob) private var ob

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ZStack(alignment: .leading) {
                Color.clear
                if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(ob.secondary) }
            }
            .frame(width: 36, height: 20)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: text.isEmpty ? 0 : 4) {
                Text(title).font(OB.rowTitle).foregroundStyle(ob.text)
                if !text.isEmpty {
                    Text(text).font(OB.rowText).foregroundStyle(ob.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: textWidth, alignment: .leading)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Allowed" with a green check, or the Allow button.
struct OBAllowButton: View {
    let granted: Bool
    let name: String
    let action: () -> Void
    var recovery = false
    var identifier: String? = nil
    var body: some View {
        let access: OnboardingAccess = granted ? .allowed : (recovery ? .denied : .notGranted)
        if granted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                Text("Allowed").font(OB.font(14.5, .semibold))
            }
            .foregroundStyle(OB.allowed)
            .accessibilityLabel("\(name) allowed")
            .accessibilityIdentifier(identifier ?? "onboarding.allowed.\(name)")
        } else {
            Button(access.actionTitle ?? "Allowed", action: action)
                .buttonStyle(OBOutlineButtonStyle())
                .frame(width: recovery ? 112 : 68)
                .accessibilityLabel(recovery ? "Open Settings for \(name)" : "Allow \(name)")
                .ownedJourneyControl(identifier ?? "onboarding.allow.\(name)")
        }
    }
}

/// Permission purpose stays visible; a denied state offers recovery without blocking navigation.
struct OBPermissionRow: View {
    let symbol: String
    let title: String
    let reason: String
    let capability: OnboardingCapability
    let services: any OnboardingServing

    var body: some View {
        let state = services.access(capability)
        OBRow(symbol: symbol, title: title, text: state.recovery ?? reason, textWidth: 218) {
            OBAllowButton(granted: state == .allowed, name: title, action: { services.request(capability) },
                          recovery: state == .denied, identifier: "onboarding.permission.\(capability.rawValue)")
        }
    }
}

/// Hairline between rows, from the text column (x 84) to the trailing edge (x 468).
struct OBDivider: View {
    @Environment(\.ob) private var ob
    var body: some View {
        Rectangle().fill(ob.hairline).frame(height: 1).padding(.leading, 36)
    }
}

/// The small info line under a step ("You can enable these features later in Settings.").
struct OBNote: View {
    let text: String
    @Environment(\.ob) private var ob
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 11)).accessibilityHidden(true)
            Text(text).font(OB.font(13))
        }
        .foregroundStyle(ob.secondary)
    }
}

/// Glance-style toggle, blue when on: small 44 x 20 (row switches), large 64 x 24 (login).
struct OBToggleStyle: ToggleStyle {
    enum Size { case small, large }
    var size: Size = .small
    @Environment(\.ob) private var ob
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.onboardingReduceMotion) private var motionOverride
    private var reduceMotion: Bool { OnboardingMotionPolicy.reduced(system: systemReduceMotion, override: motionOverride) }
    func makeBody(configuration: Configuration) -> some View {
        let track = size == .small ? CGSize(width: 44, height: 20) : CGSize(width: 64, height: 24)
        return Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? OB.toggleOn : ob.track).frame(width: track.width, height: track.height)
                Capsule().fill(configuration.isOn ? Color(rgb: 225, 235, 254) : Color(rgb: 223, 224, 224))
                    .frame(width: track.width * 0.6, height: track.height - 4).padding(.horizontal, 2)
            }
            .animation(Motion.page(reduceMotion: reduceMotion), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Switch"))
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
