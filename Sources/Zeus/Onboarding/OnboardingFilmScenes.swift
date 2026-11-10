import AppKit
import SwiftUI

// The guide's other films: approve, previews, shortcuts, everywhere and the intro. Original Zeus
// scenes, pure functions of time, drawn with the real mascot sprites (see OnboardingFilms.swift).

private let filmBlue = Color(rgb: 96, 160, 248)
private let filmGreen = Color(rgb: 70, 220, 150)
private let filmOrange = Color(rgb: 255, 160, 60)
private let filmRed = Color(rgb: 255, 92, 92)
private let filmViolet = Color(rgb: 180, 120, 255)

// MARK: Shared pieces

/// The learn films' frame: the blue desk with the lid edge at y 250, the black header on top.
private struct LearnStage<Content: View>: View {
    let t: Double
    let number: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            Desk(t: t, lidY: 250)
            content
            Color.black.frame(height: 150)
            FilmHeader(number: number, title: title, subtitle: subtitle)
        }
        .frame(width: 720, height: 900)
        .clipped()
    }
}

/// The expanded notch: black body with a glowing lower edge, the mascot at the left and a label.
private struct NotchHUD: View {
    let t: Double
    var width: CGFloat = 560
    var height: CGFloat = 70
    let glow: Color
    let pose: LivingPose
    let since: Double
    let label: String
    var trailing: AnyView? = nil
    var body: some View {
        ZStack(alignment: .top) {
            NotchBody(width: width, height: height, glow: glow)
            HStack(spacing: 14) {
                FilmMascot(pose: pose, t: t, size: 52, since: since)
                Text(label).font(Glass.font(19, .semibold)).foregroundStyle(glow)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .padding(.horizontal, 22)
            .frame(width: width, height: height)
        }
        .offset(y: 250)
    }
}

private func wave(_ t: Double, _ color: Color, bars: Int = 12) -> AnyView {
    AnyView(HStack(spacing: 2.5) {
        ForEach(0..<bars, id: \.self) { i in
            Capsule().fill(color.opacity(0.85)).frame(width: 3, height: 5 + 18 * abs(sin(t * 7 + Double(i) * 0.9)))
        }
    })
}

private func caption(_ text: String, opacity: Double = 1) -> some View {
    Text(text).font(Glass.font(26, .semibold)).foregroundStyle(.white)
        .padding(.horizontal, 26).padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .opacity(opacity)
}

/// A pale agent window behind the notch, so the notch reads as being above real work.
private struct BackWindow: View {
    let lines: [(String, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) { ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 9, height: 9) } }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.0).font(.system(size: 14, design: .monospaced)).foregroundStyle(line.1)
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 600, height: 330, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(rgb: 24, 26, 32).opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

private struct Cursor: View {
    var body: some View {
        Image(systemName: "cursorarrow").font(.system(size: 30)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 3, y: 2)
    }
}

/// ⌃ and ⌥ drawn with the system's own key symbols (the rounded font turned ⌃ into a plain "^").
private func keycapLabel(_ label: String, size: CGFloat) -> some View {
    HStack(spacing: size * 0.12) {
        ForEach(Array(label.enumerated()), id: \.offset) { _, character in
            switch character {
            case "\u{2303}": Image(systemName: "control").font(.system(size: size * 0.82, weight: .semibold))
            case "\u{2325}": Image(systemName: "option").font(.system(size: size * 0.82, weight: .semibold))
            case "\u{2318}": Image(systemName: "command").font(.system(size: size * 0.82, weight: .semibold))
            default: Text(String(character)).font(.system(size: size, weight: .medium, design: .rounded))
            }
        }
    }
}

private func keycap(_ label: String, width: CGFloat, height: CGFloat = 96, press: Double = 0, tint: Color = filmBlue, size: CGFloat = 34) -> some View {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(LinearGradient(colors: [Color(rgb: 52, 54, 60), Color(rgb: 30, 31, 36)], startPoint: .top, endPoint: .bottom))
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.9 * press), lineWidth: 3).blur(radius: 2))
        .overlay(keycapLabel(label, size: size).foregroundStyle(.white.opacity(0.9)))
        .shadow(color: tint.opacity(0.55 * press), radius: 18)
        .offset(y: CGFloat(press) * 6)
        .scaleEffect(1 - 0.04 * press)
}

