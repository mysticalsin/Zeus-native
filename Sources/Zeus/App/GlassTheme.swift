import AppKit
import CoreText
import SwiftUI

// The one shared look for every ZEUS window: Settings, setup, the menu bar panel, and any
// window other branches add (chat, usage). Glance-style dark glass: a near-black canvas with
// soft colour light behind it, large-radius translucent cards with a hairline edge, a geometric
// sans (Plus Jakarta Sans, OFL, bundled), white pill buttons, glossy tile icons, and short
// spring motion. Our own drawing and tokens; nothing is taken from another app.

enum Glass {
    // MARK: Colour
    static let canvas = Color(hex: 0x0A0A0D)
    static let sidebar = Color(hex: 0x111116)
    static let text = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.09)
    static let fill = Color.white.opacity(0.045)
    static let fillRaised = Color.white.opacity(0.08)
    static let fillPressed = Color.white.opacity(0.14)

    // MARK: Open notch (Glance-like glass: the desktop shows through below the notch row)
    /// Opacity of the open panel's black below the notch row; the top stays solid to meet the notch.
    static let notchPanelOpacity: Double = 0.80
    /// Where the solid top ends, as a fraction of the open panel's height.
    static let notchSolidStop: Double = 0.16
    /// Glance's open panel: black at the top, (8,8,6) mid, (14,12,11) at the bottom.
    /// Glance's open fill down the gap between cards on Home (parity/N4, x 864): black to y 45,
    /// then up to its brightest behind the middle of the cards, easing off at the bottom.
    static let notchPanelFill = LinearGradient(stops: [
        .init(color: .black, location: 0),
        .init(color: .black, location: 0.21),
        .init(color: Color(red: 7 / 255, green: 6 / 255, blue: 5 / 255), location: 0.33),
        .init(color: Color(red: 12 / 255, green: 11 / 255, blue: 10 / 255), location: 0.41),
        .init(color: Color(red: 16 / 255, green: 14 / 255, blue: 13 / 255), location: 0.48),
        .init(color: Color(red: 27 / 255, green: 26 / 255, blue: 23 / 255), location: 0.67),
        .init(color: Color(red: 24 / 255, green: 22 / 255, blue: 20 / 255), location: 0.86),
        .init(color: Color(red: 19 / 255, green: 18 / 255, blue: 16 / 255), location: 1),
    ], startPoint: .top, endPoint: .bottom)
    static let notchShadow = (opacity: 0.32, radius: CGFloat(18), y: CGFloat(6))
    static let notchTile = Color.white.opacity(0.075)
    static let notchTileStroke = Color.white.opacity(0.11)
    /// ZEUS accent: purple lighting (COLOR DIRECTION). Gold stays on the mascot only.
    static let accent = Theme.accent
    static let accentGlow = Theme.glow
    static let accentDeep = Theme.accentDeep
    static let live = Color(hex: 0xF06A93)
    static let ok = Theme.leaf
    static let warn = Theme.ember
    static let bad = Theme.danger

    // MARK: Shape and space
    static let windowRadius: CGFloat = 26
    static let cardRadius: CGFloat = 22
    static let rowRadius: CGFloat = 14
    static let tileRadius: CGFloat = 8
    static let pad: CGFloat = 18
    static let gap: CGFloat = 14

    // MARK: Motion
    @MainActor static var spring: Animation? { Motion.page(reduceMotion: Motion.reduced) }
    @MainActor static var quick: Animation? { Motion.feedback(reduceMotion: Motion.reduced) }

    // MARK: Type
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        GlassFonts.registered ? .custom(GlassFonts.family, size: size).weight(weight)
                              : .system(size: size, weight: weight, design: .rounded)
    }
    static var largeTitle: Font { font(26, .semibold) }
    static var title: Font { font(17, .semibold) }
    static var section: Font { font(15, .medium) }
    static var body: Font { font(13) }
    static var bodyStrong: Font { font(13, .semibold) }
    static var caption: Font { font(11.5) }
    static var eyebrow: Font { font(10, .bold) }
    /// Big numerals, Glance style (date, temperature, countdown).
    static func numeral(_ size: CGFloat) -> Font { font(size, .light).monospacedDigit() }
}

