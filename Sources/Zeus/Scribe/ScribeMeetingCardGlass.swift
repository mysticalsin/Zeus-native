import AppKit
import SwiftUI
import ZeusCore

// The meeting card's surface: one liquid-glass slab. The system blurs the desktop behind the window, a cool
// blue-violet tint sits on it, a luminous rim runs round it (brightest along the top and top left), a soft
// highlight lies near the top edge and a wide soft shadow lies under it. Reduce Transparency swaps the blur
// for an opaque deep blue and keeps the rest.

enum ScribeMeetingCardSurface: Equatable {
    case blurred
    case opaque

    /// The one rule, so a test and a still can reach both surfaces.
    static func resolve(reduceTransparency: Bool) -> ScribeMeetingCardSurface {
        reduceTransparency ? .opaque : .blurred
    }
}

enum ScribeMeetingCardPalette {
    static let tintTop = Color(hex: 0x8FA0FF)
    static let tintMidHex: UInt32 = 0x6A55E8
    static let tintMid = Color(hex: tintMidHex)
    static let tintBottom = Color(hex: 0x2F45C8)
    static let deepTop = Color(hex: 0x22328A)
    static let deepBottom = Color(hex: 0x131D5E)
    static let rimBright = Color.white
    static let rimCool = Color(hex: 0xA9BAFF)
    static let shadow = Color(hex: 0x0A1040)
    /// The relative time and the countdown's accent.
    /// Light enough for WCAG AA (4.5:1) on `tintMid`, the mid tone behind the text; still a little violet.
    static let violetHex: UInt32 = 0xF5F0FF
    static let violet = Color(hex: violetHex)
    static let dotSoon = Color(hex: 0xC59BFF)
    static let dotRecording = Color(hex: 0xFF5C6C)
    static let dotProblem = Color(hex: 0xFFA14A)
    static let ink = Color.white.opacity(0.94)
    static let inkSecondary = Color.white.opacity(0.72)

    static func dot(_ tone: ScribeMeetingCardTone) -> Color {
        switch tone {
        case .soon: return dotSoon
        case .recording: return dotRecording
        case .problem: return dotProblem
        }
    }
}

private struct ScribeMeetingCardGlass: ViewModifier {
    let surface: ScribeMeetingCardSurface
    /// A still render has no desktop to blur; the fixture draws a blurred copy of its backdrop under the card.
    let snapshot: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ScribeMeetingCardMetrics.cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background { base.clipShape(shape) }
            .overlay { rim }
            .shadow(color: ScribeMeetingCardPalette.shadow.opacity(0.5), radius: 18, y: 10)
    }

    @ViewBuilder private var base: some View {
        ZStack {
            switch surface {
            case .opaque:
                LinearGradient(colors: [ScribeMeetingCardPalette.deepTop, ScribeMeetingCardPalette.deepBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .blurred:
                if !snapshot { ScribeBehindWindowBlur() }
                LinearGradient(colors: [ScribeMeetingCardPalette.tintTop.opacity(0.4),
                                        ScribeMeetingCardPalette.tintMid.opacity(0.32),
                                        ScribeMeetingCardPalette.tintBottom.opacity(0.46)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // The soft inner highlight near the top edge.
            LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.36))
        }
    }

    /// The luminous rim, with a faint glow of its own.
    private var rim: some View {
        let width = ScribeMeetingCardMetrics.rim
        let gradient = LinearGradient(
            stops: [.init(color: ScribeMeetingCardPalette.rimBright.opacity(0.95), location: 0),
                    .init(color: ScribeMeetingCardPalette.rimCool.opacity(0.6), location: 0.3),
                    .init(color: ScribeMeetingCardPalette.rimCool.opacity(0.42), location: 0.62),
                    .init(color: ScribeMeetingCardPalette.rimCool.opacity(0.55), location: 1)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            shape.strokeBorder(gradient, lineWidth: width * 2).blur(radius: 3).opacity(0.5)
            shape.strokeBorder(gradient, lineWidth: width)
        }
        .allowsHitTesting(false)
    }
}

/// The system's behind-window material: what the desktop looks like through frosted glass.
private struct ScribeBehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    func scribeCardGlass(_ surface: ScribeMeetingCardSurface, snapshot: Bool = false) -> some View {
        modifier(ScribeMeetingCardGlass(surface: surface, snapshot: snapshot))
    }
}