// MARK: Approve (5.0 s)

/// An agent asks for permission in the notch; the cursor allows it; the notch confirms. Beats: idle
/// notch (0 to 0.7), the request unfolds (0.7 to 1.3), the cursor travels (1.5 to 2.5), the click
/// (2.6 to 2.8), approved (2.9 to 5.0).
struct ApproveScene: View {
    let t: Double
    var body: some View {
        let request = ramp(t, 0.7, 1.3) * (1 - ramp(t, 3.0, 3.5))
        let approved = t >= 2.9
        let glow = t < 0.7 ? filmBlue : (approved ? filmGreen : filmOrange)
        let label = t < 0.7 ? "Zeus" : (approved ? "Approved" : "Needs you")
        let cursor = CGPoint(x: mix(560, 535, ramp(t, 1.5, 2.5)), y: mix(780, 560, ramp(t, 1.5, 2.5)))
        let press = ramp(t, 2.6, 2.7) * (1 - ramp(t, 2.8, 2.9))
        LearnStage(t: t, number: "03", title: "Approve", subtitle: "") {
            BackWindow(lines: backLines).offset(y: 520)
            NotchHUD(t: t, glow: glow, pose: t < 0.7 ? .idle : (approved ? .success : .approval_wait),
                     since: t < 0.7 ? 0 : (approved ? 2.9 : 0.7), label: label,
                     trailing: approved || t < 0.7 ? nil : wave(t, glow, bars: 8))
            requestCard(press: press)
                .scaleEffect(mix(0.94, 1, request), anchor: .top)
                .opacity(request)
                .offset(x: 80, y: 336)
                .frame(width: 720, alignment: .topLeading)
            Cursor().scaleEffect(1 - 0.12 * press).position(x: cursor.x, y: cursor.y)
                .opacity(ramp(t, 1.4, 1.6) * (1 - ramp(t, 3.0, 3.3)))
        }
    }

    private var backLines: [(String, Color)] {
        var lines: [(String, Color)] = [("$ agent --task \"dark mode for settings\"", .white.opacity(0.8)), ("Read  src/app/settings/page.tsx", .white.opacity(0.55))]
        lines.append(("Edit  src/app/settings/page.tsx  +42 -3", .white.opacity(0.55)))
        lines.append(("Run   npm run build", t < 2.9 ? filmOrange : .white.opacity(0.8)))
        if t >= 3.4 { lines.append(("\u{2713} Build passed. 3 files changed.", filmGreen)) }
        return lines
    }

    private func requestCard(press: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(rgb: 12, 14, 20))
            RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(filmOrange.opacity(0.75), lineWidth: 1.5)
            Text("Allow the agent to run this command?").font(Glass.font(19, .semibold)).foregroundStyle(.white)
                .offset(x: 24, y: 22)
            Text("$ npm run build").font(.system(size: 17, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                .padding(14).frame(width: 512, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.5)))
                .offset(x: 24, y: 70)
            button("Deny", x: 24, width: 120, fill: Color.white.opacity(0.1), text: .white.opacity(0.85), press: 0)
            button("Always allow", x: 154, width: 190, fill: Color.white.opacity(0.1), text: .white.opacity(0.85), press: 0)
            button("Allow once", x: 354, width: 182, fill: Color(rgb: 41, 98, 210), text: .white, press: press)
        }
        .frame(width: 560, height: 250)
        .shadow(color: filmOrange.opacity(0.35), radius: 22, y: 8)
    }

    private func button(_ title: String, x: CGFloat, width: CGFloat, fill: Color, text: Color, press: Double) -> some View {
        Text(title).font(Glass.font(17, .semibold)).foregroundStyle(text)
            .frame(width: width, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .scaleEffect(1 - 0.06 * press)
            .brightness(0.15 * press)
            .offset(x: x, y: 184)
    }
}

// MARK: Previews (10.0 s)

/// Peek cards drop from the notch as three agents run, finish and fail. Card A runs then finishes,
/// B runs then fails, C is still running at the end, so the last frames hold running, done and failed.
struct PreviewsScene: View {
    let t: Double