/// ZEUS's own SwiftPM resource bundle (avatar art, fonts), in the app or beside the binary.
enum ZeusResources {
    static var candidates: [URL] {
        candidateURLs(resourceURL: Bundle.main.resourceURL, executableURL: Bundle.main.executableURL,
            mainBundleURL: Bundle.main.bundleURL, moduleBundleURL: Bundle(for: ZeusResourceBundleAnchor.self).bundleURL)
    }

    /// SwiftPM puts the resource bundle beside its loaded .xctest bundle, not inside Contents/MacOS.
    /// Only that explicit test-host shape gains a sibling candidate; installed app lookup stays contained.
    static func candidateURLs(resourceURL: URL?, executableURL: URL?, mainBundleURL: URL,
                              moduleBundleURL: URL) -> [URL] {
        let name = "Zeus_Zeus.bundle"
        var urls = [resourceURL?.appendingPathComponent(name),
                    executableURL?.deletingLastPathComponent().appendingPathComponent(name),
                    mainBundleURL.appendingPathComponent(name)].compactMap { $0 }
        for host in [mainBundleURL, moduleBundleURL] where host.pathExtension.lowercased() == "xctest" {
            urls.append(host.deletingLastPathComponent().appendingPathComponent(name))
        }
        var seen = Set<URL>()
        return urls.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
    }

    static var lookupDescription: String {
        "main=\(Bundle.main.bundleURL.path); module=\(Bundle(for: ZeusResourceBundleAnchor.self).bundleURL.path); candidates="
            + candidates.map(\.path).joined(separator: ", ")
    }

    static let bundle: Bundle? = {
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }()
}

private final class ZeusResourceBundleAnchor: NSObject {}

enum GlassFonts {
    static let family = "Plus Jakarta Sans"
    /// Set once at launch before any view is built.
    nonisolated(unsafe) private(set) static var registered = false

    /// Call once at launch (and before snapshots). Process-scoped, nothing is installed.
    static func register() {
        guard !registered else { return }
        if let url = ZeusResources.bundle?.url(forResource: "PlusJakartaSans", withExtension: "ttf", subdirectory: "Fonts") {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || NSFont(name: "PlusJakartaSans-Regular", size: 12) != nil {
                registered = true
            }
        }
    }
}

// MARK: Canvas

/// The window background: near-black with slow, soft colour light, like Glance's glass.
struct GlassBackdrop: View {
    var tint: Color = Glass.live
    var body: some View {
        ZStack {
            Glass.canvas
            Circle().fill(tint.opacity(0.22)).frame(width: 520).blur(radius: 140).offset(x: -260, y: -220)
            Circle().fill(Theme.accentDeep.opacity(0.22)).frame(width: 480).blur(radius: 150).offset(x: 320, y: 40)
            Circle().fill(Theme.glow.opacity(0.18)).frame(width: 420).blur(radius: 150).offset(x: 40, y: 320)
            Circle().fill(Theme.accent.opacity(0.12)).frame(width: 360).blur(radius: 130).offset(x: 220, y: -80)
            GlassGrain()
        }
        .ignoresSafeArea()
    }
}

/// A faint film grain over the backdrop so large dark areas don't band. Our own noise, made once at launch.
struct GlassGrain: View {
    var opacity: Double = 0.07
    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 2).resizable(resizingMode: .tile)
                .opacity(opacity).blendMode(.overlay).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    nonisolated(unsafe) static let tile: CGImage? = {
        let side = 160
        var pixels = [UInt8](repeating: 0, count: side * side)
        var seed: UInt32 = 0x9E3779B9
        for index in pixels.indices {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            pixels[index] = UInt8(truncatingIfNeeded: seed)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}

/// A translucent card with a hairline edge and a faint top highlight.
struct GlassCard<Content: View>: View {
    var title: String? = nil
    var padding: CGFloat = Glass.pad
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased()).font(Glass.eyebrow).tracking(1.1).foregroundStyle(Glass.tertiary)
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: Glass.cardRadius)
    }
}

