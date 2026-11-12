import AppKit
import SwiftUI

// Settings, measured on Glance 0.3.1's live Settings window (1080 x 780 pt; screencapture -l,
// glance-clone-proof/laneb/parity/settings). Sidebar of three groups, a 845 x 722 rounded panel
// with the page title, its subtitle, a header glyph and stacked cards of rows. Our own drawing.

enum GS {
    static let size = CGSize(width: 1080, height: 780)

    // MARK: Colour
    static let window = Color(rgb: 20, 22, 27)
    static let panel = Color(rgb: 31, 32, 37)
    static let panelStroke = Color(rgb: 53, 54, 59)
    static let card = Color(rgb: 35, 37, 44)
    static let cardStroke = Color(rgb: 61, 63, 69)
    static let separator = Color(rgb: 55, 57, 63)
    static let text = Color(rgb: 241, 243, 248)
    static let secondary = Color(rgb: 173, 181, 195)
    static let selectedFill = Color(rgb: 38, 56, 86)
    static let selectedText = Color(rgb: 128, 178, 249)
    static let buttonFill = Color(rgb: 20, 22, 27)
    static let buttonStroke = Color(rgb: 48, 50, 54)
    /// Secondary buttons and chips on dark surfaces: a lifted fill and a rim that reads on cards
    /// (3:1 against the card), with label text above 4.5:1. Use these, not buttonFill, for controls.
    static let controlFill = Color(rgb: 54, 57, 66)
    static let controlStroke = Color(rgb: 104, 109, 122)
    static let controlText = Color(rgb: 232, 235, 242)
    static let toggleOff = Color(rgb: 89, 91, 97)
    static let knob = Color(rgb: 230, 231, 232)

    // MARK: Geometry
    static let panelFrame = CGRect(x: 218.5, y: 42, width: 845, height: 722)
    static let panelRadius: CGFloat = 28
    static let pagePadding: CGFloat = 28.5 // panel edge to title / cards (x 247)
    static let cardRadius: CGFloat = 22
    static let cardInset: CGFloat = 19
    static let cardGap: CGFloat = 26

    // MARK: Type (Jakarta for titles, Poppins or its stand-in for the rest; see OB)
    static let wordmark = OB.display(33, .heavy)
    static let pageTitle = OB.display(29.5, .bold)
    static let pageSubtitle = OB.font(14)
    static let cardTitle = OB.font(16.5, .semibold)
    static let rowTitle = OB.font(14, .semibold)
    static let rowText = OB.font(13.5)
    static let sidebarItem = OB.font(15, .medium)
    static let sidebarHead = OB.font(12.5, .medium)
}

// MARK: Cards and rows

/// A titled group: 22 pt radius, 1 pt rim, 19 pt inside padding.
struct GSCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(GS.cardTitle).foregroundStyle(GS.text)
                    .padding(.top, 20).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(.horizontal, GS.cardInset)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }
}

/// Icon column (18 pt glyph, text at +42), title, optional explanation, trailing control.
struct GSRow<Trailing: View>: View {
    var symbol: String? = nil
    let title: String
    var text: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(GS.text)
                    .frame(width: 42, alignment: .leading).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(GS.rowTitle).foregroundStyle(GS.text)
                if let text, !text.isEmpty {
                    Text(text).font(GS.rowText).foregroundStyle(GS.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.vertical, 16.5)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
    }
}

extension GSRow where Trailing == EmptyView {
    init(symbol: String? = nil, title: String, text: String? = nil) {
        self.init(symbol: symbol, title: title, text: text) { EmptyView() }
    }
}

/// A row whose trailing control is Glance's switch.
struct GSToggleRow: View {
    var symbol: String? = nil
    let title: String
    var text: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        GSRow(symbol: symbol, title: title, text: text) {
            Toggle(title, isOn: $isOn).toggleStyle(GSToggleStyle()).labelsHidden()
        }
    }
}