    private enum Kind { case running, done, failed }
    private struct Card {
        let title: String, running: String, done: String, failed: String
        let appears: Double, resolves: Double, ends: Kind
    }
    private let cards = [
        Card(title: "Dark mode for settings", running: "Editing 3 files", done: "Build passed, all tests green", failed: "", appears: 0.6, resolves: 3.0, ends: .done),
        Card(title: "Release notes 1.0", running: "Reading the changelog", done: "", failed: "2 tests failed in notes.spec", appears: 4.0, resolves: 5.6, ends: .failed),
        Card(title: "Menu bar toggle", running: "Wiring the switch", done: "", failed: "", appears: 6.8, resolves: 99, ends: .running),
    ]

    private func kind(_ card: Card) -> Kind { t >= card.resolves ? card.ends : .running }
    private func color(_ kind: Kind) -> Color { kind == .running ? filmBlue : (kind == .done ? filmGreen : filmRed) }

    /// The notch reflects the latest event.
    private var notch: (Color, LivingPose, Double, String) {
        switch t {
        case ..<0.6: (filmBlue, .idle, 0, "Zeus")
        case ..<3.0: (filmBlue, .working, 0.6, "1 Running")
        case ..<4.0: (filmGreen, .success, 3.0, "Done")
        case ..<5.6: (filmBlue, .working, 4.0, "1 Running")
        case ..<6.8: (filmRed, .error, 5.6, "Failed")
        default: (filmBlue, .working, 6.8, "1 Running")
        }
    }

    var body: some View {
        let (glow, pose, since, label) = notch
        LearnStage(t: t, number: "04", title: "Previews", subtitle: "") {
            NotchHUD(t: t, glow: glow, pose: pose, since: since, label: label, trailing: nil)
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                let appear = ramp(t, card.appears, card.appears + 0.55)
                cardView(card, appear: appear)
                    .offset(x: 80, y: 336 + CGFloat(index) * 126 - CGFloat(1 - appear) * 40)
                    .frame(width: 720, alignment: .topLeading)
                    .opacity(appear)
            }
        }
    }

    private func cardView(_ card: Card, appear: Double) -> some View {
        let k = kind(card)
        let c = color(k)
        let flip = ramp(t, card.resolves, card.resolves + 0.3)
        let progress = k == .running ? ramp(t, card.appears + 0.4, card.resolves > 90 ? 12 : card.resolves) : 1
        let detail = k == .running ? card.running : (k == .done ? card.done : card.failed)
        let symbol = k == .running ? "bolt.fill" : (k == .done ? "checkmark" : "xmark")
        let status = k == .running ? "Running" : (k == .done ? "Done" : "Failed")
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(c.opacity(0.18)).frame(width: 52, height: 52)
                Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(c)
                    .scaleEffect(1 + 0.25 * sin(flip * .pi))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(card.title).font(Glass.font(20, .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 14, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1)).frame(width: 300, height: 4)
                    Capsule().fill(c).frame(width: 300 * progress, height: 4)
                }
            }
            Spacer(minLength: 0)
            Text(status).font(Glass.font(14, .semibold)).foregroundStyle(c)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(c.opacity(0.16)))
        }
        .padding(.horizontal, 20)
        .frame(width: 560, height: 112)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(rgb: 12, 14, 20)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(c.opacity(0.6), lineWidth: 1.5))
        .shadow(color: c.opacity(0.25), radius: 16, y: 6)
    }
}

// MARK: Shortcuts (7.0 s)

/// Hold the talk key (0.3 to 2.6), double-tap to latch (2.6 to 4.4), then answer a request with the
/// Control-Option keys (4.4 to 7.0).
struct ShortcutsScene: View {
    let t: Double

    var body: some View {
        let one = ramp(t, 0.2, 0.5) * (1 - ramp(t, 2.3, 2.6))
        let two = ramp(t, 2.5, 2.8) * (1 - ramp(t, 4.1, 4.4))
        let three = ramp(t, 4.3, 4.6)
        let (glow, pose, since, label) = notch
        LearnStage(t: t, number: "05", title: "Shortcuts", subtitle: "") {
            NotchHUD(t: t, glow: glow, pose: pose, since: since, label: label,
                     trailing: t > 0.9 && t < 4.4 ? wave(t, glow, bars: 10) : nil)
            Group {
                holdChapter.opacity(one)
                latchChapter.opacity(two)
                answerChapter.opacity(three)
            }
            .position(x: 360, y: 640)
        }
    }