extension View {
    /// The shared card surface: fill, top sheen, hairline.
    func glassSurface(radius: CGFloat = Glass.cardRadius, fill: Color = Glass.fill) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.fill(fill)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center))
                shape.strokeBorder(Glass.hairline, lineWidth: 1)
            }
        }
    }
}

/// Section title above a group of cards ("Home", "Music" in Glance).
struct GlassSectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Glass.section).foregroundStyle(Glass.text).padding(.leading, 2).accessibilityAddTraits(.isHeader)
    }
}

/// A glossy squircle tile with a symbol, for the sidebar and rows. Drawn, not an image.
struct GlassIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        // Frosted tinted glass with a soft top highlight and a glossy glyph, like the Glance
        // sidebar art (see docs/VISUAL-TEARDOWN.md, Settings).
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(0.92))
            shape.fill(LinearGradient(colors: [tint.opacity(0.04), tint.opacity(0.20)], startPoint: .top, endPoint: .bottom))
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.8, height: size * 0.42)
                .offset(y: -size * 0.24)
                .blendMode(.screen)
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.95), tint.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                               lineWidth: 0.8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(tint)
                .brightness(-0.08)
                .saturation(1.25)
                .shadow(color: tint.opacity(0.5), radius: 1.5, y: 1)
        }
        .clipShape(shape)
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.25), radius: 4, y: 2)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: Rows and controls

/// Label on the left, control on the right, an optional note under the label.
struct GlassRow<Control: View>: View {
    let title: String
    var note: String? = nil
    var icon: (String, Color)? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon { GlassIcon(symbol: icon.0, tint: icon.1, size: 24) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Glass.body).foregroundStyle(Glass.text)
                if let note {
                    Text(note).font(Glass.caption).foregroundStyle(Glass.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
    }
}

/// A thin divider inside cards.
struct GlassDivider: View {
    var body: some View { Rectangle().fill(Glass.hairline).frame(height: 1) }
}

/// Pill switch: white knob on the bolt when on, smoke when off.
struct GlassToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(Motion.page(reduceMotion: reduceMotion)) { configuration.isOn.toggle() } } label: {
            HStack {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Glass.accent : Glass.fillPressed)
                    Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                }
                .frame(width: 36, height: 20)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct GlassToggle: View {
    let isOn: Binding<Bool>
    var label = ""
    var body: some View {
        Toggle(isOn: isOn) { EmptyView() }.toggleStyle(GlassToggleStyle()).accessibilityLabel(label)
    }
}

/// Glance buttons: a white pill (primary), a smoke pill (secondary), or a quiet text button.
struct GlassButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, danger }
    var kind: Kind = .secondary
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(compact ? Glass.font(12, .semibold) : Glass.bodyStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 11 : 15)
            .padding(.vertical, compact ? 5 : 8)
            .background(Capsule().fill(background(pressed)))
            .overlay(Capsule().strokeBorder(kind == .secondary ? Glass.hairline : .clear, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed && isEnabled && !reduceMotion ? Motion.pressedScale : 1)
            .animation(Motion.feedback(reduceMotion: reduceMotion), value: pressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .secondary, .quiet: Glass.text
        case .danger: Glass.bad
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: .white.opacity(pressed ? 0.8 : 1)
        case .secondary: pressed ? Glass.fillPressed : Glass.fillRaised
        case .quiet: pressed ? Glass.fill : .clear
        case .danger: Glass.bad.opacity(pressed ? 0.22 : 0.14)
        }
    }
}