/// "Set in <Page>": the small link-row that replaces a duplicate control. Each control keeps one home;
/// every other page points to it.
struct GSLinkRow: View {
    let symbol: String?
    let title: String
    var text: String? = nil
    let destination: GSSection
    let navigation: GSNavigation
    var body: some View {
        GSRow(symbol: symbol, title: title, text: text) {
            Button { navigation.section = destination } label: {
                HStack(spacing: 6) {
                    Text("Set in \(destination.title)")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(GSButtonStyle())
            .accessibilityLabel("\(title): set in \(destination.title)")
        }
    }
}

struct GSDivider: View {
    var body: some View { Rectangle().fill(GS.separator).frame(height: 1) }
}

/// The (i) line under a card's rows.
struct GSInfo: View {
    let text: String
    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(GS.secondary)
                    .accessibilityHidden(true)
                Text(text).font(GS.rowText).foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A calm empty state for a list that has nothing yet: what it is for and what fills it.
struct GSEmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(GS.secondary)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(GS.rowTitle).foregroundStyle(GS.text)
                Text(text).font(GS.rowText).foregroundStyle(GS.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

/// Technical detail kept out of the way: a plain-words row stays visible and the file names, commands
/// and mechanisms live behind "Details".
struct GSDetails: View {
    let text: String
    var label = "Details"
    var body: some View {
        DisclosureGroup {
            Text(text).font(GS.rowText).foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.top, 6)
        } label: {
            Text(label).font(OB.font(13, .semibold)).foregroundStyle(GS.controlText)
        }
        .tint(GS.controlText)
        .padding(.vertical, 10)
    }
}

/// Outlined action ("Check for updates": 138 x 34, radius 10). Secondary buttons use the lifted control
/// tokens so they stay readable on dark cards; `prominent` is the single primary action of a row.
struct GSButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OB.font(14, .semibold))
            .foregroundStyle(prominent ? Color.white : GS.controlText)
            .lineLimit(1)
            .fixedSize() // a button label never wraps ("Remo / ve"); the row gives way instead
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(prominent ? OB.controlAccentFill : GS.controlFill).opacity(configuration.isPressed ? 0.75 : 1))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(prominent ? .clear : GS.controlStroke, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// QA7 round 11 (report-11.md VISUAL section): every `TextField`/`SecureField` in the live Glance
/// settings pages (keyword fields, Base URL, API key, license key, etc.) rendered as a solid yellow
/// "no-entry" placeholder glyph under `ImageRenderer`'s one-shot headless `--snapshots` pass. Root
/// cause is the same class of bug round 10 found and fixed for `PermissionSnapshotView`'s one native
/// `.borderedProminent` button (`SnapshotRenderer.swift`): AppKit controls that normally draw through
/// a real window (here, `NSTextField`'s field editor) can't produce a frame on `ImageRenderer`'s
/// synchronous, windowless pass and macOS substitutes its generic "content unavailable" glyph instead.
/// The Glass theme's own `GlassField`/`GlassSecureField` (`GlassTheme.swift`) already worked around this
/// for the deprecated settings window by drawing the value as plain `Text` under `TopBarStyle.isSnapshot`;
/// this is the same fix, written as a chainable modifier so every live `TextField`/`SecureField` call
/// site only needed one line added, not a rewrite.
extension View {
    /// Insert right after `.textFieldStyle(.plain)` (before `.font`/`.foregroundStyle`/`.padding`/etc.,
    /// so those still apply identically to whichever branch renders): shows `value` (or `placeholder`
    /// when empty, or a dot mask when `secure`) as a plain `Text` while snapshotting, the real control
    /// otherwise. Never changes live behaviour.
    @ViewBuilder func snapshotSafeText(_ value: String, placeholder: String = "", secure: Bool = false, multiline: Bool = false) -> some View {
        if TopBarStyle.isSnapshot {
            let shown = value.isEmpty ? placeholder : (secure ? String(repeating: "•", count: min(max(value.count, 1), 14)) : value)
            let color = value.isEmpty ? Color.white.opacity(0.62) : GS.text
            if multiline {
                Text(shown).foregroundStyle(color).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(shown).foregroundStyle(color).lineLimit(1).truncationMode(.tail)
            }
        } else {
            self
        }
    }

    /// Same fix for a plain SwiftUI `Slider` (`NSSlider`-backed, same offscreen-render limitation):
    /// a filled capsule standing in for the track/knob while snapshotting.
    @ViewBuilder func snapshotSafeSlider(value: Double, in range: ClosedRange<Double>) -> some View {
        if TopBarStyle.isSnapshot {
            let fraction = range.upperBound > range.lowerBound ? (value - range.lowerBound) / (range.upperBound - range.lowerBound) : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white.opacity(0.75)).frame(width: max(6, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
            .frame(height: 4)
        } else {
            self
        }
    }
}

/// Looks exactly like `.borderless`: plain coloured text, no native chrome, a touch dimmer while
/// pressed. `.borderless`'s real `NSButton` backing hits the identical offscreen-render limitation
/// documented on `snapshotSafeText` above (confirmed on `DictationPreviewCard`'s murmur-overlay
/// Cancel/Insert buttons, report-11's "two small yellow icons"); this draws the same look without it,
/// live or snapshotting.
struct PlainTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// "Use another license": frees this Mac's seat. On failure the license stays, the reason shows
/// under the button and the button becomes "Try again". Use it as the trailing control of the key row.
struct GSDeactivateLicenseControl: View {
    private var license: LicenseManager { LicenseManager.shared }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(license.deactivationError == nil ? "Use another license" : "Try again") {
                Task { await LicenseManager.shared.deactivate() }
            }
            .buttonStyle(GSButtonStyle())
            .disabled(license.busy)
            if let message = license.deactivationError {
                Text(message).font(GS.rowText).foregroundStyle(GS.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360, alignment: .trailing)
                    .accessibilityLabel(message)
            }
        }
    }
}

/// Glance's switch: 44 x 20, grey off, blue on.
struct GSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? OB.toggleOn : GS.toggleOff).frame(width: 44, height: 20)
                Capsule().fill(configuration.isOn ? Color(rgb: 225, 235, 254) : GS.knob).frame(width: 27, height: 16).padding(.horizontal, 2)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A pop-up on the settings palette (same control as the guide's).
struct GSPopup: View {
    @Binding var selection: String
    let options: [String]
    /// What VoiceOver calls the pop-up (the setting it changes). Name it at every call site.
    var label: String? = nil
    var body: some View {
        // Glance's settings pop-ups are a fixed 153 x 24, inset 13.5 pt inside the card edge.
        popup.padding(.trailing, 13.5)
    }

    @ViewBuilder private var popup: some View {
        let control = OBPopup(selection: $selection, options: options, width: 153).environment(\.ob, OB.Palette.settings)
        if let label, !label.isEmpty {
            control.accessibilityLabel(label)
        } else {
            control
        }
    }
}

extension OB.Palette {
    /// The guide's dark palette with Settings' pop-up grey.
    static let settings = OB.Palette(
        canvas: GS.window, watermark: GS.window, text: GS.text, secondary: GS.secondary, hairline: GS.separator,
        dotOff: GS.separator, fieldFill: GS.card, fieldStroke: GS.cardStroke, track: GS.toggleOff, popup: Color(rgb: 66, 68, 73),
        tile: GS.selectedFill, tileStroke: GS.cardStroke)
}

/// Large picture choices (card style, avatar, halo): a tile with a caption and a selection ring.
struct GSPictureChoice<Art: View>: View {
    let title: String
    var caption: String? = nil
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let art: Art

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                art
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(OB.font(13.5, .semibold)).foregroundStyle(GS.text)
                        if let caption { Text(caption).font(OB.font(12)).foregroundStyle(GS.secondary) }
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? GS.selectedText : GS.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? GS.selectedFill.opacity(0.55) : GS.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? GS.selectedText : GS.cardStroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Small grey status pill ("Connected", "Allowed", "Not allowed").
struct GSStatus: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle").font(.system(size: 13))
            Text(text).font(OB.font(13.5, .semibold))
        }
        .foregroundStyle(ok ? OB.allowed : GS.secondary)
    }
}