    private var notch: (Color, LivingPose, Double, String) {
        switch t {
        case ..<0.9: (filmBlue, .idle, 0, "Zeus")
        case ..<2.2: (filmViolet, .listening, 0.9, "Listening")
        case ..<3.7: (filmBlue, .idle, 2.2, "Zeus")
        case ..<4.4: (filmViolet, .listening, 3.7, "Hands-free")
        case ..<5.3: (filmOrange, .approval_wait, 4.4, "Needs you")
        case ..<6.0: (filmGreen, .success, 5.3, "Approved")
        case ..<6.6: (filmRed, .error, 6.0, "Denied")
        default: (filmBlue, .guiding, 6.6, "Opened")
        }
    }

    private var holdChapter: some View {
        VStack(spacing: 34) {
            Text("Hold to talk").font(Glass.font(34, .bold)).foregroundStyle(.white)
            keycap("talk", width: 220, height: 170, press: ramp(t, 0.9, 1.0) * (1 - ramp(t, 2.0, 2.1)), tint: filmViolet, size: 52)
            Text("Speak while you hold, release to send").font(Glass.font(20)).foregroundStyle(.white.opacity(0.65))
        }
    }

    private var latchChapter: some View {
        let tap1 = ramp(t, 2.9, 2.97) * (1 - ramp(t, 3.05, 3.12))
        let tap2 = ramp(t, 3.25, 3.32) * (1 - ramp(t, 3.4, 3.47))
        let latched = ramp(t, 3.6, 3.9)
        return VStack(spacing: 34) {
            Text("Double-tap to latch").font(Glass.font(34, .bold)).foregroundStyle(.white)
            ZStack {
                keycap("talk", width: 220, height: 170, press: max(tap1, tap2, latched * 0.6), tint: filmViolet, size: 52)
                Image(systemName: "lock.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(filmViolet)
                    .offset(x: 0, y: -118).scaleEffect(latched).opacity(latched)
            }
            Text("Hands-free until you tap again").font(Glass.font(20)).foregroundStyle(.white.opacity(0.65))
        }
    }

    private var answerChapter: some View {
        let y = ramp(t, 4.9, 5.0) * (1 - ramp(t, 5.3, 5.4))
        let n = ramp(t, 5.6, 5.7) * (1 - ramp(t, 6.0, 6.1))
        let o = ramp(t, 6.2, 6.3) * (1 - ramp(t, 6.6, 6.7))
        return VStack(spacing: 34) {
            Text("Answer without looking").font(Glass.font(34, .bold)).foregroundStyle(.white)
            HStack(spacing: 22) {
                combo("\u{2303}\u{2325}Y", "Allow", y, filmGreen)
                combo("\u{2303}\u{2325}N", "Deny", n, filmRed)
                combo("\u{2303}\u{2325}O", "Open", o, filmBlue)
            }
        }
    }

    private func combo(_ keys: String, _ name: String, _ press: Double, _ tint: Color) -> some View {
        VStack(spacing: 14) {
            keycap(keys, width: 190, height: 120, press: press, tint: tint, size: 40)
            Text(name).font(Glass.font(22, .semibold)).foregroundStyle(tint)
        }
    }
}

// MARK: Everywhere (8.5 s)

/// Every display (0 to 3.0), quiet in full screen (3.0 to 5.8), the Insomnia lid (5.8 to 8.5).
struct EverywhereScene: View {
    let t: Double

    var body: some View {
        let one = ramp(t, 0.1, 0.4) * (1 - ramp(t, 2.7, 3.0))
        let two = ramp(t, 2.9, 3.2) * (1 - ramp(t, 5.5, 5.8))
        let three = ramp(t, 5.7, 6.0)
        LearnStage(t: t, number: "06", title: "Everywhere", subtitle: "") {
            displays.opacity(one).position(x: 360, y: 560)
            fullScreen.opacity(two).position(x: 360, y: 560)
            insomnia.opacity(three).position(x: 360, y: 560)
        }
    }