/// A segmented choice drawn as glass chips with a sliding white pill.
struct GlassSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    let selection: Binding<Value>
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = selection.wrappedValue == value
                Button { withAnimation(Motion.page(reduceMotion: reduceMotion)) { selection.wrappedValue = value } } label: {
                    Text(title).font(Glass.font(12, .semibold)).foregroundStyle(on ? .black : Glass.secondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background { if on { Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill, properties: reduceMotion ? [] : .frame) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Glass.fillRaised))
        .overlay(Capsule().strokeBorder(Glass.hairline, lineWidth: 1))
    }
}

/// A menu picker that looks like a glass chip: value plus chevrons.
struct GlassMenu<Value: Hashable>: View {
    let options: [(Value, String)]
    let selection: Binding<Value>

    var body: some View {
        let current = options.first { $0.0 == selection.wrappedValue }?.1 ?? ""
        let chip = HStack(spacing: 6) {
            Text(current).font(Glass.font(12, .semibold)).foregroundStyle(Glass.text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Glass.tertiary)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(Glass.fillRaised))
        .overlay(Capsule().strokeBorder(Glass.hairline, lineWidth: 1))
        if TopBarStyle.isSnapshot {
            chip
        } else {
            Menu {
                ForEach(options, id: \.0) { value, title in
                    Button { selection.wrappedValue = value } label: {
                        if value == selection.wrappedValue { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            } label: { chip }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }
}

/// A text field in a glass capsule. Snapshots draw the value as text.
struct GlassField: View {
    let placeholder: String
    let text: Binding<String>
    var width: CGFloat = 180
    var onSubmit: () -> Void = {}

    var body: some View {
        Group {
            if TopBarStyle.isSnapshot {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .foregroundStyle(text.wrappedValue.isEmpty ? Glass.tertiary : Glass.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: text).textFieldStyle(.plain).foregroundStyle(Glass.text).onSubmit(onSubmit)
            }
        }
        .font(Glass.body)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
    }
}

/// Minus and plus in glass circles with the value between.
struct GlassStepper: View {
    let value: Binding<Int>
    let range: ClosedRange<Int>
    var step = 1
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 8) {
            circle("minus") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) }
            Text(format(value.wrappedValue)).font(Glass.font(12.5, .semibold).monospacedDigit()).foregroundStyle(Glass.text)
                .frame(minWidth: 54)
            circle("plus") { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) }
        }
    }

    private func circle(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Glass.text)
                .frame(width: 24, height: 24).background(Circle().fill(Glass.fillRaised))
                .overlay(Circle().strokeBorder(Glass.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A status dot with a soft glow.
struct GlassDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.8), radius: 3)
    }
}

/// A status capsule: dot and word.
struct GlassStatus: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            GlassDot(color: ok ? Glass.ok : Glass.tertiary)
            Text(text).font(Glass.font(11.5, .semibold)).foregroundStyle(ok ? Glass.text : Glass.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Glass.fillRaised))
    }
}

/// Configures an NSWindow for the glass look: dark, full-size content, hidden title,
/// transparent title bar so the backdrop runs under the traffic lights.
@MainActor
enum GlassWindow {
    static func style(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Glass.canvas)
    }
}

/// A tiny capsule label beside a row title ("Coming" on stubs).
struct GlassBadge: View {
    let text: String
    var tint: Color = Glass.warn
    var body: some View {
        Text(text.uppercased()).font(Glass.font(8.5, .bold)).tracking(0.8).foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.6))
    }
}

/// Search capsule with a magnifier. Bumping `focusToken` focuses it; snapshots draw the text.
struct GlassSearchField: View {
    let placeholder: String
    let text: Binding<String>
    var focusToken = 0
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Glass.tertiary)
            if TopBarStyle.isSnapshot {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue).font(Glass.body)
                    .foregroundStyle(text.wrappedValue.isEmpty ? Glass.tertiary : Glass.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                GlassSearchText(placeholder: placeholder, text: text, focusToken: focusToken, onSubmit: onSubmit)
            }
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Glass.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
    }
}