    private func screen(width: CGFloat, height: CGFloat, hue: Color) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Color(rgb: 10, 16, 40), hue], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 3))
    }

    private func pill(_ pose: LivingPose, since: Double = 0) -> some View {
        ZStack {
            Capsule().fill(.black).frame(width: 96, height: 30)
            Capsule().strokeBorder(filmBlue.opacity(0.9), lineWidth: 1.5).blur(radius: 1.2).frame(width: 96, height: 30)
            FilmMascot(pose: pose, t: t, size: 34, since: since)
        }
        .shadow(color: filmBlue.opacity(0.5), radius: 8)
    }

    /// Two displays; the pill hops from the laptop's notch to the external screen's top.
    private var displays: some View {
        let hop = ramp(t, 1.0, 1.9)
        let from = CGPoint(x: -150, y: -118)
        let to = CGPoint(x: 150, y: -134)
        let x = mix(from.x, to.x, hop)
        let y = mix(from.y, to.y, hop) - CGFloat(sin(hop * .pi)) * 70
        return ZStack {
            screen(width: 280, height: 190, hue: Color(rgb: 36, 84, 200)).offset(x: -150, y: -22)
            Rectangle().fill(.white.opacity(0.4)).frame(width: 330, height: 6).offset(x: -150, y: 86)
            screen(width: 330, height: 210, hue: Color(rgb: 60, 50, 170)).offset(x: 150, y: -30)
            Rectangle().fill(.white.opacity(0.3)).frame(width: 14, height: 50).offset(x: 150, y: 100)
            Capsule().fill(.white.opacity(0.3)).frame(width: 120, height: 8).offset(x: 150, y: 128)
            Text("Built-in").font(.system(size: 14, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).offset(x: -150, y: 124)
            Text("External").font(.system(size: 14, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).offset(x: 150, y: 156)
            pill(hop < 1 ? .walking : .idle, since: 1.0).offset(x: x, y: y + 40)
        }
        .frame(width: 720, height: 360)
    }

    /// A full-screen app: the pill slides up out of sight, the room stays quiet.
    private var fullScreen: some View {
        let gone = ramp(t, 3.5, 4.0)
        let ping = ramp(t, 4.9, 5.1) * (1 - ramp(t, 5.3, 5.5))
        return ZStack {
            screen(width: 520, height: 330, hue: Color(rgb: 8, 10, 24))
            Image(systemName: "play.rectangle.fill").font(.system(size: 80)).foregroundStyle(.white.opacity(0.25))
            Text("Full screen").font(.system(size: 14, design: .monospaced)).foregroundStyle(.white.opacity(0.45)).offset(y: 80)
            pill(.idle).offset(y: -190 + 40 * CGFloat(1 - gone)).opacity(1 - gone)
            HStack(spacing: 8) {
                Image(systemName: "moon.fill").foregroundStyle(filmViolet)
                Text("Quiet").font(Glass.font(16, .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.6)))
            .offset(y: -150).opacity(ramp(t, 3.9, 4.3))
            Circle().fill(filmOrange).frame(width: 14, height: 14)
                .shadow(color: filmOrange, radius: 10)
                .scaleEffect(1 + 0.6 * ping).opacity(ping)
                .offset(x: 0, y: -158)
        }
        .frame(width: 720, height: 400)
    }

    /// The lid closes; the status light says Insomnia is holding the Mac awake and the work carries on.
    private var insomnia: some View {
        let close = ramp(t, 6.3, 7.1)
        let pulse = 0.5 + 0.5 * sin(t * 5)
        return ZStack {
            // Base
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: 200, 204, 214), Color(rgb: 140, 146, 160)], startPoint: .top, endPoint: .bottom))
                .frame(width: 520, height: 26).offset(y: 120)
            // Lid: hinged at the base, folds flat as it closes.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: 10, 16, 40), Color(rgb: 36, 84, 200)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 3))
                .overlay { agentDots.opacity(1 - close) }
                .frame(width: 460, height: 280)
                .scaleEffect(x: 1, y: max(0.04, 1 - close), anchor: .bottom)
                .offset(y: -18 + 140 * CGFloat(close) * 0.0)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(filmViolet)
                    Text("Insomnia on").font(Glass.font(18, .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.65)))
                .overlay(Capsule().strokeBorder(filmViolet.opacity(0.6 + 0.4 * pulse), lineWidth: 1.5))
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        Circle().fill(filmBlue.opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(t * 6 - Double(i) * 0.8)))).frame(width: 7, height: 7)
                    }
                }
            }
            .offset(y: 120 - 80 * CGFloat(1 - close)).opacity(ramp(t, 6.8, 7.3))
            FilmMascot(pose: close > 0.9 ? .working : .typing, t: t, size: 70, since: 5.7)
                .offset(x: -190, y: 60 - 100 * CGFloat(close))
        }
        .frame(width: 720, height: 400)
    }

    private var agentDots: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(.white.opacity(0.18)).frame(width: CGFloat(300 - i * 50), height: 10)
            }
        }
    }
}

// MARK: Intro (20.0 s)

/// A wide view of the Mac's top edge. Zeus wakes in the notch (1.5 to 6), the halo sweeps (6.2 to 8.2),
/// the tabs unfold (8.2 to 13.2), the voice orb answers (13.2 to 18), then the end card (18.6 to 20).
struct IntroScene: View {
    let t: Double

    private let screen = CGSize(width: 1040, height: 798)
    private let cx: CGFloat = 520

    /// Camera: wide, a push in on the notch for the wake and the halo, then back out as it unfolds.
    private var camera: Double {
        let pushIn = 1 + 2.0 * ramp(t, 0.9, 2.2)
        let pullOut = 1.8 * ramp(t, 7.4, 9.0)
        let pushBack = 1.8 * ramp(t, 18.0, 18.8)
        return pushIn - pullOut + pushBack
    }
    private var openness: Double { ramp(t, 8.2, 9.6) * (1 - ramp(t, 18.0, 18.8)) }
    private var notchWidth: CGFloat { mix(220, 760, openness) }
    private var notchHeight: CGFloat { mix(38, 380, openness) }

    var body: some View {
        let endCard = ramp(t, 18.6, 19.3)
        ZStack(alignment: .top) {
            Color.black
            world.opacity(1 - endCard)
            end.opacity(endCard)
        }
        .frame(width: screen.width, height: screen.height)
        .clipped()
    }