private struct GlassSearchText: NSViewRepresentable {
    let placeholder: String
    let text: Binding<String>
    let focusToken: Int
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5, weight: .medium)
        field.textColor = .white
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search settings")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
        ])
        if field.stringValue != text.wrappedValue { field.stringValue = text.wrappedValue }
        context.coordinator.parent = self
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: GlassSearchText
        var focusToken: Int
        init(parent: GlassSearchText) { self.parent = parent; focusToken = parent.focusToken }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            return false
        }
    }
}

/// A secret field in a glass capsule. Snapshots draw dots, never the value.
struct GlassSecureField: View {
    let placeholder: String
    let text: Binding<String>
    var width: CGFloat = 220

    var body: some View {
        Group {
            if TopBarStyle.isSnapshot {
                Text(placeholder).foregroundStyle(Glass.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SecureField(placeholder, text: text).textFieldStyle(.plain).foregroundStyle(Glass.text)
            }
        }
        .font(Glass.body)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Glass.hairline, lineWidth: 1))
    }
}

// MARK: Open-notch card finishes (Settings > Appearance > Card style and Home style)

/// Glance's card finishes, drawn by ZEUS. Liquid Glass is the default, as in Glance.
enum CardFinish: String, CaseIterable {
    case liquidGlass = "Liquid Glass", glass = "Glass", classic = "Classic", physical = "Physical", dashboard = "Dashboard", dashboardB = "Dashboard B"

    /// The saved Card style name as a finish. Unknown or empty names fall back to Liquid Glass.
    static func resolve(_ name: String) -> CardFinish { CardFinish(rawValue: name) ?? .liquidGlass }

    /// Open-notch card corner radius and inset, measured from Glance's open panel.
    static let radius: CGFloat = 20
    static let inset: CGFloat = 14

    @MainActor static var current: CardFinish { resolve(SettingsStore.shared.string("appearance.cardStyle")) }

    /// Home band frame: Device (cards), Borderless, or Borderless colour.
    @MainActor static var home: (finish: CardFinish?, tinted: Bool) {
        let style = SettingsStore.shared.string("appearance.homeStyle")
        if style == "Borderless" { return (nil, false) }
        if style == "Borderless colour" { return (nil, true) }
        let separate = SettingsStore.shared.string("appearance.physicalFinish") == "Separate"
        return (current == .physical && separate ? .liquidGlass : current, false)
    }
}

struct NotchCardBackground: ViewModifier {
    let finish: CardFinish?
    var tint: Color? = nil
    var radius: CGFloat = CardFinish.radius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if let finish {
                switch finish {
                case .liquidGlass:
                    shape.fill(Color.white.opacity(0.07))
                        .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.white.opacity(0.03)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06), Color.white.opacity(0.14)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                case .glass:
                    shape.fill(Glass.notchTile).overlay(shape.strokeBorder(Glass.notchTileStroke))
                case .classic:
                    shape.fill(Color(white: 0.13))
                case .physical:
                    shape.fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6).blendMode(.plusLighter))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                case .dashboard:
                    shape.fill(Color.white.opacity(0.035))
                        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                case .dashboardB:
                    // Dashboard B: a solid instrument panel with a thin accent rule along the top edge.
                    shape.fill(Color(white: 0.085))
                        .overlay(alignment: .top) {
                            Capsule().fill(Theme.glow.opacity(0.85)).frame(height: 2).padding(.horizontal, radius * 0.9).padding(.top, 1)
                        }
                        .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
            } else if let tint {
                shape.fill(tint.opacity(0.14))
            }
        }
    }
}

extension View {
    func notchCard(_ finish: CardFinish?, tint: Color? = nil, radius: CGFloat = CardFinish.radius) -> some View {
        modifier(NotchCardBackground(finish: finish, tint: tint, radius: radius))
    }
}