    private var world: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Color(rgb: 6, 10, 26), location: 0),
                .init(color: Color(rgb: 18, 42, 104), location: 0.5),
                .init(color: Color(rgb: 40, 92, 214), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                for i in 0..<2 {
                    let base = size.height * (0.78 + 0.1 * Double(i))
                    let phase = t * 0.5 + Double(i) * 1.7
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: base))
                    wave.addCurve(to: CGPoint(x: size.width, y: base - 70 - 24 * sin(phase)),
                                  control1: CGPoint(x: size.width * 0.35, y: base + 60 + 20 * sin(phase)),
                                  control2: CGPoint(x: size.width * 0.7, y: base - 30))
                    context.stroke(wave, with: .color(.white.opacity(0.4)), lineWidth: 2)
                }
            }
            haloLayer
            notch
        }
        .frame(width: screen.width, height: screen.height)
        .scaleEffect(camera, anchor: UnitPoint(x: 0.5, y: 0.02))
        .offset(y: CGFloat(camera - 1) * 24)
    }

    // MARK: the notch

    private var notch: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: mix(14, 36, openness), bottomTrailingRadius: mix(14, 36, openness), style: .continuous)
                .fill(Color.black)
                .frame(width: notchWidth, height: notchHeight)
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(bottomLeadingRadius: mix(14, 36, openness), bottomTrailingRadius: mix(14, 36, openness), style: .continuous)
                        .stroke(glowColor.opacity(0.5 + 0.4 * halo), lineWidth: 2).blur(radius: 2)
                }
            mascotInNotch
            panel.opacity(ramp(t, 9.2, 9.9) * (1 - ramp(t, 17.8, 18.3)))
        }
        .frame(width: notchWidth, height: notchHeight, alignment: .top)
    }

    private var halo: Double { ramp(t, 6.2, 6.8) * (1 - ramp(t, 7.9, 8.4)) }
    private var glowColor: Color { t > 13.2 && t < 18 ? filmViolet : filmBlue }

    /// Asleep, waking, waving, then at home in the panel's corner.
    private var mascotInNotch: some View {
        let pose: LivingPose
        let since: Double
        switch t {
        case ..<4.0: (pose, since) = (.sleepingClean, 1.5)
        case ..<6.0: (pose, since) = (.waking, 4.0)
        case ..<7.6: (pose, since) = (.welcome, 6.0)
        case ..<13.2: (pose, since) = (t < 8.2 ? .idle : .guiding, t < 8.2 ? 7.6 : 8.2)
        case ..<15.2: (pose, since) = (.listening, 13.2)
        case ..<16.2: (pose, since) = (.thinking, 15.2)
        default: (pose, since) = (.guiding, 16.2)
        }
        // Keep him readable through the pull-out: the camera shrinks the scene before the notch
        // opens, so hold an apparent size of about 60 pt (size × camera).
        let size = max(mix(38, 70, openness), 60 / max(camera, 0.01))
        return FilmMascot(pose: pose, t: t, size: size, since: since)
            .position(x: mix(36, 70, openness), y: mix(19, 66, openness))
            .opacity(ramp(t, 1.2, 2.0))
            .frame(width: notchWidth, height: notchHeight, alignment: .topLeading)
    }

    // MARK: the halo

    private var haloLayer: some View {
        let progress = ramp(t, 6.2, 8.0) * 1.35
        let path = haloPath
        return ZStack {
            path.trim(from: max(0, progress - 0.32), to: min(1, progress))
                .stroke(LinearGradient(colors: [filmBlue, filmViolet], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .blur(radius: 14)
            path.trim(from: max(0, progress - 0.32), to: min(1, progress))
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        .opacity(halo > 0 ? 1 : 0)
        .frame(width: screen.width, height: screen.height)
    }

    /// The closed notch's outline with an arm running out along the screen edge on each side.
    private var haloPath: Path {
        let l = cx - 110, r = cx + 110, h: CGFloat = 38
        var p = Path()
        p.move(to: CGPoint(x: l - 330, y: 2))
        p.addLine(to: CGPoint(x: l - 16, y: 2))
        p.addQuadCurve(to: CGPoint(x: l, y: 16), control: CGPoint(x: l - 2, y: 2))
        p.addLine(to: CGPoint(x: l, y: h - 14))
        p.addQuadCurve(to: CGPoint(x: l + 14, y: h), control: CGPoint(x: l, y: h))
        p.addLine(to: CGPoint(x: r - 14, y: h))
        p.addQuadCurve(to: CGPoint(x: r, y: h - 14), control: CGPoint(x: r, y: h))
        p.addLine(to: CGPoint(x: r, y: 16))
        p.addQuadCurve(to: CGPoint(x: r + 16, y: 2), control: CGPoint(x: r + 2, y: 2))
        p.addLine(to: CGPoint(x: r + 330, y: 2))
        return p
    }

    // MARK: tabs and voice

    private struct Tab { let symbol: String, name: String }
    private let tabs = [Tab(symbol: "house.fill", name: "Home"), Tab(symbol: "sparkle", name: "Agents"),
                        Tab(symbol: "calendar", name: "Day"), Tab(symbol: "mic.fill", name: "Voice"),
                        Tab(symbol: "music.note", name: "Music")]

    private var selectedTab: Double {
        switch t {
        case ..<10.4: 0
        case ..<11.6: mix(0, 1, ramp(t, 10.2, 10.7))
        case ..<12.6: mix(1, 2, ramp(t, 11.4, 11.9))
        default: mix(2, 3, ramp(t, 12.4, 13.0))
        }
    }

    private var panel: some View {
        let tabWidth: CGFloat = 96
        return ZStack(alignment: .top) {
            // Tab bar
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(width: tabWidth, height: 36)
                    .offset(x: CGFloat(selectedTab) * (tabWidth + 6), y: 0)
                HStack(spacing: 6) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        let appear = ramp(t, 8.6 + Double(index) * 0.15, 9.2 + Double(index) * 0.15)
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol).font(.system(size: 14, weight: .semibold))
                            Text(tab.name).font(Glass.font(14, .semibold))
                        }
                        .foregroundStyle(abs(selectedTab - Double(index)) < 0.5 ? .white : .white.opacity(0.55))
                        .frame(width: tabWidth, height: 36)
                        .scaleEffect(mix(0.6, 1, appear)).opacity(appear)
                    }
                }
            }
            .frame(width: 5 * tabWidth + 24, height: 36, alignment: .topLeading)
            .offset(x: 70, y: 50)
            content.offset(y: 110)
        }
        .frame(width: notchWidth, height: notchHeight, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        ZStack {
            homeCard.opacity(1 - ramp(t, 10.3, 10.8))
            agentsCard.opacity(ramp(t, 10.4, 10.9) * (1 - ramp(t, 11.5, 12.0)))
            dayCard.opacity(ramp(t, 11.6, 12.1) * (1 - ramp(t, 12.5, 13.0)))
            voice.opacity(ramp(t, 12.8, 13.4))
        }
        .frame(width: 680, height: 250)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 40, height: 40).background(Circle().fill(tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Glass.font(17, .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.07)))
        .frame(width: 600)
    }

    private var homeCard: some View {
        VStack(spacing: 10) {
            row("cloud.sun.fill", "Clear, 19\u{00B0}", "Local weather", filmOrange)
            row("calendar", "Design review at 15:00", "Next event", filmBlue)
            row("list.bullet", "Send the release notes", "Reminder", filmGreen)
        }
    }

    private var agentsCard: some View {
        VStack(spacing: 10) {
            row("bolt.fill", "Dark mode for settings", "Running", filmBlue)
            row("checkmark", "Menu bar toggle", "Done", filmGreen)
            row("xmark", "Release notes 1.0", "Failed", filmRed)
        }
    }

    private var dayCard: some View {
        VStack(spacing: 10) {
            row("video.fill", "Stand-up", "09:30, 15 min", filmBlue)
            row("person.2.fill", "Design review", "15:00, 45 min", filmViolet)
            row("moon.fill", "Quiet hours", "from 22:00", filmOrange)
        }
    }

    private var voice: some View {
        let listening = ramp(t, 13.4, 13.9) * (1 - ramp(t, 15.2, 15.5))
        let thinking = ramp(t, 15.2, 15.5) * (1 - ramp(t, 16.2, 16.5))
        let speaking = ramp(t, 16.2, 16.5)
        let question = "What is on my day?"
        let answer = "Two meetings and one reminder. Clear skies."
        let q = String(question.prefix(Int(Double(question.count) * ramp(t, 13.8, 15.0))))
        let a = String(answer.prefix(Int(Double(answer.count) * ramp(t, 16.4, 17.8))))
        return VStack(spacing: 18) {
            if q.count >= 4 {
                Text(q).font(Glass.font(20)).foregroundStyle(.white.opacity(0.7))
            }
            orb(listening: listening, thinking: thinking, speaking: speaking)
            Text(a.isEmpty ? " " : a).font(Glass.font(22, .semibold)).foregroundStyle(.white)
        }
    }

    private func orb(listening: Double, thinking: Double, speaking: Double) -> some View {
        let level = listening * abs(sin(t * 6.5)) + speaking * abs(sin(t * 5.2 + 1)) * 0.8
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle().strokeBorder(filmViolet.opacity((1 - phase) * 0.5 * max(listening, speaking)), lineWidth: 3)
                    .frame(width: 70 + 90 * phase, height: 70 + 90 * phase)
            }
            Circle()
                .fill(AngularGradient(colors: [filmBlue, filmViolet, Color(rgb: 236, 72, 153), filmBlue], center: .center, angle: .degrees(t * (60 + 360 * thinking))))
                .frame(width: 84, height: 84)
                .scaleEffect(1 + 0.16 * level + 0.05 * sin(t * 3))
                .blur(radius: 1)
                .shadow(color: filmViolet.opacity(0.8), radius: 14 + 14 * level)
            Circle().fill(.white.opacity(0.25)).frame(width: 30, height: 30).offset(x: -16, y: -18).blur(radius: 6)
        }
        .frame(width: 170, height: 130)
    }

    // MARK: captions and end

    private var captions: some View {
        let items: [(String, Double, Double)] = [
            ("Zeus wakes up in the notch", 1.8, 6.0), ("A sweep of light says it is ready", 6.3, 8.2),
        ]
        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                caption(item.0, opacity: ramp(t, item.1, item.1 + 0.4) * (1 - ramp(t, item.2 - 0.4, item.2)))
            }
        }
        .position(x: screen.width / 2, y: screen.height - 70)
    }

    private var end: some View {
        VStack(spacing: 22) {
            FilmMascot(pose: .celebrate, t: t, size: 190, since: 18.6)
            Text("Zeus").font(Glass.font(110, .heavy)).tracking(-3).foregroundStyle(.white)
        }
        .scaleEffect(mix(0.94, 1, ramp(t, 18.6, 19.6)))
        .position(x: screen.width / 2, y: screen.height / 2)
    }
}
